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
    #if DEBUG
    /// Google's official test banner in debug builds — clicking your own real
    /// ads violates AdMob policy and can get the account suspended.
    static let bannerUnitID = "ca-app-pub-3940256099942544/2934735716"
    #else
    /// Production banner unit (bsekapps).
    static let bannerUnitID = "ca-app-pub-8078875407027697/9269412510"
    #endif

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
        let width = UIScreen.main.bounds.width
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

/// Sticky banner pinned above the tab bar for free users — always visible.
/// Nothing overlaps the ad itself (AdMob policy); a hairline divider separates
/// it from content, and the bar background matches the tab bar.
struct StickyAdBanner: View {
    /// Adaptive banners pick their own height for the device width.
    private var bannerHeight: CGFloat {
        currentOrientationAnchoredAdaptiveBanner(width: UIScreen.main.bounds.width).size.height
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            BannerAdView()
                .frame(maxWidth: .infinity)
                .frame(height: bannerHeight)
        }
        .background(.bar)
    }
}
