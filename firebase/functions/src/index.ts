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

async function push(userID: string, title: string, body: string): Promise<void> {
  const tokens = await tokensFor(userID);
  if (tokens.length === 0) return;
  await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    apns: { payload: { aps: { sound: "default" } } },
  });
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

    switch (data.kind as string) {
      case "miss_you_sent":
        await push(partner, "Someone misses you 🥺", "Tap to send one back.");
        break;
      case "heart_tap":
        await push(partner, "A heart just landed in your jar ❤️", "Your partner is thinking of you.");
        break;
    }
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
