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
                    HeartPulse(size: 52)
                    Text("Missuo")
                        .font(Lovio.Type_.display)
                        .foregroundStyle(Lovio.Gradients.hero)
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

    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Today", systemImage: "heart.fill") }

            // Widgets are the flagship engagement surface — first-class tab.
            NavigationStack { WidgetGalleryView() }
                .tabItem { Label("Widgets", systemImage: "square.grid.2x2.fill") }

            NavigationStack { MemoriesView() }
                .tabItem { Label("Memories", systemImage: "book.closed.fill") }

            NavigationStack { PlanView() }
                .tabItem { Label("Plans", systemImage: "calendar") }

            NavigationStack { UsView() }
                .tabItem { Label("Us", systemImage: "person.2.fill") }
        }
        .tint(Lovio.Palette.rose)
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: "session_start")
        }
        .onAppear {
            // Soft paywall exposure for free users — at most once per day.
            let key = "lovio.paywall.lastShownDay"
            let today = DayKey.today()
            if !model.premium.isPremium, UserDefaults.standard.string(forKey: key) != today {
                UserDefaults.standard.set(today, forKey: key)
                showPaywall = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await model.drainWidgetOutbox()
                await model.refreshToday()
            }
        }
    }
}
