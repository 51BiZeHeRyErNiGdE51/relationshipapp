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

    /// Written by the app so interactive widgets can talk to the backend
    /// directly (heart / miss-you pushes must fire even when the app is
    /// killed and the outbox can't drain).
    public static let relationshipIDKey = "missuo.widget.relationshipID"
    public static let userIDKey = "missuo.widget.userID"

    public static func save(_ snapshot: WidgetSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// The real app-published snapshot, or nil if the app hasn't published yet.
    public static func storedSnapshot() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Home-screen widgets NEVER show fake data: real snapshot or honest empty.
    /// (`.placeholder` is reserved for the widget-gallery preview.)
    public static func loadSnapshot() -> WidgetSnapshot {
        storedSnapshot() ?? .empty
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

    // Added after v1 — optional so older stored snapshots still decode.
    /// Nil/false → show "set your date" instead of a fake day count.
    public var hasAnniversary: Bool?
    /// Nil/false → pairing-focused empty states on partner widgets.
    public var isPaired: Bool?
    /// Days until the next yearly anniversary (0 = today 🎉).
    public var nextAnniversaryDays: Int?

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

    /// Pretty sample data — ONLY for the system widget gallery preview.
    public static let placeholder: WidgetSnapshot = {
        var s = WidgetSnapshot(
            myName: "You", partnerName: "Your Love", myInitials: "Y", partnerInitials: "L",
            daysTogether: 512, streakDays: 23, loveScore: 87, isPremium: false,
            todayQuestion: "Pineapple belongs on pizza — agree?",
            questionAnsweredByMe: false, questionAnsweredByPartner: true,
            myMood: "😊", partnerMood: "🥰", myEnergy: 4, partnerEnergy: 3,
            partnerBatteryPercent: 72, distanceKilometers: 4.2, daysSinceLastMeeting: 2,
            bothRecentlyActive: true,
            nextEventTitle: "Weekend in Rome", nextEventDate: Date().addingTimeInterval(86400 * 12),
            latestNote: "Can't stop thinking about Saturday 🤍", missYouCountToday: 3, heartsInJar: 148,
            companionKind: "love_garden", companionStageName: "Blooming", companionGrowth: 64,
            lastMemoryTitle: "Sunset picnic at the pier", lastMemoryDate: Date().addingTimeInterval(-86400 * 3))
        s.hasAnniversary = true
        s.isPaired = true
        // The system widget-gallery preview must show the widget's REAL face,
        // never the premium lock — previews aren't a paywall surface.
        s.isPremium = true
        return s
    }()

    /// What widgets render before the app has published anything real.
    public static let empty = WidgetSnapshot(
        myName: "You", partnerName: "Your Love", myInitials: "Y", partnerInitials: "L",
        daysTogether: 0, streakDays: 0, loveScore: 0, isPremium: false,
        todayQuestion: nil, questionAnsweredByMe: false, questionAnsweredByPartner: false,
        myMood: nil, partnerMood: nil, myEnergy: 0, partnerEnergy: 0,
        partnerBatteryPercent: nil, distanceKilometers: nil, daysSinceLastMeeting: nil,
        bothRecentlyActive: false, nextEventTitle: nil, nextEventDate: nil,
        latestNote: nil, missYouCountToday: 0, heartsInJar: 0,
        companionKind: "love_garden", companionStageName: "Seed", companionGrowth: 0,
        lastMemoryTitle: nil, lastMemoryDate: nil)
}

// MARK: - User-authored widget content (photo + note)
//
// Two directions, stored separately so the widgets are unambiguous:
//   .mine    → what I uploaded (shows on MY "My Polaroid" widget; also synced
//              to my partner, where it lands in THEIR .partner slot)
//   .partner → what my partner sent me (shows on my "From Your Love" widget
//              and the Secret Message widget)

public enum WidgetContent {
    public enum Slot: String, Sendable {
        case mine, partner
    }

    private static func noteKey(_ slot: Slot) -> String { "lovio.widget.note.\(slot.rawValue)" }
    private static func photoFileName(_ slot: Slot) -> String { "widget_photo_\(slot.rawValue).jpg" }

    public static func note(_ slot: Slot) -> String? {
        AppGroup.defaults.string(forKey: noteKey(slot))
    }

    public static func saveNote(_ text: String, slot: Slot) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        AppGroup.defaults.set(trimmed.isEmpty ? nil : trimmed, forKey: noteKey(slot))
        if slot == .partner {
            // A fresh note from them re-seals the Secret Message widget.
            AppGroup.defaults.removeObject(forKey: "lovio.secret.revealed")
        }
        reloadContentWidgets(slot)
    }

    public static func photoURL(_ slot: Slot) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appendingPathComponent(photoFileName(slot))
    }

    /// Expects pre-downscaled JPEG data (widgets have tight memory limits).
    public static func savePhoto(_ data: Data, slot: Slot) {
        guard let url = photoURL(slot) else { return }
        try? data.write(to: url, options: .atomic)
        AppGroup.defaults.set(Date(), forKey: "lovio.widget.photo.\(slot.rawValue).updatedAt")
        reloadContentWidgets(slot)
    }

    public static func loadPhoto(_ slot: Slot) -> Data? {
        photoURL(slot).flatMap { try? Data(contentsOf: $0) }
    }

    public static func removePhoto(_ slot: Slot) {
        if let url = photoURL(slot) {
            try? FileManager.default.removeItem(at: url)
        }
        AppGroup.defaults.removeObject(forKey: "lovio.widget.photo.\(slot.rawValue).updatedAt")
        reloadContentWidgets(slot)
    }

    public static func hasPhoto(_ slot: Slot) -> Bool {
        photoURL(slot).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// Wipe everything the ex partner left on this device (photo, secret note,
    /// sync stamps). Called when the relationship ends — locally or remotely —
    /// so "From Your Love" / Secret Message never keep an ex's content.
    public static func clearPartnerContent() {
        removePhoto(.partner)
        AppGroup.defaults.removeObject(forKey: noteKey(.partner))
        AppGroup.defaults.removeObject(forKey: "lovio.widget.note.syncedAt")
        AppGroup.defaults.removeObject(forKey: "lovio.widget.photo.syncedAt")
        AppGroup.defaults.removeObject(forKey: "lovio.secret.revealed")
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "polaroid_partner")
        WidgetCenter.shared.reloadTimelines(ofKind: "secret_message")
        #endif
    }

    /// Targeted reloads: blanket reloadAllTimelines() burns the WidgetKit
    /// refresh budget and iOS starts throttling — which shows up as "I set a
    /// photo but the widget didn't change". Only poke the affected kinds.
    private static func reloadContentWidgets(_ slot: Slot) {
        #if canImport(WidgetKit)
        switch slot {
        case .mine:
            WidgetCenter.shared.reloadTimelines(ofKind: "polaroid_mine")
        case .partner:
            WidgetCenter.shared.reloadTimelines(ofKind: "polaroid_partner")
            WidgetCenter.shared.reloadTimelines(ofKind: "secret_message")
        }
        #endif
    }
}

// MARK: - Miss You daily counter (app + widget intent both write here)

public enum MissYouCounter {
    private static let key = "lovio.missyou.day.v2"

    public static func today() -> Int {
        guard let stored = AppGroup.defaults.dictionary(forKey: key),
              stored["day"] as? String == dayString() else { return 0 }
        return stored["count"] as? Int ?? 0
    }

    public static func increment() {
        AppGroup.defaults.set(["day": dayString(), "count": today() + 1], forKey: key)
    }

    private static func dayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }
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
