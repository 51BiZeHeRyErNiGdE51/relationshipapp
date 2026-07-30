import Foundation

// MARK: - Demo backend
//
// A complete in-memory backend used for previews, UI development and when no
// Firebase configuration is bundled. Seeded with a believable couple so every
// screen renders rich content on first launch.

public actor DemoStore {
    public static let shared = DemoStore()

    let me = UserProfile(id: "user_alex", displayName: "Alex Rivera")
    let partner = UserProfile(id: "user_sam", displayName: "Sam Chen")

    var relationship: Relationship
    var journal: [JournalEntry]
    var moods: [MoodEntry]
    var dates: [SpecialDate]
    var bucket: [BucketListItem]
    var milestones: [Milestone]
    var notes: [SharedNote]
    var events: [RelationshipEvent] = []
    var answers: [String: [QuestionAnswer]] = [:]   // questionID -> answers
    var premiumPurchaser: UserID?

    init() {
        let anniversary = Calendar.current.date(byAdding: .day, value: -512, to: .now)!
        relationship = Relationship(
            id: "rel_demo", status: .active,
            memberIDs: ["user_alex", "user_sam"], createdBy: "user_alex",
            inviteCode: InviteCode(value: "LVQ7R3"), anniversary: anniversary,
            streak: Streak(current: 23, best: 41, lastCompletedDayKey: nil),
            xp: 3860, loveScore: 87,
            companion: CompanionState(kind: .loveGarden, growth: 64, stage: 3))

        let day: TimeInterval = 86_400
        journal = [
            JournalEntry(authorID: "user_sam", title: "Sunset picnic at the pier",
                         body: "You brought the bad wine and the good playlist. Perfect evening.",
                         media: [JournalMedia(kind: .photo)], locationName: "Santa Monica Pier",
                         reactions: ["user_alex": "🥹"], createdAt: .now.addingTimeInterval(-3 * day)),
            JournalEntry(authorID: "user_alex", title: "First attempt at ramen night",
                         body: "Broth took 6 hours. Worth every minute of you laughing at my apron.",
                         media: [JournalMedia(kind: .photo), JournalMedia(kind: .voice, durationSeconds: 34)],
                         reactions: ["user_sam": "😂"], commentCount: 2,
                         createdAt: .now.addingTimeInterval(-9 * day)),
            JournalEntry(authorID: "user_sam", title: "Rainy Sunday reading",
                         body: "Two books, one blanket, zero plans.",
                         createdAt: .now.addingTimeInterval(-16 * day)),
        ]

        moods = [
            MoodEntry(authorID: "user_sam", mood: .loved, energy: 3, stress: 2, loveMeter: 5,
                      note: "Long day but thinking of the weekend", loggedAt: .now.addingTimeInterval(-3600)),
            MoodEntry(authorID: "user_alex", mood: .happy, energy: 4, stress: 2, loveMeter: 4,
                      loggedAt: .now.addingTimeInterval(-7200)),
        ]

        dates = [
            SpecialDate(title: "Weekend in Rome", kind: .trip,
                        date: .now.addingTimeInterval(12 * day), createdBy: "user_alex"),
            SpecialDate(title: "Sam's Birthday", kind: .birthday,
                        date: .now.addingTimeInterval(34 * day), repeatsYearly: true, createdBy: "user_alex"),
            SpecialDate(title: "Anniversary", kind: .anniversary,
                        date: anniversary, repeatsYearly: true, createdBy: "user_sam"),
            SpecialDate(title: "Date night — that new jazz bar", kind: .date,
                        date: .now.addingTimeInterval(4 * day), createdBy: "user_sam"),
        ]

        bucket = [
            BucketListItem(title: "See the northern lights", category: .dreams, createdBy: "user_sam"),
            BucketListItem(title: "Omakase at Shirube", category: .restaurants, createdBy: "user_alex"),
            BucketListItem(title: "Japan in cherry blossom season", category: .countries, createdBy: "user_sam"),
            BucketListItem(title: "Cook every dish from Chef's Table", category: .dateIdeas, createdBy: "user_alex"),
            BucketListItem(title: "Before Sunrise trilogy marathon", category: .movies,
                           isCompleted: true, completedAt: .now.addingTimeInterval(-40 * day), createdBy: "user_sam"),
        ]

        milestones = [
            Milestone(title: "First met", emoji: "✨", date: anniversary.addingTimeInterval(-30 * day),
                      note: "Friend's rooftop party. You hated my playlist."),
            Milestone(title: "First kiss", emoji: "💋", date: anniversary),
            Milestone(title: "First trip together", emoji: "🏔️", date: anniversary.addingTimeInterval(90 * day),
                      note: "Big Sur. The tent leaked."),
            Milestone(title: "Moved in together", emoji: "🏡", date: anniversary.addingTimeInterval(365 * day)),
        ]

        notes = [
            SharedNote(title: "Groceries", items: [
                ChecklistItem(text: "Oat milk"), ChecklistItem(text: "Basil"),
                ChecklistItem(text: "That chili oil you like", isDone: true),
            ], isPinned: true, updatedBy: "user_sam"),
            SharedNote(title: "Rome packing list", items: [
                ChecklistItem(text: "Passports"), ChecklistItem(text: "Camera"),
                ChecklistItem(text: "Comfortable shoes"),
            ], updatedBy: "user_alex"),
            SharedNote(title: "Gift ideas for Sam", body: "Film camera · pottery class · vinyl of our first-dance song",
                       isPrivate: true, updatedBy: "user_alex"),
        ]

        // Partner already answered today's question — classic "come back" hook.
        let q = QuestionBank.question(for: DayKey.today())
        answers[q.id] = [QuestionAnswer(questionID: q.id, authorID: "user_sam",
                                        text: "The way you narrate the dog's thoughts on our walks.")]
    }

    // Mutating helpers used by the demo services

    func setRelationship(_ r: Relationship) { relationship = r }
    func addJournal(_ e: JournalEntry) { journal.insert(e, at: 0) }
    func removeJournal(_ id: String) { journal.removeAll { $0.id == id } }
    func reactJournal(_ id: String, user: UserID, emoji: String) {
        guard let i = journal.firstIndex(where: { $0.id == id }) else { return }
        journal[i].reactions[user] = emoji
    }
    func addMood(_ m: MoodEntry) { moods.insert(m, at: 0) }
    func saveDate(_ d: SpecialDate) {
        dates.removeAll { $0.id == d.id }; dates.append(d)
    }
    func removeDate(_ id: String) { dates.removeAll { $0.id == id } }
    func saveBucket(_ b: BucketListItem) {
        bucket.removeAll { $0.id == b.id }; bucket.append(b)
    }
    func saveMilestone(_ m: Milestone) {
        milestones.removeAll { $0.id == m.id }; milestones.append(m)
    }
    func saveNote(_ n: SharedNote) {
        notes.removeAll { $0.id == n.id }; notes.insert(n, at: 0)
    }
    func removeNote(_ id: String) { notes.removeAll { $0.id == id } }
    func addEvent(_ e: RelationshipEvent) { events.append(e) }
    func addAnswer(_ a: QuestionAnswer) { answers[a.questionID, default: []].append(a) }
    func setPremiumPurchaser(_ u: UserID?) { premiumPurchaser = u }
}

