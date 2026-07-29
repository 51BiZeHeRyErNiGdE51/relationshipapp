import SwiftUI

// MARK: - Widget Gallery
//
// Widgets are the defining feature: this screen sells the home screen takeover.
// Free tier: 1 widget. Premium: all families.

struct WidgetGalleryView: View {
    @Environment(AppModel.self) private var model
    @State private var showPaywall = false

    struct WidgetSpec: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let tint: Color
        let isPremium: Bool
    }

    private let specs: [WidgetSpec] = [
        .init(id: "love_days", title: "Love Days", subtitle: "Days together, always in sight", symbol: "heart.fill", tint: Lovio.Palette.rose, isPremium: false),
        .init(id: "love_pulse", title: "Love Pulse", subtitle: "Heart beats when you're both online", symbol: "waveform.path.ecg.rectangle.fill", tint: Lovio.Palette.rose, isPremium: true),
        .init(id: "open_question", title: "Open Question", subtitle: "Today's question, no app needed", symbol: "bubble.left.and.bubble.right.fill", tint: Lovio.Palette.lavender, isPremium: true),
        .init(id: "mood_sync", title: "Mood Sync", subtitle: "Both moods + energy, side by side", symbol: "face.smiling.inverse", tint: Lovio.Palette.teal, isPremium: true),
        .init(id: "next_adventure", title: "Next Adventure", subtitle: "Countdown to your next plan", symbol: "airplane.departure", tint: Lovio.Palette.peach, isPremium: true),
        .init(id: "miss_you", title: "Missing You", subtitle: "Tap to send an instant 'miss you'", symbol: "paperplane.fill", tint: Lovio.Palette.rose, isPremium: true),
        .init(id: "secret_message", title: "Secret Message", subtitle: "Blurred note — tap to reveal", symbol: "envelope.badge.shield.half.filled.fill", tint: Lovio.Palette.plum, isPremium: true),
        .init(id: "love_jar", title: "Love Jar", subtitle: "Collect hearts together", symbol: "cylinder.split.1x2.fill", tint: Lovio.Palette.gold, isPremium: true),
        .init(id: "hug_meter", title: "Hug Meter", subtitle: "Days since you last met", symbol: "figure.2.arms.open", tint: Lovio.Palette.teal, isPremium: true),
        .init(id: "companion", title: "Companion", subtitle: "Your shared world, growing daily", symbol: "camera.macro", tint: Lovio.Palette.teal, isPremium: true),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard(tint: Lovio.Palette.lavender) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How to add").font(Lovio.Type_.headline)
                        Text("Touch and hold your home screen → tap + → search \"Lovio\". Stack several — couples with 3+ widgets open the app twice as often.")
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !model.premium.isPremium {
                    Button { showPaywall = true } label: {
                        GlassCard(tint: Lovio.Palette.gold) {
                            Label("Free includes Love Days. Unlock all \(specs.count) families with Premium.",
                                  systemImage: "crown.fill")
                                .font(Lovio.Type_.body)
                                .foregroundStyle(Lovio.Palette.gold)
                        }
                    }
                    .buttonStyle(.plain)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(specs) { spec in
                        GlassCard(tint: spec.tint) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: spec.symbol)
                                        .font(.title2)
                                        .foregroundStyle(spec.tint)
                                    Spacer()
                                    if spec.isPremium && !model.premium.isPremium {
                                        Image(systemName: "crown.fill")
                                            .font(.caption)
                                            .foregroundStyle(Lovio.Palette.gold)
                                    }
                                }
                                Text(spec.title).font(Lovio.Type_.headline)
                                Text(spec.subtitle)
                                    .font(Lovio.Type_.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(height: 42, alignment: .top)
                            }
                        }
                    }
                }
            }
            .padding(Lovio.Metrics.screenPadding)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Widgets")
        .sheet(isPresented: $showPaywall) { PaywallView(source: "widget_gallery") }
        .onAppear {
            model.services.analytics.track(.widgetGalleryViewed)
            model.publishWidgetSnapshot()
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showEndRelationship = false

    var body: some View {
        List {
            Section("Profile") {
                LabeledContent("Name", value: model.myName)
                LabeledContent("Partner", value: model.partnerName)
                if let code = model.relationship?.inviteCode?.display {
                    LabeledContent("Invite code", value: code)
                }
            }

            Section("Subscription") {
                LabeledContent("Plan", value: model.premium.isPremium ? "Premium" : "Free")
                if model.premium.inheritedFromPartner {
                    Text("Shared from \(model.partnerName)'s subscription 💛")
                        .font(Lovio.Type_.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Restore purchases") {
                    Task { await model.restorePurchases() }
                }
            }

            Section("Notifications") {
                NavigationLink("Daily question reminder") {
                    Text("Reminder time is remote-config driven (experiment: daily_reminder_hour).")
                        .padding()
                }
            }

            Section("Privacy") {
                Text("Your journal, answers and moods are visible only to the two of you. iCloud backup keeps private notes on your device account.")
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Sign out") { Task { await model.signOut() } }
                Button("End relationship", role: .destructive) { showEndRelationship = true }
            } footer: {
                Text(model.isDemoMode
                     ? "Running in demo mode — add GoogleService-Info.plist to connect Firebase."
                     : "Lovio \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("End this relationship?", isPresented: $showEndRelationship,
                            titleVisibility: .visible) {
            Button("End relationship", role: .destructive) {
                Task {
                    if let rel = model.relationship, let me = model.user {
                        try? await model.services.relationship.endRelationship(rel.id, endedBy: me.id)
                        await model.signOut()
                    }
                }
            }
        } message: {
            Text("Shared content is archived. If you purchased Premium, it stays with you and follows you into a future relationship.")
        }
    }
}
