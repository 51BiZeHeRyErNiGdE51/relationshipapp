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
                 aiCoach: CloudAICoachService(),  // DeepSeek via Cloud Functions — key stays server-side
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
    case onboarding            // first launch: tutorial → paywall → pairing
    case active                // the app — solo (invite pending) or paired
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
    /// True when the initial session couldn't be established (offline, rules
    /// misconfigured…) — the loading screen shows a Try Again button.
    private(set) var startupFailed = false

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

    /// First names for copy. `partnerFirstName` is nil when unpaired so call
    /// sites can choose their own fallback ("your partner", "Partner", …).
    var myFirstName: String { myName.split(separator: " ").first.map(String.init) ?? "You" }
    var partnerFirstName: String? {
        partnerProfile?.displayName.split(separator: " ").first.map(String.init)
    }

    // MARK: Session lifecycle
    //
    // Accountless by design: no email, no sign-up screen. First launch runs the
    // tutorial → paywall → pairing flow; a Firebase anonymous user + a pending
    // relationship (with invite code) are created silently behind it.

    private static let onboardingCompletedKey = "lovio.onboarding.completed"
    /// Bump when onboarding logic changes so existing installs get a clean replay once.
    private static let onboardingFlowVersionKey = "missuo.onboarding.flowVersion"
    private static let onboardingFlowVersion = 2

    var isPaired: Bool { relationship?.status == .active }

    func start() async {
        services.analytics.track(.appOpened)
        // Remote Config only powers non-critical experiments (paywall copy,
        // reminder hour) — refresh in the background, NEVER block first paint.
        Task { await services.experiments.refresh() }

        migrateOnboardingFlowIfNeeded()

        // UI-test hook: jump straight past onboarding.
        if ProcessInfo.processInfo.arguments.contains("-uitest-completed-onboarding") {
            UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
        }

        if !UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey) {
            services.analytics.track(.onboardingStarted)
            phase = .onboarding
            return
        }
        await ensureSession()
        await drainWidgetOutbox()
        NotificationManager.shared.scheduleWeeklyPremiumNudge(isPremium: premium.isPremium)
    }

    /// One-time reset for installs that skipped the tutorial via an old Firebase shortcut.
    private func migrateOnboardingFlowIfNeeded() {
        guard UserDefaults.standard.integer(forKey: Self.onboardingFlowVersionKey)
                < Self.onboardingFlowVersion else { return }
        UserDefaults.standard.set(false, forKey: Self.onboardingCompletedKey)
        UserDefaults.standard.set(Self.onboardingFlowVersion, forKey: Self.onboardingFlowVersionKey)
    }

    // MARK: Secondary offer window (7 days from first paywall decline)

    private static let offerDeclineKey = "lovio.secondaryOffer.firstDeclineAt"

    var secondaryOfferDeadline: Date? {
        guard let start = UserDefaults.standard.object(forKey: Self.offerDeclineKey) as? Date
        else { return nil }
        return start.addingTimeInterval(7 * 86_400)
    }

    var isSecondaryOfferActive: Bool {
        guard !premium.isPremium else { return false }
        guard let deadline = secondaryOfferDeadline else { return true } // not started yet
        return deadline > .now
    }

    /// Called when a free user closes the paywall without buying. Starts the
    /// 7-day discounted-offer window (once) and schedules reminder pushes.
    func registerPaywallDecline() {
        guard !premium.isPremium else { return }
        if UserDefaults.standard.object(forKey: Self.offerDeclineKey) == nil {
            UserDefaults.standard.set(Date(), forKey: Self.offerDeclineKey)
        }
        if let deadline = secondaryOfferDeadline, deadline > .now {
            NotificationManager.shared.scheduleOfferReminders(deadline: deadline)
        }
    }

    /// Guarantees: a signed-in user (anonymous if needed), a profile document,
    /// and a relationship with an invite code. Safe to call repeatedly.
    func ensureSession() async {
        startupFailed = false
        do {
            var current = await services.auth.currentUser()
            if current == nil {
                current = try await services.auth.signIn(with: .anonymous)
                services.analytics.track(.signInCompleted(provider: "anonymous"))
            }
            guard let user = current else { return }
            self.user = user
            if !isDemoMode { RevenueCatBootstrap.configure(appUserID: user.id) }

            var profile = try await services.relationship.profile(for: user.id)
                ?? UserProfile(id: user.id, displayName: user.displayName)
            profile.lastActiveAt = .now
            // Register this device for partner-event pushes (Cloud Functions
            // read users/{id}.fcmTokens to fan out notifications).
            if let token = UserDefaults.standard.string(forKey: "lovio.fcm.token"),
               !profile.fcmTokens.contains(token) {
                profile.fcmTokens.append(token)
            }
            try await services.relationship.updateProfile(profile)
            myProfile = profile

            var rel = try await services.relationship.currentRelationship(for: user.id)
            if rel == nil {
                rel = try await services.relationship.createRelationship(
                    creator: user.id, anniversary: nil)
                services.analytics.track(.invitationCreated)
            }
            relationship = rel

            if let rel, rel.status == .active, let partnerID = rel.partnerID(of: user.id) {
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
            errorMessage = Self.userFacingMessage(for: error)
            // Never strand the user on the logo screen — surface a retry.
            if phase == .loading { startupFailed = true }
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("missing or insufficient permissions")
            || text.localizedCaseInsensitiveContains("permission denied") {
            return """
            Firestore blocked the app. In Firebase Console → Firestore → Rules, paste the contents of firebase/firestore.rules from this project and tap Publish. Under Authentication → Sign-in method, enable Anonymous.
            """
        }
        return text
    }

    /// Called by the onboarding flow. Solo usage is fully supported —
    /// the partner code can be entered later from the Home screen.
    func completeOnboarding(partnerCode: String?) async {
        UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
        // Paywall already shown in onboarding — don't immediately show again on Home.
        UserDefaults.standard.set(true, forKey: "lovio.paywall.skipSessionStartOnce")
        await ensureSession()
        if let code = partnerCode, !code.trimmingCharacters(in: .whitespaces).isEmpty {
            await joinRelationship(code: code)
        }
        await drainWidgetOutbox()
    }

    func replayIntro() {
        UserDefaults.standard.set(false, forKey: Self.onboardingCompletedKey)
        phase = .onboarding
    }

    func signOut() async {
        try? await services.auth.signOut()
        UserDefaults.standard.set(false, forKey: Self.onboardingCompletedKey)
        user = nil
        relationship = nil
        partnerProfile = nil
        phase = .onboarding
    }

    // MARK: Pairing

    /// Disconnects from the current partner but keeps the account (and any
    /// premium entitlement, which belongs to the purchaser). A fresh pending
    /// relationship with a new invite code is created immediately.
    func unpair() async {
        guard let rel = relationship, let me = user, isPaired else { return }
        try? await services.relationship.endRelationship(rel.id, endedBy: me.id)
        services.analytics.track(.relationshipEnded)
        partnerProfile = nil
        relationship = try? await services.relationship.createRelationship(creator: me.id, anniversary: nil)
        premium = await services.premium.premiumState(relationship: relationship, me: me.id)
        await refreshToday()
    }

    func joinRelationship(code: String) async {
        guard let user else { return }
        do {
            // Production note: joining abandons the user's own pending
            // relationship; a Cloud Function should garbage-collect it.
            let rel = try await services.relationship.joinRelationship(code: code, joiner: user.id)
            relationship = rel
            services.analytics.track(.invitationRedeemed)
            services.analytics.track(.relationshipActivated)
            Haptics.celebration()
            await ensureSession()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAnniversary(_ date: Date) async {
        guard let rel = relationship else { return }
        try? await services.relationship.updateAnniversary(rel.id, date: date)
        relationship?.anniversary = date
        publishWidgetSnapshot()
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
        await NotificationManager.shared.scheduleEventReminders(dates: upcomingDates)
        await syncIncomingWidgetContent()
    }

    // MARK: Actions (each one feeds the relationship graph + gamification)

    func answerTodayQuestion(_ text: String, rating: Int? = nil) async {
        guard let rel = relationship, let user, let state = questionState else { return }
        do {
            questionState = try await services.questions.submitAnswer(
                text, rating: rating, question: state.question, relationship: rel.id, author: user.id)
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
        // Widget taps already incremented the counter in their intent.
        if source != "widget" { MissYouCounter.increment() }
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
                NotificationManager.shared.cancelMonetizationReminders()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshPremium() async {
        guard let user else { return }
        premium = await services.premium.premiumState(relationship: relationship, me: user.id)
        publishWidgetSnapshot()
    }

    func restorePurchases() async {
        guard let user else { return }
        if let state = try? await services.premium.restorePurchases(me: user.id) {
            premium = state
            services.analytics.track(.purchaseRestored)
        }
    }

    // MARK: Widgets — shared content (photo + note reach BOTH partners)

    /// Publishes a love note to my own widgets (mine slot) AND to my partner
    /// (via Firestore; a Cloud Function pushes "new note on your widget").
    func sendWidgetNote(_ text: String) async {
        WidgetContent.saveNote(text, slot: .mine)
        publishWidgetSnapshot()
        guard let rel = relationship, let me = user else { return }
        var content = (try? await services.relationship.widgetContent(relationship: rel.id)) ?? SharedWidgetContent()
        content.note = text
        content.noteAuthorID = me.id
        content.noteUpdatedAt = .now
        try? await services.relationship.saveWidgetContent(content, relationship: rel.id)
        try? await services.relationship.record(
            event: RelationshipEvent(kind: .widgetNoteSent, actorID: me.id), relationship: rel.id)
    }

    /// Saves the photo to MY "My Polaroid" widget instantly, then uploads it so
    /// it lands on my partner's "From Your Love" widget. Photos are visible
    /// ONLY to the two members (enforced by Storage rules).
    func sendWidgetPhoto(_ jpeg: Data) async {
        WidgetContent.savePhoto(jpeg, slot: .mine)
        guard let rel = relationship, let me = user else { return }
        guard let path = try? await services.relationship.uploadImage(
            jpeg, relationship: rel.id, fileName: "widget_photo.jpg") else { return }
        var content = (try? await services.relationship.widgetContent(relationship: rel.id)) ?? SharedWidgetContent()
        content.photoPath = path
        content.photoAuthorID = me.id
        content.photoUpdatedAt = .now
        try? await services.relationship.saveWidgetContent(content, relationship: rel.id)
        try? await services.relationship.record(
            event: RelationshipEvent(kind: .widgetPhotoSent, actorID: me.id), relationship: rel.id)
    }

    /// Pulls partner-sent widget content onto THIS device (called on refresh
    /// and when a push wakes the app). Last-writer-wins, only newer content.
    func syncIncomingWidgetContent() async {
        guard let rel = relationship, let me = user,
              let content = try? await services.relationship.widgetContent(relationship: rel.id)
        else { return }
        let defaults = AppGroup.defaults

        if let note = content.note, content.noteAuthorID != me.id,
           let at = content.noteUpdatedAt,
           at > (defaults.object(forKey: "lovio.widget.note.syncedAt") as? Date ?? .distantPast) {
            WidgetContent.saveNote(note, slot: .partner)
            defaults.set(at, forKey: "lovio.widget.note.syncedAt")
            publishWidgetSnapshot()
        }

        if let path = content.photoPath, content.photoAuthorID != me.id,
           let at = content.photoUpdatedAt,
           at > (defaults.object(forKey: "lovio.widget.photo.syncedAt") as? Date ?? .distantPast),
           let data = try? await services.relationship.downloadImage(path: path) {
            WidgetContent.savePhoto(data, slot: .partner)
            defaults.set(at, forKey: "lovio.widget.photo.syncedAt")
        }
    }

    // MARK: Widgets

    /// Denormalize everything widgets need into the App Group and reload
    /// timelines. Only real data — anything we don't track yet is nil so
    /// widgets show honest empty states instead of demo numbers.
    func publishWidgetSnapshot() {
        guard let rel = relationship, let user else { return }
        let partnerID = rel.partnerID(of: user.id)
        let myMood = latestMoods[user.id]
        let partnerMood = partnerID.flatMap { latestMoods[$0] }
        let nextDate = upcomingDates.first

        // "Both online" = paired and the partner was active in the last 15 min.
        let partnerRecentlyActive = (partnerProfile?.lastActiveAt).map {
            Date.now.timeIntervalSince($0) < 15 * 60
        } ?? false

        var snapshot = WidgetSnapshot(
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
            myEnergy: myMood?.energy ?? 0, partnerEnergy: partnerMood?.energy ?? 0,
            partnerBatteryPercent: nil,      // future: partner presence doc
            distanceKilometers: nil,         // future: coarse location sync
            daysSinceLastMeeting: nil,       // future: meetup log
            bothRecentlyActive: isPaired && partnerRecentlyActive,
            nextEventTitle: nextDate?.title,
            nextEventDate: nextDate.map { Calendar.current.date(byAdding: .day, value: $0.daysUntil, to: .now) ?? $0.date },
            latestNote: WidgetContent.note(.partner),
            missYouCountToday: MissYouCounter.today(),
            heartsInJar: rel.xp / 4,
            companionKind: rel.companion.kind.rawValue,
            companionStageName: rel.companion.stageName,
            companionGrowth: rel.companion.growth,
            lastMemoryTitle: nil,
            lastMemoryDate: nil)
        snapshot.hasAnniversary = rel.anniversary != nil
        snapshot.isPaired = isPaired
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
