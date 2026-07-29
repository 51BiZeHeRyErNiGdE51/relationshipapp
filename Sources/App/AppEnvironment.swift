import Foundation
import SwiftUI
import UIKit

// MARK: - Service container

struct Services: Sendable {
    var auth: AuthService
    var relationship: RelationshipService
    var questions: QuestionService
    var journal: JournalService
    var mood: MoodService
    var planner: PlannerService
    var premium: PremiumService
    var aiCoach: AICoachService
    var analytics: AnalyticsClient
    var experiments: ExperimentsService

    /// Live Firebase + RevenueCat stack.
    static func live() -> Services {
        Services(auth: FirebaseAuthService(),
                 relationship: FirestoreRelationshipService(),
                 questions: FirestoreQuestionService(),
                 journal: FirestoreJournalService(),
                 mood: FirestoreMoodService(),
                 planner: FirestorePlannerService(),
                 premium: RevenueCatPremiumService(),
                 aiCoach: DemoAICoachService(),   // swap for server AI endpoint
                 analytics: CompositeAnalytics(sinks: [FirebaseAnalyticsClient(),
                                                       MetaAnalyticsAdapter(),
                                                       ConsoleAnalytics()]),
                 experiments: RemoteConfigExperiments())
    }

    /// Fully seeded local stack — previews, UI tests, and no-Firebase demo runs.
    static func demo() -> Services {
        Services(auth: DemoAuthService(),
                 relationship: DemoRelationshipService(),
                 questions: DemoQuestionService(),
                 journal: DemoJournalService(),
                 mood: DemoMoodService(),
                 planner: DemoPlannerService(),
                 premium: DemoPremiumService(),
                 aiCoach: DemoAICoachService(),
                 analytics: ConsoleAnalytics(),
                 experiments: DemoExperimentsService())
    }
}

// MARK: - App model (single observable facade)

enum SessionPhase: Equatable {
    case loading
    case signedOut
    case needsPairing          // signed in, no relationship yet
    case waitingForPartner     // created invite, partner hasn't joined
    case active                // paired couple — the real app
}

@MainActor
@Observable
final class AppModel {
    let services: Services
    let isDemoMode: Bool

    // Session
    private(set) var phase: SessionPhase = .loading
    private(set) var user: AuthenticatedUser?
    private(set) var relationship: Relationship?
    private(set) var myProfile: UserProfile?
    private(set) var partnerProfile: UserProfile?
    private(set) var premium: PremiumState = .free

    // Today
    private(set) var questionState: DailyQuestionState?
    private(set) var latestMoods: [UserID: MoodEntry] = [:]
    private(set) var upcomingDates: [SpecialDate] = []

    var errorMessage: String?

    init(services: Services, isDemoMode: Bool) {
        self.services = services
        self.isDemoMode = isDemoMode
    }

    static func bootstrap() -> AppModel {
        let hasFirebase = FirebaseBootstrap.configureIfPossible()
        return AppModel(services: hasFirebase ? .live() : .demo(), isDemoMode: !hasFirebase)
    }

    var partnerName: String { partnerProfile?.displayName ?? "Your partner" }
    var myName: String { myProfile?.displayName ?? user?.displayName ?? "You" }

    // MARK: Session lifecycle

    func start() async {
        services.analytics.track(.appOpened)
        await services.experiments.refresh()

        guard let user = await services.auth.currentUser() else {
            phase = .signedOut
            return
        }
        self.user = user
        if !isDemoMode { RevenueCatBootstrap.configure(appUserID: user.id) }
        await loadSession()
        await drainWidgetOutbox()
    }

