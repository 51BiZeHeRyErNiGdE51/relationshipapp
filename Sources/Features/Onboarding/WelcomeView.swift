import SwiftUI
import AuthenticationServices

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Lovio.Gradients.hero)
                        .frame(width: 130, height: 130)
                        .blur(radius: 42)
                        .opacity(0.55)
                    HeartPulse(size: 74)
                }
                .scaleEffect(appeared ? 1 : 0.7)

                VStack(spacing: 10) {
                    Text("Lovio")
                        .font(Lovio.Type_.display)
                        .foregroundStyle(Lovio.Gradients.hero)

                    Text("Feel close, every single day.")
                        .font(Lovio.Type_.title)
                        .multilineTextAlignment(.center)

                    Text("One question a day. Shared memories. Widgets that keep you on each other's home screen.")
                        .font(Lovio.Type_.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
            }

            Spacer()

            // Auth
            VStack(spacing: 12) {
                SignInWithAppleButton(.continue) { _ in } onCompletion: { _ in }
                    .allowsHitTesting(false)
                    .frame(height: 52)
                    .clipShape(Capsule())
                    .overlay {
                        // Route through our AuthService so demo mode also works.
                        Color.clear.contentShape(Capsule())
                            .onTapGesture { Task { await model.signIn(with: .apple) } }
                    }

                Button {
                    Task { await model.signIn(with: .google) }
                } label: {
                    Label("Continue with Google", systemImage: "g.circle.fill")
                }
                .buttonStyle(LovioSecondaryButtonStyle())

                if model.isDemoMode {
                    Button("Explore the demo couple") {
                        Task { await model.signIn(with: .demo) }
                    }
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }

                Text("Free to start · Premium is shared with your partner")
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }
            .padding(.horizontal, Lovio.Metrics.screenPadding)
            .padding(.bottom, 28)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            model.services.analytics.track(.onboardingStarted)
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.15)) {
                appeared = true
            }
        }
    }
}
