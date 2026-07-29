import SwiftUI

struct PairingView: View {
    enum Mode { case choose, waiting }

    @Environment(AppModel.self) private var model
    let mode: Mode

    @State private var codeInput = ""
    @State private var anniversary = Date()
    @State private var hasAnniversary = false
    @State private var showJoin = false

    var body: some View {
        VStack(spacing: Lovio.Metrics.sectionSpacing) {
            Spacer()

            AvatarPair(left: model.myProfile?.initials ?? "Y", right: "?", size: 64)

            switch mode {
            case .choose: chooseContent
            case .waiting: waitingContent
            }

            Spacer()
        }
        .padding(.horizontal, Lovio.Metrics.screenPadding)
    }

    // MARK: Choose: invite or join

    private var chooseContent: some View {
        VStack(spacing: 20) {
            Text("Bring your person in")
                .font(Lovio.Type_.largeTitle)
            Text("Lovio works as a pair. Invite your partner, or enter the code they sent you — Android or iPhone, both work.")
                .font(Lovio.Type_.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: $hasAnniversary.animation()) {
                        Label("We know our anniversary", systemImage: "heart.circle.fill")
                            .font(Lovio.Type_.headline)
                    }
                    .tint(Lovio.Palette.rose)

                    if hasAnniversary {
                        DatePicker("Together since", selection: $anniversary,
                                   in: ...Date(), displayedComponents: .date)
                            .font(Lovio.Type_.body)
                    }
                }
            }

            Button("Create our invite code") {
                Task { await model.createRelationship(anniversary: hasAnniversary ? anniversary : nil) }
            }
            .buttonStyle(LovioPrimaryButtonStyle())

            Button("I have a code from my partner") {
                showJoin = true
            }
            .buttonStyle(LovioSecondaryButtonStyle())
        }
        .sheet(isPresented: $showJoin) { joinSheet }
    }

    private var joinSheet: some View {
        VStack(spacing: 24) {
            Capsule().fill(.tertiary).frame(width: 36, height: 5).padding(.top, 10)
            Text("Enter your partner's code")
                .font(Lovio.Type_.title)

            TextField("LVQ-7R3", text: $codeInput)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                .padding(.horizontal)

            Button("Connect") {
                Task {
                    await model.joinRelationship(code: codeInput)
                    showJoin = false
                }
            }
            .buttonStyle(LovioPrimaryButtonStyle())
            .padding(.horizontal)
            .disabled(codeInput.count < 6)

            Spacer()
        }
        .presentationDetents([.medium])
        .presentationBackground(.thinMaterial)
    }

    // MARK: Waiting for partner

    private var waitingContent: some View {
        VStack(spacing: 20) {
            Text("Your code is ready")
                .font(Lovio.Type_.largeTitle)

            Text(model.relationship?.inviteCode?.display ?? "———")
                .font(.system(size: 44, weight: .heavy, design: .monospaced))
                .foregroundStyle(Lovio.Gradients.hero)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
                .contextMenu {
                    Button("Copy", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = model.relationship?.inviteCode?.value
                    }
                }

            Text("Send it to your partner. The moment they enter it, your shared space unlocks — and if either of you has Premium, you both do.")
                .font(Lovio.Type_.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let code = model.relationship?.inviteCode?.value {
                ShareLink(item: "Join me on Lovio 💞 My code: \(code)") {
                    Label("Share invite", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(LovioPrimaryButtonStyle())
            }

            if model.isDemoMode {
                Button("Simulate partner joining (demo)") {
                    Task { await model.simulatePartnerJoined() }
                }
                .font(Lovio.Type_.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