// MARK: - Question bank

public enum QuestionBank {
    /// Deterministic daily rotation: same question for both partners on a given day.
    public static func question(for dayKey: String) -> DailyQuestion {
        let index = abs(dayKey.hashValue) % all.count
        var q = all[index]
        q = DailyQuestion(id: "q_\(dayKey)", text: q.text, category: q.category,
                          dayKey: dayKey, isPremium: q.isPremium)
        return q
    }

    public static let all: [DailyQuestion] = {
        func q(_ text: String, _ cat: QuestionCategory, premium: Bool = false) -> DailyQuestion {
            DailyQuestion(text: text, category: cat, dayKey: "", isPremium: premium)
        }
        return [
            q("What tiny moment with me do you replay in your head?", .romantic),
            q("If we swapped phones for a day, what would embarrass me most?", .funny),
            q("What's one thing you've never told anyone — even me?", .deep),
            q("Where should we wake up on our 10th anniversary?", .future),
            q("What's a dream you shelved that we should un-shelve together?", .dreams),
            q("If money vanished as a concept, how would our week look?", .money),
            q("Window or aisle — and defend your honor.", .travel),
            q("What's one thing your parents did that you'd do differently?", .kids),
            q("When do you feel most heard by me?", .communication),
            q("What's the best way for me to say sorry to you?", .conflict),
            q("What's one goal we should finish before the year ends?", .goals),
            q("What makes you feel most loved: words, time, help, gifts, or touch?", .loveLanguages),
            q("Which family tradition do you want us to keep forever?", .family),
            q("What habit of mine secretly makes you smile?", .habits),
            q("If your career had a plan B you'd actually enjoy, what is it?", .career),
            q("What value would you never compromise, even for me?", .values),
            q("What's the weirdest thing you find attractive about me?", .funny),
            q("What are you afraid to ask me?", .deep, premium: true),
            q("Describe our first kiss from your point of view.", .romantic, premium: true),
            q("What should we absolutely NOT do in front of my parents?", .funny),
            q("Which city could you imagine us living in for a year?", .travel),
            q("What did today teach you about us?", .deep),
        ]
    }()
}

