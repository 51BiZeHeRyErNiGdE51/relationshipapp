import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - App Group bridge
//
// The app is the single writer; the widget extension is a reader.
// Every meaningful state change publishes a fresh snapshot + reloads timelines,
// so widgets feel alive without the app being opened.

public enum AppGroup {
    public static let identifier = "group.com.bsekapps.lovio"
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
    private static let snapshotKey = "lovio.widget.snapshot.v1"

    public static func save(_ snapshot: WidgetSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    public static func loadSnapshot() -> WidgetSnapshot {
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .placeholder }
        return snapshot
    }
}

/// Everything widgets need, denormalized into one codable blob.
public struct WidgetSnapshot: Codable, Sendable {
    public var myName: String
    public var partnerName: String
    public var myInitials: String
    public var partnerInitials: String

    public var daysTogether: Int
    public var streakDays: Int
    public var loveScore: Int
    public var isPremium: Bool

    public var todayQuestion: String?
    public var questionAnsweredByMe: Bool
    public var questionAnsweredByPartner: Bool

    public var myMood: String?          // emoji
    public var partnerMood: String?     // emoji
    public var myEnergy: Int
    public var partnerEnergy: Int

    public var partnerBatteryPercent: Int?
    public var distanceKilometers: Double?
    public var daysSinceLastMeeting: Int?
    public var bothRecentlyActive: Bool

    public var nextEventTitle: String?
    public var nextEventDate: Date?

    public var latestNote: String?      // "love letter" / secret message
    public var missYouCountToday: Int
    public var heartsInJar: Int

    public var companionKind: String
    public var companionStageName: String
    public var companionGrowth: Double

    public var lastMemoryTitle: String?
    public var lastMemoryDate: Date?

    public var generatedAt: Date

    public init(myName: String, partnerName: String, myInitials: String, partnerInitials: String,
                daysTogether: Int, streakDays: Int, loveScore: Int, isPremium: Bool,
                todayQuestion: String?, questionAnsweredByMe: Bool, questionAnsweredByPartner: Bool,
                myMood: String?, partnerMood: String?, myEnergy: Int, partnerEnergy: Int,
                partnerBatteryPercent: Int?, distanceKilometers: Double?, daysSinceLastMeeting: Int?,
                bothRecentlyActive: Bool, nextEventTitle: String?, nextEventDate: Date?,
                latestNote: String?, missYouCountToday: Int, heartsInJar: Int,
                companionKind: String, companionStageName: String, companionGrowth: Double,
                lastMemoryTitle: String?, lastMemoryDate: Date?, generatedAt: Date = .now) {
        self.myName = myName
        self.partnerName = partnerName
        self.myInitials = myInitials
        self.partnerInitials = partnerInitials
        self.daysTogether = daysTogether
        self.streakDays = streakDays
        self.loveScore = loveScore
        self.isPremium = isPremium
        self.todayQuestion = todayQuestion
        self.questionAnsweredByMe = questionAnsweredByMe
        self.questionAnsweredByPartner = questionAnsweredByPartner
        self.myMood = myMood
        self.partnerMood = partnerMood
        self.myEnergy = myEnergy
        self.partnerEnergy = partnerEnergy
        self.partnerBatteryPercent = partnerBatteryPercent
        self.distanceKilometers = distanceKilometers
        self.daysSinceLastMeeting = daysSinceLastMeeting
        self.bothRecentlyActive = bothRecentlyActive
        self.nextEventTitle = nextEventTitle
        self.nextEventDate = nextEventDate
        self.latestNote = latestNote
        self.missYouCountToday = missYouCountToday
        self.heartsInJar = heartsInJar
        self.companionKind = companionKind
        self.companionStageName = companionStageName
        self.companionGrowth = companionGrowth
        self.lastMemoryTitle = lastMemoryTitle
        self.lastMemoryDate = lastMemoryDate
        self.generatedAt = generatedAt
    }

    public static let placeholder = WidgetSnapshot(
        myName: "You", partnerName: "Your Love", myInitials: "Y", partnerInitials: "L",
        daysTogether: 512, streakDays: 23, loveScore: 87, isPremium: false,
        todayQuestion: "What tiny moment with me do you replay in your head?",
        questionAnsweredByMe: false, questionAnsweredByPartner: true,
        myMood: "😊", partnerMood: "🥰", myEnergy: 4, partnerEnergy: 3,
        partnerBatteryPercent: 72, distanceKilometers: 4.2, daysSinceLastMeeting: 2,
        bothRecentlyActive: true,
        nextEventTitle: "Weekend in Rome", nextEventDate: Date().addingTimeInterval(86400 * 12),
        latestNote: "Can't stop thinking about Saturday 🤍", missYouCountToday: 3, heartsInJar: 148,
        companionKind: "love_garden", companionStageName: "Blooming", companionGrowth: 64,
        lastMemoryTitle: "Sunset picnic at the pier", lastMemoryDate: Date().addingTimeInterval(-86400 * 3))
}

// MARK: - Outbox: widget → app messages
//
// Interactive widgets (Miss You, Heart Tap) enqueue lightweight actions here;
// the app drains the outbox on next launch/foreground and syncs to the backend.

public enum WidgetOutbox {
    private static let key = "lovio.widget.outbox.v1"

    public struct Action: Codable, Sendable {
        public var kind: String       // "miss_you" | "heart_tap"
        public var at: Date
        public init(kind: String, at: Date = .now) {
            self.kind = kind
            self.at = at
        }
    }

    public static func enqueue(_ kind: String) {
        var all = pending()
        all.append(Action(kind: kind))
        if let data = try? JSONEncoder().encode(all) {
            AppGroup.defaults.set(data, forKey: key)
        }
    }

    public static func pending() -> [Action] {
        guard let data = AppGroup.defaults.data(forKey: key),
              let all = try? JSONDecoder().decode([Action].self, from: data)
        else { return [] }
        return all
    }

    public static func drain() -> [Action] {
        let all = pending()
        AppGroup.defaults.removeObject(forKey: key)
        return all
    }
}
