/**
 * Firebase Gen2 deploys often wipe Cloud Run invokers. Without them,
 * Eventarc cannot invoke onEventCreated / onAnswerCreated / onMoodLogged —
 * partner pushes never leave the server (users only see in-app local banners).
 *
 * Run after every functions deploy:
 *   node firebase/scripts/fix-invokers.mjs
 */
import { readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";

const PROJECT = "lovio-18416";
const PROJECT_NUMBER = "583801376624";
const SERVICES = ["oneventcreated", "onanswercreated", "onmoodlogged"];
const INVOKERS = [
  `serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-eventarc.iam.gserviceaccount.com`,
  `serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com`,
  `serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com`,
];

async function accessToken() {
  const cfg = JSON.parse(
    readFileSync(join(homedir(), ".config/configstore/firebase-tools.json"), "utf8"),
  );
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com",
      client_secret: "j9iVZfS8kkCEFUPaAeJV0sAi",
      grant_type: "refresh_token",
      refresh_token: cfg.tokens.refresh_token,
    }),
  });
  const json = await res.json();
  if (!json.access_token) throw new Error("Firebase CLI login expired — run: firebase login --reauth");
  return json.access_token;
}

async function main() {
  const token = await accessToken();
  const H = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };

  for (const name of SERVICES) {
    const getUrl =
      `https://run.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/services/${name}:getIamPolicy`;
    const policy = await (await fetch(getUrl, { headers: H })).json();
    if (policy.error) {
      console.error(name, policy.error.message);
      continue;
    }
    if (!policy.bindings) policy.bindings = [];
    let binding = policy.bindings.find((b) => b.role === "roles/run.invoker");
    if (!binding) {
      binding = { role: "roles/run.invoker", members: [] };
      policy.bindings.push(binding);
    }
    for (const m of INVOKERS) {
      if (!binding.members.includes(m)) binding.members.push(m);
    }
    const setUrl =
      `https://run.googleapis.com/v2/projects/${PROJECT}/locations/us-central1/services/${name}:setIamPolicy`;
    const r = await (
      await fetch(setUrl, { method: "POST", headers: H, body: JSON.stringify({ policy }) })
    ).json();
    console.log(name, r.error ? r.error.message : `OK (${binding.members.length} invokers)`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
