import SwiftUI
import PhotosUI

// MARK: - Memories: shared journal + relationship timeline

struct MemoriesView: View {
    @Environment(AppModel.self) private var model
    @State private var entries: [JournalEntry] = []
    @State private var searchText = ""
    @State private var showComposer = false
    @State private var showPaywall = false

    private var filtered: [JournalEntry] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
            || $0.body.localizedCaseInsensitiveContains(searchText)
            || ($0.locationName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    /// Free tier: 10 journal entries, then paywall.
    private var canAddMore: Bool {
        model.premium.isPremium || entries.count < 10
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                yearlyRecapCard

                NavigationLink {
                    RelationshipTimelineView()
                } label: {
                    GlassCard(tint: Lovio.Palette.peach) {
                        HStack {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                                .foregroundStyle(Lovio.Palette.rose)
                            Text("Our Timeline — from first kiss to today")
                                .font(Lovio.Type_.headline)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)

                ForEach(filtered) { entry in
                    journalCard(entry)
                }
            }
            .padding(Lovio.Metrics.screenPadding)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Memories")
        .searchable(text: $searchText, prompt: "Search memories")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if canAddMore { showComposer = true } else { showPaywall = true }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Lovio.Palette.rose)
                }
            }
        }
        .sheet(isPresented: $showComposer) {
            JournalComposerView { await load() }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: "journal_limit")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let rel = model.relationship else { return }
        entries = (try? await model.services.journal.entries(relationship: rel.id)) ?? []
    }

    // MARK: Yearly recap (AI, premium)

    private var yearlyRecapCard: some View {
        GlassCard(tint: Lovio.Palette.lavender) {
            HStack(spacing: 14) {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(Lovio.Gradients.hero)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your Year Together").font(Lovio.Type_.headline)
                    Text(model.premium.isPremium
                         ? "AI recap of \(Calendar.current.component(.year, from: .now)) — ready to generate"
                         : "AI-generated yearly recap · Premium")
                        .font(Lovio.Type_.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !model.premium.isPremium {
                    Image(systemName: "crown.fill").foregroundStyle(Lovio.Palette.gold)
                }
            }
        }
    }

    // MARK: Journal card

    private func journalCard(_ entry: JournalEntry) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(entry.authorID == model.user?.id ? model.myName : model.partnerName)
                        .font(Lovio.Type_.caption)
                        .foregroundStyle(Lovio.Palette.rose)
                    Spacer()
                    Text(entry.createdAt, style: .date)
                        .font(Lovio.Type_.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(entry.title).font(Lovio.Type_.headline)
                if !entry.body.isEmpty {
                    Text(entry.body)
                        .font(Lovio.Type_.body)
                        .foregroundStyle(.secondary)
                }

                if !entry.media.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(entry.media) { media in
                            mediaChip(media)
                        }
                    }
                }

                HStack(spacing: 14) {
                    if let location = entry.locationName {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    ForEach(Array(entry.reactions.values), id: \.self) { emoji in
                        Text(emoji)
                    }
                    Button {
                        Task {
                            guard let rel = model.relationship, let me = model.user else { return }
                            try? await model.services.journal.react(
                                entryID: entry.id, relationship: rel.id, user: me.id, emoji: "❤️")
                            Haptics.light()
                            await load()
                        }
                    } label: {
                        Image(systemName: "heart")
                            .foregroundStyle(Lovio.Palette.rose)
                    }
                }
            }
        }
    }

    private func mediaChip(_ media: JournalMedia) -> some View {
        let (symbol, label): (String, String) = switch media.kind {
        case .photo: ("photo.fill", "Photo")
        case .video: ("video.fill", "Video")
        case .voice: ("waveform", media.durationSeconds.map { "\(Int($0))s" } ?? "Voice")
        case .livePhoto: ("livephoto", "Live")
        }
        return Label(label, systemImage: symbol)
            .font(Lovio.Type_.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.ultraThinMaterial))
    }
}

// MARK: - Composer

struct JournalComposerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onSave: () async -> Void

    @State private var title = ""
    @State private var body_ = ""
    @State private var location = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isVoiceAttached = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Moment") {
                    TextField("Title", text: $title)
                    TextField("What happened?", text: $body_, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Location (optional)", text: $location)
                }
                Section("Attachments") {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 5,
                                 matching: .any(of: [.images, .livePhotos, .videos])) {
                        Label(photoItems.isEmpty ? "Add photos or video"
                                                 : "\(photoItems.count) selected",
                              systemImage: "photo.on.rectangle.angled")
                    }
                    Toggle(isOn: $isVoiceAttached) {
                        Label("Voice memory", systemImage: "waveform")
                    }
                    .tint(Lovio.Palette.rose)
                    if isVoiceAttached && !model.premium.isPremium {
                        Label("Voice memories are Premium", systemImage: "crown.fill")
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(Lovio.Palette.gold)
                    }
                }
            }
            .navigationTitle("New Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            guard let me = model.user else { return }
                            var media: [JournalMedia] = photoItems.map { _ in JournalMedia(kind: .photo) }
                            if isVoiceAttached && model.premium.isPremium {
                                media.append(JournalMedia(kind: .voice, durationSeconds: 0))
                            }
                            await model.addJournalEntry(JournalEntry(
                                authorID: me.id, title: title, body: body_,
                                media: media,
                                locationName: location.isEmpty ? nil : location))
                            await onSave()
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Relationship Timeline

struct RelationshipTimelineView: View {
    @Environment(AppModel.self) private var model
    @State private var milestones: [Milestone] = []
    @State private var showAdd = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 0) {
                            Text(milestone.emoji)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(.ultraThinMaterial))
                            if index < milestones.count - 1 {
                                Rectangle()
                                    .fill(Lovio.Palette.rose.opacity(0.3))
                                    .frame(width: 2, height: 44)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(milestone.title).font(Lovio.Type_.headline)
                            Text(milestone.date, style: .date)
                                .font(Lovio.Type_.caption)
                                .foregroundStyle(.secondary)
                            if let note = milestone.note {
                                Text(note)
                                    .font(Lovio.Type_.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.bottom, 24)
                        Spacer()
                    }
                }
            }
            .padding(Lovio.Metrics.screenPadding)
        }
        .navigationTitle("Our Timeline")
        .toolbar {
            Button { showAdd = true } label: { Image(systemName: "plus") }
        }
        .sheet(isPresented: $showAdd) {
            MilestoneEditor { await load() }
        }
        .task { await load() }
    }

    private func load() async {
        guard let rel = model.relationship else { return }
        milestones = (try? await model.services.planner.milestones(relationship: rel.id)) ?? []
    }
}

struct MilestoneEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onSave: () async -> Void

    @State private var title = ""
    @State private var emoji = "💞"
    @State private var date = Date()
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Milestone (e.g. First trip)", text: $title)
                TextField("Emoji", text: $emoji)
                DatePicker("When", selection: $date, in: ...Date(), displayedComponents: .date)
                TextField("Note (optional)", text: $note, axis: .vertical)
            }
            .navigationTitle("New Milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            guard let rel = model.relationship else { return }
                            try? await model.services.planner.save(
                                Milestone(title: title, emoji: String(emoji.prefix(2)),
                                          date: date, note: note.isEmpty ? nil : note),
                                relationship: rel.id)
                            await onSave()
                            dismiss()
                        }
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
