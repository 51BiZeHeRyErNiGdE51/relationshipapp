import SwiftUI
import WidgetKit

// MARK: - Premium gate
//
// iOS can't hide widgets from the system widget gallery, so free users CAN
// add premium widgets — instead of breaking, the widget renders a warm
// invitation until the couple joins Premium. It unlocks live (snapshot
// republish) the moment either partner subscribes.

private struct PremiumLockedView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "crown.fill")
                .font(.title3)
                .foregroundStyle(Lovio.Palette.gold)
            Text(String(localized: "A Premium widget"))
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text(String(localized: "Join Premium in Missuo to light it up 💛"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .lovioWidgetContainer([Lovio.Palette.plum, Lovio.Palette.midnight])
    }
}

extension View {
    /// Premium widgets: real content for premium couples, a warm lock for free.
    /// Tapping the lock opens Missuo on the paywall.
    @ViewBuilder
    func premiumGate(_ snapshot: WidgetSnapshot) -> some View {
        if snapshot.isPremium {
            self
        } else {
            PremiumLockedView()
                .widgetURL(URL(string: "missuo://paywall?source=premium_widget"))
        }
    }
}

// MARK: - Love Days (free tier)

struct LoveDaysWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "love_days", provider: SnapshotProvider()) { entry in
            if entry.snapshot.hasAnniversary == true {
                VStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.title3)
                        .foregroundStyle(Lovio.Palette.rose)
                    Text("\(entry.snapshot.daysTogether)")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("days of us")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                    if let next = entry.snapshot.nextAnniversaryDays {
                        Text(next == 0 ? "Anniversary today 🎉" : "🎂 anniversary in \(next)d")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(Lovio.Palette.gold)
                    }
                }
                .lovioWidgetContainer()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title2)
                        .foregroundStyle(Lovio.Palette.rose)
                    Text("Set your anniversary in Missuo → Us")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .lovioWidgetContainer()
            }
        }
        .configurationDisplayName("Love Days")
        .description("Days together, always in sight.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Polaroids
//
// Two separate widgets so the direction is never ambiguous:
//   MyPolaroidWidget      → the photo YOU uploaded (your own home screen)
//   PartnerPolaroidWidget → the photo your PARTNER sent you

private struct PolaroidBody: View {
    let slot: WidgetContent.Slot
    let emptyTitle: String
    var forceEmpty: Bool = false

    var body: some View {
        if !forceEmpty, let data = WidgetContent.loadPhoto(slot), let image = UIImage(data: data) {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                if let note = WidgetContent.note(slot), !note.isEmpty {
                    Text(note)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                        .padding(8)
                }
            }
            .containerBackground(for: .widget) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2)
                    .foregroundStyle(Lovio.Palette.peach)
                Text(emptyTitle)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .lovioWidgetContainer()
        }
    }
}

/// The photo I chose — mirrors what my partner sees on their "From Your Love".
struct MyPolaroidWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "polaroid_mine", provider: SnapshotProvider()) { _ in
            PolaroidBody(slot: .mine,
                         emptyTitle: "Choose a photo in Missuo → Widgets")
        }
        .configurationDisplayName("My Polaroid")
        .description("The photo you picked — the same one your partner sees.")
        // Small photo tiles rendered unreliably — large only, by design.
        .supportedFamilies([.systemLarge])
    }
}

/// The photo my partner sent me.
struct PartnerPolaroidWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "polaroid_partner", provider: SnapshotProvider()) { entry in
            // After a breakup, never show a leftover App Group photo even if
            // the file somehow wasn't cleared yet.
            if entry.snapshot.isPaired == true {
                PolaroidBody(slot: .partner,
                             emptyTitle: "Photos your partner sends land here 💌")
            } else {
                PolaroidBody(slot: .partner,
                             emptyTitle: "Pair in Missuo to receive their photos",
                             forceEmpty: true)
            }
        }
        .configurationDisplayName("From Your Love")
        .description("The photo and note your partner sent you.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Love Pulse (heartbeat when both online)

struct LovePulseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "love_pulse", provider: SnapshotProvider()) { entry in
            if entry.snapshot.isPaired == true {
                VStack(spacing: 8) {
                    Image(systemName: entry.snapshot.bothRecentlyActive
                          ? "waveform.path.ecg" : "heart.slash")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(entry.snapshot.bothRecentlyActive
                                         ? Lovio.Palette.rose : .white.opacity(0.4))
                        .symbolEffect(.pulse, options: .repeating,
                                      isActive: entry.snapshot.bothRecentlyActive)
                    Text(entry.snapshot.bothRecentlyActive
                         ? "You're both here 💗" : "Waiting for \(entry.snapshot.partnerName)…")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 4) {
                        initialDot(entry.snapshot.myInitials, active: true)
                        initialDot(entry.snapshot.partnerInitials, active: entry.snapshot.bothRecentlyActive)
                    }
                }
                .lovioWidgetContainer([Lovio.Palette.rose.opacity(0.85), Lovio.Palette.plum])
                .premiumGate(entry.snapshot)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "person.2.badge.plus.fill")
                        .font(.title2)
                        .foregroundStyle(Lovio.Palette.rose)
                    Text("Pair with your partner in Missuo first")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .lovioWidgetContainer()
                .premiumGate(entry.snapshot)
            }
        }
        .configurationDisplayName("Love Pulse")
        .description("An animated heartbeat when you're both online.")
        .supportedFamilies([.systemSmall])
    }

    private func initialDot(_ initials: String, active: Bool) -> some View {
        Text(initials)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(.white.opacity(active ? 0.35 : 0.12)))
    }
}

