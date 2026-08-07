/**
 * Lovio Cloud Functions — partner-event push notifications.
 *
 * Deploy (one time setup):
 *   npm i -g firebase-tools
 *   firebase login
 *   cd firebase/functions && npm install && cd ../..
 *   firebase deploy --only functions --project lovio-18416
 *
 * Requires the Blaze plan and an APNs key uploaded in
 * Firebase console → Cloud Messaging.
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

/** FCM tokens for a user (all their devices). */
async function tokensFor(userID: string): Promise<string[]> {
  const doc = await db.collection("users").doc(userID).get();
  return (doc.data()?.fcmTokens as string[] | undefined) ?? [];
}

/** The other member of a relationship. */
async function partnerOf(relID: string, actorID: string): Promise<string | null> {
  const rel = await db.collection("relationships").doc(relID).get();
  const members = (rel.data()?.memberIDs as string[] | undefined) ?? [];
  return members.find((m) => m !== actorID) ?? null;
}

async function push(userID: string, title: string, body: string, data: Record<string, string> = {}): Promise<void> {
  const tokens = await tokensFor(userID);
  if (tokens.length === 0) {
    console.warn(`push: no FCM tokens for user ${userID}`);
    return;
  }
  // Alert push (shows on lock screen / banner even when the app is killed)
  // + content-available so iOS can wake us briefly to sync widgets/photos.
  // apns-push-type MUST be "alert" or Apple may drop the notification.
  const result = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: { sync: "widgets", ...data },
    apns: {
      headers: {
        "apns-priority": "10",
        "apns-push-type": "alert",
      },
      payload: {
        aps: {
          alert: { title, body },
          sound: "default",
          badge: 1,
          "content-available": 1,
          "mutable-content": 1,
        },
      },
    },
  });
  console.log(`push → ${userID}: success=${result.successCount} failure=${result.failureCount} title="${title}"`);
  result.responses.forEach((r, i) => {
    if (!r.success) {
      console.error(`push fail token…${tokens[i].slice(-8)}: ${r.error?.code} ${r.error?.message}`);
    }
  });
  // Drop dead tokens so future sends aren't poisoned.
  const dead = result.responses
    .map((r, i) => (!r.success && /registration-token-not-registered|invalid-registration-token/i.test(r.error?.code ?? "") ? tokens[i] : null))
    .filter(Boolean) as string[];
  if (dead.length) {
    const remaining = tokens.filter((t) => !dead.includes(t));
    await db.collection("users").doc(userID).update({ fcmTokens: remaining });
    console.log(`pruned ${dead.length} dead token(s) for ${userID}`);
  }
}

/** First name of the actor for personalized pushes ("Eren misses you"). */
async function nameOf(userID: string): Promise<string> {
  const doc = await db.collection("users").doc(userID).get();
  const raw = ((doc.data()?.displayName as string) ?? "").trim();
  if (!raw || raw === "You") return "Your love";
  return raw.split(" ")[0];
}

/** Partner answered the daily question → notify; both answered → unlock push to both. */
export const onAnswerCreated = onDocumentCreated(
  "relationships/{relID}/answers/{answerID}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const { relID } = event.params;
    const actor = data.authorID as string;
    const partner = await partnerOf(relID, actor);
    if (!partner) return;

    const both = await db
      .collection("relationships").doc(relID)
      .collection("answers")
      .where("questionID", "==", data.questionID)
      .get();

    if (both.size >= 2) {
      await Promise.all([
        push(partner, "Answers unlocked 🔓", "You both answered — read them together."),
        push(actor, "Answers unlocked 🔓", "You both answered — read them together."),
      ]);
    } else {
      await push(partner, "Your partner answered 💭",
        "Answer today's question to unlock what they wrote.");
    }
  });

/** Mood logged → notify partner. */
export const onMoodLogged = onDocumentCreated(
  "relationships/{relID}/moods/{moodID}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const partner = await partnerOf(event.params.relID, data.authorID as string);
    if (!partner) return;
    await push(partner, "Mood update 💗", "Your partner just checked in. See how they're feeling.");
  });

