# Localization maintenance

Missuo strings live in `Resources/Localizable.xcstrings` (EN + FR + DE + KO + PT + ES).

After adding new user-facing English copy in Swift (`Text("…")`, `L10n.s("…")`):

1. Build once in Xcode so new keys appear in the catalog (or add them manually).
2. Run a fill script if you add keys without translations — ask your editor to backfill FR/DE/KO/PT/ES for any key missing those locales.

Partner **remote** push copy is in `firebase/functions/src/pushCopy.ts` (keep in sync when adding new push types).

The app writes `users/{id}.appLanguage` so Cloud Functions know which language to use for the **recipient**.