// MARK: - Demo service implementations

public struct DemoAuthService: AuthService {
    public init() {}
    public func currentUser() async -> AuthenticatedUser? {
        AuthenticatedUser(id: "user_alex", displayName: "Alex Rivera", email: "alex@demo.lovio")
    }
    public func signIn(with provider: AuthProviderKind) async throws -> AuthenticatedUser {
        AuthenticatedUser(id: "user_alex", displayName: "Alex Rivera", email: "alex@demo.lovio")
    }
    public func signOut() async throws {}
    public func deleteAccount() async throws {}
}

public struct DemoRelationshipService: RelationshipService {
    public init() {}
    public func currentRelationship(for user: UserID) async throws -> Relationship? {
        await DemoStore.shared.relationship
    }
    public func createRelationship(creator: UserID, anniversary: Date?) async throws -> Relationship {
        var r = Relationship(memberIDs: [creator], createdBy: creator, anniversary: anniversary)
        r.status = .pendingPartner
        await DemoStore.shared.setRelationship(r)
        return r
    }
    public func joinRelationship(code: String, joiner: UserID) async throws -> Relationship {
        var r = await DemoStore.shared.relationship
        guard r.inviteCode?.value.caseInsensitiveCompare(code.replacingOccurrences(of: "-", with: "")) == .orderedSame
        else { throw LovioError.invalidInviteCode }
        if !r.memberIDs.contains(joiner) { r.memberIDs.append(joiner) }
        r.status = .active
        await DemoStore.shared.setRelationship(r)
        return r
    }
    public func endRelationship(_ id: RelationshipID, endedBy: UserID) async throws {
        var r = await DemoStore.shared.relationship
        r.status = .ended
        r.endedAt = .now
        await DemoStore.shared.setRelationship(r)
    }
    public func updateAnniversary(_ id: RelationshipID, date: Date) async throws {
        var r = await DemoStore.shared.relationship
        r.anniversary = date
        await DemoStore.shared.setRelationship(r)
    }
    public func profile(for user: UserID) async throws -> UserProfile? {
        let store = DemoStore.shared
        return user == store.me.id ? store.me : store.partner
    }
    public func updateProfile(_ profile: UserProfile) async throws {}
    public func record(event: RelationshipEvent, relationship: RelationshipID) async throws {
        await DemoStore.shared.addEvent(event)
    }
    public func updateGamification(_ relationship: Relationship) async throws {
        await DemoStore.shared.setRelationship(relationship)
    }
}

public struct DemoQuestionService: QuestionService {
    public init() {}

    public func todayState(relationship: RelationshipID, me: UserID) async throws -> DailyQuestionState {
        let q = QuestionBank.question(for: DayKey.today())
        let answers = await DemoStore.shared.answers[q.id] ?? []
        return makeState(q, answers: answers, me: me)
    }

    public func submitAnswer(_ text: String, question: DailyQuestion,
                             relationship: RelationshipID, author: UserID) async throws -> DailyQuestionState {
        let answer = QuestionAnswer(questionID: question.id, authorID: author, text: text)
        await DemoStore.shared.addAnswer(answer)
        let answers = await DemoStore.shared.answers[question.id] ?? []
        return makeState(question, answers: answers, me: author)
    }

