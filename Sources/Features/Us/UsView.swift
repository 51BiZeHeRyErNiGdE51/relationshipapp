import SwiftUI

// MARK: - Us: relationship hub

struct UsView: View {
    @Environment(AppModel.self) private var model
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                coupleHeader
                loveScoreCard

                if !model.premium.isPremium {
                    premiumBanner
                }

                levelCard
                achievementsCard

                NavigationLink { WidgetGalleryView() } label: {
                    rowCard(symbol: "square.grid.2x2.fill", tint: Lovio.Palette.lavender,
                            title: "Widget Gallery",
                            subtitle: "Put Lovio on your home screen — the app that loves you back")
                }
                .buttonStyle(.plain)

                NavigationLink { CompanionView() } label: {
                    rowCard(symbol: model.relationship?.companion.kind.symbol ?? "leaf.fill",
                            tint: Lovio.Palette.teal,
                            title: "Our Companion",
                            subtitle: "\(model.relationship?.companion.kind.title ?? "") · \(model.relationship?.companion.stageName ?? "")")
                }
                .buttonStyle(.plain)

                NavigationLink { MoodAnalyticsView() } label: {
                    rowCard(symbol: "chart.xyaxis.line", tint: Lovio.Palette.peach,
                            title: "Mood & Trends",
                            subtitle: "Monthly analytics for both of you")
                }
                .buttonStyle(.plain)