/** Relationship-graph events → targeted pushes (miss you, heart taps). */
export const onEventCreated = onDocumentCreated(
  "relationships/{relID}/events/{eventID}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const partner = await partnerOf(event.params.relID, data.actorID as string);
    if (!partner) return;

    const name = await nameOf(data.actorID as string);
    switch (data.kind as string) {
      case "miss_you_sent":
        await push(partner, `${name} misses you 🥺`, "Tap to send one back.");
        break;
      case "heart_tap":
        await push(partner, `${name} dropped a heart in your love jar ❤️`,
          "They're thinking of you right now.");
        break;
      case "hug_sent":
        await push(partner, `${name} sent you a hug 🤗`,
          "Wrap it around yourself.");
        break;
      case "widget_note_sent":
        await push(partner, `${name} left a note on your widget 💌`,
          "It's syncing to your home screen now.");
        break;
      case "widget_photo_sent":
        await push(partner, `${name} sent a photo to your widget 📸`,
          "It's syncing to your Polaroid now.");
        break;
      case "meetup_logged":
        await push(partner, `${name} logged a hug 🤗`,
          "Your Hug Meter is back to day zero.");
        break;
    }
  });

/**
 * Widget → server bridge. Interactive widgets (Miss You / Heart Tap) run in
 * the widget extension where there's no Firebase SDK — while the app is
 * killed, their outbox never drains and the partner never gets a push.
 * The widget calls this endpoint directly instead; it writes the same event
 * document the app would, so onEventCreated delivers the push immediately.
 *
 * Auth: no ID token available in the extension, so membership is verified by
 * requiring the caller to know BOTH opaque IDs (userID + relationshipID) and
 * that the user is a member of that relationship.
 */
const WIDGET_EVENT_KINDS = new Set(["miss_you_sent", "heart_tap", "hug_sent"]);

export const widgetAction = onRequest({ invoker: "public", cors: true }, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("POST only");
    return;
  }
  const { relationshipID, userID, kind } = (req.body ?? {}) as {
    relationshipID?: string; userID?: string; kind?: string;
  };
  if (!relationshipID || !userID || !kind || !WIDGET_EVENT_KINDS.has(kind)) {
    res.status(400).json({ ok: false, error: "relationshipID, userID and a valid kind are required" });
    return;
  }

  const rel = await db.collection("relationships").doc(relationshipID).get();
  const members = (rel.data()?.memberIDs as string[] | undefined) ?? [];
  if (!members.includes(userID)) {
    res.status(403).json({ ok: false, error: "not a member" });
    return;
  }

  // Same shape the iOS app writes (RelationshipEvent) so both clients and
  // onEventCreated treat it identically.
  const ref = db.collection("relationships").doc(relationshipID).collection("events").doc();
  await ref.set({
    id: ref.id,
    kind,
    actorID: userID,
    occurredAt: admin.firestore.Timestamp.now(),
    metadata: { source: "widget" },
  });
  console.log(`widgetAction: ${kind} by ${userID} in ${relationshipID}`);
  res.json({ ok: true });
});

// ---------------------------------------------------------------------------
// AI Coach — DeepSeek, strictly server-side.
//
// The API key lives in a Cloud Functions secret, never in the app binary:
//   firebase functions:secrets:set DEEPSEEK_API_KEY --project lovio-18416
//   (paste the key when prompted, then redeploy functions)
//
// The function reads the couple's recent rated answers and moods from
// Firestore itself, so the model sees real alignment data without the client
// shipping anything sensitive.
// ---------------------------------------------------------------------------

const deepseekKey = defineSecret("DEEPSEEK_API_KEY");

interface AnswerDoc {
  authorID: string;
  questionID: string;
  questionText?: string;
  text: string;
  rating?: number;
}

/** Compact context block the model can reason over. */
async function coachContext(relID: string, callerID: string): Promise<string> {
  const rel = await db.collection("relationships").doc(relID).get();
  const relData = rel.data() ?? {};

  const answersSnap = await db
    .collection("relationships").doc(relID)
    .collection("answers")
    .orderBy("answeredAt", "desc")
    .limit(40)
    .get();
  const answers = answersSnap.docs.map((d) => d.data() as AnswerDoc);

  // Group by question; keep only ones both partners answered.
  const byQuestion = new Map<string, AnswerDoc[]>();
  for (const a of answers) {
    byQuestion.set(a.questionID, [...(byQuestion.get(a.questionID) ?? []), a]);
  }
  const lines: string[] = [];
  for (const [, pair] of byQuestion) {
    if (pair.length < 2 || !pair[0].questionText) continue;
    const mine = pair.find((a) => a.authorID === callerID);
    const theirs = pair.find((a) => a.authorID !== callerID);
    if (!mine || !theirs) continue;
    lines.push(`- "${pair[0].questionText}" — user: ${mine.text}, partner: ${theirs.text}`);
    if (lines.length >= 15) break;
  }

  const moodsSnap = await db
    .collection("relationships").doc(relID)
    .collection("moods")
    .orderBy("loggedAt", "desc")
    .limit(10)
    .get();
  const moods = moodsSnap.docs
    .map((d) => d.data())
    .map((m) => `${m.authorID === callerID ? "user" : "partner"}: ${m.mood}`)
    .join(", ");

  return [
    relData.anniversary ? `Anniversary: ${relData.anniversary.toDate?.().toISOString?.().slice(0, 10)}` : "",
    lines.length ? `Recent daily-question answers (both partners):\n${lines.join("\n")}` : "",
    moods ? `Recent moods: ${moods}` : "",
  ].filter(Boolean).join("\n\n");
}

