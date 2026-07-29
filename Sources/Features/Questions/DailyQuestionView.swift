import SwiftUI

// MARK: - Daily Question
//
// The core habit loop: both answer blind → simultaneous reveal.

struct DailyQuestionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let state = model.questionState {
                        categoryPill(state.question.category)

                        Text(state.question.text)
                            .font(Lovio.Type_.largeTitle)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)

                        if state.isRevealed {
                            revealedAnswers(state)
                        } else if state.myAnswer != nil {
                            sealedWaiting(state)
                        } else {
                            composer(state)
                        }
                    } else {
                        ProgressView().padding(48)
                    }
                }
                .padding(Lovio.Metrics.screenPadding)
            }
            .background(Lovio.Gradients.ambient(.light).ignoresSafeArea())
            .navigationTitle("Daily Question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if let state = model.questionState {
                    model.services.analytics.track(.questionViewed(category: state.question.category.rawValue))
                }
            }
        }
    }

    private func categoryPill(_ category: QuestionCategory) -> some View {
        Text("\(category.emoji)  \(category.title)")
            .font(Lovio.Type_.caption)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(.ultraThinMaterial))
    }

    // MARK: Compose

    private func composer(_ state: DailyQuestionState) -> some View {
        VStack(spacing: 16) {
            if state.partnerHasAnswered {
                Label("\(model.partnerName) has already answered — theirs unlocks the moment you reply",
                      systemImage: "sparkles")
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(Lovio.Palette.rose)
                    .multilineTextAlignment(.center)
            }

            TextField("Write your answer…", text: $draft, axis: .vertical)
                .lineLimit(4...10)
                .font(Lovio.Type_.body)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
                .focused($focused)

            Button("Seal my answer") {
                Task { await model.answerTodayQuestion(draft) }
            }
            .buttonStyle(LovioPrimaryButtonStyle())
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Text("Your partner can't see it until they answer too.")
                .font(Lovio.Type_.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { focused = true }
    }

    // MARK: Sealed

    private func sealedWaiting(_ state: DailyQuestionState) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.heart.fill")
                .font(.system(size: 52))
                .foregroundStyle(Lovio.Gradients.hero)
                .symbolEffect(.pulse)

            Text("Sealed until \(model.partnerName.split(separator: " ").first.map(String.init) ?? "your partner") answers")
                .font(Lovio.Type_.headline)

            Text("We'll ping you the moment both answers unlock.")
                .font(Lovio.Type_.caption)
                .foregroundStyle(.secondary)

            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your answer").font(Lovio.Type_.caption).foregroundStyle(.secondary)
                    Text(state.myAnswer?.text ?? "")
                        .font(Lovio.Type_.body)
                        .blur(radius: 0)
                }
            }
        }
        .padding(.top, 12)
    }

    // MARK: Revealed

    private func revealedAnswers(_ state: DailyQuestionState) -> some View {
        VStack(spacing: 14) {
            ForEach(state.revealedAnswers) { answer in
                let isMine = answer.authorID == model.user?.id
                GlassCard(tint: isMine ? Lovio.Palette.rose : Lovio.Palette.lavender) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isMine ? model.myName : model.partnerName)
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(isMine ? Lovio.Palette.rose : Lovio.Palette.lavender)
                        Text(answer.text)
                            .font(Lovio.Type_.body)
                    }
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            NavigationLink("Browse past questions") {
                QuestionArchiveView()
            }
            .font(Lovio.Type_.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: state.revealedAnswers.count)
    }
}

// MARK: - Archive

struct QuestionArchiveView: View {
    @Environment(AppModel.self) private var model
    @State private var history: [DailyQuestionState] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(history, id: \.question.id) { state in
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(state.question.category.emoji) \(state.question.text)")
                                .font(Lovio.Type_.headline)
                            ForEach(state.revealedAnswers) { answer in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(answer.authorID == model.user?.id
                                              ? Lovio.Palette.rose : Lovio.Palette.lavender)
                                        .frame(width: 7, height: 7)
                                        .padding(.top, 6)
                                    Text(answer.text)
                                        .font(Lovio.Type_.body)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(Lovio.Metrics.screenPadding)
        }
        .navigationTitle("Past Questions")
        .task {
            guard let rel = model.relationship else { return }
            history = (try? await model.services.questions.history(relationship: rel.id, limit: 20)) ?? []
        }
    }
}

// MARK: - Mood check-in sheet

struct MoodSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var selected: MoodKind?
    @State private var energy = 3.0
    @State private var stress = 2.0
    @State private var love = 4.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    Text("How are you right now?")
                        .font(Lovio.Type_.title)

                    // Mood wheel
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                        ForEach(MoodKind.allCases, id: \.self) { mood in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    selected = mood
                                }
                                Haptics.light()
                            } label: {
                                VStack(spacing: 6) {
                                    Text(mood.emoji).font(.system(size: 34))
                                    Text(mood.title)
                                        .font(Lovio.Type_.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background {
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(selected == mood ? AnyShapeStyle(Lovio.Palette.teal.opacity(0.25))
                                                               : AnyShapeStyle(.ultraThinMaterial))
                                }
                                .scaleEffect(selected == mood ? 1.06 : 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    GlassCard {
                        VStack(spacing: 18) {
                            meter("Energy", symbol: "bolt.fill", value: $energy, tint: Lovio.Palette.gold)
                            meter("Stress", symbol: "wind", value: $stress, tint: Lovio.Palette.teal)
                            meter("Love meter", symbol: "heart.fill", value: $love, tint: Lovio.Palette.rose)
                        }
                    }

                    Button("Share with \(model.partnerName.split(separator: " ").first.map(String.init) ?? "partner")") {
                        Task {
                            guard let me = model.user, let mood = selected else { return }
                            await model.logMood(MoodEntry(authorID: me.id, mood: mood,
                                                          energy: Int(energy), stress: Int(stress),
                                                          loveMeter: Int(love)))
                            dismiss()
                        }
                    }
                    .buttonStyle(LovioPrimaryButtonStyle())
                    .disabled(selected == nil)
                }
                .padding(Lovio.Metrics.screenPadding)
            }
            .navigationTitle("Mood Check-in")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationBackground(.thinMaterial)
    }

    private func meter(_ title: String, symbol: String, value: Binding<Double>, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(Lovio.Type_.caption)
                .foregroundStyle(tint)
            Slider(value: value, in: 1...5, step: 1)
                .tint(tint)
        }
    }
}
