import SwiftUI

// MARK: - Onboarding
//
// Accountless flow: tutorial (3 pages) → paywall → pair with partner (or skip).
// No email, no passwords — an anonymous user is minted silently at the
// pairing step. Pairing stays available on Home for anyone who skips.

struct OnboardingFlowView: View {
    @Environment(AppModel.self) private var model

    private enum Step { case tutorial, age, pairing }

    @State private var step: Step = .tutorial
    @State private var page = 0
    @State private var showPaywall = false

    var body: some View {
        Group {
            switch step {
            case .tutorial: tutorial
            case .age: AgeGateView { withAnimation(.smooth) { showPaywall = true } }
            case .pairing: PairingStepView()
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            // Closing the paywall (or purchasing) advances to pairing.
            withAnimation(.smooth) { step = .pairing }
        } content: {
            PaywallView(source: "onboarding")
        }
        .onAppear {
            // Returning underage users land directly on the (blocked) age gate.
            if let dob = AppModel.storedBirthday, AppModel.age(from: dob) < AppModel.minimumAge {
                step = .age
            }
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
        .init(symbol: "bubble.left.and.bubble.right.fill",
              title: "One question.\nEvery day.",
              subtitle: "You both answer blind — answers unlock only when you've both replied. The little ritual couples look forward to.",
              tint: Lovio.Palette.lavender),
        .init(symbol: "square.grid.2x2.fill",
              title: "Your home screens,\nconnected.",
              subtitle: "Moods, countdowns, secret notes and a heartbeat that pulses when you're both online — live on your home screen, no app opening needed.",
              tint: Lovio.Palette.rose),
        .init(symbol: "camera.macro",
              title: "Grow something\ntogether.",
              subtitle: "A shared garden that blooms when you show up for each other — and wilts when you don't. Streaks, memories, milestones. All of it, yours.",
              tint: Lovio.Palette.teal),
    ]

    private var tutorial: some View {
        VStack(spacing: 0) {
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
                        Text(item.title)
                            .font(Lovio.Type_.display)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                        Text(item.subtitle)
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

            Button(page < pages.count - 1 ? "Continue" : "Get started") {
                Haptics.light()
                if page < pages.count - 1 {
                    withAnimation(.smooth) { page += 1 }
                } else {
                    withAnimation(.smooth) { step = .age }
                }
            }
            .buttonStyle(LovioPrimaryButtonStyle())
            .padding(.horizontal, Lovio.Metrics.screenPadding)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Age gate (16+)
//
// Stores date of birth, never an "is adult" boolean — age is recomputed on
// every launch, so a 15-year-old is admitted automatically on their 16th
// birthday, and the check stays valid as time passes.

struct AgeGateView: View {
    @Environment(AppModel.self) private var model
    var onPassed: () -> Void

    @State private var birthday = Calendar.current.date(byAdding: .year, value: -20, to: .now)!
    @State private var isUnderage = AppModel.storedBirthday.map {
        AppModel.age(from: $0) < AppModel.minimumAge
    } ?? false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: isUnderage ? "hourglass" : "birthday.cake.fill")
                .font(.system(size: 56))
                .foregroundStyle(Lovio.Gradients.hero)

            if isUnderage {
                Text("See you soon 💛")
                    .font(Lovio.Type_.largeTitle)
                Text("Lovio is for people aged \(AppModel.minimumAge) and up. Based on the birthday you entered, you can join on \(sixteenthBirthday.formatted(date: .long, time: .omitted)) — we'll be here.")
                    .font(Lovio.Type_.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Button("I entered the wrong birthday") {
                    withAnimation(.smooth) { isUnderage = false }
                }
                .font(Lovio.Type_.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("When were you born?")
                    .font(Lovio.Type_.largeTitle)
                Text("Lovio is for ages \(AppModel.minimumAge)+. We use your birthday only for this check and for anniversary magic later.")
                    .font(Lovio.Type_.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                DatePicker("Birthday", selection: $birthday, in: ...Date(),
                           displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()

                Button("Continue") {
                    if model.submitBirthday(birthday) {
                        Haptics.light()
                        onPassed()
                    } else {
                        Haptics.success()
                        withAnimation(.smooth) { isUnderage = true }
                    }
                }
                .buttonStyle(LovioPrimaryButtonStyle())
                .padding(.horizontal, Lovio.Metrics.screenPadding)
            }

            Spacer()
        }
    }

    private var sixteenthBirthday: Date {
        guard let dob = AppModel.storedBirthday else { return .now }
        return Calendar.current.date(byAdding: .year, value: AppModel.minimumAge, to: dob) ?? .now
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
        .scrollDismissesKeyboard(.interactively)
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
            Button("Enter Lovio") {
                Task { await model.completeOnboarding(partnerCode: nil) }
            }
            .buttonStyle(LovioPrimaryButtonStyle())
        }
    }

    private var unpairedContent: some View {
        VStack(spacing: 18) {
            Text("Bring your person in")
                .font(Lovio.Type_.largeTitle)
            Text("Lovio works as a pair — iPhone or Android. Share your code, or enter theirs. You can also do this later.")
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
                        ShareLink(item: "Join me on Lovio 💞 My code: \(code)") {
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
                    if hasAnniversary { await model.setAnniversary(anniversary) }
                    await model.completeOnboarding(
                        partnerCode: partnerCode.isEmpty ? nil : partnerCode)
                    isWorking = false
                }
            } label: {
                if isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text(partnerCode.count >= 6 ? "Connect & enter Lovio" : "Skip for now")
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
        .presentationDetents([.medium])
        .presentationBackground(.thinMaterial)
    }
}