const SYSTEM_PROMPTS: Record<string, string> = {
  chat:
    "You are Missuo's warm, practical relationship coach for couples — many in " +
    "long-distance relationships. Use the provided context about the couple's " +
    "question answers (their agreements and disagreements matter) and moods. " +
    "Be specific to them, kind but honest, never clinical. Keep replies under " +
    "120 words unless asked for detail. Never mention the context block itself.",
  dateIdeas:
    "You suggest date ideas for couples, including virtual dates for " +
    "long-distance couples. Use the couple's context to personalize. Reply " +
    "with exactly 5 ideas, one per line, no numbering, each under 12 words.",
  weeklyReport:
    "You write a weekly relationship report for a couple based ONLY on their " +
    "real context (question answers, agreements/disagreements, moods). Never " +
    "invent names, events or facts not in the context; refer to them as 'you " +
    "two' or 'your partner'. Reply with exactly 3 lines, each formatted as " +
    "'Title | insight' — title under 6 words, insight under 35 words, warm " +
    "and actionable. No numbering, no extra text.",
};

export const askCoach = onCall({ secrets: [deepseekKey] }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const { mode, message, relationshipID } = request.data as {
    mode?: string; message?: string; relationshipID?: string;
  };
  if (!relationshipID || typeof relationshipID !== "string") {
    throw new HttpsError("invalid-argument", "relationshipID required.");
  }

  // Only members of the relationship may ask about it.
  const rel = await db.collection("relationships").doc(relationshipID).get();
  const members = (rel.data()?.memberIDs as string[] | undefined) ?? [];
  if (!members.includes(request.auth.uid)) {
    throw new HttpsError("permission-denied", "Not a member of this relationship.");
  }

  const system = SYSTEM_PROMPTS[mode ?? "chat"] ?? SYSTEM_PROMPTS.chat;
  const context = await coachContext(relationshipID, request.auth.uid);

  const response = await fetch("https://api.deepseek.com/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${deepseekKey.value()}`,
    },
    body: JSON.stringify({
      model: "deepseek-chat",
      max_tokens: 400,
      messages: [
        { role: "system", content: system },
        { role: "user", content: `Couple context:\n${context || "(new couple, no data yet)"}` },
        { role: "user", content: message ?? "Give me one helpful insight about us." },
      ],
    }),
  });

  if (!response.ok) {
    const detail = await response.text();
    console.error("DeepSeek error", response.status, detail);
    throw new HttpsError("unavailable", "AI is temporarily unavailable.");
  }

  const json = (await response.json()) as {
    choices?: { message?: { content?: string } }[];
  };
  const reply = json.choices?.[0]?.message?.content?.trim();
  if (!reply) throw new HttpsError("internal", "Empty AI response.");
  return { reply };
});

/** Daily 09:00 UTC sweep: remind both partners of dates happening tomorrow. */
export const dailyDateReminders = onSchedule("every day 09:00", async () => {
  const snapshot = await db.collectionGroup("dates").get();
  const now = new Date();

  for (const doc of snapshot.docs) {
    const data = doc.data();
    let target: Date = data.date.toDate();

    if (data.repeatsYearly) {
      target = new Date(now.getFullYear(), target.getMonth(), target.getDate());
      if (target < now) target.setFullYear(target.getFullYear() + 1);
    }

    const days = Math.round((target.getTime() - now.getTime()) / 86_400_000);
    if (days !== 1) continue;

    const relID = doc.ref.parent.parent?.id;
    if (!relID) continue;
    const rel = await db.collection("relationships").doc(relID).get();
    const members = (rel.data()?.memberIDs as string[] | undefined) ?? [];
    await Promise.all(members.map((m) =>
      push(m, `Tomorrow: ${data.title} 💛`, "One more sleep — anything left to plan together?")));
  }
});
