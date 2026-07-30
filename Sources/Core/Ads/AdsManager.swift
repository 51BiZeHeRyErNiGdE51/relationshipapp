import GoogleMobileAds
import SwiftUI
import UIKit

// MARK: - Ads (free tier only)
//
// Google Mobile Ads with Google's official TEST unit IDs — swap for your real
// AdMob unit IDs (and the GADApplicationIdentifier in project.yml) before
// release. Premium users never see ads; the banner also doubles as a paywall
// entry point ("Remove ads").

enum AdsManager {
    /// TEST banner unit. Replace with your real unit from apps.admob.com.
    static let bannerUnitID = "ca-app-pub-3940256099942544/2934735716"

    private static var isStarted = false

    static func ensureStarted() {
        guard !isStarted else { return }
        isStarted = true
        MobileAds.shared.start(completionHandler: nil)
    }
}

/// Adaptive banner wrapped for SwiftUI.
struct BannerAdView: UIViewRepresentable {
    func makeUIView(context: Context) -> BannerView {
        AdsManager.ensureStarted()
        let width = UIScreen.main.bounds.width - 2 * Lovio.Metrics.screenPadding
        let banner = BannerView(adSize: currentOrientationAnchoredAdaptiveBanner(width: width))
        banner.adUnitID = AdsManager.bannerUnitID
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}

/// Banner card with a "remove ads" premium hook underneath.
struct AdBannerCard: View {
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 6) {
            BannerAdView()
                .frame(height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            Button {
                showPaywall = true
            } label: {
                Text("Remove ads with Premium")
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: "remove_ads")
        }
    }
}
