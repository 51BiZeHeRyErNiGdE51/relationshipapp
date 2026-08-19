import SwiftUI

// MARK: - Onboarding
//
// Accountless flow: tutorial (3 pages) → paywall → pair with partner (or skip).
// No email, no passwords — an anonymous user is minted silently at the
// pairing step. Pairing stays available on Home for anyone who skips.

struct OnboardingFlowView: View {
    @Environment(AppModel.self) private var model

    private enum Step { case tutorial, pairing }

    @State private var step: Step = .tutorial
    @State private var page = 0
    @State private var showPaywall = false

    var body: some View {
        Group {
            switch step {
            case .tutorial: tutorial
            case .pairing: PairingStepView()
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            // Closing the paywall (or purchasing) advances to pairing.
            withAnimation(.smooth) { step = .pairing }
        } content: {
            PaywallView(source: "onboarding")
        }
    }

    // MARK: Tutorial pages

    private struct TutorialPage {
        let symbol: String
        let title: String
        let subtitle: String
        let tint: Color
    }

    private let pages: [TutorialPage] = [
        .init(symbol: "photo.on.rectangle.angled",
              title: "Any photo.\nOn their home screen.",
              subtitle: "Send whatever you want straight to your partner's widget — a selfie, a meme, a quiet moment. Only the two of you can see it. Private, encrypted, never shared.",
              tint: Lovio.Palette.rose),
        .init(symbol: "bell.badge.fill",
              title: "Love, hugs &\nmiss-you — as a ping.",
              subtitle: "Tap Love, Hug or Miss you and it lands as a push on their phone — even when the app is closed. Little signals that say you're thinking of them right now.",
              tint: Lovio.Palette.lavender),
        .init(symbol: "lock.rectangle.on.rectangle.fill",
              title: "Secret notes\njust for them.",
              subtitle: "Leave a private message on their home screen. Sealed for their eyes only — the same quiet privacy as every photo you send.",
              tint: Lovio.Palette.teal),
    ]

    private var tutorial: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                MissuoLogoMark(size: 36, shadow: false)
                Text(verbatim: "Missuo")
                    .font(Lovio.Type_.title)
                    .foregroundStyle(Lovio.Palette.plum)
                Spacer()
                // Language is changeable later in Us → Settings too.
                LanguageMenu()
                // Skip straight to pairing; Home shows the paywall right after
                // (tutorial skippers never saw the onboarding paywall).
                Button {
                    Haptics.light()
                    UserDefaults.standard.set(true, forKey: AppModel.skippedTutorialKey)
                    withAnimation(.smooth) { step = .pairing }
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .accessibilityLabel("Skip tutorial")
            }
            .padding(.horizontal, Lovio.Metrics.screenPadding)
            .padding(.top, 12)

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 26) {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(item.tint)
                                .frame(width: 130, height: 130)
                                .blur(radius: 46)
                                .opacity(0.45)
                            Image(systemName: item.symbol)
                                .font(.system(size: 76))
                                .foregroundStyle(Lovio.Gradients.hero)
                                .symbolEffect(.pulse)
                        }
                        // LocalizedStringKey(...) so the catalog translations apply
                        // (plain String properties render verbatim).
                        Text(LocalizedStringKey(item.title))
                            .font(Lovio.Type_.display)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                        Text(LocalizedStringKey(item.subtitle))
                            .font(Lovio.Type_.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                        Spacer()
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(page < pages.count - 1 ? LocalizedStringKey("Continue")
                                          : LocalizedStringKey("Get started")) {
                Haptics.light()
                if page < pages.count - 1 {
                    withAnimation(.smooth) { page += 1 }
                } else {
                    withAnimation(.smooth) { showPaywall = true }
                }
            }
            .buttonStyle(LovioPrimaryButtonStyle())
            .padding(.horizontal, Lovio.Metrics.screenPadding)
            .padding(.bottom, Lovio.Metrics.ctaBottomPadding)
        }
    }
}

// MARK: - Pairing step

struct PairingStepView: View {
    @Environment(AppModel.self) private var model