    public func history(relationship: RelationshipID, limit: Int) async throws -> [DailyQuestionState] {
        // Fabricate a few past revealed days for the archive UI.
        (1...min(limit, 6)).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: .now)!
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            let key = f.string(from: date)
            let q = QuestionBank.question(for: key)
            return DailyQuestionState(
                question: q,
                myAnswer: QuestionAnswer(questionID: q.id, authorID: "user_alex", text: "…", answeredAt: date),
                partnerHasAnswered: true,
                revealedAnswers: [
                    QuestionAnswer(questionID: q.id, authorID: "user_alex", text: "Honestly, our kitchen dance breaks.", answeredAt: date),
                    QuestionAnswer(questionID: q.id, authorID: "user_sam", text: "That you always warm my side of the bed first.", answeredAt: date),
                ])
        }
    }

    private func makeState(_ q: DailyQuestion, answers: [QuestionAnswer], me: UserID) -> DailyQuestionState {
        let mine = answers.first { $0.authorID == me }
        let partners = answers.first { $0.authorID != me }
        return DailyQuestionState(
            question: q,
            myAnswer: mine,
            partnerHasAnswered: partners != nil,
            revealedAnswers: (mine != nil && partners != nil) ? answers : [])
    }
}

public struct DemoJournalService: JournalService {
    public init() {}
    public func entries(relationship: RelationshipID) async throws -> [JournalEntry] {
        await DemoStore.shared.journal
    }
    public func add(_ entry: JournalEntry, relationship: RelationshipID) async throws {
        await DemoStore.shared.addJournal(entry)
    }
    public func react(entryID: String, relationship: RelationshipID, user: UserID, emoji: String) async throws {
        await DemoStore.shared.reactJournal(entryID, user: user, emoji: emoji)
    }
    public func delete(entryID: String, relationship: RelationshipID) async throws {
        await DemoStore.shared.removeJournal(entryID)
    }
}

public struct DemoMoodService: MoodService {
    public init() {}
    public func latestMoods(relationship: RelationshipID) async throws -> [UserID: MoodEntry] {
        let moods = await DemoStore.shared.moods
        var latest: [UserID: MoodEntry] = [:]
        for m in moods where latest[m.authorID] == nil { latest[m.authorID] = m }
        return latest
    }
    public func log(_ entry: MoodEntry, relationship: RelationshipID) async throws {
        await DemoStore.shared.addMood(entry)
    }
    public func history(relationship: RelationshipID, days: Int) async throws -> [MoodEntry] {
        await DemoStore.shared.moods
    }
}

public struct DemoPlannerService: PlannerService {
    public init() {}
    public func specialDates(relationship: RelationshipID) async throws -> [SpecialDate] {
        await DemoStore.shared.dates.sorted { $0.daysUntil < $1.daysUntil }
    }
    public func save(_ date: SpecialDate, relationship: RelationshipID) async throws {
        await DemoStore.shared.saveDate(date)
    }
    public func deleteDate(id: String, relationship: RelationshipID) async throws {
        await DemoStore.shared.removeDate(id)
    }
    public func bucketList(relationship: RelationshipID) async throws -> [BucketListItem] {
        await DemoStore.shared.bucket
    }
    public func save(_ item: BucketListItem, relationship: RelationshipID) async throws {
        await DemoStore.shared.saveBucket(item)
    }
    public func milestones(relationship: RelationshipID) async throws -> [Milestone] {
        await DemoStore.shared.milestones.sorted { $0.date < $1.date }
    }
    public func save(_ milestone: Milestone, relationship: RelationshipID) async throws {
        await DemoStore.shared.saveMilestone(milestone)
    }
    public func notes(relationship: RelationshipID) async throws -> [SharedNote] {
        await DemoStore.shared.notes.sorted { ($0.isPinned ? 0 : 1, $1.updatedAt) < ($1.isPinned ? 0 : 1, $0.updatedAt) }
    }
    public func save(_ note: SharedNote, relationship: RelationshipID) async throws {
        await DemoStore.shared.saveNote(note)
    }
    public func deleteNote(id: String, relationship: RelationshipID) async throws {
        await DemoStore.shared.removeNote(id)
    }
}

public struct DemoPremiumService: PremiumService {
    public init() {}

