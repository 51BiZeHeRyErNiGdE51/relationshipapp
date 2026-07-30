import SwiftUI
import AppTrackingTransparency
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
                .task {
                    await model.start()
                    // UI tests / screenshot automation skip system permission prompts.
                    guard !ProcessInfo.processInfo.arguments.contains("-skip-permission-prompts") else { return }
                    await NotificationManager.shared.requestPermissionsAndSchedule(
                        reminderHour: Int(model.services.experiments.variant(for: "daily_reminder_hour")) ?? 20)
                    await requestTrackingAuthorization()
                }
        }
    }

    /// ATT prompt, deferred until after first meaningful screen renders.
    private func requestTrackingAuthorization() async {
        try? await Task.sleep(for: .seconds(2))
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
    }
}

// MARK: - App Delegate (push registration + FCM)

final class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate,
                          UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
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
        if FirebaseBootstrap.isConfigured {
            Messaging.messaging().apnsToken = deviceToken
        }
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // Persisted here; AppModel.ensureSession merges it into
        // users/{id}.fcmTokens, which Cloud Functions (firebase/functions)
        // read to deliver partner-event pushes: answered, mood, miss-you.
        UserDefaults.standard.set(fcmToken, forKey: "lovio.fcm.token")
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}

// MARK: - Local notification scheduling
//
// Server-side pushes (partner answered / mood / miss-you) live in
// firebase/functions. Everything below is scheduled on-device.

final class NotificationManager {
    static let shared = NotificationManager()
    private var center: UNUserNotificationCenter { .current() }

    func requestPermissionsAndSchedule(reminderHour: Int) async {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }

        // Daily question reminder — the single most important retention push.
        center.removePendingNotificationRequests(withIdentifiers: ["daily_question"])
        let content = UNMutableNotificationContent()
        content.title = "Today's question is waiting 💭"
        content.body = "Answer before midnight to keep your streak alive."
        content.sound = .default

        var components = DateComponents()
        components.hour = reminderHour
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
        let midpoint = deadline.addingTimeInterval(-4 * 86_400)
        let lastCall = deadline.addingTimeInterval(-1 * 86_400)
        Task {
            if midpoint > .now {
                await schedule(id: "offer_reminder_mid",
                               title: "Your couple's offer is waiting 💝",
                               body: "50% off Lovio Premium — for both of you. A few days left.",
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
        guard !isPremium else {
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
