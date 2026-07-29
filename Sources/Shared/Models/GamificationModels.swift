import Foundation

// MARK: - Streaks

public struct Streak: Codable, Hashable, Sendable {
    public var current: Int
    public var best: Int
    /// yyyy-MM-dd of the last day BOTH partners completed a daily action.
    public var lastCompletedDayKey: String?

    public init(current: Int = 0, best: Int = 0, lastCompletedDayKey: String? = nil) {
        self.current = current
        self.best = best
        self.lastCompletedDayKey = lastCompletedDayKey
    }

    public var weeks: Int { current / 7 }
    public var months: Int { current / 30 }
}

public enum DayKey {
    public static func today(calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }
}

// MARK: - Achievements

public struct Achievement: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var symbol: String
    public var xpReward: Int
    public var unlockedAt: Date?

    public init(id: String, title: String, detail: String, symbol: String,
                xpReward: Int, unlockedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.xpReward = xpReward
        self.unlockedAt = unlockedAt
    }

    public var isUnlocked: Bool { unlockedAt != nil }

    public static let catalog: [Achievement] = [
        Achievement(id: "first_answer", title: "Ice Breaker", detail: "Answer your first daily question", symbol: "bubble.left.and.bubble.right.fill", xpReward: 50),
        Achievement(id: "streak_7", title: "One Week Strong", detail: "Keep a 7-day streak together", symbol: "flame.fill", xpReward: 100),
        Achievement(id: "streak_30", title: "Inseparable", detail: "Keep a 30-day streak together", symbol: "flame.circle.fill", xpReward: 400),
        Achievement(id: "journal_10", title: "Memory Keepers", detail: "Add 10 journal memories", symbol: "book.closed.fill", xpReward: 150),
        Achievement(id: "bucket_5", title: "Dream Team", detail: "Complete 5 bucket list items", symbol: "checklist.checked", xpReward: 200),
        Achievement(id: "mood_14", title: "In Tune", detail: "Both log moods 14 days in a row", symbol: "waveform.path.ecg", xpReward: 250),
        Achievement(id: "appreciation", title: "Seen & Loved", detail: "Send 20 appreciation badges", symbol: "hands.sparkles.fill", xpReward: 120),
        Achievement(id: "game_night", title: "Game Night", detail: "Play 5 couple games", symbol: "gamecontroller.fill", xpReward: 100),
    ]
}

// MARK: - Virtual Companions
//
// Multiple companion systems, one shared evolution model. The companion grows
// from real relationship behavior — questions, journals, moods, consistency.

public enum CompanionKind: String, Codable, CaseIterable, Sendable {
    case loveGarden = "love_garden"
    case bonsai
    case galaxy
    case island
    case campfire
    case tinyHouse = "tiny_house"
    case aquarium
    case library
    case musicRoom = "music_room"

    public var title: String {
        switch self {
        case .loveGarden: "Love Garden"
        case .tinyHouse: "Tiny House"
        case .musicRoom: "Music Room"
        default: rawValue.capitalized
        }
    }

    public var symbol: String {
        switch self {
        case .loveGarden: "camera.macro"
        case .bonsai: "tree.fill"
        case .galaxy: "sparkles"
        case .island: "sun.horizon.fill"
        case .campfire: "flame.fill"
        case .tinyHouse: "house.fill"
        case .aquarium: "fish.fill"
        case .library: "books.vertical.fill"
        case .musicRoom: "music.note.house.fill"
        }
    }

    public var isPremium: Bool {
        switch self {
        case .loveGarden, .bonsai, .campfire: false
        default: true
        }
    }

    /// Names for evolution stages, from seed to fully grown.
    public var stageNames: [String] {
        switch self {
        case .loveGarden: ["Seed", "Sprout", "Budding", "Blooming", "In Full Bloom"]
        case .bonsai: ["Cutting", "Sapling", "Shaping", "Mature", "Ancient"]
        case .galaxy: ["Stardust", "Nebula", "Protostar", "Star System", "Galaxy"]
        case .island: ["Sandbar", "Shore", "Grove", "Village", "Paradise"]
        case .campfire: ["Spark", "Kindling", "Flame", "Blaze", "Eternal Fire"]
        case .tinyHouse: ["Foundation", "Frame", "Walls", "Furnished", "Home"]
        case .aquarium: ["Bowl", "Tank", "Reef", "Lagoon", "Ocean"]
        case .library: ["Shelf", "Nook", "Study", "Archive", "Great Library"]
        case .musicRoom: ["First Note", "Melody", "Harmony", "Ensemble", "Symphony"]
        }
    }
}

public struct CompanionState: Codable, Hashable, Sendable {
    public var kind: CompanionKind
    /// 0–100 within the current stage.
    public var growth: Double
    public var stage: Int
    public var lastNurturedAt: Date?

    public init(kind: CompanionKind = .loveGarden, growth: Double = 12,
                stage: Int = 0, lastNurturedAt: Date? = nil) {
        self.kind = kind
        self.growth = growth
        self.stage = stage
        self.lastNurturedAt = lastNurturedAt
    }

    public var stageName: String {
        let names = kind.stageNames
        return names[min(stage, names.count - 1)]
    }

    /// Apply nurture points from a relationship event; evolves stage at 100.
    public mutating func nurture(points: Double) {
        growth += points
        lastNurturedAt = .now
        while growth >= 100, stage < kind.stageNames.count - 1 {
            growth -= 100
            stage += 1
        }
        growth = min(growth, 100)
    }
}

// MARK: - Couple Games

public enum CoupleGame: String, Codable, CaseIterable, Identifiable, Sendable {
    case whosMoreLikely = "whos_more_likely"
    case wouldYouRather = "would_you_rather"
    case neverHaveIEver = "never_have_i_ever"
    case guessMyAnswer = "guess_my_answer"
    case trivia
    case emojiStory = "emoji_story"
    case speedQuiz = "speed_quiz"
    case compatibilityQuiz = "compatibility_quiz"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .whosMoreLikely: "Who's More Likely"
        case .wouldYouRather: "Would You Rather"
        case .neverHaveIEver: "Never Have I Ever"
        case .guessMyAnswer: "Guess My Answer"
        case .trivia: "Couple Trivia"
        case .emojiStory: "Emoji Story"
        case .speedQuiz: "Speed Quiz"
        case .compatibilityQuiz: "Compatibility Quiz"
        }
    }

    public var symbol: String {
        switch self {
        case .whosMoreLikely: "person.2.fill"
        case .wouldYouRather: "arrow.left.arrow.right"
        case .neverHaveIEver: "hand.raised.fill"
        case .guessMyAnswer: "questionmark.bubble.fill"
        case .trivia: "brain.head.profile"
        case .emojiStory: "face.smiling.inverse"
        case .speedQuiz: "bolt.fill"
        case .compatibilityQuiz: "heart.text.square.fill"
        }
    }

    public var isPremium: Bool {
        switch self {
        case .whosMoreLikely, .wouldYouRather: false
        default: true
        }
    }
}
