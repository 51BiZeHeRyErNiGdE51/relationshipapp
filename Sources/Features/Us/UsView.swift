import SwiftUI

// MARK: - Us: relationship hub

struct UsView: View {
    @Environment(AppModel.self) private var model
    @State private var showPaywall = false
    @State private var showUnpair = false

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

                NavigationLink { PlanView() } label: {
                    rowCard(symbol: "calendar", tint: Lovio.Palette.lavender,
                            title: "Plans & Countdowns",
                            subtitle: "Dates, bucket list and shared notes")
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

                if model.isPaired {
                    Button { showUnpair = true } label: {
                        rowCard(symbol: "person.2.slash.fill", tint: .red,
                                title: "Unpair from \(model.partnerFirstName ?? "partner")",
                                subtitle: "Disconnect this relationship — your account stays")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Lovio.Metrics.screenPadding)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Us")
        .sheet(isPresented: $showPaywall) { PaywallView(source: "us_tab") }
        .confirmationDialog("Unpair from \(model.partnerName)?",
                            isPresented: $showUnpair, titleVisibility: .visible) {
            Button("Unpair", role: .destructive) {
                Task { await model.unpair() }
            }
        } message: {
            Text("You'll get a fresh invite code and can pair again anytime. If you purchased Premium, it stays with you.")
        }
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
                        Text("Missuo Premium — for both of you")
                            .font(Lovio.Type_.headline)
                        Text("One subscription covers you and \(model.partnerFirstName ?? "your partner")")
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

                    // Growth journey — where it's headed
                    GlassCard(tint: Lovio.Palette.teal) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Its journey").font(Lovio.Type_.headline)
                            ForEach(Array(companion.kind.stageNames.enumerated()), id: \.offset) { index, name in
                                HStack(spacing: 12) {
                                    Image(systemName: index < companion.stage ? "checkmark.circle.fill"
                                                    : index == companion.stage ? "circle.dotted.circle"
                                                    : "circle")
                                        .foregroundStyle(index <= companion.stage
                                                         ? Lovio.Palette.teal : Color.secondary)
                                    Text(name)
                                        .font(index == companion.stage
                                              ? Lovio.Type_.headline : Lovio.Type_.body)
                                        .foregroundStyle(index <= companion.stage ? .primary : .secondary)
                                    if index == companion.stage {
                                        Text("now")
                                            .font(Lovio.Type_.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Lovio.Palette.teal.opacity(0.2)))
                                    }
                                    Spacer()
                                }
                            }
                            Text("Every answered question, mood check-in, memory and streak day feeds it. Reach 100% growth to evolve to the next stage.")
                                .font(Lovio.Type_.caption)
                                .foregroundStyle(.secondary)
                        }
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
                        Text(history.isEmpty
                             ? "Check in moods daily — your real energy trend builds here."
                             : "Average energy trend for both of you")
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.premium.isPremium {
                    premiumInsights
                } else {
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
        // Real data when it exists; deterministic placeholder otherwise.
        let dayStart = Calendar.current.date(byAdding: .day, value: day - 29,
                                             to: Calendar.current.startOfDay(for: .now))!
        let entries = history.filter { Calendar.current.isDate($0.loggedAt, inSameDayAs: dayStart) }
        if !entries.isEmpty {
            let avg = entries.map { Double($0.energy) }.reduce(0, +) / Double(entries.count)
            return CGFloat(12 + (avg / 5) * 52)
        }
        guard history.isEmpty else { return 12 } // no check-in that day
        let seed = sin(Double(day) * 0.9) * 0.5 + 0.5
        return CGFloat(18 + seed * 46)
    }

    // MARK: Premium — real numbers computed from your check-in history

    @ViewBuilder
    private var premiumInsights: some View {
        let mine = history.filter { $0.authorID == model.user?.id }
        let partners = history.filter { $0.authorID != model.user?.id }

        GlassCard(tint: Lovio.Palette.gold) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Your month, in numbers", systemImage: "crown.fill")
                    .font(Lovio.Type_.headline)
                    .foregroundStyle(Lovio.Palette.gold)

                if history.isEmpty {
                    Text("No check-ins yet. Once you both start logging moods, this becomes your monthly relationship report: energy patterns, love meter trends and who checks in more.")
                        .font(Lovio.Type_.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 12) {
                        statBox(value: "\(history.count)", label: "check-ins")
                        statBox(value: String(format: "%.1f", average(history.map { Double($0.energy) })),
                                label: "avg energy")
                        statBox(value: String(format: "%.0f", average(history.map { Double($0.loveMeter) })),
                                label: "love meter")
                    }

                    HStack(spacing: 12) {
                        statBox(value: "\(mine.count)", label: "you")
                        statBox(value: "\(partners.count)", label: model.partnerFirstName ?? "partner")
                        statBox(value: bestWeekday, label: "best day")
                    }

                    Text(mine.count > partners.count
                         ? "You've been checking in more — a gentle nudge to \(model.partnerFirstName ?? "your partner") might be nice."
                         : "\(model.partnerFirstName ?? "Your partner") is keeping the rhythm — match their check-ins to grow your streak.")
                        .font(Lovio.Type_.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func statBox(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(.title3, design: .rounded, weight: .heavy))
            Text(label).font(Lovio.Type_.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
    }

    private func average(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    /// Weekday with the highest average love meter.
    private var bestWeekday: String {
        let grouped = Dictionary(grouping: history) {
            Calendar.current.component(.weekday, from: $0.loggedAt)
        }
        guard let best = grouped.max(by: {
            average($0.value.map { Double($0.loveMeter) }) < average($1.value.map { Double($0.loveMeter) })
        }) else { return "—" }
        return Calendar.current.shortWeekdaySymbols[best.key - 1]
    }
}