// MARK: - Open Question

struct OpenQuestionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "open_question", provider: SnapshotProvider()) { entry in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Today's Question", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(Lovio.Palette.lavender)
                    Spacer()
                    if entry.snapshot.questionAnsweredByPartner && !entry.snapshot.questionAnsweredByMe {
                        Text("✨ \(entry.snapshot.partnerName.split(separator: " ").first.map(String.init) ?? "") answered")
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(Lovio.Palette.gold)
                    }
                }
                Text(entry.snapshot.todayQuestion ?? "Open Missuo for today's question")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    statusPill(done: entry.snapshot.questionAnsweredByMe, label: "You")
                    statusPill(done: entry.snapshot.questionAnsweredByPartner,
                               label: entry.snapshot.partnerInitials)
                    Spacer()
                    Image(systemName: "arrow.up.right.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .lovioWidgetContainer()
            .premiumGate(entry.snapshot)
        }
        .configurationDisplayName("Open Question")
        .description("Today's question without opening the app.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }

    private func statusPill(done: Bool, label: String) -> some View {
        Label(label, systemImage: done ? "checkmark.circle.fill" : "circle.dotted")
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(done ? Lovio.Palette.teal : .white.opacity(0.5))
    }
}

// MARK: - Mood Sync / Energy Sync

