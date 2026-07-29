# Lovio Architecture

## Layering

```
┌──────────────────────────────────────────────────────────┐
│ Features (SwiftUI views)                                 │
│   Onboarding · Home · Questions · Memories · Plans       │
│   Play · Us · Paywall · Widget Gallery · Settings        │
├──────────────────────────────────────────────────────────┤
│ AppModel (@Observable, @MainActor)                       │
│   session phase · relationship state · gamification      │
│   widget snapshot publishing · widget outbox draining    │
├──────────────────────────────────────────────────────────┤
│ Service protocols (platform-agnostic contracts)          │
│   Auth · Relationship · Question · Journal · Mood        │
│   Planner · Premium · AICoach · Analytics · Experiments  │
├───────────────────────────┬──────────────────────────────┤
│ Live adapters             │ Demo backend                 │
│  Firebase Auth/Firestore/ │  Seeded in-memory actor      │
│  Messaging/RemoteConfig,  │  (previews, UI tests,        │
│  RevenueCat, GA4          │   no-config demo runs)       │
└───────────────────────────┴──────────────────────────────┘
```

`AppModel.bootstrap()` checks for `GoogleService-Info.plist`; present → live stack, absent → demo stack. Nothing above the protocol layer knows which one is running.

## Firestore schema (Android-ready)

All identifiers are opaque strings minted server-side. No Apple types, no platform assumptions. Documents are plain Codable/JSON.

```
users/{userID}                          UserProfile
invites/{CODE}                          { relationshipID }
relationships/{relID}                   Relationship (status, memberIDs, streak, xp,
                                        loveScore, companion, anniversary)
relationships/{relID}/journal/{id}      JournalEntry
relationships/{relID}/moods/{id}        MoodEntry
relationships/{relID}/dates/{id}        SpecialDate
relationships/{relID}/bucket/{id}       BucketListItem
relationships/{relID}/milestones/{id}   Milestone
relationships/{relID}/notes/{id}        SharedNote
relationships/{relID}/answers/{qID_uID} QuestionAnswer
relationships/{relID}/events/{id}       RelationshipEvent   ← relationship graph
relationships/{relID}/premium/state     PremiumEntitlement  ← premium mirror
```

Security rules sketch: membership in `relationship.memberIDs` gates every subcollection; `isPrivate` notes/journal readable only by `updatedBy`/`authorID`.

## Daily question reveal mechanics

Answers are stored under deterministic IDs (`{questionID}_{userID}`). A client only surfaces `revealedAnswers` when both documents exist — for hard secrecy in production, move the reveal behind a Cloud Function or security rule that denies reading the partner's answer until yours exists.

## Premium = relationship-level entitlement

1. RevenueCat is configured with `appUserID = our UserID` → entitlement follows the person across devices and platforms.
2. After purchase, the client mirrors `PremiumEntitlement { purchaserID, productID, expiresAt }` to `relationships/{id}/premium/state`. Production hardening: RevenueCat webhook → Cloud Function owns the mirror (handles billing retry, grace periods, refunds, win-backs).
3. Resolution order in `PremiumService.premiumState`:
   - my own active entitlement → premium (and re-mirror),
   - else active mirror whose purchaser is a current member → inherited premium,
   - else free.
4. Breakup: relationship doc is `ended`, mirror is orphaned; the purchaser's entitlement is untouched and re-mirrors when they pair again. Partner drops to free. Only one active relationship per user is allowed (`currentRelationship` queries for `pending|active`).

## Widget pipeline

```
AppModel state change
   └─ publishWidgetSnapshot() → JSON blob in App Group defaults
        └─ WidgetCenter.reloadAllTimelines()
             └─ SnapshotProvider (extension) renders 10 widget families

Widget interaction (Miss You / Heart Tap / Reveal)
   └─ AppIntent → WidgetOutbox (App Group)
        └─ app foreground → drainWidgetOutbox() → analytics + backend + gamification
```

Production additions: FCM data pushes with `content-available` trigger snapshot refresh when the *partner* acts (answered, mood change, new note), so widgets update while the app is closed.

## Relationship graph → AI

Every meaningful action appends `RelationshipEvent(kind, actorID, occurredAt, metadata)`. The AI coach consumes `(Relationship, [RelationshipEvent])` — swap `DemoAICoachService` for a server endpoint (or Apple Intelligence on-device summarization) without UI changes. Weekly/monthly reports, love score and churn-risk notifications all read from this single event stream.

## Gamification rules (AppModel.recordEngagement)

- **Streak** extends once per day on the first meaningful action; `lastCompletedDayKey` prevents double counting. (Production: require BOTH partners via Cloud Function daily rollup.)
- **XP** = 5 × nurture points; level = 1 + xp/500.
- **Companion** gains nurture points per action, evolves each 100, has 5 named stages per world; premium worlds gated at selection.
- **Love score** drifts upward with high-value actions, capped 0–100. (Production: weekly decay + partner-balance factors server-side.)

## Experimentation

`ExperimentsService` backed by Firebase Remote Config. Active hooks: `paywall_headline` (headline copy variant, logged on every paywall impression) and `daily_reminder_hour` (notification timing). Add variants without shipping app updates.

## Targets

- **Lovio** (app): links Firebase, RevenueCat, GoogleSignIn.
- **LovioWidgets** (extension): links nothing external; compiles `Sources/Shared` for models, design tokens and the App Group bridge.

## Known production TODOs

- Cloud Functions: FCM fan-out (partner answered / mood / miss-you), streak rollups, RevenueCat webhook, yearly recap generation.
- Storage upload pipeline for journal media (photo/video/voice) with thumbnail generation.
- EventKit calendar sync behind the existing premium gate.
- Facebook SDK: replace `MetaAnalyticsAdapter` stub once a Meta App ID exists.
- Ads for the free tier (AdMob or similar) — deliberately not wired yet.
- Presence/battery/distance sync for widgets (currently placeholder values in the snapshot).
