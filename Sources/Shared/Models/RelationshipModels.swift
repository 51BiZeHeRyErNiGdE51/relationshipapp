import Foundation

// MARK: - Platform-independent identifiers
//
// Relationship logic must never depend on platform concepts (Apple user IDs,
// device tokens, StoreKit transaction IDs). All identifiers are opaque strings
// minted by the backend so Android and iOS clients interoperate freely.

public typealias UserID = String
public typealias RelationshipID = String

/// A short human-friendly code one partner shares with the other to pair.
/// Format: 6 characters, unambiguous alphabet (no 0/O/1/I).
public struct InviteCode: Codable, Hashable, Sendable {
    public let value: String

    public init(value: String) { self.value = value }

    public static func generate() -> InviteCode {
        let alphabet = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        return InviteCode(value: String((0..<6).map { _ in alphabet.randomElement()! }))
    }

    public var display: String {
        let v = value
        guard v.count == 6 else { return v }
        return "\(v.prefix(3))-\(v.suffix(3))"
    }
}

// MARK: - User

public struct UserProfile: Codable, Identifiable, Hashable, Sendable {
    public var id: UserID
    public var displayName: String
    public var avatarURL: URL?
    public var birthday: Date?
    /// "ios" | "android" | "web" — informational only, never used in logic.
    public var lastSeenPlatform: String
    public var lastActiveAt: Date
    public var fcmTokens: [String]
    public var loveLanguage: LoveLanguage?

    public init(id: UserID, displayName: String, avatarURL: URL? = nil,
                birthday: Date? = nil, lastSeenPlatform: String = "ios",
                lastActiveAt: Date = .now, fcmTokens: [String] = [],
                loveLanguage: LoveLanguage? = nil) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.birthday = birthday
        self.lastSeenPlatform = lastSeenPlatform
        self.lastActiveAt = lastActiveAt
        self.fcmTokens = fcmTokens
        self.loveLanguage = loveLanguage
    }

    public var initials: String {
        displayName.split(separator: " ").compactMap { $0.first.map(String.init) }
            .prefix(2).joined().uppercased()
    }
}

public enum LoveLanguage: String, Codable, CaseIterable, Sendable {
    case wordsOfAffirmation = "words_of_affirmation"
    case qualityTime = "quality_time"
    case actsOfService = "acts_of_service"
    case gifts = "gifts"
    case physicalTouch = "physical_touch"

    public var title: String {
        switch self {
        case .wordsOfAffirmation: "Words of Affirmation"
        case .qualityTime: "Quality Time"
        case .actsOfService: "Acts of Service"
        case .gifts: "Receiving Gifts"
        case .physicalTouch: "Physical Touch"
        }
    }
}

// MARK: - Relationship

public enum RelationshipStatus: String, Codable, Sendable {
    /// Created by one partner, waiting for the other to redeem the invite code.
    case pendingPartner = "pending_partner"
    case active
    /// Ended by either partner. Premium stays with the purchaser (see PremiumEntitlement).
    case ended
}

public struct Relationship: Codable, Identifiable, Hashable, Sendable {
    public var id: RelationshipID
    public var status: RelationshipStatus
    public var memberIDs: [UserID]          // exactly 1 while pending, 2 when active
    public var createdBy: UserID
    public var inviteCode: InviteCode?
    public var anniversary: Date?           // "together since"
    public var createdAt: Date
    public var endedAt: Date?

    // Gamification state lives on the relationship, not the individual.
    public var streak: Streak
    public var xp: Int
    public var loveScore: Int               // 0–100 rolling health score
    public var companion: CompanionState

    public init(id: RelationshipID = UUID().uuidString,
                status: RelationshipStatus = .pendingPartner,
                memberIDs: [UserID],
                createdBy: UserID,
                inviteCode: InviteCode? = .generate(),
                anniversary: Date? = nil,
                createdAt: Date = .now,
                endedAt: Date? = nil,
                streak: Streak = Streak(),
                xp: Int = 0,
                loveScore: Int = 50,
                companion: CompanionState = CompanionState()) {
        self.id = id
        self.status = status
        self.memberIDs = memberIDs
        self.createdBy = createdBy
        self.inviteCode = inviteCode
        self.anniversary = anniversary
        self.createdAt = createdAt
        self.endedAt = endedAt
        self.streak = streak
        self.xp = xp
        self.loveScore = loveScore
        self.companion = companion
    }

    public func partnerID(of user: UserID) -> UserID? {
        memberIDs.first { $0 != user }
    }

    public var daysTogether: Int {
        guard let anniversary else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: anniversary, to: .now).day ?? 0)
    }

    /// Days until the next yearly anniversary (0 = today 🎉), nil when unset.
    public var daysUntilNextAnniversary: Int? {
        guard let anniversary else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let components = cal.dateComponents([.month, .day], from: anniversary)
        if cal.dateComponents([.month, .day], from: today) == components { return 0 }
        guard let next = cal.nextDate(after: today, matching: components,
                                      matchingPolicy: .nextTimePreservingSmallerComponents)
        else { return nil }
        return cal.dateComponents([.day], from: today, to: next).day
    }

    public var level: Int { 1 + xp / 500 }
    public var xpIntoLevel: Int { xp % 500 }
}

// MARK: - Premium (belongs to the RELATIONSHIP, anchored to a purchaser)
//
// Person A purchases → entitlement document references purchaserID.
// While A is in an active relationship, the whole relationship is premium.
// If the relationship ends, premium follows A into their next relationship.

public struct PremiumEntitlement: Codable, Hashable, Sendable {
    public var purchaserID: UserID
    public var productID: String
    public var expiresAt: Date?
    public var isInGracePeriod: Bool
    public var willRenew: Bool

    public init(purchaserID: UserID, productID: String, expiresAt: Date?,
                isInGracePeriod: Bool = false, willRenew: Bool = true) {
        self.purchaserID = purchaserID
        self.productID = productID
        self.expiresAt = expiresAt
        self.isInGracePeriod = isInGracePeriod
        self.willRenew = willRenew
    }

    public var isActive: Bool {
        if isInGracePeriod { return true }
        guard let expiresAt else { return true } // lifetime
        return expiresAt > .now
    }
}

// MARK: - Relationship Graph event
//
// Every meaningful interaction is appended as an event. This is the substrate
// for AI insights, love score, streaks and analytics — one write, many readers.

public enum RelationshipEventKind: String, Codable, Sendable {
    case questionAnswered = "question_answered"
    case journalEntryAdded = "journal_entry_added"
    case moodLogged = "mood_logged"
    case missYouSent = "miss_you_sent"
    case heartTap = "heart_tap"
    case dateCompleted = "date_completed"
    case bucketItemCompleted = "bucket_item_completed"
    case gamePlayed = "game_played"
    case milestoneAdded = "milestone_added"
    case widgetInteraction = "widget_interaction"
    case widgetNoteSent = "widget_note_sent"
    case widgetPhotoSent = "widget_photo_sent"
    case appOpened = "app_opened"
}

public struct RelationshipEvent: Codable, Identifiable, Sendable {
    public var id: String
    public var kind: RelationshipEventKind
    public var actorID: UserID
    public var occurredAt: Date
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, kind: RelationshipEventKind,
                actorID: UserID, occurredAt: Date = .now,
                metadata: [String: String] = [:]) {
        self.id = id
        self.kind = kind
        self.actorID = actorID
        self.occurredAt = occurredAt
        self.metadata = metadata
    }
}
