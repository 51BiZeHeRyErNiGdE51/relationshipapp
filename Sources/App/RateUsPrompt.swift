import SwiftUI
import UIKit

// MARK: - Rate Us
//
// Ask for an App Store rating twice across the first two sessions, each time
// after ~1 minute on the main screen. Opens the write-review destination so
// the ask is actionable (not the silent StoreKit dialog Apple may suppress).

enum RateUsPrompt {
    static let appStoreURL = URL(
        string: "https://apps.apple.com/us/app/missuo-couples-widget-love/id6796360734?action=write-review"
    )!

    private static let sessionCountKey = "missuo.rate.sessionCount"
    private static let promptCountKey = "missuo.rate.promptCount"
    private static let promptedSessionsKey = "missuo.rate.promptedSessions"
    private static let maxSessions = 2
    private static let maxPrompts = 2
    private static let delaySeconds: UInt64 = 60

    /// Call once when the main tabs become active for this process.
    static func markSessionStarted() {
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: sessionCountKey)
        defaults.set(count + 1, forKey: sessionCountKey)
    }

    /// True when we still owe a Rate Us ask in this early-session window.
    static func shouldSchedulePrompt() -> Bool {
        let defaults = UserDefaults.standard
        let session = defaults.integer(forKey: sessionCountKey)
        let prompts = defaults.integer(forKey: promptCountKey)
        guard session >= 1, session <= maxSessions else { return false }
        guard prompts < maxPrompts else { return false }
        let prompted = Set(defaults.array(forKey: promptedSessionsKey) as? [Int] ?? [])
        return !prompted.contains(session)
    }

    static func markPromptShown() {
        let defaults = UserDefaults.standard
        let session = defaults.integer(forKey: sessionCountKey)
        defaults.set(defaults.integer(forKey: promptCountKey) + 1, forKey: promptCountKey)
        var prompted = Set(defaults.array(forKey: promptedSessionsKey) as? [Int] ?? [])
        prompted.insert(session)
        defaults.set(Array(prompted).sorted(), forKey: promptedSessionsKey)
    }

    static var delayNanoseconds: UInt64 { delaySeconds * 1_000_000_000 }

    static func openAppStore() {
        UIApplication.shared.open(appStoreURL)
    }
}
