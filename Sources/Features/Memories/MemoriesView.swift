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
                         ? "AI yearly recap — coming with the AI coach launch"
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
            .dismissableKeyboard()
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
                if milestones.isEmpty {
                    emptyState
                }

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
                                    .frame(width: 2)
                                    .frame(minHeight: 44, maxHeight: .infinity)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(milestone.title).font(Lovio.Type_.headline)
                            Text(milestone.date, style: .date)
                                .font(Lovio.Type_.caption)
                                .foregroundStyle(.secondary)
                            if let note = milestone.note {
                                Text(note)
                                    .font(Lovio.Type_.body)
                                    .foregroundStyle(.secondary)
                            }
                            if let path = milestone.photoPath {
                                StoredImageView(path: path)
                                    .frame(height: 150)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
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

    /// First-run guidance: what the timeline is for, with tappable examples.
    private var emptyState: some View {
        GlassCard(tint: Lovio.Palette.peach) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Your story, one moment at a time", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(Lovio.Type_.headline)
                    .foregroundStyle(Lovio.Palette.rose)
                Text("Build the timeline of your relationship — every milestone gets an emoji marker, a date, a note and a photo. Ideas to start with:")
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text("💋  The first kiss")
                    Text("✈️  Your first trip together")
                    Text("🏠  The day you moved in")
                    Text("💍  The proposal")
                    Text("🐶  Adopting your pet")
                }
                .font(Lovio.Type_.body)
                Text("Tap + in the top corner to add your first one.")
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 20)
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
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What happened? (e.g. First kiss)", text: $title)
                    TextField("Emoji", text: $emoji)
                } footer: {
                    Text("The emoji becomes the marker on your timeline — 💋 first kiss, ✈️ first trip, 💍 proposal, 🏠 moved in…")
                }

                Section {
                    DatePicker("When", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("Note (optional)", text: $note, axis: .vertical)
                }

                Section {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(photoData == nil ? "Add a photo" : "Photo attached ✓",
                              systemImage: "photo.on.rectangle.angled")
                    }
                } footer: {
                    Text("A photo makes the moment come alive on your shared timeline. Only the two of you can see it.")
                }
            }
            .navigationTitle("New Milestone")
            .navigationBarTitleDisplayMode(.inline)
            .dismissableKeyboard()
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        photoData = image.downscaled(maxDimension: 1200).jpegData(compressionQuality: 0.85)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Add") {
                        Task {
                            guard let rel = model.relationship, let me = model.user else { return }
                            isSaving = true
                            var milestone = Milestone(title: title, emoji: String(emoji.prefix(2)),
                                                      date: date, note: note.isEmpty ? nil : note)
                            if let photoData {
                                milestone.photoPath = try? await model.services.relationship.uploadImage(
                                    photoData, relationship: rel.id,
                                    fileName: "milestone_\(milestone.id).jpg")
                            }
                            try? await model.services.planner.save(milestone, relationship: rel.id)
                            try? await model.services.relationship.record(
                                event: RelationshipEvent(kind: .milestoneAdded, actorID: me.id),
                                relationship: rel.id)
                            await onSave()
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(title.isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Async image loaded from shared storage

struct StoredImageView: View {
    @Environment(AppModel.self) private var model
    let path: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 0)
                    .fill(.ultraThinMaterial)
                    .overlay { ProgressView() }
            }
        }
        .task {
            if let data = try? await model.services.relationship.downloadImage(path: path) {
                image = UIImage(data: data)
            }
        }
    }
}
