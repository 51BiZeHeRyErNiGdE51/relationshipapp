import Foundation
import UIKit
#if canImport(TikTokBusinessSDK)
import TikTokBusinessSDK
#endif

// MARK: - TikTok App Events SDK integration
//
// Purpose: install attribution + purchase/trial events for TikTok ad
// campaigns (Spark Ads / creator content). Credentials live in Info.plist
// (TikTokAppID + TikTokAccessToken, both from TikTok Events Manager);
// like Meta, the SDK stays completely idle until both are filled in.

enum TikTokBootstrap {
    private(set) static var isConfigured = false

    private static func plistValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.hasPrefix("$(") else { return nil }
        return value
    }

    static func configure() {
        #if canImport(TikTokBusinessSDK)
        guard let tiktokAppID = plistValue("TikTokAppID"),
              let accessToken = plistValue("TikTokAccessToken") else {
            #if DEBUG
            print("🎵 TikTok SDK idle — add TikTokAppID + TikTokAccessToken to project.yml to activate.")
            #endif
            return
        }
        // appId = the numeric App Store ID of this app's listing. The SDK
        // never shows the ATT dialog itself — our permission flow owns that.
        guard let config = TikTokConfig(accessToken: accessToken,
                                        appId: "6796360734",
                                        tiktokAppId: tiktokAppID) else { return }
        TikTokBusiness.initializeSdk(config) { success, error in
            #if DEBUG
            if let error { print("🎵 TikTok SDK init failed: \(error.localizedDescription)") }
            else { print("🎵 TikTok SDK ready: \(success)") }
            #endif
        }
        isConfigured = true
        #endif
    }
}

struct TikTokAnalyticsAdapter: AnalyticsClient {
    func track(_ event: AnalyticsEvent) {
        #if canImport(TikTokBusinessSDK)
        guard TikTokBootstrap.isConfigured else { return }

        // Map funnel milestones to TikTok standard events (needed for App
        // Event Optimization); everything else flows through as custom
        // events under the same snake_case name.
        let name: String
        switch event {
        case .signInCompleted: name = "Registration"
        case .trialStarted: name = "StartTrial"
        case .purchaseCompleted: name = "Purchase"
        case .relationshipActivated: name = "AchieveLevel"
        default: name = event.name
        }

        let ttEvent = TikTokBaseEvent(name: name)
        for (key, value) in event.parameters {
            ttEvent.addProperty(withKey: key, value: value)
        }
        TikTokBusiness.trackTTEvent(ttEvent)
        #endif
    }

    func setUserProperty(_ value: String?, forName name: String) {
        // TikTok has no user-property concept comparable to GA4 — no-op.
    }
}
