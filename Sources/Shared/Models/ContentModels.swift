import Foundation

// MARK: - Daily Questions

public enum QuestionCategory: String, Codable, CaseIterable, Sendable {
    case funny, deep, romantic, spicy, future, dreams, money, travel, kids
    case communication, conflict, goals, loveLanguages = "love_languages"
    case family, habits, career, values

    public var title: String {
        switch self {
        case .loveLanguages: "Love Languages"
        case .spicy: "Spicy"
        default: rawValue.capitalized
        }
    }

    public var emoji: String {
        switch self {
        case .funny: "😂"; case .deep: "🌊"; case .romantic: "🌹"; case .spicy: "🔥"
        case .future: "🔮"; case .dreams: "✨"; case .money: "💰"; case .travel: "✈️"
        case .kids: "👶"; case .communication: "💬"; case .conflict: "🤝"
        case .goals: "🎯"; case .loveLanguages: "💗"; case .family: "🏡"
        case .habits: "🔁"; case .career: "💼"; case .values: "🧭"
        }
    }

    /// Spicy is opt-in per relationship.
    public var isOptIn: Bool { self == .spicy }
}

public struct DailyQuestion: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var text: String
    public var category: QuestionCategory
    /// yyyy-MM-dd in the couple's shared timezone — the "question day" key.
    public var dayKey: String
    public var isPremium: Bool

    public init(id: String = UUID().uuidString, text: String,
                category: QuestionCategory, dayKey: String, isPremium: Bool = false) {
        self.id = id
        self.text = text
        self.category = category
        self.dayKey = dayKey
        self.isPremium = isPremium
    }
}

/// Answers stay sealed until BOTH partners answer — then unlock simultaneously.
public struct QuestionAnswer: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var questionID: String
    public var authorID: UserID
    public var text: String
    public var answeredAt: Date

    public init(id: String = UUID().uuidString, questionID: String,
                authorID: UserID, text: String, answeredAt: Date = .now) {
        self.id = id
        self.questionID = questionID
        self.authorID = authorID
        self.text = text
        self.answeredAt = answeredAt
    }
}

public struct DailyQuestionState: Sendable {
    public var question: DailyQuestion
    public var myAnswer: QuestionAnswer?
    public var partnerHasAnswered: Bool
    /// Only populated once both sides have answered.
    public var revealedAnswers: [QuestionAnswer]

    public init(question: DailyQuestion, myAnswer: QuestionAnswer? = nil,
                partnerHasAnswered: Bool = false, revealedAnswers: [QuestionAnswer] = []) {
        self.question = question
        self.myAnswer = myAnswer
        self.partnerHasAnswered = partnerHasAnswered
        self.revealedAnswers = revealedAnswers
    }

    public var isRevealed: Bool { !revealedAnswers.isEmpty }
}

// MARK: - Journal

public enum JournalMediaKind: String, Codable, Sendable {
    case photo, video, voice, livePhoto = "live_photo"
}

public struct JournalMedia: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: JournalMediaKind
    public var remoteURL: URL?
    public var durationSeconds: Double?

    public init(id: String = UUID().uuidString, kind: JournalMediaKind,
                remoteURL: URL? = nil, durationSeconds: Double? = nil) {
        self.id = id
        self.kind = kind
        self.remoteURL = remoteURL
        self.durationSeconds = durationSeconds
    }
}

public struct JournalEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var authorID: UserID
    public var title: String
    public var body: String
    public var media: [JournalMedia]
    public var locationName: String?
    public var latitude: Double?
    public var longitude: Double?
    public var reactions: [String: String]   // userID -> emoji
    public var commentCount: Int
    public var createdAt: Date
    public var isPrivate: Bool

    public init(id: String = UUID().uuidString, authorID: UserID, title: String,
                body: String, media: [JournalMedia] = [], locationName: String? = nil,
                latitude: Double? = nil, longitude: Double? = nil,
                reactions: [String: String] = [:], commentCount: Int = 0,
                createdAt: Date = .now, isPrivate: Bool = false) {
        self.id = id
        self.authorID = authorID
        self.title = title
        self.body = body
        self.media = media
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.reactions = reactions
        self.commentCount = commentCount
        self.createdAt = createdAt
        self.isPrivate = isPrivate
    }
}

// MARK: - Mood

public enum MoodKind: String, Codable, CaseIterable, Sendable {
    case loved, happy, calm, excited, tired, stressed, sad, missingYou = "missing_you"

    public var emoji: String {
        switch self {
        case .loved: "🥰"; case .happy: "😊"; case .calm: "😌"; case .excited: "🤩"
        case .tired: "🥱"; case .stressed: "😮‍💨"; case .sad: "😔"; case .missingYou: "🥺"
        }
    }