    public func premiumState(relationship: Relationship?, me: UserID) async -> PremiumState {
        guard let purchaser = await DemoStore.shared.premiumPurchaser else { return .free }
        let members = relationship?.memberIDs ?? [me]
        guard members.contains(purchaser) else { return .free }
        return PremiumState(
            isPremium: true,
            inheritedFromPartner: purchaser != me,
            entitlement: PremiumEntitlement(purchaserID: purchaser, productID: "lovio_yearly",
                                            expiresAt: .now.addingTimeInterval(86_400 * 365)))
    }

    public func offers() async throws -> [PaywallOffer] {
        [
            PaywallOffer(id: "lovio_yearly", title: "Yearly", monthlyEquivalent: 4.99,
                         totalPrice: 59.99, currencyCode: "USD", trialDays: 7, isFeatured: true),
            PaywallOffer(id: "lovio_monthly", title: "Monthly", monthlyEquivalent: 9.99,
                         totalPrice: 9.99, currencyCode: "USD", trialDays: 0, isFeatured: false),
        ]
    }

    public func secondaryOffer() async throws -> PaywallOffer? {
        PaywallOffer(id: "lovio_yearly_offer", title: "Yearly — 50% off",
                     monthlyEquivalent: 2.50, totalPrice: 29.99,
                     currencyCode: "USD", trialDays: 0, isFeatured: true)
    }

    public func purchase(offerID: String, me: UserID, relationship: RelationshipID?) async throws -> PremiumState {
        await DemoStore.shared.setPremiumPurchaser(me)
        return PremiumState(isPremium: true,
                            entitlement: PremiumEntitlement(purchaserID: me, productID: offerID,
                                                            expiresAt: .now.addingTimeInterval(86_400 * 365)))
    }

    public func restorePurchases(me: UserID) async throws -> PremiumState {
        await premiumState(relationship: nil, me: me)
    }
}

public struct DemoAICoachService: AICoachService {
    public init() {}

    public func weeklyReport(relationship: Relationship, events: [RelationshipEvent]) async throws -> [AIInsight] {
        [
            AIInsight(title: "Your rhythm is strong",
                      body: "You answered \(min(7, max(3, events.count))) daily questions together this week — couples who answer 5+ report feeling 2× more connected.",
                      symbol: "waveform.path.ecg"),
            AIInsight(title: "Sam feels loved through time",
                      body: "Quality Time keeps showing up in Sam's answers. Your jazz bar date on Friday lands exactly right — consider making it phone-free.",
                      symbol: "clock.badge.heart"),
            AIInsight(title: "Mood dip on Wednesdays",
                      body: "Both of your energy scores drop midweek. A 10-minute evening walk together on Wednesdays could smooth the curve.",
                      symbol: "chart.line.downtrend.xyaxis"),
        ]
    }

    public func dateIdeas(relationship: Relationship) async throws -> [String] {
        ["Golden-hour photo walk, then compare shots over dessert",
         "Cook the dish from your Rome trip playlist night",
         "Bookstore date: pick a book for each other, read the first chapter aloud",
         "Sunrise drive with a thermos of the fancy coffee"]
    }

    public func conversationStarters(relationship: Relationship) async throws -> [String] {
        ["What's something I did this month that you want more of?",
         "If we designed a perfect ordinary Tuesday, what's in it?",
         "What's one adventure that scares us both — should we book it?"]
    }

    public func chat(message: String, relationship: Relationship) async throws -> String {
        "That's worth sitting with. From your recent check-ins, you both recharge in different ways — Alex through activity, Sam through quiet. Try naming which mode you're in before reacting; it turns friction into information. Want a small exercise for tonight?"
    }
}

public struct DemoExperimentsService: ExperimentsService {
    public init() {}
    public func variant(for experiment: String) -> String { "control" }
    public func refresh() async {}
}

// MARK: - Errors

public enum LovioError: LocalizedError {
    case invalidInviteCode
    case relationshipFull
    case notSignedIn
    case premiumRequired

    public var errorDescription: String? {
        switch self {
        case .invalidInviteCode: "That invite code doesn't look right. Double-check it with your partner."
        case .relationshipFull: "This relationship already has two partners."
        case .notSignedIn: "Please sign in first."
        case .premiumRequired: "This feature is part of Lovio Premium."
        }
    }
}
