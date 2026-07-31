import PhotosUI
import SwiftUI

// MARK: - Widget hub
//
// Widgets are the defining feature: this tab sells the home screen takeover
// AND is where users push content (photo, love note) onto their widgets.
// Free tier: 1 widget. Premium: all families.

struct WidgetGalleryView: View {
    @Environment(AppModel.self) private var model
    @State private var showPaywall = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoSaved = false
    @State private var note = WidgetContent.note ?? ""
    @State private var noteSaved = false

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
        .init(id: "polaroid", title: "Polaroid", subtitle: "Your photo + note on the home screen", symbol: "photo.on.rectangle.angled", tint: Lovio.Palette.peach, isPremium: false),
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
                sendPhotoCard
                sendNoteCard

                GlassCard(tint: Lovio.Palette.lavender) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("How to add a widget", systemImage: "plus.square.on.square")
                            .font(Lovio.Type_.headline)
                            .foregroundStyle(Lovio.Palette.lavender)
                        VStack(alignment: .leading, spacing: 6) {
                            instructionRow(1, "Touch and hold an empty spot on your home screen")
                            instructionRow(2, "Tap the + button in the top corner")
                            instructionRow(3, "Search \"Missuo\" and pick a widget")
                        }
                        Text("Stack several — couples with 3+ widgets open the app twice as often.")
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
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                // Downscale: widgets have tight memory limits (~30 MB).
                let jpeg = image.downscaled(maxDimension: 800).jpegData(compressionQuality: 0.82)
                if let jpeg {
                    WidgetContent.savePhoto(jpeg)
                    Haptics.success()
                    withAnimation(.smooth) { photoSaved = true }
                    model.services.analytics.track(.widgetInteraction(widget: "polaroid", action: "photo_set"))
                }
            }
        }
    }

    // MARK: Send content to widgets

    private var sendPhotoCard: some View {
        GlassCard(tint: Lovio.Palette.peach) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Photo on your home screen", systemImage: "photo.on.rectangle.angled")
                    .font(Lovio.Type_.headline)
                    .foregroundStyle(Lovio.Palette.peach)

                HStack(spacing: 14) {
                    if let data = WidgetContent.loadPhoto(), let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial)
                            .frame(width: 64, height: 64)
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(photoSaved
                             ? "Saved! It's live on your Polaroid widget."
                             : "Pick a favorite moment — it appears on the Polaroid widget.")
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(.secondary)

                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(WidgetContent.hasPhoto ? "Change photo" : "Choose photo",
                                  systemImage: "photo.badge.plus")
                                .font(Lovio.Type_.caption)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(.ultraThinMaterial))
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    private var sendNoteCard: some View {
        GlassCard(tint: Lovio.Palette.plum) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Note on your widgets", systemImage: "envelope.open.fill")
                    .font(Lovio.Type_.headline)
                    .foregroundStyle(Lovio.Palette.plum)

                TextField("Write something sweet…", text: $note, axis: .vertical)
                    .lineLimit(2...3)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                    .onChange(of: note) { _, _ in noteSaved = false }

                HStack {
                    Text(noteSaved
                         ? "On your widgets ✓"
                         : "Shows on the Secret Message and Polaroid widgets.")
                        .font(Lovio.Type_.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        WidgetContent.saveNote(note)
                        model.publishWidgetSnapshot()
                        Haptics.success()
                        withAnimation(.smooth) { noteSaved = true }
                        model.services.analytics.track(.widgetInteraction(widget: "secret_message", action: "note_set"))
                    } label: {
                        Label("Send", systemImage: "arrow.up.circle.fill")
                            .font(Lovio.Type_.caption)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(.ultraThinMaterial))
                    }
                    .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func instructionRow(_ step: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(step)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Lovio.Palette.lavender.opacity(0.25)))
            Text(text)
                .font(Lovio.Type_.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - UIImage downscale helper

extension UIImage {
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return self }
        let scale = maxDimension / largest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
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
                if model.premium.isPremium, !RevenueCatBootstrap.isConfigured {
                    // Fake-purchase mode: lets you flip back to the free flow.
                    Button("Switch back to Free (test)", role: .destructive) {
                        DemoPremiumService.resetFakePurchase()
                        Task { await model.refreshPremium() }
                    }
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
                Button("Replay intro") { model.replayIntro() }
                Button("Sign out") { Task { await model.signOut() } }
                Button("End relationship", role: .destructive) { showEndRelationship = true }
            } footer: {
                Text(model.isDemoMode
                     ? "Running in demo mode — add GoogleService-Info.plist to connect Firebase."
                     : "Missuo \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("End this relationship?", isPresented: $showEndRelationship,
                            titleVisibility: .visible) {
            Button("End relationship", role: .destructive) {
                Task { await model.unpair() }
            }
        } message: {
            Text("Shared content is archived. If you purchased Premium, it stays with you and follows you into a future relationship.")
        }
    }
}
