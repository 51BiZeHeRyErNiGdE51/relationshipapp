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
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        // Sample data ONLY in the system widget gallery — on the real home
        // screen, show the app-published snapshot or an honest empty state.
        let snapshot = context.isPreview ? .placeholder : AppGroup.loadSnapshot()
        completion(SnapshotEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = AppGroup.loadSnapshot()
        let entries = (0..<4).map { hour in
            SnapshotEntry(date: Calendar.current.date(byAdding: .hour, value: hour, to: .now)!,
                          snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Interactive intents (widget → outbox → app → backend)

struct SendMissYouIntent: AppIntent {
    static let title: LocalizedStringResource = "Send Miss You"
    static let description = IntentDescription("Sends an animated 'I miss you' to your partner.")

    func perform() async throws -> some IntentResult {
        WidgetOutbox.enqueue("miss_you")
        MissYouCounter.increment()
        return .result()
    }
}

struct HeartTapIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a Heart"
    static let description = IntentDescription("Drops a heart into your shared Love Jar.")

    func perform() async throws -> some IntentResult {
        WidgetOutbox.enqueue("heart_tap")
        var hearts = AppGroup.defaults.integer(forKey: "lovio.hearts.bonus")
        hearts += 1
        AppGroup.defaults.set(hearts, forKey: "lovio.hearts.bonus")
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
            // The app ships in English; keep relative countdowns ("in 11 days")
            // in English too instead of following the device language.
            .environment(\.locale, Locale(identifier: "en_US"))
    }
}
