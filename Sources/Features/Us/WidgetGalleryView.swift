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
    @State private var note = WidgetContent.note(.mine) ?? ""
    @State private var noteSaved = false
    @State private var howToSpec: WidgetSpec?
    @State private var events: [RelationshipEvent] = []

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
        .init(id: "polaroid_mine", title: "My Polaroid", subtitle: "The photo YOU picked — on your screen", symbol: "photo.on.rectangle.angled", tint: Lovio.Palette.peach, isPremium: false),
        .init(id: "polaroid_partner", title: "From Your Love", subtitle: "The photo your PARTNER sent you", symbol: "photo.artframe", tint: Lovio.Palette.rose, isPremium: false),
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
                        Button {
                            if spec.isPremium && !model.premium.isPremium {
                                showPaywall = true
                            } else {
                                howToSpec = spec
                            }
                        } label: {
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
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                activitySection
            }
            .padding(Lovio.Metrics.screenPadding)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Widgets")
        .sheet(isPresented: $showPaywall) { PaywallView(source: "widget_gallery") }
        .sheet(item: $howToSpec) { spec in
            WidgetHowToSheet(spec: spec)
        }
        .onAppear {
            model.services.analytics.track(.widgetGalleryViewed)
            model.publishWidgetSnapshot()
        }
        .task { await loadEvents() }
        .refreshable {
            await model.syncIncomingWidgetContent()
            await loadEvents()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    model.errorMessage = "Couldn't load that photo — if it's in iCloud, wait for it to download in Photos and try again."
                    return
                }
                // Downscale: widgets have tight memory limits (~30 MB).
                let jpeg = image.downscaled(maxDimension: 800).jpegData(compressionQuality: 0.82)
                if let jpeg {
                    await model.sendWidgetPhoto(jpeg)
                    Haptics.success()
                    withAnimation(.smooth) { photoSaved = true }
                    model.services.analytics.track(.widgetInteraction(widget: "polaroid", action: "photo_set"))
                    await loadEvents()
                }
            }
        }
    }

    private func loadEvents() async {
        guard let rel = model.relationship else { return }
        let all = (try? await model.services.relationship.recentEvents(relationship: rel.id, limit: 30)) ?? []
        events = all.filter { Self.eventText($0.kind) != nil }
    }

    // MARK: Between you two — history of what was sent back and forth

    @ViewBuilder
    private var activitySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Between you two", systemImage: "arrow.up.arrow.down.circle.fill")
                    .font(Lovio.Type_.headline)
                    .foregroundStyle(Lovio.Palette.rose)

                if events.isEmpty {
                    Text("Everything you send each other — notes, photos, miss-yous, moods — shows up here.")
                        .font(Lovio.Type_.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(events.prefix(12), id: \.id) { event in
                        HStack(spacing: 10) {
                            Image(systemName: Self.eventSymbol(event.kind))
                                .font(.subheadline)
                                .foregroundStyle(Lovio.Palette.rose)
                                .frame(width: 24)
                            Text("\(event.actorID == model.user?.id ? "You" : (model.partnerFirstName ?? "Partner")) \(Self.eventText(event.kind) ?? "")")
                                .font(Lovio.Type_.body)
                            Spacer()
                            Text(event.occurredAt, style: .relative)
                                .font(Lovio.Type_.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private static func eventText(_ kind: RelationshipEventKind) -> String? {
        switch kind {
        case .widgetPhotoSent: "changed the Polaroid photo"
        case .widgetNoteSent: "sent a widget note"
        case .missYouSent: "sent a miss you 🥺"
        case .heartTap: "dropped a heart in the jar"
        case .questionAnswered: "answered the daily question"
        case .moodLogged: "checked in a mood"
        case .journalEntryAdded: "saved a memory"
        case .milestoneAdded: "added a milestone"
        case .gamePlayed: "played a game"
        case .dateCompleted, .bucketItemCompleted: "completed a plan"
        case .widgetInteraction, .appOpened: nil
        }
    }

    private static func eventSymbol(_ kind: RelationshipEventKind) -> String {
        switch kind {
        case .widgetPhotoSent: "photo.fill"
        case .widgetNoteSent: "envelope.fill"
        case .missYouSent: "paperplane.fill"
        case .heartTap: "heart.fill"
        case .questionAnswered: "bubble.left.and.bubble.right.fill"
        case .moodLogged: "face.smiling"
        case .journalEntryAdded: "book.fill"
        case .milestoneAdded: "flag.fill"
        case .gamePlayed: "gamecontroller.fill"
        default: "sparkles"
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
                    if let data = WidgetContent.loadPhoto(.mine), let image = UIImage(data: data) {
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
                             ? "Done! It's on your My Polaroid widget\(model.isPaired ? ", and lands on \(model.partnerFirstName ?? "your partner")'s From Your Love widget" : "")."
                             : model.isPaired
                               ? "Shows on YOUR \"My Polaroid\" widget and on \(model.partnerFirstName ?? "your partner")'s \"From Your Love\" widget. Only you two can see it."
                               : "Shows on your \"My Polaroid\" widget now — and on your partner's \"From Your Love\" widget once you pair.")
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(.secondary)

                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(WidgetContent.hasPhoto(.mine) ? "Change photo" : "Choose photo",
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
                         ? "Sent ✓ It's on your My Polaroid caption\(model.isPaired ? " and \(model.partnerFirstName ?? "your partner")'s Secret Message widget" : "")."
                         : model.isPaired
                           ? "Lands on \(model.partnerFirstName ?? "your partner")'s Secret Message widget, blurred until they tap."
                           : "Captions your My Polaroid widget — and reaches your partner once you pair.")
                        .font(Lovio.Type_.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task {
                            await model.sendWidgetNote(note)
                            await loadEvents()
                        }
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

// MARK: - Notification settings
//
// Every locally-scheduled push can be turned off here; the daily reminder
// time is user-adjustable (defaults to the remote-config experiment hour).

struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var model

    @AppStorage(NotificationManager.Pref.dailyEnabled) private var dailyEnabled = true
    @AppStorage(NotificationManager.Pref.eventsEnabled) private var eventsEnabled = true
    @AppStorage(NotificationManager.Pref.offersEnabled) private var offersEnabled = true
    @State private var reminderTime = Date()

    private var defaultHour: Int {
        Int(model.services.experiments.variant(for: "daily_reminder_hour")) ?? 20
    }

    var body: some View {
        List {
            Section {
                Toggle("Daily question reminder", isOn: $dailyEnabled)
                if dailyEnabled {
                    DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Daily question")
            } footer: {
                Text("One reminder per day so you never lose your streak.")
            }

            Section {
                Toggle("Event reminders", isOn: $eventsEnabled)
            } footer: {
                Text("The day before and the morning of your countdowns, birthdays and anniversaries.")
            }

            Section {
                Toggle("Offers & tips", isOn: $offersEnabled)
            } footer: {
                Text("Occasional premium offers and feature tips. Never more than one a week.")
            }

            Section {
                Label("Partner answered the daily question", systemImage: "bubble.left.and.bubble.right")
                Label("Partner logged a mood", systemImage: "face.smiling")
                Label("Miss you & heart taps", systemImage: "heart")
                Label("New widget photo or note", systemImage: "photo")
            } header: {
                Text("From your partner")
            } footer: {
                Text("These arrive automatically from your partner's actions and are controlled in iOS Settings → Notifications → Missuo.")
            }
        }
        .navigationTitle("Notifications")
        .onAppear {
            let defaults = UserDefaults.standard
            let hour = defaults.object(forKey: NotificationManager.Pref.dailyHour) != nil
                ? defaults.integer(forKey: NotificationManager.Pref.dailyHour) : defaultHour
            let minute = defaults.integer(forKey: NotificationManager.Pref.dailyMinute)
            reminderTime = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        }
        .onChange(of: reminderTime) { _, time in
            let components = Calendar.current.dateComponents([.hour, .minute], from: time)
            UserDefaults.standard.set(components.hour ?? defaultHour, forKey: NotificationManager.Pref.dailyHour)
            UserDefaults.standard.set(components.minute ?? 0, forKey: NotificationManager.Pref.dailyMinute)
            Task { await NotificationManager.shared.applyDailyReminder(defaultHour: defaultHour) }
        }
        .onChange(of: dailyEnabled) { _, _ in
            Task { await NotificationManager.shared.applyDailyReminder(defaultHour: defaultHour) }
        }
        .onChange(of: eventsEnabled) { _, _ in
            Task { await NotificationManager.shared.scheduleEventReminders(dates: model.upcomingDates) }
        }
        .onChange(of: offersEnabled) { _, _ in
            if !offersEnabled {
                NotificationManager.shared.cancelMonetizationReminders()
            } else {
                NotificationManager.shared.scheduleWeeklyPremiumNudge(isPremium: model.premium.isPremium)
            }
        }
    }
}

// MARK: - Widget how-to sheet
//
// iOS doesn't let apps place widgets programmatically, so tapping a widget
// walks the user through doing it themselves — step by step, per widget.

struct WidgetHowToSheet: View {
    @Environment(\.dismiss) private var dismiss
    let spec: WidgetGalleryView.WidgetSpec

    var body: some View {
        VStack(spacing: 22) {
            Capsule().fill(.tertiary).frame(width: 36, height: 5).padding(.top, 10)

            Image(systemName: spec.symbol)
                .font(.system(size: 44))
                .foregroundStyle(spec.tint)
                .frame(width: 92, height: 92)
                .background(RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial))

            VStack(spacing: 6) {
                Text(spec.title).font(Lovio.Type_.title)
                Text(spec.subtitle)
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                step(1, "Go to your home screen and touch and hold an empty spot until the apps jiggle")
                step(2, "Tap the + button in the top-left corner")
                step(3, "Search for \"Missuo\"")
                step(4, "Swipe to \(spec.title), pick a size, then tap Add Widget")
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))

            Text("Apple doesn't allow apps to add widgets for you — it only takes a few seconds by hand.")
                .font(Lovio.Type_.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button("Got it") { dismiss() }
                .buttonStyle(LovioPrimaryButtonStyle())

            Spacer(minLength: 0)
        }
        .padding(Lovio.Metrics.screenPadding)
        .presentationDetents([.large])
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .frame(width: 24, height: 24)
                .background(Circle().fill(spec.tint.opacity(0.2)))
            Text(text).font(Lovio.Type_.body)
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
                NavigationLink("Notifications & reminders") {
                    NotificationSettingsView()
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
