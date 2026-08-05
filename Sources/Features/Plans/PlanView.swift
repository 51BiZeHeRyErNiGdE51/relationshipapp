import SwiftUI

// MARK: - Plans: shared calendar + bucket list + notes

struct PlanView: View {
    @Environment(AppModel.self) private var model
    @State private var section: PlanSection = .dates
    @State private var dates: [SpecialDate] = []
    @State private var bucket: [BucketListItem] = []
    @State private var notes: [SharedNote] = []
    @State private var showDateEditor = false
    @State private var showBucketEditor = false
    @State private var showNoteEditor = false

    enum PlanSection: String, CaseIterable {
        case dates = "Dates", bucket = "Bucket List", notes = "Notes"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Section", selection: $section) {
                    ForEach(PlanSection.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)

                switch section {
                case .dates: datesSection
                case .bucket: bucketSection
                case .notes: notesSection
                }
            }
            .padding(Lovio.Metrics.screenPadding)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Plans")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    switch section {
                    case .dates: showDateEditor = true
                    case .bucket: showBucketEditor = true
                    case .notes: showNoteEditor = true
                    }
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Lovio.Palette.rose)
                }
            }
        }
        // refreshToday() keeps Home's "next adventure" card in sync with new dates.
        .sheet(isPresented: $showDateEditor) { SpecialDateEditor { await load(); await model.refreshToday() } }
        .sheet(isPresented: $showBucketEditor) { BucketItemEditor { await load() } }
        .sheet(isPresented: $showNoteEditor) { NoteEditor(note: nil) { await load() } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let rel = model.relationship else { return }
        async let d = try? model.services.planner.specialDates(relationship: rel.id)
        async let b = try? model.services.planner.bucketList(relationship: rel.id)
        async let n = try? model.services.planner.notes(relationship: rel.id)
        dates = await d ?? []
        bucket = await b ?? []
        notes = await n ?? []
    }

    // MARK: Dates & countdowns

    private var datesSection: some View {
        VStack(spacing: 12) {
            GlassCard(tint: Lovio.Palette.teal) {
                HStack {
                    Label("Sync with Apple Calendar", systemImage: "calendar.badge.plus")
                        .font(Lovio.Type_.headline)
                    Spacer()
                    if !model.premium.isPremium {
                        Image(systemName: "crown.fill").foregroundStyle(Lovio.Palette.gold)
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Lovio.Palette.teal)
                    }
                }
            }

            if dates.isEmpty {
                emptyCard(symbol: "calendar.badge.clock", tint: Lovio.Palette.rose,
                          title: "Count down to what's next",
                          examples: ["🎂  Her birthday (repeats yearly)",
                                     "✈️  Trip to Rome",
                                     "💞  Your anniversary",
                                     "🎬  Date night on Friday"],
                          footer: "The nearest one appears on your Home screen and the Next Adventure widget, and you both get reminded the day before.")
            }

            ForEach(dates) { date in
                GlassCard {
                    HStack(spacing: 14) {
                        Image(systemName: date.kind.symbol)
                            .font(.title3)
                            .foregroundStyle(Lovio.Palette.rose)
                            .frame(width: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(date.title).font(Lovio.Type_.headline)
                            Text(date.repeatsYearly ? "Every year" : "One time")
                                .font(Lovio.Type_.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if date.isUpcoming {
                                Text(date.daysUntil == 0 ? "Today" : "\(date.daysUntil) days")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(Lovio.Gradients.hero)
                            } else {
                                Text("Past")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            Text(date.shortDateLabel)
                                .font(Lovio.Type_.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        Task {
                            guard let rel = model.relationship else { return }
                            try? await model.services.planner.deleteDate(id: date.id, relationship: rel.id)
                            await load()
                        }
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
    }

    // MARK: Bucket list

    private var bucketSection: some View {
        VStack(spacing: 12) {
            if bucket.isEmpty {
                emptyCard(symbol: "sparkles", tint: Lovio.Palette.gold,
                          title: "Things you'll do together — someday, on purpose",
                          examples: ["🍜  That ramen place downtown",
                                     "🇯🇵  See Japan in cherry blossom season",
                                     "⛺  Camp under the stars",
                                     "💃  Take a dance class"],
                          footer: "Tick items off together — each completed one becomes a memory.")
            }

            ForEach(BucketCategory.allCases, id: \.self) { category in
                let items = bucket.filter { $0.category == category }
                if !items.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("\(category.emoji)  \(category.title)")
                                .font(Lovio.Type_.headline)
                            ForEach(items) { item in
                                Button {
                                    Task {
                                        guard let rel = model.relationship else { return }
                                        var updated = item
                                        updated.isCompleted.toggle()
                                        updated.completedAt = updated.isCompleted ? .now : nil
                                        try? await model.services.planner.save(updated, relationship: rel.id)
                                        Haptics.light()
                                        await load()
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: item.isCompleted
                                              ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(item.isCompleted
                                                             ? Lovio.Palette.teal : .secondary)
                                        Text(item.title)
                                            .font(Lovio.Type_.body)
                                            .strikethrough(item.isCompleted)
                                            .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Notes

    private var notesSection: some View {
        VStack(spacing: 12) {
            if notes.isEmpty {
                emptyCard(symbol: "note.text", tint: Lovio.Palette.teal,
                          title: "One shared brain for you two",
                          examples: ["🛒  Groceries (you both can check off)",
                                     "🧳  Packing list for the weekend",
                                     "🎁  Gift ideas — mark it private so it stays a surprise",
                                     "🎵  Songs that remind you of each other"],
                          footer: "Pin important notes to the top. Private notes are visible only to you.")
            }

            ForEach(notes) { note in
                GlassCard(tint: note.isPinned ? Lovio.Palette.gold : nil) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(note.title).font(Lovio.Type_.headline)
                            if note.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption)
                                    .foregroundStyle(Lovio.Palette.gold)
                            }
                            if note.isPrivate {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                        }
                        if !note.body.isEmpty {
                            Text(note.body).font(Lovio.Type_.body).foregroundStyle(.secondary)
                        }
                        ForEach(note.items.prefix(5)) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.isDone ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(item.isDone ? Lovio.Palette.teal : .secondary)
                                    .font(.subheadline)
                                Text(item.text)
                                    .font(Lovio.Type_.body)
                                    .strikethrough(item.isDone)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Empty state guidance

extension PlanView {
    fileprivate func emptyCard(symbol: String, tint: Color, title: String,
                               examples: [String], footer: String) -> some View {
        GlassCard(tint: tint) {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: symbol)
                    .font(Lovio.Type_.headline)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(examples, id: \.self) { Text($0).font(Lovio.Type_.body) }
                }
                Text(footer)
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(.secondary)
                Text("Tap + in the top corner to add one.")
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Editors

struct SpecialDateEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onSave: () async -> Void

    @State private var title = ""
    @State private var kind: SpecialDateKind = .date
    @State private var date = Date().addingTimeInterval(86_400 * 7)
    @State private var yearly = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                Picker("Type", selection: $kind) {
                    ForEach(SpecialDateKind.allCases, id: \.self) {
                        Label($0.rawValue.capitalized, systemImage: $0.symbol).tag($0)
                    }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Toggle("Repeats yearly", isOn: $yearly)
            }
            .navigationTitle("New Countdown")
            .navigationBarTitleDisplayMode(.inline)
            .dismissableKeyboard()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            guard let rel = model.relationship, let me = model.user else { return }
                            try? await model.services.planner.save(
                                SpecialDate(title: title, kind: kind, date: date,
                                            repeatsYearly: yearly, createdBy: me.id),
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

struct BucketItemEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onSave: () async -> Void

    @State private var title = ""
    @State private var category: BucketCategory = .dateIdeas

    var body: some View {
        NavigationStack {
            Form {
                TextField("What should we do together?", text: $title)
                Picker("Category", selection: $category) {
                    ForEach(BucketCategory.allCases, id: \.self) {
                        Text("\($0.emoji) \($0.title)").tag($0)
                    }
                }
            }
            .navigationTitle("Bucket List")
            .navigationBarTitleDisplayMode(.inline)
            .dismissableKeyboard()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            guard let rel = model.relationship, let me = model.user else { return }
                            try? await model.services.planner.save(
                                BucketListItem(title: title, category: category, createdBy: me.id),
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

struct NoteEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let note: SharedNote?
    var onSave: () async -> Void

    @State private var title = ""
    @State private var body_ = ""
    @State private var isPinned = false
    @State private var isPrivate = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Write anything…", text: $body_, axis: .vertical)
                    .lineLimit(4...12)
                Toggle("Pin to top", isOn: $isPinned)
                Toggle("Private (only me)", isOn: $isPrivate)
            }
            .navigationTitle(note == nil ? "New Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .dismissableKeyboard()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            guard let rel = model.relationship, let me = model.user else { return }
                            var saved = note ?? SharedNote(title: "", updatedBy: me.id)
                            saved.title = title
                            saved.body = body_
                            saved.isPinned = isPinned
                            saved.isPrivate = isPrivate
                            saved.updatedAt = .now
                            saved.updatedBy = me.id
                            try? await model.services.planner.save(saved, relationship: rel.id)
                            await onSave()
                            dismiss()
                        }
                    }
                    .disabled(title.isEmpty)
                }
            }
            .onAppear {
                if let note {
                    title = note.title
                    body_ = note.body
                    isPinned = note.isPinned
                    isPrivate = note.isPrivate
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