                NavigationLink { SettingsView() } label: {
                    rowCard(symbol: "gearshape.fill", tint: .gray,
                            title: "Settings",
                            subtitle: "Profile, notifications, privacy, account")
                }
                .buttonStyle(.plain)
            }
            .padding(Lovio.Metrics.screenPadding)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Us")
        .sheet(isPresented: $showPaywall) { PaywallView(source: "us_tab") }
    }

    private var coupleHeader: some View {
        VStack(spacing: 12) {
            AvatarPair(left: model.myProfile?.initials ?? "Y",
                       right: model.partnerProfile?.initials ?? "L", size: 72)
            Text("\(model.myName) & \(model.partnerName)")
                .font(Lovio.Type_.title)
            if let anniversary = model.relationship?.anniversary {
                Text("Together since \(anniversary.formatted(date: .abbreviated, time: .omitted)) · \(model.relationship?.daysTogether ?? 0) days")
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var loveScoreCard: some View {
        GlassCard(tint: Lovio.Palette.rose) {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Lovio.Palette.rose.opacity(0.15), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: CGFloat(model.relationship?.loveScore ?? 0) / 100)
                        .stroke(Lovio.Gradients.hero, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(model.relationship?.loveScore ?? 0)")
                        .font(Lovio.Type_.numeric)
                }
                .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Love Score").font(Lovio.Type_.headline)
                    Text("A weekly pulse built from your questions, moods, memories and time together.")
                        .font(Lovio.Type_.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var levelCard: some View {
        GlassCard(tint: Lovio.Palette.gold) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Level \(model.relationship?.level ?? 1)", systemImage: "rosette")
                        .font(Lovio.Type_.headline)
                        .foregroundStyle(Lovio.Palette.gold)
                    Spacer()
                    Text("\(model.relationship?.xpIntoLevel ?? 0) / 500 XP")
                        .font(Lovio.Type_.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(model.relationship?.xpIntoLevel ?? 0), total: 500)
                    .tint(Lovio.Palette.gold)
            }
        }
    }

    private var achievementsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Achievements").font(Lovio.Type_.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Achievement.catalog) { achievement in
                            VStack(spacing: 8) {
                                Image(systemName: achievement.symbol)
                                    .font(.title2)
                                    .foregroundStyle(achievement.isUnlocked
                                                     ? AnyShapeStyle(Lovio.Gradients.streak)
                                                     : AnyShapeStyle(.tertiary))
                                    .frame(width: 56, height: 56)
                                    .background(Circle().fill(.ultraThinMaterial))
                                Text(achievement.title)
                                    .font(Lovio.Type_.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 84)
                        }
                    }
                }
            }
        }
    }

    private var premiumBanner: some View {
        Button { showPaywall = true } label: {
            GlassCard(tint: Lovio.Palette.gold) {
                HStack(spacing: 14) {
                    Image(systemName: "crown.fill")
                        .font(.title2)
                        .foregroundStyle(Lovio.Palette.gold)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Lovio Premium — for both of you")
                            .font(Lovio.Type_.headline)
                        Text("One subscription covers you and \(model.partnerName.split(separator: " ").first.map(String.init) ?? "your partner")")
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

    private func rowCard(symbol: String, tint: Color, title: String, subtitle: String) -> some View {
        GlassCard(tint: tint) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Lovio.Type_.headline)
                    Text(subtitle)
                        .font(Lovio.Type_.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Companion

struct CompanionView: View {
    @Environment(AppModel.self) private var model
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if let companion = model.relationship?.companion {
                    // Hero
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Lovio.Gradients.mood)
                                .frame(width: 150, height: 150)
                                .blur(radius: 38)
                                .opacity(0.5)
                            Image(systemName: companion.kind.symbol)
                                .font(.system(size: 84))
                                .foregroundStyle(Lovio.Gradients.mood)
                                .symbolEffect(.pulse)
                        }
                        Text("\(companion.kind.title)")
                            .font(Lovio.Type_.largeTitle)
                        Text("Stage \(companion.stage + 1) · \(companion.stageName)")
                            .font(Lovio.Type_.headline)
                            .foregroundStyle(.secondary)

                        ProgressView(value: companion.growth, total: 100)
                            .tint(Lovio.Palette.teal)
                            .padding(.horizontal, 40)

                        Text("It grows when you answer questions, log moods, save memories and keep your streak. Neglect it and it wilts — together means every day.")
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // Picker
                    Text("Choose your world")
                        .font(Lovio.Type_.title)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                        ForEach(CompanionKind.allCases, id: \.self) { kind in
                            Button {
                                if kind.isPremium && !model.premium.isPremium {
                                    showPaywall = true
                                } else {
                                    Task { await model.switchCompanion(kind) }
                                }
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: kind.symbol)
                                        .font(.title2)
                                        .foregroundStyle(kind == companion.kind
                                                         ? AnyShapeStyle(Lovio.Gradients.mood)
                                                         : AnyShapeStyle(.secondary))
                                    Text(kind.title)
                                        .font(Lovio.Type_.caption)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    if kind.isPremium && !model.premium.isPremium {
                                        Image(systemName: "crown.fill")
                                            .font(.caption2)
                                            .foregroundStyle(Lovio.Palette.gold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background {
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(.ultraThinMaterial)
                                        .overlay {
                                            if kind == companion.kind {
                                                RoundedRectangle(cornerRadius: 18)
                                                    .strokeBorder(Lovio.Palette.teal, lineWidth: 2)
                                            }
                                        }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(Lovio.Metrics.screenPadding)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Companion")
        .sheet(isPresented: $showPaywall) { PaywallView(source: "companion") }
    }
}

// MARK: - Mood analytics

struct MoodAnalyticsView: View {
    @Environment(AppModel.self) private var model
    @State private var history: [MoodEntry] = []
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard(tint: Lovio.Palette.teal) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Last 30 days").font(Lovio.Type_.headline)
                        HStack(alignment: .bottom, spacing: 5) {
                            ForEach(0..<30, id: \.self) { day in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Lovio.Gradients.mood)
                                    .frame(height: barHeight(day: day))
                                    .frame(maxWidth: .infinity)
                                    .opacity(0.55 + 0.45 * (barHeight(day: day) / 64))
                            }
                        }
                        .frame(height: 64, alignment: .bottom)
                        Text("Average energy trend for both of you")
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !model.premium.isPremium {
                    Button { showPaywall = true } label: {
                        GlassCard(tint: Lovio.Palette.gold) {
                            Label("Full mood analytics, correlations and relationship trends are Premium",
                                  systemImage: "crown.fill")
                                .font(Lovio.Type_.body)
                                .foregroundStyle(Lovio.Palette.gold)
                        }
                    }
                    .buttonStyle(.plain)
                }

                ForEach(history) { entry in
                    GlassCard {
                        HStack {
                            Text(entry.mood.emoji).font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.authorID == model.user?.id ? model.myName : model.partnerName)
                                    .font(Lovio.Type_.headline)
                                Text(entry.loggedAt, style: .relative)
                                    .font(Lovio.Type_.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Label("\(entry.energy)", systemImage: "bolt.fill")
                                .font(Lovio.Type_.caption)
                                .foregroundStyle(Lovio.Palette.gold)
                            Label("\(entry.loveMeter)", systemImage: "heart.fill")
                                .font(Lovio.Type_.caption)
                                .foregroundStyle(Lovio.Palette.rose)
                        }
                    }
                }
            }
            .padding(Lovio.Metrics.screenPadding)
        }
        .navigationTitle("Mood & Trends")
        .sheet(isPresented: $showPaywall) { PaywallView(source: "mood_analytics") }
        .task {
            guard let rel = model.relationship else { return }
            history = (try? await model.services.mood.history(relationship: rel.id, days: 30)) ?? []
        }
    }

    private func barHeight(day: Int) -> CGFloat {
        // Deterministic pseudo-trend for the chart placeholder.
        let seed = sin(Double(day) * 0.9) * 0.5 + 0.5
        return CGFloat(18 + seed * 46)
    }
}