    public var title: String {
        switch self {
        case .missingYou: "Missing you"
        default: rawValue.capitalized
        }
    }
}

public struct MoodEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var authorID: UserID
    public var mood: MoodKind
    public var energy: Int      // 1–5
    public var stress: Int      // 1–5
    public var loveMeter: Int   // 1–5
    public var note: String?
    public var loggedAt: Date

    public init(id: String = UUID().uuidString, authorID: UserID, mood: MoodKind,
                energy: Int = 3, stress: Int = 2, loveMeter: Int = 4,
                note: String? = nil, loggedAt: Date = .now) {
        self.id = id
        self.authorID = authorID
        self.mood = mood
        self.energy = energy
        self.stress = stress
        self.loveMeter = loveMeter
        self.note = note
        self.loggedAt = loggedAt
    }
}

// MARK: - Calendar / Special Dates

public enum SpecialDateKind: String, Codable, CaseIterable, Sendable {
    case anniversary, birthday, trip, date, reminder, custom

    public var symbol: String {
        switch self {
        case .anniversary: "heart.circle.fill"
        case .birthday: "birthday.cake.fill"
        case .trip: "airplane"
        case .date: "sparkles"
        case .reminder: "bell.fill"
        case .custom: "star.fill"
        }
    }
}

public struct SpecialDate: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var kind: SpecialDateKind
    public var date: Date
    public var repeatsYearly: Bool
    public var createdBy: UserID

    public init(id: String = UUID().uuidString, title: String, kind: SpecialDateKind,
                date: Date, repeatsYearly: Bool = false, createdBy: UserID) {
        self.id = id
        self.title = title
        self.kind = kind
        self.date = date
        self.repeatsYearly = repeatsYearly
        self.createdBy = createdBy
    }

    /// Days until the next occurrence (handles yearly repeats).
    public var daysUntil: Int {
        let cal = Calendar.current
        var target = date
        if repeatsYearly {
            var comps = cal.dateComponents([.month, .day], from: date)
            comps.hour = 0
            target = cal.nextDate(after: cal.startOfDay(for: .now).addingTimeInterval(-1),
                                  matching: comps, matchingPolicy: .nextTime) ?? date
        }
        return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: .now),
                                         to: cal.startOfDay(for: target)).day ?? 0)
    }
}

// MARK: - Bucket List

public enum BucketCategory: String, Codable, CaseIterable, Sendable {
    case restaurants, countries, movies, dreams, dateIdeas = "date_ideas"

    public var title: String { self == .dateIdeas ? "Date Ideas" : rawValue.capitalized }
    public var emoji: String {
        switch self {
        case .restaurants: "🍽️"; case .countries: "🌍"; case .movies: "🎬"
        case .dreams: "💫"; case .dateIdeas: "🌆"
        }
    }
}

public struct BucketListItem: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var category: BucketCategory
    public var isCompleted: Bool
    public var completedAt: Date?
    public var linkedJournalEntryID: String?
    public var createdBy: UserID

    public init(id: String = UUID().uuidString, title: String, category: BucketCategory,
                isCompleted: Bool = false, completedAt: Date? = nil,
                linkedJournalEntryID: String? = nil, createdBy: UserID) {
        self.id = id
        self.title = title
        self.category = category
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.linkedJournalEntryID = linkedJournalEntryID
        self.createdBy = createdBy
    }
}

// MARK: - Milestones (Relationship Timeline)

public struct Milestone: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var emoji: String
    public var date: Date
    public var note: String?

    public init(id: String = UUID().uuidString, title: String, emoji: String,
                date: Date, note: String? = nil) {
        self.id = id
        self.title = title
        self.emoji = emoji
        self.date = date
        self.note = note
    }
}

// MARK: - Shared Notes

public struct SharedNote: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var items: [ChecklistItem]
    public var body: String
    public var isPinned: Bool
    public var isPrivate: Bool
    public var updatedAt: Date
    public var updatedBy: UserID

    public init(id: String = UUID().uuidString, title: String,
                items: [ChecklistItem] = [], body: String = "",
                isPinned: Bool = false, isPrivate: Bool = false,
                updatedAt: Date = .now, updatedBy: UserID) {
        self.id = id
        self.title = title
        self.items = items
        self.body = body
        self.isPinned = isPinned
        self.isPrivate = isPrivate
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }
}

public struct ChecklistItem: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var text: String
    public var isDone: Bool

    public init(id: String = UUID().uuidString, text: String, isDone: Bool = false) {
        self.id = id
        self.text = text
        self.isDone = isDone
    }
}