    @State private var partnerCode = ""
    @State private var anniversary = Date()
    @State private var hasAnniversary = false
    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 30)

                AvatarPair(left: model.myProfile?.initials ?? "Y",
                           right: model.isPaired ? (model.partnerProfile?.initials ?? "L") : "?",
                           size: 64)

                if model.isPaired {
                    pairedContent
                } else {
                    unpairedContent
                }
            }
            .padding(.horizontal, Lovio.Metrics.screenPadding)
            .padding(.bottom, 30)
        }
        .dismissableKeyboard()
        .task { await model.ensureSession() }   // silent anonymous sign-in + invite code
    }

    // Already connected (e.g. demo mode, or re-running the intro).
    private var pairedContent: some View {
        VStack(spacing: 18) {
            Text("You're connected 💞")
                .font(Lovio.Type_.largeTitle)
            Text("You and \(model.partnerName) share one space now. Everything either of you adds appears for both.")
                .font(Lovio.Type_.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Enter Missuo") {
                Task { await model.completeOnboarding(partnerCode: nil) }
            }
            .buttonStyle(LovioPrimaryButtonStyle())
        }
    }

    private var unpairedContent: some View {
        VStack(spacing: 18) {
            Text("Bring your person in")
                .font(Lovio.Type_.largeTitle)
            Text("Missuo works as a pair — iPhone or Android. Share your code, or enter theirs. You can also do this later.")
                .font(Lovio.Type_.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // My code
            GlassCard(tint: Lovio.Palette.rose) {
                VStack(spacing: 10) {
                    Text("Your code")
                        .font(Lovio.Type_.caption)
                        .foregroundStyle(.secondary)
                    Text(model.relationship?.inviteCode?.display ?? "· · · · · ·")
                        .font(.system(size: 38, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Lovio.Gradients.hero)
                    if let code = model.relationship?.inviteCode?.value {
                        ShareLink(item: "Join me on Missuo 💞 My code: \(code)") {
                            Label("Share with your partner", systemImage: "square.and.arrow.up")
                                .font(Lovio.Type_.headline)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Text("— or —")
                .font(Lovio.Type_.caption)
                .foregroundStyle(.tertiary)

            // Their code
            GlassCard(tint: Lovio.Palette.lavender) {
                VStack(spacing: 12) {
                    Text("Have their code?")
                        .font(Lovio.Type_.headline)
                    PartnerCodeField(code: $partnerCode)
                }
                .frame(maxWidth: .infinity)
            }

            // Optional anniversary
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $hasAnniversary.animation()) {
                        Label("We know our anniversary", systemImage: "heart.circle.fill")
                            .font(Lovio.Type_.headline)
                    }
                    .tint(Lovio.Palette.rose)
                    if hasAnniversary {
                        DatePicker("Together since", selection: $anniversary,
                                   in: ...Date(), displayedComponents: .date)
                    }
                }
            }

            Button {
                isWorking = true
                Task {
                    // Complete onboarding FIRST: entering a partner code
                    // switches to THEIR relationship document — an anniversary
                    // written before the join landed on the abandoned solo
                    // relationship and silently vanished (the bug where it
                    // "only worked from Settings").
                    await model.completeOnboarding(
                        partnerCode: partnerCode.isEmpty ? nil : partnerCode)
                    if hasAnniversary { await model.setAnniversary(anniversary) }
                    isWorking = false
                }
            } label: {
                if isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text(partnerCode.count >= 6 ? LocalizedStringKey("Connect & enter Missuo")
                                                : LocalizedStringKey("Skip for now"))
                }
            }
            .buttonStyle(LovioPrimaryButtonStyle())
            .disabled(isWorking)
        }
    }
}

// MARK: - Reusable partner-code entry (also used from Home)

struct PartnerCodeField: View {
    @Binding var code: String

    var body: some View {
        TextField("LVQ-7R3", text: $code)
            .font(.system(size: 28, weight: .bold, design: .monospaced))
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
    }
}

struct JoinPartnerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 22) {
            Capsule().fill(.tertiary).frame(width: 36, height: 5).padding(.top, 10)
            Text("Enter your partner's code")
                .font(Lovio.Type_.title)
            PartnerCodeField(code: $code)
                .padding(.horizontal)
            Button {
                isWorking = true
                Task {
                    await model.joinRelationship(code: code)
                    isWorking = false
                    if model.isPaired { dismiss() }
                }
            } label: {
                if isWorking { ProgressView().tint(.white) } else { Text("Connect") }
            }
            .buttonStyle(LovioPrimaryButtonStyle())
            .padding(.horizontal)
            .disabled(code.count < 6 || isWorking)
            Spacer()
        }
        .dismissableKeyboard()
        .presentationDetents([.medium])
        .presentationBackground(.thinMaterial)
    }
}
