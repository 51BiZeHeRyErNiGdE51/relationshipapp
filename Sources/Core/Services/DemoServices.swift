import Foundation
import FirebaseFirestore

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
    var gameAnswers: [String: [GameAnswer]] = [:]   // "gameID_promptID" -> answers
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
    func addGameAnswer(_ a: GameAnswer) {
        let key = "\(a.gameID)_\(a.promptID)"
        gameAnswers[key, default: []].removeAll { $0.authorID == a.authorID }
        gameAnswers[key, default: []].append(a)
    }
    func setPremiumPurchaser(_ u: UserID?) { premiumPurchaser = u }

    // Shared widget content (per author) + in-memory image store (demo mode)
    var widgetContent: [UserID: SharedWidgetContent] = [:]
    var imageStore: [String: Data] = [:]
    func setWidgetContent(_ c: SharedWidgetContent, author: UserID) { widgetContent[author] = c }
    func storeImage(_ data: Data, path: String) { imageStore[path] = data }
}

// MARK: - Question bank

public enum QuestionBank {
    /// Deterministic daily rotation: same question for both partners on a
    /// given day. NEVER use String.hashValue here — Swift seeds it randomly
    /// per process, which gave each partner a different daily question.
    public static func question(for dayKey: String) -> DailyQuestion {
        let seed = dayKey.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fff_ffff }
        let index = seed % all.count
        var q = all[index]
        q = DailyQuestion(id: "q_\(dayKey)", text: q.text, category: q.category,
                          dayKey: dayKey, isPremium: q.isPremium, kind: q.kind)
        return q
    }

    /// Mostly playful "who" questions — tap your name or theirs, both answers
    /// unlock together. A few thumbs statements stay for variety.
    /// English source text is the localization key (see Localizable.xcstrings).
    public static let all: [DailyQuestion] = {
        func w(_ text: String, _ cat: QuestionCategory, premium: Bool = false) -> DailyQuestion {
            DailyQuestion(text: text, category: cat, dayKey: "", isPremium: premium, kind: .who)
        }
        func t(_ text: String, _ cat: QuestionCategory, premium: Bool = false) -> DailyQuestion {
            DailyQuestion(text: text, category: cat, dayKey: "", isPremium: premium, kind: .thumbs)
        }
        return [
            // —— Who (partner A vs B) ——
            w("Who snores louder?", .funny),
            w("Who eats the last cookie without asking?", .funny),
            w("Who said \"I love you\" first?", .romantic),
            w("Who is worse at answering texts?", .communication),
            w("Who packs for a trip at the last minute?", .habits),
            w("Who would survive longer on a deserted island?", .funny),
            w("Who falls asleep first during a movie?", .habits),
            w("Who steals the blankets?", .funny),
            w("Who is the better cook?", .habits),
            w("Who cries more at movies?", .romantic),
            w("Who starts the most arguments?", .conflict),
            w("Who apologizes first after a fight?", .conflict),
            w("Who is more stubborn?", .conflict, premium: true),
            w("Who has the better music taste?", .funny),
            w("Who would get lost even with GPS?", .travel),
            w("Who spends more money shopping?", .money),
            w("Who is more romantic?", .romantic),
            w("Who plans better dates?", .romantic),
            w("Who is more likely to adopt a pet on impulse?", .family),
            w("Who is the morning person?", .habits),
            w("Who is more competitive?", .goals),
            w("Who remembers anniversaries better?", .loveLanguages),
            w("Who gives better hugs?", .loveLanguages),
            w("Who would win in a pillow fight?", .funny),
            w("Who is more likely to send a \"miss you\" first?", .romantic),
            w("Who talks more on video calls?", .communication),
            w("Who is the better driver?", .travel),
            w("Who would forget an anniversary?", .funny),
            w("Who is more adventurous with food?", .travel),
            w("Who worries more about the future?", .future),
            w("Who is better with kids?", .kids),
            w("Who would cry at the wedding?", .future),
            w("Who is more likely to quit their job for love?", .career, premium: true),
            w("Who is the big spoon?", .romantic),
            w("Who takes longer in the bathroom?", .habits),
            w("Who has the messier side of the bed?", .habits),
            w("Who is more likely to start a dance party in the kitchen?", .funny),
            w("Who is better at keeping secrets?", .deep),
            w("Who knows the other better?", .deep),
            w("Who is more likely to get us lost on vacation?", .travel),
            w("Who leaves wet towels on the floor?", .habits),
            w("Who always loses the remote?", .funny),
            w("Who is more likely to burn toast?", .habits),
            w("Who sings louder in the car?", .funny),
            w("Who takes better photos of us?", .loveLanguages),
            w("Who is more likely to cry from happiness?", .romantic),
            w("Who picks the restaurant?", .habits),
            w("Who changes the restaurant last minute?", .funny),
            w("Who is more likely to double-text?", .communication),
            w("Who leaves the dishes \"to soak\"?", .habits),
            w("Who is better at gift-giving?", .loveLanguages),
            w("Who is more likely to start a group chat?", .communication),
            w("Who would survive a horror movie?", .funny),
            w("Who is more likely to become famous?", .career),
            w("Who is more likely to adopt a plant and name it?", .funny),
            w("Who is the better listener?", .communication),
            w("Who interrupts more during stories?", .communication),
            w("Who is more likely to book a spontaneous trip?", .travel),
            w("Who overpacks for every trip?", .travel),
            w("Who underpacks and borrows everything?", .travel),
            w("Who is more likely to get sunburned first?", .travel),
            w("Who navigates better without a map?", .travel),
            w("Who is more likely to fall asleep on a flight?", .travel),
            w("Who spends more on coffee?", .money),
            w("Who is better at sticking to a budget?", .money),
            w("Who is more likely to impulse-buy online?", .money),
            w("Who remembers passwords better?", .habits),
            w("Who is more likely to lose their keys?", .habits),
            w("Who makes the bed in the morning?", .habits),
            w("Who is messier with laundry?", .habits),
            w("Who is more likely to stay up too late?", .habits),
            w("Who needs coffee before speaking?", .habits),
            w("Who is more likely to cancel plans to stay in?", .habits),
            w("Who is more social at parties?", .communication),
            w("Who leaves parties earlier?", .habits),
            w("Who is more likely to dance in public?", .funny),
            w("Who is more likely to sing karaoke?", .funny),
            w("Who tells better jokes?", .funny),
            w("Who laughs until they cry?", .funny),
            w("Who is more dramatic when sick?", .funny),
            w("Who is the better nurse when the other is sick?", .loveLanguages),
            w("Who is more likely to send a cute good-morning text?", .romantic),
            w("Who initiates more affection?", .loveLanguages),
            w("Who is more likely to plan a surprise?", .romantic),
            w("Who is worse at keeping surprises secret?", .funny),
            w("Who writes better love notes?", .loveLanguages),
            w("Who is more likely to tear up at a proposal video?", .romantic),
            w("Who is more nostalgic about old photos?", .romantic),
            w("Who says \"I love you\" more often?", .romantic),
            w("Who is more likely to start a pillow fight?", .funny),
            w("Who wins more petty arguments?", .conflict),
            w("Who needs more cool-down time after a fight?", .conflict),
            w("Who brings up old arguments more?", .conflict, premium: true),
            w("Who is better at compromising?", .conflict),
            w("Who is more likely to say sorry with food?", .conflict),
            w("Who is more conflict-avoidant?", .conflict),
            w("Who is more direct when upset?", .conflict),
            w("Who is more likely to sulk quietly?", .conflict),
            w("Who dreams bigger about our future?", .future),
            w("Who is more ready to settle down?", .future),
            w("Who would want more kids?", .kids, premium: true),
            w("Who is more likely to spoil the kids?", .kids),
            w("Who would be the stricter parent?", .kids),
            w("Who is more likely to move cities for a job?", .career),
            w("Who works later hours?", .career),
            w("Who is more ambitious at work?", .career),
            w("Who is better at work-life balance?", .career),
            w("Who would rather work from home forever?", .career),
            w("Who is closer to their family?", .family),
            w("Who calls their parents more?", .family),
            w("Who is more likely to host family holidays?", .family),
            w("Who gets along better with in-laws?", .family, premium: true),
            w("Who is more likely to start a new hobby this year?", .goals),
            w("Who sticks to New Year's resolutions longer?", .goals),
            w("Who is more likely to join a gym and actually go?", .goals),
            w("Who is more competitive in games?", .goals),
            w("Who hates losing more?", .goals),
            w("Who is more likely to binge a whole season alone?", .funny),
            w("Who picks better movies?", .habits),
            w("Who falls for spoilers first?", .funny),
            w("Who is more likely to rewatch comfort shows?", .habits),
            w("Who controls the thermostat?", .habits),
            w("Who is colder in bed?", .funny),
            w("Who steals hoodies more often?", .romantic),
            w("Who is more likely to wear the other's clothes?", .romantic),
            w("Who has the better style?", .habits),
            w("Who takes longer to get ready?", .habits),
            w("Who is more likely to be fashionably late?", .habits),
            w("Who is always early?", .habits),
            w("Who is better at small talk?", .communication),
            w("Who is more likely to overshare with strangers?", .communication),
            w("Who remembers people's names better?", .communication),
            w("Who is more likely to send voice notes?", .communication),
            w("Who writes longer texts?", .communication),
            w("Who is more likely to leave someone on read?", .communication),
            w("Who is better at reading the other's mood?", .deep),
            w("Who opens up emotionally faster?", .deep),
            w("Who needs more alone time?", .deep),
            w("Who is more likely to overthink a text?", .deep),
            w("Who trusts more easily?", .deep),
            w("Who is more jealous?", .deep, premium: true),
            w("Who is more likely to check if the other is online?", .deep),
            w("Who forgives faster?", .deep),
            w("Who holds onto feelings longer?", .deep),
            w("Who is more likely to plan our retirement fantasy?", .future),
            w("Who would rather live by the ocean?", .future),
            w("Who would rather live in a big city?", .future),
            w("Who is more likely to suggest matching tattoos?", .romantic),
            w("Who is more spontaneous?", .habits),
            w("Who is more of a planner?", .habits),
            w("Who is more likely to say yes to adventure?", .travel),
            w("Who is more likely to say \"maybe next time\"?", .travel),
            w("Who tips more generously?", .money),
            w("Who splits the bill more carefully?", .money),
            w("Who is more likely to forget a wallet?", .funny),
            w("Who is luckier?", .funny),
            w("Who is more superstitious?", .funny),
            w("Who believes in soulmates more?", .romantic),
            w("Who is more likely to write a song about us?", .romantic),
            w("Who would survive without the other for a week easier?", .deep),
            w("Who misses the other more when apart?", .romantic),
            w("Who is more likely to send a random \"thinking of you\"?", .romantic),
            w("Who is better at morning energy?", .habits),
            w("Who is better at night energy?", .habits),
            w("Who would win a cooking competition between us?", .habits),
            w("Who would win a cleaning competition between us?", .habits),
            w("Who is more likely to start decorating for holidays too early?", .funny),
            w("Who is more likely to take the holiday decorations down late?", .funny),
            w("Who is the better gift wrapper?", .loveLanguages),
            w("Who puts more thought into anniversary plans?", .loveLanguages),
            w("Who is more likely to suggest a picnic?", .romantic),
            w("Who is more likely to suggest staying in pajamas all day?", .habits),
            w("Who is more likely to order dessert?", .habits),
            w("Who finishes the other's sentences more?", .communication),
            w("Who knows the other's coffee order by heart?", .loveLanguages),
            w("Who would notice a haircut first?", .loveLanguages),
            w("Who is more likely to give a compliment in public?", .loveLanguages),
            w("Who is more likely to tease the other in public?", .funny),
            w("Who is braver with spiders?", .funny),
            w("Who is braver with heights?", .travel),
            w("Who would try skydiving first?", .travel),
            w("Who would try raw oysters first?", .travel),
            w("Who is more likely to get us upgraded somehow?", .travel),
            w("Who complains more when hungry?", .funny),
            w("Who is more likely to turn a chore into a competition?", .goals),
            w("Who is more likely to say \"I told you so\"?", .conflict),
            w("Who is more likely to become the couple that hosts everything?", .family),
            w("Who would be more emotional at our kids' graduation?", .kids, premium: true),
            w("Who is more likely to keep a shared calendar updated?", .habits),
            w("Who is more likely to forget why they walked into a room?", .funny),

            // —— Agree / Disagree ——
            t("Watching a series ahead of your partner is a crime.", .funny),
            t("Long-distance made us stronger.", .deep),
            t("Date night should be weekly, not optional.", .romantic),
            t("Phones should stay out of the bedroom.", .habits),
            t("It's okay to need a night alone sometimes.", .deep),
            t("Saying \"I'm fine\" when you're not is never okay.", .communication),
            t("Surprise visits are romantic.", .romantic),
            t("We should always celebrate small wins together.", .goals),
            t("Sharing passwords is a trust issue, not a love issue.", .deep, premium: true),
            t("Matching outfits are cute, not cringe.", .funny),
            t("A good apology matters more than a gift.", .conflict),
            t("We argue because we care, not because we're incompatible.", .conflict),
            t("Brunch counts as a personality.", .funny),
            t("It's romantic to grocery shop together.", .romantic),
            t("We should travel somewhere new every year.", .travel),
            t("Pets are practice for parenting.", .family),
            t("Honesty always beats kindness when they conflict.", .deep),
            t("Quality time beats expensive gifts.", .loveLanguages),
            t("We should have a shared savings goal.", .money),
            t("Laughing together is our strongest glue.", .romantic),
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
        guard !r.memberIDs.contains(joiner) else { throw LovioError.cantPairWithSelf }
        r.memberIDs.append(joiner)
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
    public func recentEvents(relationship: RelationshipID, limit: Int) async throws -> [RelationshipEvent] {
        Array(await DemoStore.shared.events.sorted { $0.occurredAt > $1.occurredAt }.prefix(limit))
    }
    public func updateGamification(_ relationship: Relationship) async throws {
        await DemoStore.shared.setRelationship(relationship)
    }

    public func widgetContent(relationship: RelationshipID, author: UserID) async throws -> SharedWidgetContent? {
        await DemoStore.shared.widgetContent[author]
    }
    public func saveWidgetContent(_ content: SharedWidgetContent, relationship: RelationshipID, author: UserID) async throws {
        await DemoStore.shared.setWidgetContent(content, author: author)
    }
    public func uploadImage(_ jpeg: Data, relationship: RelationshipID, fileName: String) async throws -> String {
        let path = "demo/\(relationship)/\(fileName)"
        await DemoStore.shared.storeImage(jpeg, path: path)
        return path
    }
    public func downloadImage(path: String) async throws -> Data {
        guard let data = await DemoStore.shared.imageStore[path] else {
            throw LovioError.notSignedIn // unreachable in practice
        }
        return data
    }
}

public struct DemoQuestionService: QuestionService {
    public init() {}

    public func todayState(relationship: RelationshipID, me: UserID) async throws -> DailyQuestionState {
        let q = QuestionBank.question(for: DayKey.today())
        let answers = await DemoStore.shared.answers[q.id] ?? []
        return makeState(q, answers: answers, me: me)
    }

    public func submitAnswer(_ text: String, rating: Int?, selectedUserID: UserID?,
                             question: DailyQuestion, relationship: RelationshipID,
                             author: UserID) async throws -> DailyQuestionState {
        let answer = QuestionAnswer(questionID: question.id, authorID: author, text: text,
                                    rating: rating, selectedUserID: selectedUserID,
                                    questionText: question.text)
        await DemoStore.shared.addAnswer(answer)
        let answers = await DemoStore.shared.answers[question.id] ?? []
        return makeState(question, answers: answers, me: author)
    }

    public func history(relationship: RelationshipID, limit: Int) async throws -> [DailyQuestionState] {
        // Fabricate a few past revealed days for the archive UI, with ratings
        // that match each question's format so alignment scoring has data.
        (1...min(limit, 6)).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: .now)!
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            let key = f.string(from: date)
            let q = QuestionBank.question(for: key)
            let (mine, partners): (QuestionAnswer, QuestionAnswer)
            switch q.format {
            case .who:
                let pickAlex = offset % 2 == 0
                let chosen = pickAlex ? "user_alex" : "user_sam"
                let name = pickAlex ? "Alex" : "Sam"
                mine = QuestionAnswer(questionID: q.id, authorID: "user_alex", text: name,
                                      answeredAt: date, selectedUserID: chosen, questionText: q.text)
                partners = QuestionAnswer(questionID: q.id, authorID: "user_sam", text: name,
                                          answeredAt: date, selectedUserID: chosen, questionText: q.text)
            case .thumbs:
                let agree = offset % 3 != 0
                mine = QuestionAnswer(questionID: q.id, authorID: "user_alex", text: "Agree",
                                      answeredAt: date, rating: 1, questionText: q.text)
                partners = QuestionAnswer(questionID: q.id, authorID: "user_sam",
                                          text: agree ? "Agree" : "Disagree",
                                          answeredAt: date, rating: agree ? 1 : 0, questionText: q.text)
            case .scale:
                let a = 3 + offset % 3, b = max(1, a - offset % 2)
                mine = QuestionAnswer(questionID: q.id, authorID: "user_alex", text: "\(a)/5",
                                      answeredAt: date, rating: a, questionText: q.text)
                partners = QuestionAnswer(questionID: q.id, authorID: "user_sam", text: "\(b)/5",
                                          answeredAt: date, rating: b, questionText: q.text)
            case .open:
                mine = QuestionAnswer(questionID: q.id, authorID: "user_alex",
                                      text: "Honestly, our kitchen dance breaks.",
                                      answeredAt: date, questionText: q.text)
                partners = QuestionAnswer(questionID: q.id, authorID: "user_sam",
                                          text: "That you always warm my side of the bed first.",
                                          answeredAt: date, questionText: q.text)
            }
            return DailyQuestionState(question: q, myAnswer: mine,
                                      partnerHasAnswered: true,
                                      revealedAnswers: [mine, partners])
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

public struct DemoGameService: GameService {
    public init() {}

    public func deck(game: CoupleGame, relationship: RelationshipID, me: UserID) async throws -> [GamePromptState] {
        let prompts = GameBank.prompts(for: game)
        let all = await DemoStore.shared.gameAnswers
        return prompts.map { prompt in
            let answers = all["\(game.rawValue)_\(prompt.id)"] ?? []
            return assemble(prompt, answers: answers, me: me)
        }
    }

    public func submitChoice(game: CoupleGame, prompt: GamePrompt, choice: String,
                             choiceLabel: String, relationship: RelationshipID,
                             author: UserID) async throws -> GamePromptState {
        let answer = GameAnswer(gameID: game.rawValue, promptID: prompt.id,
                                authorID: author, choice: choice, choiceLabel: choiceLabel)
        await DemoStore.shared.addGameAnswer(answer)
        let answers = await DemoStore.shared.gameAnswers["\(game.rawValue)_\(prompt.id)"] ?? []
        return assemble(prompt, answers: answers, me: author)
    }

    private func assemble(_ prompt: GamePrompt, answers: [GameAnswer], me: UserID) -> GamePromptState {
        let mine = answers.first { $0.authorID == me }
        let partner = answers.first { $0.authorID != me }
        return GamePromptState(prompt: prompt, myAnswer: mine,
                               partnerHasAnswered: partner != nil,
                               revealedAnswers: (mine != nil && partner != nil) ? answers : [])
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

    // Fake purchases: persisted locally so the premium experience survives
    // relaunches, letting both flows (paid / unpaid) be tested end-to-end
    // before RevenueCat is wired. Real StoreKit never runs.
    static let fakePurchaserKey = "missuo.fakePremium.purchaser"
    static let fakeProductKey = "missuo.fakePremium.product"

    public static func resetFakePurchase() {
        UserDefaults.standard.removeObject(forKey: fakePurchaserKey)
        UserDefaults.standard.removeObject(forKey: fakeProductKey)
    }

    public func premiumState(relationship: Relationship?, me: UserID) async -> PremiumState {
        // 1. Local fake purchase on THIS device (purchaser).
        if let purchaser = UserDefaults.standard.string(forKey: Self.fakePurchaserKey) {
            let members = relationship?.memberIDs ?? [me]
            if members.contains(purchaser) {
                let ent = PremiumEntitlement(
                    purchaserID: purchaser,
                    productID: UserDefaults.standard.string(forKey: Self.fakeProductKey) ?? "lovio_yearly",
                    expiresAt: .now.addingTimeInterval(86_400 * 365))
                // Keep the shared mirror fresh so the partner inherits.
                if let relationship { await RevenueCatPremiumService.mirror(ent, to: relationship.id) }
                return PremiumState(isPremium: true,
                                    inheritedFromPartner: purchaser != me,
                                    entitlement: ent)
            }
        }
        // 2. Partner's purchase mirrored into Firestore (other phone).
        if let relationship,
           relationship.status == .active || relationship.status == .pendingPartner,
           FirebaseBootstrap.isConfigured,
           let doc = try? await Firestore.firestore()
                .collection("relationships").document(relationship.id)
                .collection("premium").document("state").getDocument(),
           let entitlement = try? doc.data(as: PremiumEntitlement.self),
           entitlement.isActive,
           relationship.memberIDs.contains(entitlement.purchaserID) {
            return PremiumState(isPremium: true,
                                inheritedFromPartner: entitlement.purchaserID != me,
                                entitlement: entitlement)
        }
        return .free
    }

    public func offers() async throws -> [PaywallOffer] {
        [
            PaywallOffer(id: "lovio_yearly", title: "Yearly", monthlyEquivalent: 4.99,
                         totalPrice: 59.99, currencyCode: "USD", trialDays: 3, isFeatured: true),
            PaywallOffer(id: "lovio_monthly", title: "Monthly", monthlyEquivalent: 9.99,
                         totalPrice: 9.99, currencyCode: "USD", trialDays: 0, isFeatured: false),
        ]
    }

    public func secondaryOffer() async throws -> PaywallOffer? {
        PaywallOffer(id: "lovio_yearly_offer", title: "Yearly",
                     monthlyEquivalent: 2.50, totalPrice: 29.99,
                     currencyCode: "USD", trialDays: 0, isFeatured: true,
                     anchorPrice: 59.99)
    }

    public func purchase(offerID: String, me: UserID, relationship: RelationshipID?) async throws -> PremiumState {
        // Simulated App Store confirmation delay for a believable flow.
        try? await Task.sleep(for: .milliseconds(900))
        UserDefaults.standard.set(me, forKey: Self.fakePurchaserKey)
        UserDefaults.standard.set(offerID, forKey: Self.fakeProductKey)
        let entitlement = PremiumEntitlement(purchaserID: me, productID: offerID,
                                             expiresAt: .now.addingTimeInterval(86_400 * 365))
        // Critical: write the shared mirror so Partner B unlocks on their phone.
        if let relationship {
            await RevenueCatPremiumService.mirror(entitlement, to: relationship)
        }
        return PremiumState(isPremium: true, entitlement: entitlement)
    }

    public func restorePurchases(me: UserID) async throws -> PremiumState {
        await premiumState(relationship: nil, me: me)
    }
}

public struct DemoAICoachService: AICoachService {
    public init() {}

    /// Offline fallback: built ONLY from the couple's real stats — never
    /// invents names or events (an old canned version mentioned "Sam").
    public func weeklyReport(relationship: Relationship, events: [RelationshipEvent]) async throws -> [AIInsight] {
        let week = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let recent = events.filter { $0.occurredAt > week }
        let answers = recent.filter { $0.kind == .questionAnswered }.count
        let hearts = recent.filter { $0.kind == .missYouSent || $0.kind == .heartTap }.count
        let streak = relationship.streak.current

        var insights: [AIInsight] = []
        insights.append(AIInsight(
            title: streak > 0 ? "\(streak)-day streak" : "Restart your rhythm",
            body: streak > 0
                ? "You've both shown up \(streak) day\(streak == 1 ? "" : "s") in a row. Couples who keep a daily ritual report feeling noticeably closer — keep it alive with one small check-in today."
                : "Your streak reset — no guilt, it happens. One answered question or a quick mood check-in today starts it again.",
            symbol: "flame.fill"))
        insights.append(AIInsight(
            title: answers > 0 ? "\(answers) question\(answers == 1 ? "" : "s") answered" : "Try today's question",
            body: answers > 0
                ? "You answered \(answers) daily question\(answers == 1 ? "" : "s") this week. Every match (or mismatch!) you discover is a conversation you wouldn't have had otherwise."
                : "No questions answered this week. Today's takes under 10 seconds — and you get to see your partner's take once you both answer.",
            symbol: "bubble.left.and.bubble.right.fill"))
        insights.append(AIInsight(
            title: hearts > 0 ? "\(hearts) love signal\(hearts == 1 ? "" : "s") sent" : "Send a tiny signal",
            body: hearts > 0
                ? "Miss-yous and heart taps flew \(hearts) time\(hearts == 1 ? "" : "s") between you. Those tiny pings matter more across distance than grand gestures."
                : "The Miss You button takes one tap and lights up your partner's phone. Small signals, big feeling.",
            symbol: "heart.fill"))
        return insights
    }

    public func dateIdeas(relationship: Relationship) async throws -> [String] {
        ["Golden-hour photo walk, then compare shots over dessert",
         "Cook the same recipe together over a video call",
         "Bookstore date: pick a book for each other, read the first chapter aloud",
         "Sunrise drive with a thermos of the fancy coffee"]
    }

    public func conversationStarters(relationship: Relationship) async throws -> [String] {
        ["What's something I did this month that you want more of?",
         "If we designed a perfect ordinary Tuesday, what's in it?",
         "What's one adventure that scares us both — should we book it?"]
    }

    public func chat(message: String, relationship: Relationship) async throws -> String {
        "I couldn't reach the coach right now — check your connection and try again in a moment. Meanwhile: naming which mode you're in (recharging vs. connecting) before reacting turns friction into information."
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
    case cantPairWithSelf
    case relationshipFull
    case notSignedIn
    case premiumRequired
    case purchaseUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidInviteCode: "That invite code doesn't look right. Double-check it with your partner."
        case .cantPairWithSelf: "That's your own code 😄 Share it with your partner and have them enter it on their phone."
        case .relationshipFull: "This relationship already has two partners."
        case .notSignedIn: "Please sign in first."
        case .premiumRequired: "This feature is part of Missuo Premium."
        case .purchaseUnavailable: "Purchases aren't available right now. Please try again in a moment."
        }
    }
}
