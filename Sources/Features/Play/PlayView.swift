import SwiftUI

// MARK: - Play: couple games hub

struct PlayView: View {
    @Environment(AppModel.self) private var model
    @State private var activeGame: CoupleGame?
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Two players. One couch. No losers.")
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(CoupleGame.allCases) { game in
                        Button {
                            if game.isPremium && !model.premium.isPremium {
                                showPaywall = true
                            } else {
                                activeGame = game
                                model.services.analytics.track(.gamePlayed(game: game.rawValue))
                            }
                        } label: {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 10) {
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
                                    Text(game.title)
                                        .font(Lovio.Type_.headline)
                                        .multilineTextAlignment(.leading)
                                        .frame(height: 44, alignment: .topLeading)
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
            PromptDeckGameView(game: game)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: "games")
        }
    }
}

// MARK: - Prompt-deck game (pass and play)

struct PromptDeckGameView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let game: CoupleGame

    @State private var index = 0
    @State private var flipped = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                Text(game.title)
                    .font(Lovio.Type_.title)

                // Card
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Lovio.Gradients.hero)
                        .shadow(color: Lovio.Palette.rose.opacity(0.35), radius: 22, y: 10)

                    Text(prompts[index % prompts.count])
                        .font(Lovio.Type_.title)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(28)
                }
                .frame(height: 300)
                .padding(.horizontal, 28)
                .rotation3DEffect(.degrees(flipped ? 360 : 0), axis: (x: 0, y: 1, z: 0))
                .onTapGesture { next() }

                Text("Tap the card for the next one")
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    Button {
                        next()
                    } label: {
                        Label("Next", systemImage: "arrow.right")
                    }
                    .buttonStyle(LovioPrimaryButtonStyle())
                }
                .padding(.horizontal, 28)

                Spacer()
            }
            .background(Lovio.Gradients.ambient(.light).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func next() {
        Haptics.light()
        withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
            flipped.toggle()
            index += 1
        }
    }

    private var prompts: [String] {
        switch game {
        case .whosMoreLikely:
            ["Who's more likely to cry at a movie?",
             "Who's more likely to forget an anniversary… and recover beautifully?",
             "Who's more likely to adopt a pet without asking?",
             "Who's more likely to become famous?",
             "Who's more likely to get lost with GPS on?",
             "Who's more likely to spend the vacation budget in one day?"]
        case .wouldYouRather:
            ["Would you rather relive our first date or fast-forward to our 10th anniversary?",
             "Would you rather always know what I'm thinking, or me always know yours?",
             "Would you rather live in a tiny house by the sea or a penthouse downtown?",
             "Would you rather give up coffee together or takeout together?"]
        case .neverHaveIEver:
            ["Never have I ever pretended to like a gift from you.",
             "Never have I ever read your texts over your shoulder.",
             "Never have I ever let you win an argument on purpose.",
             "Never have I ever stalked your ex online."]
        case .guessMyAnswer:
            ["What would I grab first in a fire (after you)?",
             "What's my dream vacation?",
             "What's my most-used emoji when texting you?",
             "What food could I eat every day forever?"]
        case .trivia:
            ["What was the first thing I said to you?",
             "What was I wearing on our first date?",
             "Name the song that always reminds me of you.",
             "What's my proudest moment since we met?"]
        case .emojiStory:
            ["Tell the story of our first date in exactly 5 emojis.",
             "Describe your morning mood today in 3 emojis.",
             "Our next vacation, but only emojis.",
             "Your favorite memory of us — emoji edition."]
        case .speedQuiz:
            ["10 seconds: my shoe size?",
             "10 seconds: my boss's name?",
             "10 seconds: my coffee order?",
             "10 seconds: the date of our anniversary?"]
        case .compatibilityQuiz:
            ["Ideal Sunday: adventure or absolute stillness? Answer together on 3…",
             "Money: save for the house or spend on the trip?",
             "Kids' bedtime: strict schedule or vibes?",
             "Conflict style: talk it out now or cool off first?"]
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

                // Weekly report
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

                // Date planner
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

                // Chat
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ask the coach")
                        .font(Lovio.Type_.title)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Live DeepSeek coach via Cloud Functions once `askCoach`
                    // is deployed; falls back to example replies until then.
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
