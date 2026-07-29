import Foundation

// MARK: - Service contracts
//
// Every backend capability is a protocol. The app composes either the live
// Firebase/RevenueCat implementations or the seeded demo backend (used in
// previews, UI tests, and when no GoogleService-Info.plist is bundled).
//
// These contracts intentionally mirror the future REST/Android surface:
// no Apple types in signatures that touch relationship logic.

public struct AuthenticatedUser: Sendable, Equatable {
    public var id: UserID
    public var displayName: String
    public var email: String?
    public init(id: UserID, displayName: String, email: String?) {
        self.id = id
        self.displayName = displayName
        self.email = email
    }
}

public enum AuthProviderKind: String, Sendable {
    /// Default: frictionless, accountless entry. Firebase anonymous auth mints
    /// a stable UserID with zero user-facing steps. Apple/Google remain
    /// available for later account linking (device migration).
    case anonymous
    case apple, google, demo
}

public protocol AuthService: Sendable {
    /// Currently signed-in user, if any (restored session).
    func currentUser() async -> AuthenticatedUser?
    func signIn(with provider: AuthProviderKind) async throws -> AuthenticatedUser
    func signOut() async throws
    func deleteAccount() async throws
}

// MARK: Relationship

public protocol RelationshipService: Sendable {
    /// The active or pending relationship for this user, if any.
    func currentRelationship(for user: UserID) async throws -> Relationship?
    /// Creates a pending relationship and returns it with a fresh invite code.
    func createRelationship(creator: UserID, anniversary: Date?) async throws -> Relationship
    /// Partner B redeems A's code. Fails if code is invalid or relationship full.
    func joinRelationship(code: String, joiner: UserID) async throws -> Relationship
    func endRelationship(_ id: RelationshipID, endedBy: UserID) async throws
    func updateAnniversary(_ id: RelationshipID, date: Date) async throws
    func profile(for user: UserID) async throws -> UserProfile?
    func updateProfile(_ profile: UserProfile) async throws

    /// Append to the relationship graph + apply gamification side effects.
    func record(event: RelationshipEvent, relationship: RelationshipID) async throws
    /// Persist mutated gamification state (streak / xp / love score / companion).
    func updateGamification(_ relationship: Relationship) async throws
}

// MARK: Content

public protocol QuestionService: Sendable {
    func todayState(relationship: RelationshipID, me: UserID) async throws -> DailyQuestionState
    func submitAnswer(_ text: String, question: DailyQuestion,
                      relationship: RelationshipID, author: UserID) async throws -> DailyQuestionState
    func history(relationship: RelationshipID, limit: Int) async throws -> [DailyQuestionState]
}

public protocol JournalService: Sendable {
    func entries(relationship: RelationshipID) async throws -> [JournalEntry]
    func add(_ entry: JournalEntry, relationship: RelationshipID) async throws
    func react(entryID: String, relationship: RelationshipID, user: UserID, emoji: String) async throws
    func delete(entryID: String, relationship: RelationshipID) async throws
}

public protocol MoodService: Sendable {
    func latestMoods(relationship: RelationshipID) async throws -> [UserID: MoodEntry]
    func log(_ entry: MoodEntry, relationship: RelationshipID) async throws
    func history(relationship: RelationshipID, days: Int) async throws -> [MoodEntry]
}

public protocol PlannerService: Sendable {
    func specialDates(relationship: RelationshipID) async throws -> [SpecialDate]
    func save(_ date: SpecialDate, relationship: RelationshipID) async throws
    func deleteDate(id: String, relationship: RelationshipID) async throws

    func bucketList(relationship: RelationshipID) async throws -> [BucketListItem]
    func save(_ item: BucketListItem, relationship: RelationshipID) async throws
    func milestones(relationship: RelationshipID) async throws -> [Milestone]
    func save(_ milestone: Milestone, relationship: RelationshipID) async throws

    func notes(relationship: RelationshipID) async throws -> [SharedNote]
    func save(_ note: SharedNote, relationship: RelationshipID) async throws
    func deleteNote(id: String, relationship: RelationshipID) async throws
}

// MARK: Premium

/// Premium is a property of the RELATIONSHIP, anchored to the purchaser.
public struct PremiumState: Sendable, Equatable {
    public var isPremium: Bool
    /// True when premium comes from the partner's purchase.
    public var inheritedFromPartner: Bool
    public var entitlement: PremiumEntitlement?

    public init(isPremium: Bool, inheritedFromPartner: Bool = false,
                entitlement: PremiumEntitlement? = nil) {
        self.isPremium = isPremium
        self.inheritedFromPartner = inheritedFromPartner
        self.entitlement = entitlement
    }

    public static let free = PremiumState(isPremium: false)
}

public struct PaywallOffer: Sendable, Identifiable, Equatable {
    public var id: String              // store product id
    public var title: String           // "Yearly"
    public var monthlyEquivalent: Decimal
    public var totalPrice: Decimal
    public var currencyCode: String
    public var trialDays: Int
    public var isFeatured: Bool

    public init(id: String, title: String, monthlyEquivalent: Decimal, totalPrice: Decimal,
                currencyCode: String, trialDays: Int, isFeatured: Bool) {
        self.id = id
        self.title = title
        self.monthlyEquivalent = monthlyEquivalent
        self.totalPrice = totalPrice
        self.currencyCode = currencyCode
        self.trialDays = trialDays
        self.isFeatured = isFeatured
    }

    /// The core Lovio pricing frame: price ÷ weeks ÷ 2 partners.
    /// "$9.99/month" becomes "only $1.25 per week per person".
    public var perWeekPerPerson: Decimal {
        (monthlyEquivalent / Decimal(4.0)) / Decimal(2)
    }

    public func formattedPerWeekPerPerson(locale: Locale = .current) -> String {
        perWeekPerPerson.formatted(.currency(code: currencyCode).locale(locale).precision(.fractionLength(2)))
    }
}

public protocol PremiumService: Sendable {
    /// Resolves premium for a relationship: active if EITHER member holds
    /// an active entitlement. Purchaser keeps premium across relationships.
    func premiumState(relationship: Relationship?, me: UserID) async -> PremiumState
    func offers() async throws -> [PaywallOffer]
    func purchase(offerID: String, me: UserID, relationship: RelationshipID?) async throws -> PremiumState
    func restorePurchases(me: UserID) async throws -> PremiumState
}

// MARK: AI

public struct AIInsight: Sendable, Identifiable {
    public var id: String
    public var title: String
    public var body: String
    public var symbol: String
    public init(id: String = UUID().uuidString, title: String, body: String, symbol: String) {
        self.id = id
        self.title = title
        self.body = body
        self.symbol = symbol
    }
}

public protocol AICoachService: Sendable {
    /// Weekly report generated from the relationship graph.
    func weeklyReport(relationship: Relationship, events: [RelationshipEvent]) async throws -> [AIInsight]
    func dateIdeas(relationship: Relationship) async throws -> [String]
    func conversationStarters(relationship: Relationship) async throws -> [String]
    func chat(message: String, relationship: Relationship) async throws -> String
}

// MARK: Analytics & Experiments

public protocol AnalyticsClient: Sendable {
    func track(_ event: AnalyticsEvent)
    func setUserProperty(_ value: String?, forName: String)
}

public protocol ExperimentsService: Sendable {
    /// Remote-config backed variant lookup, e.g. "paywall_headline" → "b".
    func variant(for experiment: String) -> String
    func refresh() async
}
