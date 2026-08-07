import Combine
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        @Bindable var model = model
        ZStack {
            Lovio.Gradients.ambient(scheme).ignoresSafeArea()

            switch model.phase {
            case .loading:
                VStack(spacing: 16) {
                    MissuoLogoMark(size: 88)
                    Text("Missuo")
                        .font(Lovio.Type_.display)
                        .foregroundStyle(Lovio.Palette.plum)
                    if model.startupFailed {
                        Text("We couldn't connect. Check your internet and try again.")
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Button("Try Again") {
                            Task { await model.start() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Lovio.Palette.rose)
                    } else {
                        ProgressView()
                            .tint(Lovio.Palette.rose)
                            .padding(.top, 4)
                    }
                }
                .transition(.opacity)

            case .onboarding:
                OnboardingFlowView()
                    .transition(.opacity)

            case .active:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.45), value: model.phase)
        .alert("Something went wrong", isPresented: .init(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - Main tabs

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @State private var showPaywall = false
    @State private var loveBurst: HomeView.HeartBurst?

    var body: some View {
        TabView {
            withStickyBanner { HomeView() }
                .tabItem { Label("Today", systemImage: "heart.fill") }

            // Widgets are the flagship engagement surface — first-class tab.
            withStickyBanner { WidgetGalleryView() }
                .tabItem { Label("Widgets", systemImage: "square.grid.2x2.fill") }

            withStickyBanner { MemoriesView() }
                .tabItem { Label("Memories", systemImage: "book.closed.fill") }

            withStickyBanner { PlayView() }
                .tabItem { Label("Play", systemImage: "gamecontroller.fill") }

            withStickyBanner { UsView() }
                .tabItem { Label("Us", systemImage: "person.2.fill") }
        }
        .tint(Lovio.Palette.rose)
        // Global love burst — lives above every tab so a hug/miss-you
        // still animates even when you're not on the Home screen.
        .overlay {
            if model.justPaired {
                PairedCelebrationView(partnerName: model.partnerFirstName ?? "your love") {
                    model.justPaired = false
                }
            } else if let burst = loveBurst {
                HeartBurstView(burst: burst)
            }
        }
        .onChange(of: model.incomingLove) { _, love in
            guard let love else { return }
            let who = model.partnerFirstName ?? L10n.s("Your love")
            let title: String
            let emoji: String
            switch love.kind {
            case .heartTap:
                title = love.count == 1
                    ? L10n.s("%@ dropped a heart in your jar", who)
                    : L10n.s("%@ dropped %@ hearts in your jar", who, "\(love.count)")
                emoji = "💛"
            case .hugSent:
                title = love.count > 1
                    ? L10n.s("%@ sent you a hug ×%@", who, "\(love.count)")
                    : L10n.s("%@ sent you a hug 🤗", who)
                emoji = "🤗"
            default:
                title = love.count > 1
                    ? L10n.s("%@ misses you ×%@", who, "\(love.count)")
                    : L10n.s("%@ misses you 🥺", who)
                emoji = "💌"
            }
            withAnimation(.smooth) { loveBurst = HomeView.HeartBurst(title: title, emoji: emoji) }
            model.incomingLove = nil
            Task {
                try? await Task.sleep(for: .seconds(2.8))
                withAnimation(.smooth) { loveBurst = nil }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: "session_start")
        }
        .task {
            // Fresh data on cold start (pairing status, partner photo, jar).
            await model.refreshToday()
            // Strict order, one thing on screen at a time:
            // 1) ATT dialog  2) push dialog  3) (maybe) daily paywall.
            await model.runPermissionPrompts()
            maybeShowSessionPaywall()
            // Gentle foreground poll so the partner joining, hearts and
            // widget photos show up WITHOUT pull-to-refresh.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await model.refreshToday()
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await model.drainWidgetOutbox()
                await model.refreshToday()
                // Picks up the user flipping notifications on in Settings.
                await model.refreshNotificationStatus()
            }
        }
    }

    /// Soft paywall exposure for free users. Respectful cadence:
    /// they already saw the paywall in onboarding and (if declined) get the
    /// 7-day offer chip + reminder pushes — so we never auto-open the paywall
    /// while that offer window runs, and at most once a week afterwards.
    /// Locked features remain the natural upsell in between.
    private func maybeShowSessionPaywall() {
        if UserDefaults.standard.bool(forKey: "lovio.paywall.skipSessionStartOnce") {
            UserDefaults.standard.set(false, forKey: "lovio.paywall.skipSessionStartOnce")
            return
        }
        guard !model.premium.isPremium else { return }
        // Offer window running → the Home chip is already selling; stay quiet.
        if model.secondaryOfferDeadline != nil, model.isSecondaryOfferActive { return }

        let key = "missuo.paywall.lastAutoShownAt"
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard Date.now.timeIntervalSince(last) >= 7 * 86_400 else { return }
        UserDefaults.standard.set(Date(), forKey: key)
        showPaywall = true
    }

    /// Wraps a tab's root view so free users get a sticky ad banner pinned
    /// directly above the tab bar — content scrolls behind, banner stays put.
    private func withStickyBanner<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack { content() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !model.premium.isPremium {
                    StickyAdBanner()
                }
            }
    }
}
