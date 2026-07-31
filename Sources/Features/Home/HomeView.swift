import SwiftUI

// MARK: - Today
//
// The retention surface. Everything above the fold answers:
// "what can we do together right now?"

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showMoodSheet = false
    @State private var showQuestion = false
    @State private var missYouBurst = false
    @State private var showJoinSheet = false
    @State private var showOfferPaywall = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if model.isPaired { coupleHero } else { pairingHero }
                questionCard
                moodRow
                widgetPromoCard
                companionCard
                nextEventCard
                aiTeaserCard
                offerChip
                if !model.premium.isPremium {
                    AdBannerCard()
                }
            }
            .padding(.horizontal, Lovio.Metrics.screenPadding)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                missYouButton
            }
        }
        .sheet(isPresented: $showMoodSheet) { MoodSheet() }
        .sheet(isPresented: $showQuestion) { DailyQuestionView() }
        .sheet(isPresented: $showJoinSheet) { JoinPartnerSheet() }
        .sheet(isPresented: $showOfferPaywall) {
            PaywallView(source: "home_offer_chip", startOnSecondary: true)
        }
        .refreshable { await model.refreshToday() }
    }

    // MARK: Secondary-offer reminder chip (in-app companion to the push nudges)

    @ViewBuilder
    private var offerChip: some View {
        if !model.premium.isPremium,
           let deadline = model.secondaryOfferDeadline, deadline > .now {
            Button { showOfferPaywall = true } label: {
                GlassCard(tint: Lovio.Palette.gold) {
                    HStack(spacing: 12) {
                        Image(systemName: "gift.fill")
                            .foregroundStyle(Lovio.Palette.gold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your 50% couple's offer")
                                .font(Lovio.Type_.headline)
                            Text("Ends \(deadline, style: .relative) from now")
                                .font(Lovio.Type_.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Hero — paired
    //
    // One card that makes the relationship feel like a living thing:
    // days counter front and center, streak + love score as satellites.

    private var coupleHero: some View {
        VStack(spacing: 16) {
            HStack {
                AvatarPair(left: model.myProfile?.initials ?? "Y",
                           right: model.partnerProfile?.initials ?? "L", size: 44)
                Spacer()
                HeartPulse(size: 26)
            }

            VStack(spacing: 2) {
                Text("\(model.relationship?.daysTogether ?? 0)")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text("days of \(model.myFirstName) & \(model.partnerFirstName ?? "you")")
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }

            HStack(spacing: 10) {
                heroChip(symbol: "flame.fill",
                         value: "\(model.relationship?.streak.current ?? 0)",
                         label: "streak")
                heroChip(symbol: "heart.fill",
                         value: "\(model.relationship?.loveScore ?? 0)",
                         label: "love score")
                heroChip(symbol: "rosette",
                         value: "\(model.relationship?.level ?? 1)",
                         label: "level")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Lovio.Metrics.cornerRadius)
                .fill(Lovio.Gradients.hero)
                .shadow(color: Lovio.Palette.rose.opacity(0.35), radius: 18, y: 8)
        }
    }

    private func heroChip(symbol: String, value: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.caption)
            Text(value).font(.system(.subheadline, design: .rounded, weight: .heavy))
            Text(label).font(.system(.caption2, design: .rounded))
                .opacity(0.8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(.white.opacity(0.18)))
        .frame(maxWidth: .infinity)
    }

    // MARK: Hero — solo (pairing)
    //
    // Users can enter the app without a partner; connecting stays one tap
    // away. This card disappears the moment a partner joins.

    private var pairingHero: some View {
        VStack(spacing: 14) {
            HeartPulse(size: 34)

            Text("Missuo is better with your person")
                .font(Lovio.Type_.title)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("Share your code — it takes them 30 seconds to join.")
                .font(Lovio.Type_.caption)
                .foregroundStyle(.white.opacity(0.8))

            Text(model.relationship?.inviteCode?.display ?? "· · · · · ·")
                .font(.system(size: 38, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.15)))

            HStack(spacing: 10) {
                if let code = model.relationship?.inviteCode?.value {
                    ShareLink(item: "Join me on Missuo 💞 My code: \(code)") {
                        Label("Share code", systemImage: "square.and.arrow.up")
                            .font(Lovio.Type_.caption.weight(.semibold))
                            .foregroundStyle(Lovio.Palette.plum)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(.white))
                    }
                }
                Button {
                    showJoinSheet = true
                } label: {
                    Label("Enter their code", systemImage: "keyboard")
                        .font(Lovio.Type_.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(.white.opacity(0.2)))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Lovio.Metrics.cornerRadius)
                .fill(Lovio.Gradients.hero)
                .shadow(color: Lovio.Palette.rose.opacity(0.35), radius: 18, y: 8)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(Lovio.Type_.headline)
                Text(Date.now.formatted(date: .complete, time: .omitted))
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.premium.isPremium {
                Label("Premium", systemImage: "crown.fill")
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(Lovio.Palette.gold)
            }
        }
        .padding(.top, 4)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Good morning, lovebirds"
        case 12..<18: return "Hope your day is going well"
        default: return "Winding down together"
        }
    }

    // MARK: Widgets promo — the flagship surface deserves a Home entry point

    private var widgetPromoCard: some View {
        NavigationLink { WidgetGalleryView() } label: {
            GlassCard(tint: Lovio.Palette.peach) {
                HStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                        .foregroundStyle(Lovio.Palette.peach)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Send a photo to your widgets")
                            .font(Lovio.Type_.headline)
                        Text("Your moments on the home screen, all day")
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Daily question

    private var questionCard: some View {
        Button { showQuestion = true } label: {
            GlassCard(tint: Lovio.Palette.lavender) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Today's Question", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(Lovio.Palette.lavender)
                        Spacer()
                        if let state = model.questionState {
                            questionStatusBadge(state)
                        }
                    }

                    Text(model.questionState?.question.text ?? "Loading today's question…")
                        .font(Lovio.Type_.title)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)

                    if let state = model.questionState {
                        Text(statusLine(state))
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func questionStatusBadge(_ state: DailyQuestionState) -> some View {
        Group {
            if state.isRevealed {
                Label("Revealed", systemImage: "lock.open.fill")
            } else if state.myAnswer != nil {
                Label("Waiting", systemImage: "hourglass")
            } else if state.partnerHasAnswered {
                Label("\(model.partnerFirstName ?? "Partner") answered!", systemImage: "sparkles")
            }
        }
        .font(Lovio.Type_.caption)
        .foregroundStyle(Lovio.Palette.rose)
    }

    private func statusLine(_ state: DailyQuestionState) -> String {
        if state.isRevealed { return "Both answers unlocked — read them together." }
        if state.myAnswer != nil { return "You've answered. Answers reveal when your partner does too." }
        if state.partnerHasAnswered { return "Your partner already answered. Yours unlocks both." }
        return "Answers stay sealed until you've both replied."
    }

    // MARK: Mood

    private var moodRow: some View {
        Button { showMoodSheet = true } label: {
            GlassCard(tint: Lovio.Palette.teal) {
                HStack(spacing: 18) {
                    moodBubble(name: "You", entry: model.user.flatMap { model.latestMoods[$0.id] })
                    Divider().frame(height: 44)
                    moodBubble(name: model.partnerFirstName ?? "Partner", entry: partnerMood)
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Lovio.Palette.teal)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var partnerMood: MoodEntry? {
        guard let rel = model.relationship, let me = model.user,
              let partnerID = rel.partnerID(of: me.id) else { return nil }
        return model.latestMoods[partnerID]
    }

    private func moodBubble(name: String, entry: MoodEntry?) -> some View {
        HStack(spacing: 10) {
            Text(entry?.mood.emoji ?? "＋")
                .font(.system(size: 30))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(Lovio.Type_.caption).foregroundStyle(.secondary)
                Text(entry?.mood.title ?? "Check in")
                    .font(Lovio.Type_.headline)
            }
        }
    }

    // MARK: Companion

    private var companionCard: some View {
        NavigationLink { CompanionView() } label: {
            GlassCard {
                HStack(spacing: 16) {
                    if let companion = model.relationship?.companion {
                        Image(systemName: companion.kind.symbol)
                            .font(.system(size: 34))
                            .foregroundStyle(Lovio.Gradients.mood)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(.ultraThinMaterial))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(companion.kind.title) · \(companion.stageName)")
                                .font(Lovio.Type_.headline)
                            ProgressView(value: companion.growth, total: 100)
                                .tint(Lovio.Palette.teal)
                            Text("Grows every time you two show up for each other")
                                .font(Lovio.Type_.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Next event

    @ViewBuilder
    private var nextEventCard: some View {
        if let next = model.upcomingDates.first {
            GlassCard(tint: Lovio.Palette.peach) {
                HStack {
                    Image(systemName: next.kind.symbol)
                        .font(.title2)
                        .foregroundStyle(Lovio.Palette.rose)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.title).font(Lovio.Type_.headline)
                        Text("Next adventure").font(Lovio.Type_.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(spacing: 0) {
                        Text("\(next.daysUntil)")
                            .font(Lovio.Type_.numeric)
                            .foregroundStyle(Lovio.Gradients.hero)
                        Text("days").font(Lovio.Type_.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: AI teaser

    private var aiTeaserCard: some View {
        NavigationLink { AICoachView() } label: {
            GlassCard(tint: Lovio.Palette.lavender) {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(Lovio.Gradients.hero)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your week, decoded")
                            .font(Lovio.Type_.headline)
                        Text("AI coach · insights from your questions, moods and moments")
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Miss you

    private var missYouButton: some View {
        Button {
            missYouBurst = true
            Task {
                await model.sendMissYou()
                try? await Task.sleep(for: .seconds(1))
                missYouBurst = false
            }
        } label: {
            Image(systemName: missYouBurst ? "heart.fill" : "paperplane.fill")
                .symbolEffect(.bounce, value: missYouBurst)
                .foregroundStyle(Lovio.Palette.rose)
        }
        .accessibilityLabel("Send Miss You")
    }
}
