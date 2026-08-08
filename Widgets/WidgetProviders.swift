import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Shared timeline provider
//
// All widgets render from the app-published WidgetSnapshot. Timelines refresh
// hourly; the app force-reloads on every meaningful state change, and pushes
// (partner answered / mood changed) trigger reloads via the notification
// service extension in production.

struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        // System widget gallery must NEVER show the premium lock — it's a
        // preview surface, not a paywall. Home-screen widgets use live data.
        if context.isPreview {
            completion(SnapshotEntry(date: .now, snapshot: .placeholder))
            return
        }
        var snapshot = AppGroup.loadSnapshot()
        // Stale timelines (purchased Premium after last reload) still unlock.
        if AppGroup.defaults.bool(forKey: "missuo.widget.isPremium") {
            snapshot.isPremium = true
        }
        completion(SnapshotEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        if context.isPreview {
            completion(Timeline(entries: [SnapshotEntry(date: .now, snapshot: .placeholder)],
                                policy: .atEnd))
            return
        }
        var snapshot = AppGroup.loadSnapshot()
        if AppGroup.defaults.bool(forKey: "missuo.widget.isPremium") {
            snapshot.isPremium = true
        }
        var entries: [SnapshotEntry] = [SnapshotEntry(date: .now, snapshot: snapshot)]

        // Presence decays: "you're both here" is only true for ~20 min after
        // the app last verified it — schedule an entry that flips it off so
        // Love Pulse never shows a stale heartbeat for hours.
        if snapshot.bothRecentlyActive {
            let expiry = snapshot.generatedAt.addingTimeInterval(20 * 60)
            if expiry > .now {
                var expired = snapshot
                expired.bothRecentlyActive = false
                entries.append(SnapshotEntry(date: expiry, snapshot: expired))
            } else {
                entries[0].snapshot.bothRecentlyActive = false
            }
        }

        for hour in 1..<4 {
            var future = snapshot
            future.bothRecentlyActive = false
            entries.append(SnapshotEntry(
                date: Calendar.current.date(byAdding: .hour, value: hour, to: .now)!,
                snapshot: future))
        }
        entries.sort { $0.date < $1.date }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Interactive intents (widget → server push, outbox for gamification)
//
// The intent runs inside the widget extension — no Firebase SDK, and the app
// may be killed. To make the partner's push fire immediately, the intent
// calls the widgetAction Cloud Function directly (it writes the same event
// document the app would, which triggers the push). The outbox entry is kept
// so the app can apply XP/streak/love-jar on next open; the "_synced" suffix
// tells it the server event (and push) already happened.

enum WidgetServer {
    static func send(_ kind: String) async -> Bool {
        guard let relID = AppGroup.defaults.string(forKey: AppGroup.relationshipIDKey),
              let userID = AppGroup.defaults.string(forKey: AppGroup.userIDKey),
              let url = URL(string: "https://us-central1-lovio-18416.cloudfunctions.net/widgetAction")
        else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "relationshipID": relID, "userID": userID, "kind": kind])
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
        return true
    }
}

struct SendMissYouIntent: AppIntent {
    static let title: LocalizedStringResource = "Send Miss You"
    static let description = IntentDescription("Sends an animated 'I miss you' to your partner.")

    func perform() async throws -> some IntentResult {
        MissYouCounter.increment()
        let pushed = await WidgetServer.send("miss_you_sent")
        WidgetOutbox.enqueue(pushed ? "miss_you_synced" : "miss_you")
        return .result()
    }
}

struct HeartTapIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a Heart"
    static let description = IntentDescription("Drops a heart into your shared Love Jar.")

    func perform() async throws -> some IntentResult {
        var hearts = AppGroup.defaults.integer(forKey: "lovio.hearts.bonus")
        hearts += 1
        AppGroup.defaults.set(hearts, forKey: "lovio.hearts.bonus")
        let pushed = await WidgetServer.send("heart_tap")
        WidgetOutbox.enqueue(pushed ? "heart_tap_synced" : "heart_tap")
        return .result()
    }
}

struct RevealSecretIntent: AppIntent {
    static let title: LocalizedStringResource = "Reveal Secret Message"

    func perform() async throws -> some IntentResult {
        let key = "lovio.secret.revealed"
        AppGroup.defaults.set(!AppGroup.defaults.bool(forKey: key), forKey: key)
        return .result()
    }
}

// MARK: - Shared widget chrome

struct WidgetBackground: View {
    var colors: [Color] = [Lovio.Palette.plum, Lovio.Palette.midnight]
    var body: some View {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension View {
    func lovioWidgetContainer(_ colors: [Color] = [Lovio.Palette.plum, Lovio.Palette.midnight]) -> some View {
        containerBackground(for: .widget) { WidgetBackground(colors: colors) }
            // Match whatever language the app resolved to (EN/FR/DE/KO/PT/ES,
            // English fallback) so relative countdowns ("in 11 days") never
            // show up in an unsupported device language next to English text.
            .environment(\.locale, Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en"))
    }
}
