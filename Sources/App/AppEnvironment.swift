import AppTrackingTransparency
import CoreLocation
import Foundation
import SwiftUI
import UIKit
import UserNotifications

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
    /// True when the user declined push permission — Home shows a gentle
    /// inline card instead of us ever re-prompting.
    private(set) var notificationsDenied = false
    /// Set the moment the couple becomes paired (either direction) —
    /// Home plays a full-screen celebration and clears it.
    var justPaired = false

    init(services: Services, isDemoMode: Bool) {
        self.services = services
        self.isDemoMode = isDemoMode
    }

    /// Set by bootstrap() so the AppDelegate can trigger a background sync
    /// when a silent push arrives (partner sent a photo, heart, message…).
    static weak var current: AppModel?

    static func bootstrap() -> AppModel {
        let hasFirebase = FirebaseBootstrap.configureIfPossible()
        let model = AppModel(services: hasFirebase ? .live() : .demo(), isDemoMode: !hasFirebase)
        current = model
        return model
    }

    // "You" was a literal default written by an old build — treat it as unnamed.
    private static func realName(_ raw: String?) -> String? {
        let name = (raw ?? "").trimmingCharacters(in: .whitespaces)
        return (name.isEmpty || name == "You") ? nil : name
    }

    var partnerName: String { Self.realName(partnerProfile?.displayName) ?? "Your partner" }
    var myName: String {
        Self.realName(myProfile?.displayName) ?? Self.realName(user?.displayName) ?? "You"
    }

    /// Anonymous sign-in means nobody typed a name; Home shows a one-time
    /// card until they do (editable later in Settings). "You" counts as
    /// unnamed — an old build wrote it as a literal default.
    var needsMyName: Bool {
        guard user != nil else { return false }
        let name = (myProfile?.displayName ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty || name == "You"
    }

    /// Saves my display name — it syncs to my partner's app (their "partner
    /// name") and to the widgets on both phones.
    func updateMyName(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var profile = myProfile else { return }
        profile.displayName = trimmed
        try? await services.relationship.updateProfile(profile)
        myProfile = profile
        publishWidgetSnapshot()
    }

    /// First names for copy. `partnerFirstName` is nil when unpaired so call
    /// sites can choose their own fallback ("your partner", "Partner", …).
    var myFirstName: String { myName.split(separator: " ").first.map(String.init) ?? "You" }
    var partnerFirstName: String? {
        Self.realName(partnerProfile?.displayName)?
            .split(separator: " ").first.map(String.init)
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

    // MARK: System permission prompts — one at a time, never during the tutorial
    //
    // Order on the main screen: 1) App Tracking Transparency, 2) push
    // notifications. Each waits for the previous answer plus a small pause so
    // the user never faces a stack of dialogs. If pushes are declined, Home
    // shows a small inline card instead of re-prompting.

    func runPermissionPrompts() async {
        guard !ProcessInfo.processInfo.arguments.contains("-skip-permission-prompts") else { return }

        // Let the main screen settle before the first dialog.
        try? await Task.sleep(for: .seconds(1.2))
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
            // Breathing room between the two dialogs.
            try? await Task.sleep(for: .seconds(1))
        }

        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            await NotificationManager.shared.requestPermissionsAndSchedule(
                reminderHour: Int(services.experiments.variant(for: "daily_reminder_hour")) ?? 20)
        }
        await refreshNotificationStatus()
    }

    func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsDenied = settings.authorizationStatus == .denied
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
            // Only enter the main app once onboarding is truly finished.
            // (The onboarding pairing step calls ensureSession() for its silent
            // sign-in — flipping to .active here used to yank users out of
            // onboarding before the completed flag was set, so every relaunch
            // replayed the tutorial.)
            if UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey) {
                phase = .active
            }
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
        // Instant feedback when someone enters their own code.
        let normalized = code.replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespaces).uppercased()
        if let mine = relationship?.inviteCode?.value.uppercased(), mine == normalized {
            errorMessage = LovioError.cantPairWithSelf.errorDescription
            return
        }
        do {
            // Production note: joining abandons the user's own pending
            // relationship; a Cloud Function should garbage-collect it.
            let rel = try await services.relationship.joinRelationship(code: code, joiner: user.id)
            relationship = rel
            services.analytics.track(.invitationRedeemed)
            services.analytics.track(.relationshipActivated)
            Haptics.celebration()
            await ensureSession()
            justPaired = true   // Home shows the "you're connected" celebration
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
        guard let user else { return }

        // Live pairing detection: re-pull the relationship every refresh so
        // the creator's phone notices the partner joining (and both phones
        // stay in sync on XP / love jar / streak).
        let wasPaired = isPaired
        if let fresh = try? await services.relationship.currentRelationship(for: user.id) {
            relationship = fresh
            if fresh.status == .active, let partnerID = fresh.partnerID(of: user.id) {
                partnerProfile = try? await services.relationship.profile(for: partnerID)
                if !wasPaired {
                    justPaired = true
                    Haptics.celebration()
                    services.analytics.track(.relationshipActivated)
                }
            }
        }
        guard let rel = relationship else { return }

        await syncMyPresence()

        async let question = try? services.questions.todayState(relationship: rel.id, me: user.id)
        async let moods = try? services.mood.latestMoods(relationship: rel.id)
        async let dates = try? services.planner.specialDates(relationship: rel.id)
        questionState = await question
        latestMoods = await moods ?? [:]
        upcomingDates = await dates ?? []
        publishWidgetSnapshot()
        await NotificationManager.shared.scheduleEventReminders(dates: upcomingDates)
        await syncIncomingWidgetContent()
        await detectIncomingLove(rel: rel, me: user.id)
    }

    /// Keeps my profile fresh while the app is in use:
    /// - uploads the FCM push token if Firestore doesn't have it yet
    ///   (ensureSession runs BEFORE the user grants push permission, so the
    ///   first token used to sit on-device only → partner pushes never fired)
    /// - heart-beats `lastActiveAt` (max every 5 min) so the partner's
    ///   Love Pulse widget can show "you're both here" truthfully.
    private func syncMyPresence() async {
        guard var profile = myProfile else { return }
        var dirty = false
        if let token = UserDefaults.standard.string(forKey: "lovio.fcm.token") {
            // Keep only the latest token — stale tokens from deleted installs
            // poison multicast sends and hide real delivery failures.
            if profile.fcmTokens != [token] {
                profile.fcmTokens = [token]
                dirty = true
            }
        }
        if Date.now.timeIntervalSince(profile.lastActiveAt) > 5 * 60 {
            profile.lastActiveAt = .now
            dirty = true
        }
        // Distance widget: ONE coarse fix (~1 km) per presence heartbeat,
        // only if the user opted in. No continuous tracking — battery cost
        // is effectively zero.
        if distanceEnabled,
           Date.now.timeIntervalSince(profile.locationUpdatedAt ?? .distantPast) > 5 * 60,
           let coordinate = await OneShotLocation.request() {
            profile.latitude = (coordinate.latitude * 100).rounded() / 100
            profile.longitude = (coordinate.longitude * 100).rounded() / 100
            profile.locationUpdatedAt = .now
            dirty = true
        }
        guard dirty else { return }
        try? await services.relationship.updateProfile(profile)
        myProfile = profile
    }

    // MARK: Distance widget opt-in

    var distanceEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "missuo.location.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "missuo.location.enabled") }
    }

    func enableDistance() async {
        let status = CLLocationManager().authorizationStatus
        if status == .notDetermined {
            // Must use a retained manager — throwaway managers never finish the dialog.
            OneShotLocation.requestPermission()
            try? await Task.sleep(for: .seconds(2))
        }
        distanceEnabled = true
        // Force a location write on the next presence sync (ignore 5‑min throttle).
        if var profile = myProfile {
            profile.locationUpdatedAt = .distantPast
            myProfile = profile
        }
        await refreshToday()
    }

    /// Km between the two partners' coarse locations (nil unless both opted
    /// in and reported within the last 48 h).
    var distanceKilometers: Double? {
        guard let myLat = myProfile?.latitude, let myLon = myProfile?.longitude,
              let pLat = partnerProfile?.latitude, let pLon = partnerProfile?.longitude,
              let myAt = myProfile?.locationUpdatedAt, let pAt = partnerProfile?.locationUpdatedAt,
              Date.now.timeIntervalSince(myAt) < 48 * 3600,
              Date.now.timeIntervalSince(pAt) < 48 * 3600 else { return nil }
        return CLLocation(latitude: myLat, longitude: myLon)
            .distance(from: CLLocation(latitude: pLat, longitude: pLon)) / 1000
    }

    /// Silent-push / notification-tap entry point: pull everything the partner
    /// changed (photo, note, hearts, pairing) and refresh the widgets without
    /// the user opening the app.
    func backgroundSync() async {
        await drainWidgetOutbox()
        await refreshToday()
    }

    // MARK: Meetup log — powers the Hug Meter widget

    /// True when a meetup was already logged today (button shows a checkmark).
    var meetupLoggedToday: Bool {
        guard let at = relationship?.lastMeetupAt else { return false }
        return Calendar.current.isDateInToday(at)
    }

    func logMeetup() async {
        guard var rel = relationship, let user else { return }
        rel.lastMeetupAt = .now
        relationship = rel
        publishWidgetSnapshot()
        Haptics.success()
        try? await services.relationship.updateGamification(rel)
        try? await services.relationship.record(
            event: RelationshipEvent(kind: .meetupLogged, actorID: user.id), relationship: rel.id)
    }

    // MARK: Incoming love (partner's miss-yous / heart taps since last check)

    private static let loveSeenKey = "missuo.love.lastSeenAt"

    /// Set when the partner sent miss-yous / hearts since the last refresh —
    /// Home plays a full-screen heart burst and clears it.
    var incomingLove: IncomingLove?

    struct IncomingLove: Equatable {
        var count: Int
        var kind: RelationshipEventKind
    }

    private func detectIncomingLove(rel: Relationship, me: UserID) async {
        let defaults = UserDefaults.standard
        guard let lastSeen = defaults.object(forKey: Self.loveSeenKey) as? Date else {
            // First run: baseline quietly, don't replay history as new love.
            defaults.set(Date(), forKey: Self.loveSeenKey)
            return
        }
        let events = (try? await services.relationship.recentEvents(relationship: rel.id, limit: 30)) ?? []
        let fresh = events.filter {
            $0.actorID != me && $0.occurredAt > lastSeen
                && ($0.kind == .missYouSent || $0.kind == .heartTap || $0.kind == .hugSent)
        }
        defaults.set(Date(), forKey: Self.loveSeenKey)
        if !fresh.isEmpty {
            let kind = fresh.first?.kind ?? .missYouSent
            incomingLove = IncomingLove(count: fresh.count, kind: kind)
            Haptics.heartbeat()
            // Local banner as a safety net while APNs is being configured —
            // still shows when the app is open/backgrounded and we detect love.
            let who = partnerFirstName ?? "Your love"
            let title: String
            let body: String
            switch kind {
            case .heartTap:
                title = "\(who) dropped a heart in your jar ❤️"
                body = "They're thinking of you right now."
            case .hugSent:
                title = "\(who) sent you a hug 🤗"
                body = "Wrap it around yourself."
            default:
                title = "\(who) misses you 🥺"
                body = "Tap to send one back."
            }
            await NotificationManager.shared.postLocal(title: title, body: body)
        }
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

    /// In-app heart: lands in the shared love jar + pushes to the partner.
    func sendHeart() async {
        Haptics.heartbeat()
        await recordEngagement(.heartTap, nurture: 1)
        publishWidgetSnapshot()   // jar count updates on my widgets instantly
    }

    /// Virtual hug: pushes "X sent you a hug 🤗" to the partner's phone.
    func sendHug() async {
        Haptics.heartbeat()
        await recordEngagement(.hugSent, nurture: 1)
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
    /// (via my per-author Firestore doc; a Cloud Function pushes "new note").
    func sendWidgetNote(_ text: String) async {
        WidgetContent.saveNote(text, slot: .mine)
        publishWidgetSnapshot()
        guard let rel = relationship, let me = user else { return }
        var content = (try? await services.relationship.widgetContent(relationship: rel.id, author: me.id)) ?? SharedWidgetContent()
        content.note = text
        content.noteAuthorID = me.id
        content.noteUpdatedAt = .now
        try? await services.relationship.saveWidgetContent(content, relationship: rel.id, author: me.id)
        try? await services.relationship.record(
            event: RelationshipEvent(kind: .widgetNoteSent, actorID: me.id), relationship: rel.id)
    }

    /// Saves the photo to MY "My Polaroid" widget instantly, then uploads it so
    /// it lands on my partner's "From Your Love" widget. Photos are visible
    /// ONLY to the two members (enforced by Storage rules).
    /// Returns as soon as the local widget is updated — the upload to the
    /// partner runs in the background so the UI confirms without waiting.
    func sendWidgetPhoto(_ jpeg: Data) async {
        WidgetContent.savePhoto(jpeg, slot: .mine)
        guard let rel = relationship, let me = user else { return }
        Task {
            // Per-author file name — partners must never overwrite each other.
            guard let path = try? await services.relationship.uploadImage(
                jpeg, relationship: rel.id, fileName: "widget_photo_\(me.id).jpg") else { return }
            var content = (try? await services.relationship.widgetContent(relationship: rel.id, author: me.id)) ?? SharedWidgetContent()
            content.photoPath = path
            content.photoAuthorID = me.id
            content.photoUpdatedAt = .now
            try? await services.relationship.saveWidgetContent(content, relationship: rel.id, author: me.id)
            try? await services.relationship.record(
                event: RelationshipEvent(kind: .widgetPhotoSent, actorID: me.id), relationship: rel.id)
        }
    }

    /// Pulls partner-sent widget content onto THIS device (called on refresh
    /// and when a push wakes the app). Reads the PARTNER's per-author doc.
    func syncIncomingWidgetContent() async {
        guard let rel = relationship, let me = user,
              let partnerID = rel.partnerID(of: me.id),
              let content = try? await services.relationship.widgetContent(relationship: rel.id, author: partnerID)
        else { return }
        let defaults = AppGroup.defaults

        if let note = content.note,
           let at = content.noteUpdatedAt,
           at > (defaults.object(forKey: "lovio.widget.note.syncedAt") as? Date ?? .distantPast) {
            WidgetContent.saveNote(note, slot: .partner)
            defaults.set(at, forKey: "lovio.widget.note.syncedAt")
            publishWidgetSnapshot()
        }

        // Re-download when newer OR when the local file vanished (reinstall,
        // storage purge) even if we think we already synced this version.
        if let path = content.photoPath,
           let at = content.photoUpdatedAt,
           at > (defaults.object(forKey: "lovio.widget.photo.syncedAt") as? Date ?? .distantPast)
            || !WidgetContent.hasPhoto(.partner),
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
        // Only FUTURE plans — a passed date must never count upward forever.
        let nextDate = upcomingDates.first { $0.daysUntil >= 0 }

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
            distanceKilometers: distanceKilometers,
            daysSinceLastMeeting: rel.lastMeetupAt.map {
                max(0, Calendar.current.dateComponents(
                    [.day], from: Calendar.current.startOfDay(for: $0),
                    to: Calendar.current.startOfDay(for: .now)).day ?? 0)
            },
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
        snapshot.nextAnniversaryDays = rel.daysUntilNextAnniversary
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

// MARK: - One-shot coarse location (Distance widget)
//
// A single reduced-accuracy fix per request — no monitoring, no background
// tracking, effectively zero battery. Returns nil on denial/timeouts.
//
// IMPORTANT: CLLocationManager.delegate is weak. The helper MUST be retained
// for the duration of the request or the callback never fires (this is why
// Distance stayed empty even after both partners "allowed" location).

final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    /// Keeps the helper alive while waiting for Core Location (delegate is weak).
    private static var inflight: OneShotLocation?

    static func request() async -> CLLocationCoordinate2D? {
        // Serialize: one fix at a time.
        if inflight != nil { return nil }
        let helper = OneShotLocation()
        inflight = helper
        let status = helper.manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            inflight = nil
            return nil
        }
        return await withCheckedContinuation { continuation in
            helper.continuation = continuation
            helper.manager.desiredAccuracy = kCLLocationAccuracyKilometer
            helper.manager.distanceFilter = kCLDistanceFilterNone
            helper.manager.requestLocation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                helper.finish(nil)
            }
        }
    }

    /// Ask for When-In-Use permission from a retained manager (a throwaway
    /// CLLocationManager dies before the system dialog can complete).
    static func requestPermission() {
        let helper = OneShotLocation()
        inflight = helper
        helper.manager.requestWhenInUseAuthorization()
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            if inflight === helper { inflight = nil }
        }
    }

    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        guard continuation != nil else { return }
        continuation?.resume(returning: coordinate)
        continuation = nil
        if Self.inflight === self { Self.inflight = nil }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.first?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Permission dialog answered — a follow-up refresh will request the fix.
    }

    override init() {
        super.init()
        manager.delegate = self
    }
}

// MARK: - Haptics

// MARK: - Keyboard dismissal
//
// iOS keyboards have no built-in close button. Every screen with text input
// gets: a "Done" button above the keyboard + drag-down-to-dismiss on scrolls.

extension View {
    func dismissableKeyboard() -> some View {
        self.scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil)
                    }
                    .font(.body.weight(.semibold))
                }
            }
    }
}

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
