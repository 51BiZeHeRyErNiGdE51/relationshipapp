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
        // Token is uploaded to users/{id}.fcmTokens on next profile save.
        // Cloud Functions use it for: partner answered, mood changed, miss-you,
        // anniversary, streak-at-risk and AI weekly summary pushes.
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}

// MARK: - Local notification scheduling

final class NotificationManager {
    static let shared = NotificationManager()

    func requestPermissionsAndSchedule(reminderHour: Int) async {
        let center = UNUserNotificationCenter.current()
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
}
