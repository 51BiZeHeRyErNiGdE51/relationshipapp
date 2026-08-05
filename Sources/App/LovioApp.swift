import SwiftUI
import UserNotifications
import FirebaseMessaging

@main
struct LovioApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.bootstrap()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                // System permission prompts (ATT, push) are intentionally NOT
                // requested here — AppModel.runPermissionPrompts() asks them
                // one at a time once the user reaches the main screen.
                .task { await model.start() }
        }
    }
}

// MARK: - App Delegate (push registration + FCM)

final class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate,
                          UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Configure before Meta / Analytics so nothing touches Firebase first.
        _ = FirebaseBootstrap.configureIfPossible()
        UNUserNotificationCenter.current().delegate = self
        MetaBootstrap.configure(application: application, launchOptions: launchOptions)
        if FirebaseBootstrap.isConfigured {
            Messaging.messaging().delegate = self
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Meta deferred deep links (Instagram ad attribution).
        MetaBootstrap.handle(url: url)
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard FirebaseBootstrap.isConfigured else { return }
        // Swizzling is OFF (FirebaseAppDelegateProxyEnabled=false) — we MUST
        // tell FCM the APNs token AND the environment. Wrong type → Apple
        // rejects sends even when the .p8 key looks correct in Firebase.
        #if DEBUG
        Messaging.messaging().setAPNSToken(deviceToken, type: .sandbox)
        #else
        Messaging.messaging().setAPNSToken(deviceToken, type: .prod)
        #endif
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error.localizedDescription)")
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // Persisted here; AppModel merges it into users/{id}.fcmTokens (on
        // session start AND every refresh — the token often arrives only
        // after the user grants push permission, which happens well after
        // ensureSession). Cloud Functions read it to deliver partner pushes.
        UserDefaults.standard.set(fcmToken, forKey: "lovio.fcm.token")
        // Upload immediately so partner pushes work without waiting for a refresh.
        Task { @MainActor in
            await AppModel.current?.backgroundSync()
        }
    }

    /// Alert + content-available pushes wake us here (even from background)
    /// so we can pull photos onto widgets without the user opening the app.
    /// Note: if the user force-quits the app, iOS will not deliver silent
    /// wakes — but the alert banner still shows; tapping it syncs.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let model = AppModel.current else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            await model.backgroundSync()
            completionHandler(.newData)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Sync while showing the banner in the foreground.
        Task { @MainActor in await AppModel.current?.backgroundSync() }
        return [.banner, .sound, .badge]
    }

    /// Tapping a partner notification also syncs right away.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        await AppModel.current?.backgroundSync()
    }
}

// MARK: - Local notification scheduling
//
// Server-side pushes (partner answered / mood / miss-you) live in
// firebase/functions. Everything below is scheduled on-device.

final class NotificationManager {
    static let shared = NotificationManager()
    private var center: UNUserNotificationCenter { .current() }

    // User-facing notification preferences (Settings → Notifications).
    // Missing key == enabled, so pushes work out of the box.
    enum Pref {
        static let dailyEnabled = "missuo.notif.daily.enabled"
        static let dailyHour = "missuo.notif.daily.hour"
        static let dailyMinute = "missuo.notif.daily.minute"
        static let eventsEnabled = "missuo.notif.events.enabled"
        static let offersEnabled = "missuo.notif.offers.enabled"

        static func isOn(_ key: String) -> Bool {
            UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key)
        }
    }

    func requestPermissionsAndSchedule(reminderHour: Int) async {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }
        await applyDailyReminder(defaultHour: reminderHour)
    }

    /// Immediate local banner (partner hug / miss-you / heart) — used when we
    /// detect an event in-app, and as a fallback until remote APNs is solid.
    func postLocal(title: String, body: String) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "love_\(UUID().uuidString)",
            content: content,
            trigger: nil) // deliver immediately
        try? await center.add(request)
    }

    /// Daily question reminder — the single most important retention push.
    /// Time defaults to the remote-config experiment; the user's own choice
    /// in Settings always wins.
    func applyDailyReminder(defaultHour: Int) async {
        center.removePendingNotificationRequests(withIdentifiers: ["daily_question"])
        guard Pref.isOn(Pref.dailyEnabled) else { return }

        let defaults = UserDefaults.standard
        let hour = defaults.object(forKey: Pref.dailyHour) != nil
            ? defaults.integer(forKey: Pref.dailyHour) : defaultHour
        let minute = defaults.integer(forKey: Pref.dailyMinute)

        let content = UNMutableNotificationContent()
        content.title = "Today's question is waiting 💭"
        content.body = "Answer before midnight to keep your streak alive."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: "daily_question",
                                                    content: content, trigger: trigger))
    }

    // MARK: Special date reminders ("auto notifications for events")

    /// Day-before (10:00) and day-of (09:00) reminders for upcoming dates.
    func scheduleEventReminders(dates: [SpecialDate]) async {
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier).filter { $0.hasPrefix("event_") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard Pref.isOn(Pref.eventsEnabled) else { return }

        for date in dates.prefix(10) {
            let days = date.daysUntil
            guard days > 0 else { continue }

            if let dayBefore = Calendar.current.date(byAdding: .day, value: days - 1,
                                                     to: Calendar.current.startOfDay(for: .now)),
               days >= 1 {
                await schedule(id: "event_\(date.id)_pre",
                               title: "Tomorrow: \(date.title) 💛",
                               body: "One more sleep. Anything left to plan together?",
                               at: dayBefore, hour: 10)
            }
            if let dayOf = Calendar.current.date(byAdding: .day, value: days,
                                                 to: Calendar.current.startOfDay(for: .now)) {
                await schedule(id: "event_\(date.id)_day",
                               title: "Today: \(date.title) 🎉",
                               body: "It's here — make it count.",
                               at: dayOf, hour: 9)
            }
        }
    }

    // MARK: Monetization reminders

    /// Two nudges inside the 7-day secondary-offer window.
    func scheduleOfferReminders(deadline: Date) {
        guard Pref.isOn(Pref.offersEnabled) else { return }
        let midpoint = deadline.addingTimeInterval(-4 * 86_400)
        let lastCall = deadline.addingTimeInterval(-1 * 86_400)
        Task {
            if midpoint > .now {
                await schedule(id: "offer_reminder_mid",
                               title: "Your couple's offer is waiting 💝",
                               body: "50% off Missuo Premium — for both of you. A few days left.",
                               at: midpoint, hour: 19)
            }
            if lastCall > .now {
                await schedule(id: "offer_reminder_last",
                               title: "Last day: 50% off for you two",
                               body: "Your discounted Premium offer expires tomorrow.",
                               at: lastCall, hour: 19)
            }
        }
    }

    /// Gentle weekly reminder for free users; cancelled on purchase.
    func scheduleWeeklyPremiumNudge(isPremium: Bool) {
        guard !isPremium, Pref.isOn(Pref.offersEnabled) else {
            center.removePendingNotificationRequests(withIdentifiers: ["premium_weekly"])
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "One subscription, two of you 💞"
        content.body = "All widgets, the AI coach and every companion — shared with your partner."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 7 * 86_400, repeats: true)
        center.add(UNNotificationRequest(identifier: "premium_weekly",
                                         content: content, trigger: trigger))
    }

    func cancelMonetizationReminders() {
        center.removePendingNotificationRequests(withIdentifiers:
            ["offer_reminder_mid", "offer_reminder_last", "premium_weekly"])
    }

    // MARK: Helpers

    private func schedule(id: String, title: String, body: String, at day: Date, hour: Int) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