struct MoodSyncWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "mood_sync", provider: SnapshotProvider()) { entry in
            HStack(spacing: 14) {
                moodColumn(name: "You", emoji: entry.snapshot.myMood, energy: entry.snapshot.myEnergy)
                Rectangle().fill(.white.opacity(0.15)).frame(width: 1)
                moodColumn(name: entry.snapshot.partnerName.split(separator: " ").first.map(String.init) ?? "Them",
                           emoji: entry.snapshot.partnerMood, energy: entry.snapshot.partnerEnergy)
            }
            .lovioWidgetContainer([Lovio.Palette.teal.opacity(0.7), Lovio.Palette.midnight])
            .premiumGate(entry.snapshot)
        }
        .configurationDisplayName("Mood Sync")
        .description("Both moods and energy, side by side.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    private func moodColumn(name: String, emoji: String?, energy: Int) -> some View {
        VStack(spacing: 6) {
            Text(emoji ?? "…").font(.system(size: 30))
            Text(name)
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(i < energy ? Lovio.Palette.gold : .white.opacity(0.15))
                        .frame(width: 5, height: 5)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Next Adventure

struct NextAdventureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "next_adventure", provider: SnapshotProvider()) { entry in
            VStack(alignment: .leading, spacing: 6) {
                Label("Next Adventure", systemImage: "airplane.departure")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(Lovio.Palette.peach)
                Text(entry.snapshot.nextEventTitle ?? "Plan something together")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if let target = entry.snapshot.nextEventDate,
                   target >= Calendar.current.startOfDay(for: .now) {
                    Group {
                        if Calendar.current.isDateInToday(target) {
                            Text("Today 🎉")
                        } else {
                            Text(target, style: .relative)
                        }
                    }
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Lovio.Palette.gold)
                    Text(target.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Text("Add a plan in Missuo → Us → Plans")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lovioWidgetContainer()
            .premiumGate(entry.snapshot)
        }
        .configurationDisplayName("Next Adventure")
        .description("Countdown to your next planned date or trip.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

// MARK: - Missing You (interactive)

struct MissYouWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "miss_you", provider: SnapshotProvider()) { entry in
            let sentToday = MissYouCounter.today()
            VStack(spacing: 10) {
                Button(intent: SendMissYouIntent()) {
                    VStack(spacing: 6) {
                        Image(systemName: "paperplane.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white, Lovio.Palette.rose)
                        Text("Miss you")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                Text(sentToday == 0 ? "Tap to send one" : "\(sentToday) sent today")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lovioWidgetContainer([Lovio.Palette.rose, Lovio.Palette.plum])
            .premiumGate(entry.snapshot)
        }
        .configurationDisplayName("Missing You")
        .description("Tap to send an animated 'I miss you' — right from your home screen.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

// MARK: - Secret Message (blur → tap to reveal)

struct SecretMessageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "secret_message", provider: SnapshotProvider()) { entry in
            let paired = entry.snapshot.isPaired == true
            let partnerNote = paired ? WidgetContent.note(.partner) : nil
            let revealed = paired && AppGroup.defaults.bool(forKey: "lovio.secret.revealed")
            Button(intent: RevealSecretIntent()) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(revealed ? "From \(entry.snapshot.partnerName.split(separator: " ").first.map(String.init) ?? "them")" : "Secret note",
                          systemImage: revealed ? "envelope.open.fill" : "envelope.fill")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(Lovio.Palette.gold)
                    Text(partnerNote ?? (paired
                                         ? "Notes your partner sends appear here"
                                         : "Pair in Missuo to receive secret notes"))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .blur(radius: (revealed || partnerNote == nil) ? 0 : 7)
                        .lineLimit(3)
                    if !revealed, partnerNote != nil {
                        Text("Tap to reveal")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .lovioWidgetContainer()
            .premiumGate(entry.snapshot)
        }
        .configurationDisplayName("Secret Message")
        .description("A blurred note from your partner that reveals when you tap.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Love Jar (interactive heart collecting)

struct LoveJarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "love_jar", provider: SnapshotProvider()) { entry in
            let bonus = AppGroup.defaults.integer(forKey: "lovio.hearts.bonus")
            VStack(spacing: 6) {
                Button(intent: HeartTapIntent()) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.white, Lovio.Palette.rose)
                }
                .buttonStyle(.plain)
                Text("\(entry.snapshot.heartsInJar + bonus)")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Lovio.Palette.gold)
                    .contentTransition(.numericText())
                Text("hearts in your jar")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .lovioWidgetContainer()
            .premiumGate(entry.snapshot)
        }
        .configurationDisplayName("Love Jar")
        .description("Collect hearts together, one tap at a time.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Distance

struct DistanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "distance", provider: SnapshotProvider()) { entry in
            VStack(spacing: 6) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.title3)
                    .foregroundStyle(Lovio.Palette.lavender)
                if entry.snapshot.isPaired != true {
                    Text("Pair in Missuo to share distance")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                } else if let km = entry.snapshot.distanceKilometers {
                    if km < 1 {
                        Text("Together 🥰")
                            .font(.system(.headline, design: .rounded, weight: .heavy))
                            .foregroundStyle(.white)
                    } else {
                        Text(km < 100 ? String(format: "%.1f km", km) : "\(Int(km)) km")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text("between your hearts")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                } else {
                    Text("Turn on distance in Missuo → Widgets (both phones)")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
            .lovioWidgetContainer([Lovio.Palette.lavender.opacity(0.75), Lovio.Palette.midnight])
            .premiumGate(entry.snapshot)
        }
        .configurationDisplayName("Distance")
        .description("How far apart you are — updates when either of you uses Missuo. No background tracking.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Hug Meter

struct HugMeterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "hug_meter", provider: SnapshotProvider()) { entry in
            VStack(spacing: 6) {
                Image(systemName: "figure.2.arms.open")
                    .font(.title2)
                    .foregroundStyle(Lovio.Palette.teal)
                if let days = entry.snapshot.daysSinceLastMeeting {
                    Text("\(days)")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(days == 0 ? "hug achieved today" : "days since your last hug")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                } else {
                    Text("Together? Tap 🤗 on Missuo's home screen")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
            }
            .lovioWidgetContainer([Lovio.Palette.teal.opacity(0.7), Lovio.Palette.midnight])
            .premiumGate(entry.snapshot)
        }
        .configurationDisplayName("Hug Meter")
        .description("Days since you were last in the same place.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Companion

struct CompanionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "companion", provider: SnapshotProvider()) { entry in
            VStack(spacing: 8) {
                Image(systemName: CompanionKind(rawValue: entry.snapshot.companionKind)?.symbol ?? "camera.macro")
                    .font(.system(size: 34))
                    .foregroundStyle(Lovio.Palette.teal)
                Text(entry.snapshot.companionStageName)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                ProgressView(value: entry.snapshot.companionGrowth, total: 100)
                    .tint(Lovio.Palette.teal)
                    .scaleEffect(y: 1.4)
            }
            .lovioWidgetContainer()
            .premiumGate(entry.snapshot)
        }
        .configurationDisplayName("Companion")
        .description("Your shared world, growing with every check-in.")
        .supportedFamilies([.systemSmall])
    }
}
