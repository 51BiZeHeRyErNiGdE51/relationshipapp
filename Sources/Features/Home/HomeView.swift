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
    @State private var nameDraft = ""
    @State private var showAnniversaryEditor = false
    @State private var showScoreInfo = false
    @State private var heartBurst: HeartBurst?

    /// Full-screen floating-hearts moment (sent or received).
    struct HeartBurst: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let emoji: String
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                nameCaptureCard
                if model.isPaired { coupleHero } else { pairingHero }
                anniversaryCard
                notificationNudgeCard
                questionCard
                sendLoveRow
                moodRow
                hugCard
                widgetPromoCard
                companionCard
                nextEventCard
                aiTeaserCard
                offerChip
            }
            .padding(.horizontal, Lovio.Metrics.screenPadding)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        // No nav bar at all on Home — the greeting header row (logo +
        // greeting + Miss You) is the top of the screen, no dead space.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showMoodSheet) { MoodSheet() }
        .sheet(isPresented: $showQuestion) { DailyQuestionView() }
        .sheet(isPresented: $showJoinSheet) { JoinPartnerSheet() }
        .sheet(isPresented: $showOfferPaywall) {
            PaywallView(source: "home_offer_chip", startOnSecondary: true)
        }
        .sheet(isPresented: $showAnniversaryEditor) { AnniversaryEditorSheet() }
        .alert("How your scores work", isPresented: $showScoreInfo) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("Streak — days in a row you've both shown up (answers, moods, hearts).\n\nLove score — a 0–100 health score that rises with every shared action and gently drifts down when things go quiet.\n\nLevel — grows with everything you two do together; it never goes down.")
        }
        // Incoming love bursts are handled at MainTabView so they show on
        // every tab (not only Home). Local send bursts still play here.
        .overlay {
            if let burst = heartBurst {
                HeartBurstView(burst: burst)
            }
        }
        .refreshable { await model.refreshToday() }
    }

    private func showHeartBurst(_ burst: HeartBurst) {
        withAnimation(.smooth) { heartBurst = burst }
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(.smooth) {
                if heartBurst == burst { heartBurst = nil }
            }
        }
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
        VStack(spacing: 14) {
            HStack {
                AvatarPair(left: model.myProfile?.initials ?? "♥",
                           right: model.partnerProfile?.initials ?? "♥", size: 44)
                Spacer()
                HeartPulse(size: 26)
            }

            VStack(spacing: 2) {
                if model.relationship?.anniversary != nil {
                    Text("\(model.relationship?.daysTogether ?? 0)")
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("days of \(model.myFirstName) & \(model.partnerFirstName ?? "you")")
                        .font(Lovio.Type_.caption)
                        .foregroundStyle(.white.opacity(0.85))
                    if let next = model.relationship?.daysUntilNextAnniversary {
                        Text(next == 0 ? "It's your anniversary — today! 🎉"
                                       : "🎂 Anniversary in \(next) day\(next == 1 ? "" : "s")")
                            .font(Lovio.Type_.caption.weight(.semibold))
                            .foregroundStyle(Lovio.Palette.gold)
                            .padding(.top, 2)
                    }
                } else {
                    Text("\(model.myFirstName) & \(model.partnerFirstName ?? "you")")
                        .font(Lovio.Type_.title)
                        .foregroundStyle(.white)
                }
            }

            // Tap any stat for a plain-language explanation.
            Button { showScoreInfo = true } label: {
                HStack(spacing: 8) {
                    heroChip(symbol: "flame.fill",
                             value: "\(model.relationship?.streak.current ?? 0)",
                             label: "streak")
                    heroChip(symbol: "heart.fill",
                             value: "\(model.relationship?.loveScore ?? 0)",
                             label: "love")
                    heroChip(symbol: "rosette",
                             value: "\(model.relationship?.level ?? 1)",
                             label: "level")
                }
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Lovio.Metrics.cornerRadius)
                .fill(Lovio.Gradients.hero)
                .shadow(color: Lovio.Palette.rose.opacity(0.35), radius: 18, y: 8)
        }
    }

    /// Compact: number on top, single short word under it — never wraps.
    private func heroChip(symbol: String, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.caption2)
                Text(value).font(.system(.subheadline, design: .rounded, weight: .heavy))
            }
            Text(label)
                .font(.system(size: 10, design: .rounded))
                .opacity(0.75)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.18)))
    }

    // MARK: Anniversary — prompt once paired, edit any time in Settings

    @ViewBuilder
    private var anniversaryCard: some View {
        if model.isPaired, model.relationship?.anniversary == nil {
            Button { showAnniversaryEditor = true } label: {
                GlassCard(tint: Lovio.Palette.gold) {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.title3)
                            .foregroundStyle(Lovio.Palette.gold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("When did you two begin?")
                                .font(Lovio.Type_.headline)
                            Text("Set your date to unlock the day counter, anniversary countdown and the Love Days widget.")
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

    // MARK: Hero — solo (pairing)
    //
    // Users can enter the app without a partner; connecting stays one tap
    // away. Deliberately compact — one line, the code, two buttons.
    // This card disappears the moment a partner joins.

    private var pairingHero: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invite your person")
                        .font(Lovio.Type_.headline)
                        .foregroundStyle(.white)
                    Text("Joining takes 30 seconds")
                        .font(Lovio.Type_.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Text(model.relationship?.inviteCode?.display ?? "· · · · · ·")
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.15)))
            }

            HStack(spacing: 10) {
                if let code = model.relationship?.inviteCode?.value {
                    ShareLink(item: "Join me on Missuo 💞 My code: \(code)") {
                        Label("Share code", systemImage: "square.and.arrow.up")
                            .font(Lovio.Type_.caption.weight(.semibold))
                            .foregroundStyle(Lovio.Palette.plum)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
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
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.white.opacity(0.2)))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Lovio.Metrics.cornerRadius)
                .fill(Lovio.Gradients.hero)
                .shadow(color: Lovio.Palette.rose.opacity(0.35), radius: 18, y: 8)
        }
    }

    // MARK: Name capture — one-time card; closes forever once saved
    //
    // Onboarding never asks for a name (kept frictionless), so this is where
    // "You" and "L" become real names. Editable later in Settings.

    @ViewBuilder
    private var nameCaptureCard: some View {
        if model.needsMyName {
            GlassCard(tint: Lovio.Palette.lavender) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("What should we call you?", systemImage: "person.crop.circle.badge.plus")
                        .font(Lovio.Type_.headline)
                        .foregroundStyle(Lovio.Palette.lavender)
                    Text("Your partner sees this name in the app and on their widgets.")
                        .font(Lovio.Type_.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        TextField("Your first name", text: $nameDraft)
                            .textInputAutocapitalization(.words)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                            .onSubmit { saveName() }
                        Button("Save") { saveName() }
                            .font(Lovio.Type_.caption.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Lovio.Palette.lavender.opacity(0.25)))
                            .disabled(nameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func saveName() {
        let name = nameDraft
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            await model.updateMyName(name)
            Haptics.success()
        }
    }

    // MARK: Notification nudge — shown only if the user declined the push prompt

    @ViewBuilder
    private var notificationNudgeCard: some View {
        if model.notificationsDenied {
            Button {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                GlassCard(tint: Lovio.Palette.rose) {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.badge.fill")
                            .font(.title3)
                            .foregroundStyle(Lovio.Palette.rose)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Don't miss their moments")
                                .font(Lovio.Type_.headline)
                            Text("Turn on notifications and we'll only ping you when your love sends something — a miss-you, an answer, a photo.")
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

    // MARK: Header

    // Single compact top row: logo + greeting + Miss You. Premium badge lives
    // in Us → Settings — no crown chip and no empty nav-bar row above.
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            MissuoLogoMark(size: 36, shadow: false)
            Text(greeting)
                .font(Lovio.Type_.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            missYouButton
        }
        .padding(.top, 0)
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
                    moodBubble(name: model.myFirstName, entry: model.user.flatMap { model.latestMoods[$0.id] })
                    Divider().frame(height: 44)
                    if model.isPaired {
                        moodBubble(name: model.partnerFirstName ?? "Partner", entry: partnerMood)
                    } else {
                        // Honest unpaired state — no phantom partner.
                        HStack(spacing: 10) {
                            Text("🫥").font(.system(size: 30)).opacity(0.5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Partner").font(Lovio.Type_.caption).foregroundStyle(.secondary)
                                Text("Not paired yet")
                                    .font(Lovio.Type_.headline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Lovio.Palette.teal)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Send love — hearts to the jar, hugs to their phone

    @ViewBuilder
    private var sendLoveRow: some View {
        if model.isPaired {
            HStack(spacing: 12) {
                sendLoveButton(emoji: "💗", label: "Send a heart",
                               burstTitle: "A heart landed in your love jar 💗") {
                    await model.sendHeart()
                }
                sendLoveButton(emoji: "🤗", label: "Send a hug",
                               burstTitle: "Hug sent — \(model.partnerFirstName ?? "your love") feels it 🤗") {
                    await model.sendHug()
                }
            }
        }
    }

    private func sendLoveButton(emoji: String, label: String, burstTitle: String,
                                action: @escaping () async -> Void) -> some View {
        Button {
            showHeartBurst(HeartBurst(title: burstTitle, emoji: emoji))
            Task { await action() }
        } label: {
            GlassCard(tint: Lovio.Palette.rose) {
                VStack(spacing: 6) {
                    Text(emoji).font(.title2)
                    Text(label)
                        .font(Lovio.Type_.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Hug log — feeds the Hug Meter widget ("days since your last hug")

    @ViewBuilder
    private var hugCard: some View {
        if model.isPaired {
            Button {
                guard !model.meetupLoggedToday else { return }
                showHeartBurst(HeartBurst(
                    title: "Hug logged — your Hug Meter is back to day zero 🤗",
                    emoji: "🤗"))
                Task { await model.logMeetup() }
            } label: {
                GlassCard(tint: Lovio.Palette.teal) {
                    HStack(spacing: 12) {
                        Text("🤗").font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.meetupLoggedToday
                                 ? "Together today — logged!"
                                 : "Together right now?")
                                .font(Lovio.Type_.headline)
                            Text(model.meetupLoggedToday
                                 ? "Your Hug Meter widgets show day zero on both phones."
                                 : "Log a hug — it resets the Hug Meter widget for both of you.")
                                .font(Lovio.Type_.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: model.meetupLoggedToday
                              ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Lovio.Palette.teal)
                    }
                }
            }
            .buttonStyle(.plain)
        }
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
        if let next = model.upcomingDates.first(where: \.isUpcoming) {
            GlassCard(tint: Lovio.Palette.peach) {
                HStack {
                    Image(systemName: next.kind.symbol)
                        .font(.title2)
                        .foregroundStyle(Lovio.Palette.rose)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.title).font(Lovio.Type_.headline)
                        Text(next.shortDateLabel)
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(spacing: 0) {
                        Text(next.daysUntil == 0 ? "Today" : "\(next.daysUntil)")
                            .font(Lovio.Type_.numeric)
                            .foregroundStyle(Lovio.Gradients.hero)
                        Text(next.daysUntil == 0 ? "🎉" : "days").font(Lovio.Type_.caption).foregroundStyle(.secondary)
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

    /// One-tap "miss you" — sends a push to the partner's phone.
    /// Labeled so its purpose is obvious (was a bare paperplane icon).
    private var missYouButton: some View {
        Button {
            missYouBurst = true
            showHeartBurst(HeartBurst(
                title: model.isPaired
                    ? "Sent! \(model.partnerFirstName ?? "Your love")'s phone lights up 💗"
                    : "Saved — it reaches them once you pair 💗",
                emoji: "💗"))
            Task {
                await model.sendMissYou()
                try? await Task.sleep(for: .seconds(1.4))
                missYouBurst = false
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: missYouBurst ? "heart.fill" : "paperplane.fill")
                    .symbolEffect(.bounce, value: missYouBurst)
                Text(missYouBurst ? "Sent!" : "Miss you")
                    .font(Lovio.Type_.caption.weight(.semibold))
            }
            .foregroundStyle(Lovio.Palette.rose)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Lovio.Palette.rose.opacity(0.12)))
        }
        .accessibilityLabel("Send Miss You to your partner")
    }
}

// MARK: - Paired celebration (full screen, one-time per pairing)

struct PairedCelebrationView: View {
    let partnerName: String
    let dismiss: () -> Void
    @State private var animate = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            FloatingHearts(emoji: "💞", count: 14)

            VStack(spacing: 18) {
                Text("💞")
                    .font(.system(size: 84))
                    .scaleEffect(animate ? 1 : 0.3)
                    .animation(.bouncy(duration: 0.7), value: animate)

                Text("You're connected!")
                    .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                Text("You and \(partnerName) now share one space — questions, moods, hearts and widgets flow both ways.")
                    .font(Lovio.Type_.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button(action: dismiss) {
                    Text("Start your story")
                        .font(Lovio.Type_.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(Lovio.Gradients.hero))
                }
                .padding(.horizontal, 40)
                .padding(.top, 8)
            }
            .opacity(animate ? 1 : 0)
            .animation(.smooth(duration: 0.5), value: animate)
        }
        .onAppear { animate = true }
        .transition(.opacity)
    }
}

// MARK: - Heart burst (sent / received love)

struct HeartBurstView: View {
    let burst: HomeView.HeartBurst
    @State private var showBanner = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            FloatingHearts(emoji: burst.emoji, count: 14)
            VStack {
                Spacer()
                Text(burst.title)
                    .font(Lovio.Type_.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .scaleEffect(showBanner ? 1 : 0.7)
                    .opacity(showBanner ? 1 : 0)
                    .padding(.bottom, 90)
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
        .onAppear {
            withAnimation(.bouncy(duration: 0.45)) { showBanner = true }
        }
    }
}

/// Emojis float from the bottom to the top of the screen and fade out.
struct FloatingHearts: View {
    let emoji: String
    let count: Int
    @State private var rise = false

    var body: some View {
        GeometryReader { geo in
            let height = max(geo.size.height, 1)
            let width = max(geo.size.width, 1)
            ForEach(0..<count, id: \.self) { i in
                let x = CGFloat.random(in: 0.08...0.92, seeded: i)
                let delay = Double(i) * 0.1
                let size = CGFloat.random(in: 28...52, seeded: i + 100)
                Text(emoji)
                    .font(.system(size: size))
                    .position(x: width * x, y: rise ? -80 : height + 40)
                    .opacity(rise ? 0 : 1)
                    .animation(.easeOut(duration: 2.4).delay(delay), value: rise)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            // Next run-loop so the starting position paints before we animate.
            DispatchQueue.main.async { rise = true }
        }
    }
}

private extension CGFloat {
    /// Deterministic pseudo-random in range — stable per heart index so the
    /// layout doesn't jump between renders.
    static func random(in range: ClosedRange<CGFloat>, seeded seed: Int) -> CGFloat {
        var value = UInt64(seed &+ 1) &* 6364136223846793005 &+ 1442695040888963407
        value = (value ^ (value >> 33)) &* 0xff51afd7ed558ccd
        let unit = CGFloat(value % 10_000) / 10_000
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}

// MARK: - Anniversary editor (also reachable from Settings)

struct AnniversaryEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("The day you two began", selection: $date,
                               in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                } footer: {
                    Text("Powers your day counter, the anniversary countdown on Home and the Love Days widget. Change it any time in Settings.")
                }
            }
            .navigationTitle("Your anniversary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await model.setAnniversary(date)
                            await model.refreshToday()
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { date = model.relationship?.anniversary ?? .now }
    }
}
