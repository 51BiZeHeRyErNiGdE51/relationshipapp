import SwiftUI
import WidgetKit

// MARK: - Love Days (free tier)

struct LoveDaysWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "love_days", provider: SnapshotProvider()) { entry in
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
            }
            .lovioWidgetContainer()
        }
        .configurationDisplayName("Love Days")
        .description("Days together, always in sight.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Love Pulse (heartbeat when both online)

struct LovePulseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "love_pulse", provider: SnapshotProvider()) { entry in
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
                Text(entry.snapshot.todayQuestion ?? "Open Lovio for today's question")
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
                if let target = entry.snapshot.nextEventDate {
                    Text(target, style: .relative)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Lovio.Palette.gold)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lovioWidgetContainer()
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
                Text("\(entry.snapshot.missYouCountToday) sent today")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lovioWidgetContainer([Lovio.Palette.rose, Lovio.Palette.plum])
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
            let revealed = AppGroup.defaults.bool(forKey: "lovio.secret.revealed")
            Button(intent: RevealSecretIntent()) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(revealed ? "From \(entry.snapshot.partnerName.split(separator: " ").first.map(String.init) ?? "them")" : "Secret note",
                          systemImage: revealed ? "envelope.open.fill" : "envelope.fill")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(Lovio.Palette.gold)
                    Text(entry.snapshot.latestNote ?? "No note yet — send one from Lovio")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .blur(radius: revealed ? 0 : 7)
                        .lineLimit(3)
                    if !revealed {
                        Text("Tap to reveal")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .lovioWidgetContainer()
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
        }
        .configurationDisplayName("Love Jar")
        .description("Collect hearts together, one tap at a time.")
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
                    Text("Log a meetup in Lovio")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .lovioWidgetContainer([Lovio.Palette.teal.opacity(0.7), Lovio.Palette.midnight])
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
        }
        .configurationDisplayName("Companion")
        .description("Your shared world, growing with every check-in.")
        .supportedFamilies([.systemSmall])
    }
}
