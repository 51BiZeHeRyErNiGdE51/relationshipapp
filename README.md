# Lovio 💞

A premium, iOS-first daily relationship platform. Not an anniversary tracker — a product couples open every day, with widgets as the primary engagement surface.

## Quick start

```bash
brew install xcodegen          # if not installed
xcodegen generate              # produces Lovio.xcodeproj
open Lovio.xcodeproj           # build & run the "Lovio" scheme
```

**The app runs immediately with no backend setup.** When no `GoogleService-Info.plist` is bundled, Lovio boots in **demo mode**: a fully seeded couple (Alex & Sam) with journal entries, moods, streaks, countdowns and a partner who has already answered today's question.

### Going live

1. Add your Firebase `GoogleService-Info.plist` to `Sources/App/` (gitignored) and add it to the Lovio target — Auth, Firestore, Storage, Messaging, GA4 and Remote Config light up automatically.
2. Set `REVENUECAT_API_KEY` (scheme environment variable, or hardcode in `RevenueCatBootstrap`) with a `premium` entitlement, monthly/yearly packages in the default offering, and a discounted package in an offering with identifier `secondary` (powers the 7-day decline offer).
3. Update bundle IDs / App Group (`group.com.bsekapps.lovio`) / signing team to your own.
4. Deploy push notification functions: `cd firebase/functions && npm install`, then `firebase deploy --only functions` (Blaze plan + APNs key in Firebase → Cloud Messaging required).
5. Replace AdMob test IDs: `GADApplicationIdentifier` in `project.yml` and `AdsManager.bannerUnitID`.

## Product pillars

| Pillar | Implementation |
| --- | --- |
| **Daily retention** | Daily question with sealed simultaneous reveal, mood check-ins, streaks, companion that wilts without care, daily reminder push |
| **Widgets first** | 10 widget families + Live Activity; app publishes a denormalized snapshot to the App Group on every state change; interactive widgets (Miss You, Love Jar, Secret Message) work without opening the app |
| **Relationship premium** | One purchase covers both partners. Entitlement is anchored to the purchaser and mirrored onto the relationship; survives breakups, follows the purchaser into the next relationship |
| **Value framing** | Paywall never says "$9.99/month" — always "per week · per person" (`PaywallOffer.perWeekPerPerson`) |
| **Platform independence** | Relationship IDs, invite codes and all Firestore documents are opaque/JSON — an Android client can pair with an iOS user with zero changes |

## Architecture

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full picture. In short:

```
Sources/
  Shared/          Models, design system, widget bridge — compiled into app + widget extension
  Core/            Service protocols, demo backend, Firebase/RevenueCat adapters, analytics
  App/             Composition root (AppModel), app entry, root navigation
  Features/        Onboarding, Home, Questions, Memories, Plans, Play, Us, Paywall
Widgets/           WidgetKit extension: 10 widgets + Dynamic Island Live Activity
```

Every backend capability is a protocol (`AuthService`, `RelationshipService`, `QuestionService`, `PremiumService`, …) with two implementations: **live** (Firebase/RevenueCat) and **demo** (seeded, in-memory). The composition root picks one at launch.

## Monetization

- **Free:** 1 widget family, 10 journal entries, 2 games, 3 companion worlds, basic countdowns.
- **Premium (relationship-wide):** all widgets, AI coach + weekly reports, all companions, unlimited journal + voice memories, mood analytics, Live Activities, calendar sync, no ads.
- RevenueCat handles trials, grace periods, billing retry and win-backs; entitlement state is mirrored to Firestore so the partner inherits premium (production: RevenueCat webhook → Cloud Function keeps the mirror authoritative).

## Analytics

Typed event taxonomy in `AnalyticsEvent` fans out to GA4 + a Meta SDK adapter stub: paywall impressions per source & variant, widget interactions, question completion, streaks, subscription funnel. Remote Config drives experiments (`paywall_headline`, `daily_reminder_hour`).

## Roadmap hooks already in place

- **Android**: platform-independent IDs, JSON-schema Firestore docs, `lastSeenPlatform` is informational only.
- **Relationship Graph**: every meaningful action appends a `RelationshipEvent` — the substrate for AI insights.
- **Apple Intelligence**: AI features sit behind `AICoachService`; swap the demo implementation for on-device/server models without touching UI.
- **Experimentation**: `ExperimentsService` (Remote Config) consulted at paywall + notification scheduling.
