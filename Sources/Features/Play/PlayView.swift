import SwiftUI

// MARK: - Play: distance-friendly couple games
//
// Every game is 2-choice. Both partners answer blind on their own phones;
// answers unlock when both have picked. Same cards for both (shared bank).

struct PlayView: View {
    @Environment(AppModel.self) private var model
    @State private var activeGame: CoupleGame?
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Play from anywhere — pick your answer, then see theirs when they reply.")
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !model.isPaired {
                    GlassCard(tint: Lovio.Palette.rose) {
                        Label("Pair with your partner first — games unlock together.",
                              systemImage: "person.2.badge.plus")
                            .font(Lovio.Type_.body)
                            .foregroundStyle(Lovio.Palette.rose)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(CoupleGame.allCases) { game in
                        Button {
                            if game.isPremium && !model.premium.isPremium {
                                showPaywall = true
                            } else if model.isPaired {
                                activeGame = game
                            } else {
                                model.errorMessage = L10n.s("Connect with your partner first — games are better together.")
                            }
                        } label: {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: game.symbol)
                                            .font(.title2)
                                            .foregroundStyle(Lovio.Gradients.hero)
                                        Spacer()
                                        if game.isPremium && !model.premium.isPremium {
                                            Image(systemName: "crown.fill")
                                                .font(.caption)
                                                .foregroundStyle(Lovio.Palette.gold)
                                        }
                                    }
                                    Text(L10n.copy(game.title))
                                        .font(Lovio.Type_.headline)
                                        .multilineTextAlignment(.leading)
                                    Text(L10n.copy(game.subtitle))
                                        .font(Lovio.Type_.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(height: 36, alignment: .topLeading)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Lovio.Metrics.screenPadding)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Play")
        .sheet(item: $activeGame) { game in
            SharedGameDeckView(game: game)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: "games")
        }
    }
}

// MARK: - Shared 2-choice deck

struct SharedGameDeckView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let game: CoupleGame

    @State private var states: [GamePromptState] = []
    @State private var index = 0
    @State private var isLoading = true

    private var current: GamePromptState? {
        guard !states.isEmpty else { return nil }
        return states[index % states.count]
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let state = current {
                    promptCard(state)
                } else {
                    Text("No prompts yet.")
                        .foregroundStyle(.secondary)
                }
            }
            .background(Lovio.Gradients.ambient(.light).ignoresSafeArea())
            .navigationTitle(L10n.copy(game.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await reload() }
        }
    }

    private func reload() async {
        guard let rel = model.relationship, let me = model.user else { return }
        isLoading = true
        states = (try? await model.services.games.deck(game: game, relationship: rel.id, me: me.id)) ?? []
        isLoading = false
    }

    @ViewBuilder
    private func promptCard(_ state: GamePromptState) -> some View {
        VStack(spacing: 20) {
            // Progress
            HStack {
                Text("\(index + 1) / \(states.count)")
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                let revealed = states.filter(\.isRevealed).count
                Text(L10n.s("%lld unlocked together", Int64(revealed)))
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Lovio.Metrics.screenPadding)
            .padding(.top, 8)

            Spacer(minLength: 8)

            // Question
            Text(L10n.copy(state.prompt.text))
                .font(Lovio.Type_.largeTitle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .minimumScaleFactor(0.7)

            if state.isRevealed {
                revealedView(state)
            } else if state.myAnswer != nil {
                waitingView(state)
            } else {
                choicesView(state)
            }

            Spacer(minLength: 8)

            // Navigation between prompts
            HStack(spacing: 14) {
                Button {
                    withAnimation(.smooth) { index = max(0, index - 1) }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .disabled(index == 0)

                Button {
                    Haptics.light()
                    withAnimation(.smooth) { index = min(states.count - 1, index + 1) }
                } label: {
                    Text(index < states.count - 1 ? L10n.copy("Next card") : L10n.copy("Back to start"))
                        .font(Lovio.Type_.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Lovio.Palette.rose.opacity(0.15)))
                        .foregroundStyle(Lovio.Palette.rose)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    if index >= states.count - 1 { index = 0 }
                })

                Button {
                    withAnimation(.smooth) { index = min(states.count - 1, index + 1) }
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .disabled(index >= states.count - 1)
            }
            .padding(.horizontal, Lovio.Metrics.screenPadding)
            .padding(.bottom, 24)
        }
    }

    /// English source labels (stored + used as localization keys).
    private func sourceChoices(for prompt: GamePrompt) -> (a: String, b: String) {
        if let a = prompt.choiceA, let b = prompt.choiceB {
            return (a, b)
        }
        // Who's More Likely — real names (not localized).
        return (model.myFirstName, model.partnerFirstName ?? L10n.copy("Partner"))
    }

    private func choicesView(_ state: GamePromptState) -> some View {
        let pair = sourceChoices(for: state.prompt)
        let namesOnly = state.prompt.choiceA == nil
        return VStack(spacing: 12) {
            if state.partnerHasAnswered {
                let who = model.partnerFirstName ?? L10n.copy("Your partner")
                Label(L10n.s("%@ already answered — yours unlocks both", who),
                      systemImage: "sparkles")
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(Lovio.Palette.rose)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            HStack(spacing: 12) {
                choiceButton(sourceLabel: pair.a, display: namesOnly ? pair.a : L10n.copy(pair.a),
                             choice: "a", state: state)
                choiceButton(sourceLabel: pair.b, display: namesOnly ? pair.b : L10n.copy(pair.b),
                             choice: "b", state: state)
            }
            .padding(.horizontal, Lovio.Metrics.screenPadding)
            Text("They won't see your pick until they answer too.")
                .font(Lovio.Type_.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func choiceButton(sourceLabel: String, display: String,
                              choice: String, state: GamePromptState) -> some View {
        Button {
            Task {
                if let updated = await model.submitGameChoice(
                    game: game, prompt: state.prompt,
                    choice: choice, choiceLabel: sourceLabel),
                   let i = states.firstIndex(where: { $0.prompt.id == updated.prompt.id }) {
                    withAnimation(.smooth) { states[i] = updated }
                }
            }
        } label: {
            Text(display)
                .font(Lovio.Type_.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Lovio.Palette.plum)
                .frame(maxWidth: .infinity, minHeight: 88)
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(.white)
                        .shadow(color: Lovio.Palette.rose.opacity(0.2), radius: 12, y: 4)
                }
        }
        .buttonStyle(.plain)
    }

    private func waitingView(_ state: GamePromptState) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.heart.fill")
                .font(.system(size: 44))
                .foregroundStyle(Lovio.Gradients.hero)
                .symbolEffect(.pulse)
            Text(L10n.s("Sealed until %@ answers",
                        model.partnerFirstName ?? L10n.copy("your partner")))
                .font(Lovio.Type_.headline)
                .multilineTextAlignment(.center)
            if let mine = state.myAnswer {
                GlassCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("You picked").font(Lovio.Type_.caption).foregroundStyle(.secondary)
                        Text(L10n.copy(mine.choiceLabel)).font(Lovio.Type_.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, Lovio.Metrics.screenPadding)
            }
        }
    }

    private func revealedView(_ state: GamePromptState) -> some View {
        VStack(spacing: 14) {
            if let matched = state.matched {
                Text(matched
                      ? L10n.copy("You picked the same! 💞")
                      : L10n.copy("Different picks — fun to talk about 👀"))
                    .font(Lovio.Type_.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Lovio.Palette.rose.opacity(0.15)))
            }

            ForEach(state.revealedAnswers) { answer in
                let isMine = answer.authorID == model.user?.id
                GlassCard(tint: isMine ? Lovio.Palette.rose : Lovio.Palette.lavender) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.s("%@ picked",
                                    isMine ? model.myFirstName
                                    : (model.partnerFirstName ?? model.partnerName)))
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(isMine ? Lovio.Palette.rose : Lovio.Palette.lavender)
                        Text(L10n.copy(answer.choiceLabel))
                            .font(Lovio.Type_.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, Lovio.Metrics.screenPadding)
        }
    }
}

