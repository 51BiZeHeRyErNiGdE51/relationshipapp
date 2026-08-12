import FBSDKCoreKit
import Foundation
import UIKit

// MARK: - Meta (Facebook) SDK integration
//
// Purpose: install attribution + purchase/subscription events for Instagram
// and Facebook ad campaigns. App ID lives in Info.plist (FacebookAppID);
// activation is guarded until FacebookClientToken is filled in, so the app
// runs safely while credentials are incomplete.
//
// Note on revenue events: for exact purchase values, prefer enabling the
// RevenueCat → Meta Ads server-side integration (survives app deletion and
// ATT denials). The client-side events below cover funnel optimization.

enum MetaBootstrap {
    private(set) static var isConfigured = false

    private static var clientToken: String? {
        Bundle.main.object(forInfoDictionaryKey: "FacebookClientToken") as? String
    }

    static func configure(application: UIApplication,
                          launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        guard let token = clientToken, !token.isEmpty else {
            #if DEBUG
            print("📘 Meta SDK idle — add FacebookClientToken to project.yml to activate.")
            #endif
            return
        }
        // FBSDK aborts if our Privacy Manifest lists facebook.com tracking domains
        // (it ships its own). Keep this false as a safety belt.
        Settings.shared.isDomainErrorEnabled = false
        ApplicationDelegate.shared.application(application,
                                               didFinishLaunchingWithOptions: launchOptions)
        isConfigured = true
    }

    /// Deep links / deferred deep links from Meta ads.
    static func handle(url: URL) {
        guard isConfigured else { return }
        ApplicationDelegate.shared.application(UIApplication.shared, open: url, options: [:])
    }
}

struct MetaAnalyticsAdapter: AnalyticsClient {
    func track(_ event: AnalyticsEvent) {
        guard MetaBootstrap.isConfigured else { return }
        let parameters = Dictionary(uniqueKeysWithValues: event.parameters.map {
            (AppEvents.ParameterName($0.key), $0.value as Any)
        })

        // Map funnel milestones to Meta standard events for ad optimization;
        // everything else flows through as custom events under the same name.
        switch event {
        case .signInCompleted:
            AppEvents.shared.logEvent(.completedRegistration, parameters: parameters)
        case .trialStarted:
            AppEvents.shared.logEvent(.startTrial, parameters: parameters)
        case .purchaseCompleted:
            AppEvents.shared.logEvent(.subscribe, parameters: parameters)
        case .relationshipActivated:
            AppEvents.shared.logEvent(.achievedLevel, parameters: parameters)
        default:
            AppEvents.shared.logEvent(AppEvents.Name(event.name), parameters: parameters)
        }
    }

    func setUserProperty(_ value: String?, forName name: String) {
        // Meta has no user-property concept comparable to GA4 — intentionally a no-op.
    }
}