    func signIn(with provider: AuthProviderKind) async {
        do {
            let user = try await services.auth.signIn(with: provider)
            self.user = user
            services.analytics.track(.signInCompleted(provider: provider.rawValue))
            if !isDemoMode { RevenueCatBootstrap.configure(appUserID: user.id) }
            var profile = try await services.relationship.profile(for: user.id)
                ?? UserProfile(id: user.id, displayName: user.displayName)
            profile.lastActiveAt = .now
            try await services.relationship.updateProfile(profile)
            await loadSession()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        try? await services.auth.signOut()
        user = nil
        relationship = nil
        partnerProfile = nil
        phase = .signedOut
    }

    private func loadSession() async {
        guard let user else { phase = .signedOut; return }
        do {
            myProfile = try await services.relationship.profile(for: user.id)
                ?? UserProfile(id: user.id, displayName: user.displayName)

            guard let rel = try await services.relationship.currentRelationship(for: user.id) else {
                phase = .needsPairing
                return
            }
            relationship = rel

            if rel.status == .pendingPartner {
                phase = .waitingForPartner
                return
            }

            if let partnerID = rel.partnerID(of: user.id) {
                partnerProfile = try await services.relationship.profile(for: partnerID)
            }
            premium = await services.premium.premiumState(relationship: rel, me: user.id)
            if premium.inheritedFromPartner {
                services.analytics.track(.premiumInherited)
            }
            services.analytics.setUserProperty(premium.isPremium ? "premium" : "free",
                                               forName: "subscription_tier")
            phase = .active
            await refreshToday()
        } catch {
            errorMessage = error.localizedDescription
            phase = user.id.isEmpty ? .signedOut : .needsPairing
        }
    }

    // MARK: Pairing

    func createRelationship(anniversary: Date?) async {
        guard let user else { return }
        do {
            relationship = try await services.relationship.createRelationship(
                creator: user.id, anniversary: anniversary)
            services.analytics.track(.invitationCreated)
            phase = .waitingForPartner
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func joinRelationship(code: String) async {
        guard let user else { return }
        do {
            let rel = try await services.relationship.joinRelationship(code: code, joiner: user.id)
            relationship = rel
            services.analytics.track(.invitationRedeemed)
            services.analytics.track(.relationshipActivated)
            await loadSession()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Demo/dev helper — pretend the partner redeemed the code.
    func simulatePartnerJoined() async {
        guard var rel = relationship else { return }
        rel.status = .active
        if rel.memberIDs.count < 2 { rel.memberIDs.append("user_sam") }
        try? await services.relationship.updateGamification(rel)
        await loadSession()
    }

    // MARK: Today surface

    func refreshToday() async {
        guard let rel = relationship, let user else { return }
        async let question = try? services.questions.todayState(relationship: rel.id, me: user.id)
        async let moods = try? services.mood.latestMoods(relationship: rel.id)
        async let dates = try? services.planner.specialDates(relationship: rel.id)
        questionState = await question
        latestMoods = await moods ?? [:]
        upcomingDates = await dates ?? []
        publishWidgetSnapshot()
    }

    // MARK: Actions (each one feeds the relationship graph + gamification)

    func answerTodayQuestion(_ text: String) async {
        guard let rel = relationship, let user, let state = questionState else { return }
        do {
            questionState = try await services.questions.submitAnswer(
                text, question: state.question, relationship: rel.id, author: user.id)
            services.analytics.track(.questionAnswered(category: state.question.category.rawValue))
            if questionState?.isRevealed == true {
                services.analytics.track(.answersRevealed)
            }
            Haptics.success()
            await recordEngagement(.questionAnswered, nurture: 8)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logMood(_ entry: MoodEntry) async {
        guard let rel = relationship else { return }
        do {
            try await services.mood.log(entry, relationship: rel.id)
            latestMoods[entry.authorID] = entry
            services.analytics.track(.moodLogged(mood: entry.mood.rawValue))
            Haptics.light()
            await recordEngagement(.moodLogged, nurture: 4)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addJournalEntry(_ entry: JournalEntry) async {
        guard let rel = relationship else { return }
        do {
            try await services.journal.add(entry, relationship: rel.id)
            services.analytics.track(.journalEntryCreated(mediaCount: entry.media.count))
            Haptics.success()
            await recordEngagement(.journalEntryAdded, nurture: 10)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendMissYou(source: String = "app") async {
        services.analytics.track(.missYouSent(source: source))
        Haptics.heartbeat()
        await recordEngagement(.missYouSent, nurture: 2)
        // Production: Cloud Function fans this out via FCM to the partner
        // + updates their widget push payload.
    }

    /// Central gamification pipeline: graph event → streak / XP / love score / companion.
    private func recordEngagement(_ kind: RelationshipEventKind, nurture: Double) async {
        guard var rel = relationship, let user else { return }

        try? await services.relationship.record(
            event: RelationshipEvent(kind: kind, actorID: user.id), relationship: rel.id)

        // XP + companion growth
        rel.xp += Int(nurture) * 5
        let previousStage = rel.companion.stage
        rel.companion.nurture(points: nurture)
        if rel.companion.stage > previousStage {
            services.analytics.track(.companionEvolved(kind: rel.companion.kind.rawValue,
                                                       stage: rel.companion.stage))
            Haptics.celebration()
        }

        // Streak: extends once per day on first meaningful action.
        let today = DayKey.today()
        if rel.streak.lastCompletedDayKey != today {
            rel.streak.current += 1
            rel.streak.best = max(rel.streak.best, rel.streak.current)
            rel.streak.lastCompletedDayKey = today
            services.analytics.track(.streakExtended(days: rel.streak.current))
        }

        // Love score: gentle rolling nudge, capped 0–100.
        rel.loveScore = min(100, rel.loveScore + (nurture >= 8 ? 1 : 0))

        relationship = rel
        try? await services.relationship.updateGamification(rel)
        publishWidgetSnapshot()
    }

    func switchCompanion(_ kind: CompanionKind) async {
        guard var rel = relationship else { return }
        guard !kind.isPremium || premium.isPremium else { return }
        rel.companion = CompanionState(kind: kind)
        relationship = rel
        try? await services.relationship.updateGamification(rel)
        publishWidgetSnapshot()
    }

    // MARK: Premium

    func purchase(offer: PaywallOffer) async {
        guard let user else { return }
        do {
            services.analytics.track(.paywallOfferSelected(offerID: offer.id))
            let state = try await services.premium.purchase(
                offerID: offer.id, me: user.id, relationship: relationship?.id)
            if state.isPremium {
                premium = state
                services.analytics.track(offer.trialDays > 0
                    ? .trialStarted(offerID: offer.id)
                    : .purchaseCompleted(offerID: offer.id))
                Haptics.celebration()
                publishWidgetSnapshot()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        guard let user else { return }
        if let state = try? await services.premium.restorePurchases(me: user.id) {
            premium = state
            services.analytics.track(.purchaseRestored)
        }
    }

    // MARK: Widgets

    /// Denormalize everything widgets need into the App Group and reload timelines.
    func publishWidgetSnapshot() {
        guard let rel = relationship, let user else { return }
        let partnerID = rel.partnerID(of: user.id)
        let myMood = latestMoods[user.id]
        let partnerMood = partnerID.flatMap { latestMoods[$0] }
        let nextDate = upcomingDates.first

        let snapshot = WidgetSnapshot(
            myName: myName, partnerName: partnerName,
            myInitials: myProfile?.initials ?? "Y",
            partnerInitials: partnerProfile?.initials ?? "L",
            daysTogether: rel.daysTogether,
            streakDays: rel.streak.current,
            loveScore: rel.loveScore,
            isPremium: premium.isPremium,
            todayQuestion: questionState?.question.text,
            questionAnsweredByMe: questionState?.myAnswer != nil,
            questionAnsweredByPartner: questionState?.partnerHasAnswered ?? false,
            myMood: myMood?.mood.emoji, partnerMood: partnerMood?.mood.emoji,
            myEnergy: myMood?.energy ?? 3, partnerEnergy: partnerMood?.energy ?? 3,
            partnerBatteryPercent: 72,           // production: partner presence doc
            distanceKilometers: 4.2,             // production: coarse location sync
            daysSinceLastMeeting: 2,
            bothRecentlyActive: true,
            nextEventTitle: nextDate?.title, 
            nextEventDate: nextDate.map { Calendar.current.date(byAdding: .day, value: $0.daysUntil, to: .now) ?? $0.date },
            latestNote: "Can't stop thinking about Saturday 🤍",
            missYouCountToday: 3,
            heartsInJar: 100 + rel.xp / 25,
            companionKind: rel.companion.kind.rawValue,
            companionStageName: rel.companion.stageName,
            companionGrowth: rel.companion.growth,
            lastMemoryTitle: "Sunset picnic at the pier",
            lastMemoryDate: .now.addingTimeInterval(-86_400 * 3))
        AppGroup.save(snapshot)
    }

    /// Interactive widgets queue actions while the app is closed; sync them here.
    func drainWidgetOutbox() async {
        for action in WidgetOutbox.drain() {
            services.analytics.track(.widgetInteraction(widget: action.kind, action: "tap"))
            switch action.kind {
            case "miss_you": await sendMissYou(source: "widget")
            case "heart_tap": await recordEngagement(.heartTap, nurture: 1)
            default: break
            }
        }
    }
}

// MARK: - Haptics

enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func heartbeat() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            generator.impactOccurred(intensity: 0.6)
        }
    }
    static func celebration() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
    }
}