// MARK: - AI Coach

struct AICoachView: View {
    @Environment(AppModel.self) private var model
    @State private var insights: [AIInsight] = []
    @State private var dateIdeas: [String] = []
    @State private var chatInput = ""
    @State private var chatLog: [(role: String, text: String)] = []
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !model.premium.isPremium {
                    Button { showPaywall = true } label: {
                        GlassCard(tint: Lovio.Palette.gold) {
                            Label("Unlock the full AI coach with Premium",
                                  systemImage: "crown.fill")
                                .font(Lovio.Type_.headline)
                                .foregroundStyle(Lovio.Palette.gold)
                        }
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("This week's report")
                        .font(Lovio.Type_.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(insights) { insight in
                        GlassCard(tint: Lovio.Palette.lavender) {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: insight.symbol)
                                    .font(.title3)
                                    .foregroundStyle(Lovio.Gradients.hero)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(insight.title).font(Lovio.Type_.headline)
                                    Text(insight.body)
                                        .font(Lovio.Type_.body)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Dates planned for you two")
                        .font(Lovio.Type_.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(dateIdeas, id: \.self) { idea in
                        GlassCard {
                            Label(idea, systemImage: "sparkles")
                                .font(Lovio.Type_.body)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Ask the coach")
                        .font(Lovio.Type_.title)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Label("The coach knows your daily-question answers and moods — ask anything about you two", systemImage: "sparkles")
                        .font(Lovio.Type_.caption)
                        .foregroundStyle(.tertiary)

                    ForEach(Array(chatLog.enumerated()), id: \.offset) { _, message in
                        GlassCard(tint: message.role == "me" ? Lovio.Palette.rose : Lovio.Palette.teal) {
                            Text(message.text).font(Lovio.Type_.body)
                        }
                    }

                    HStack(spacing: 10) {
                        TextField("How do we handle…", text: $chatInput)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                        Button {
                            Task { await sendChat() }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title)
                                .foregroundStyle(Lovio.Palette.rose)
                        }
                        .disabled(chatInput.isEmpty)
                    }
                }
            }
            .padding(Lovio.Metrics.screenPadding)
        }
        .scrollIndicators(.hidden)
        .dismissableKeyboard()
        .navigationTitle("AI Coach")
        .sheet(isPresented: $showPaywall) { PaywallView(source: "ai_coach") }
        .task { await load() }
    }

    private func load() async {
        guard let rel = model.relationship else { return }
        insights = (try? await model.services.aiCoach.weeklyReport(relationship: rel, events: [])) ?? []
        dateIdeas = (try? await model.services.aiCoach.dateIdeas(relationship: rel)) ?? []
    }

    private func sendChat() async {
        guard let rel = model.relationship else { return }
        let question = chatInput
        chatInput = ""
        chatLog.append((role: "me", text: question))
        if let reply = try? await model.services.aiCoach.chat(message: question, relationship: rel) {
            chatLog.append((role: "coach", text: reply))
        }
    }
}
