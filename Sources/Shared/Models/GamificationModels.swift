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

// MARK: - Couple Games (distance-friendly, 2-choice)

public enum CoupleGame: String, Codable, CaseIterable, Identifiable, Sendable {
    case whosMoreLikely = "whos_more_likely"
    case wouldYouRather = "would_you_rather"
    case neverHaveIEver = "never_have_i_ever"
    case thisOrThat = "this_or_that"
    case yesOrNo = "yes_or_no"
    case doOrDont = "do_or_dont"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .whosMoreLikely: "Who's More Likely"
        case .wouldYouRather: "Would You Rather"
        case .neverHaveIEver: "Never Have I Ever"
        case .thisOrThat: "This or That"
        case .yesOrNo: "Yes or No"
        case .doOrDont: "Do or Don't"
        }
    }

    public var subtitle: String {
        switch self {
        case .whosMoreLikely: "Pick you or them — then compare"
        case .wouldYouRather: "Two options. One pick. No wrong answer."
        case .neverHaveIEver: "Have you… or haven't you?"
        case .thisOrThat: "Quick preferences, side by side"
        case .yesOrNo: "Big questions, tiny answers"
        case .doOrDont: "Would you actually do it?"
        }
    }

    public var symbol: String {
        switch self {
        case .whosMoreLikely: "person.2.fill"
        case .wouldYouRather: "arrow.left.arrow.right"
        case .neverHaveIEver: "hand.raised.fill"
        case .thisOrThat: "rectangle.split.2x1.fill"
        case .yesOrNo: "checkmark.circle.fill"
        case .doOrDont: "figure.walk"
        }
    }

    public var isPremium: Bool {
        switch self {
        case .whosMoreLikely, .wouldYouRather, .thisOrThat: false
        default: true
        }
    }
}

/// A single prompt with exactly two answers. `choiceA` / `choiceB` are nil
/// for "Who's More Likely" — the UI fills in the couple's real names.
public struct GamePrompt: Identifiable, Hashable, Sendable {
    public var id: String
    public var text: String
    public var choiceA: String?
    public var choiceB: String?

    public init(id: String, text: String, choiceA: String? = nil, choiceB: String? = nil) {
        self.id = id
        self.text = text
        self.choiceA = choiceA
        self.choiceB = choiceB
    }
}

public struct GameAnswer: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var gameID: String
    public var promptID: String
    public var authorID: UserID
    /// `"a"` or `"b"`
    public var choice: String
    /// Display label at answer time (name or option text).
    public var choiceLabel: String
    public var answeredAt: Date

    public init(id: String = UUID().uuidString, gameID: String, promptID: String,
                authorID: UserID, choice: String, choiceLabel: String,
                answeredAt: Date = .now) {
        self.id = id
        self.gameID = gameID
        self.promptID = promptID
        self.authorID = authorID
        self.choice = choice
        self.choiceLabel = choiceLabel
        self.answeredAt = answeredAt
    }
}

public struct GamePromptState: Identifiable, Sendable {
    public var prompt: GamePrompt
    public var myAnswer: GameAnswer?
    public var partnerHasAnswered: Bool
    public var revealedAnswers: [GameAnswer]

    public var id: String { prompt.id }
    public var isRevealed: Bool { revealedAnswers.count >= 2 }
    public var isWaiting: Bool { myAnswer != nil && !isRevealed }

    public init(prompt: GamePrompt, myAnswer: GameAnswer? = nil,
                partnerHasAnswered: Bool = false, revealedAnswers: [GameAnswer] = []) {
        self.prompt = prompt
        self.myAnswer = myAnswer
        self.partnerHasAnswered = partnerHasAnswered
        self.revealedAnswers = revealedAnswers
    }

    public var matched: Bool? {
        guard revealedAnswers.count == 2 else { return nil }
        return revealedAnswers[0].choice == revealedAnswers[1].choice
    }
}

/// Static prompt decks — same IDs for both partners so they play the same cards.
/// Every prompt has exactly two selectable answers (or names for Who's More Likely).
public enum GameBank {
    public static func prompts(for game: CoupleGame) -> [GamePrompt] {
        switch game {
        case .whosMoreLikely: whoMoreLikely
        case .wouldYouRather: wouldYouRather
        case .neverHaveIEver: neverHaveIEver
        case .thisOrThat: thisOrThat
        case .yesOrNo: yesOrNo
        case .doOrDont: doOrDont
        }
    }

    // MARK: Helpers

    private static func named(_ texts: [String], prefix: String) -> [GamePrompt] {
        texts.enumerated().map { i, text in
            GamePrompt(id: "\(prefix)_\(i + 1)", text: text)
        }
    }

    private static func pair(_ id: String, _ a: String, _ b: String,
                             prompt: String = "Would you rather…") -> GamePrompt {
        GamePrompt(id: id, text: prompt, choiceA: a, choiceB: b)
    }

    private static func tot(_ id: String, _ a: String, _ b: String) -> GamePrompt {
        GamePrompt(id: id, text: "This or that?", choiceA: a, choiceB: b)
    }

    private static func yn(_ id: String, _ text: String) -> GamePrompt {
        GamePrompt(id: id, text: text, choiceA: "Yes", choiceB: "No")
    }

    private static func dod(_ id: String, _ text: String) -> GamePrompt {
        GamePrompt(id: id, text: text, choiceA: "Do it", choiceB: "Don't")
    }

    private static func nhie(_ id: String, _ text: String) -> GamePrompt {
        GamePrompt(id: id, text: text, choiceA: "I have", choiceB: "I haven't")
    }

    // MARK: Who's More Likely (~70) — choices filled with couple names at runtime

    private static var whoMoreLikely: [GamePrompt] {
        named([
            "Who's more likely to cry at a movie?",
            "Who's more likely to forget an anniversary?",
            "Who's more likely to adopt a pet on impulse?",
            "Who's more likely to get lost with GPS on?",
            "Who's more likely to spend the whole vacation budget in one day?",
            "Who's more likely to fall asleep first?",
            "Who's more likely to start a kitchen dance party?",
            "Who's more likely to send a miss-you first?",
            "Who's more likely to win a pillow fight?",
            "Who's more likely to order dessert?",
            "Who's more likely to plan the perfect date?",
            "Who's more likely to become famous?",
            "Who's more likely to burn dinner?",
            "Who's more likely to hog the blankets?",
            "Who's more likely to start a fight over nothing?",
            "Who's more likely to apologize first?",
            "Who's more likely to buy something unnecessary online?",
            "Who's more likely to cancel plans to stay in?",
            "Who's more likely to talk to strangers?",
            "Who's more likely to get sunburned first?",
            "Who's more likely to sing in the car?",
            "Who's more likely to take too many photos?",
            "Who's more likely to lose their keys?",
            "Who's more likely to overpack for a weekend?",
            "Who's more likely to underpack for a week?",
            "Who's more likely to eat ice cream for breakfast?",
            "Who's more likely to stay up doomscrolling?",
            "Who's more likely to fall asleep on a video call?",
            "Who's more likely to flirt in public (with each other)?",
            "Who's more likely to get us a table upgrade?",
            "Who's more likely to cry at a wedding?",
            "Who's more likely to make a scene over bad service?",
            "Who's more likely to forgive quickly?",
            "Who's more likely to hold a tiny grudge?",
            "Who's more likely to invent a silly nickname?",
            "Who's more likely to remember song lyrics?",
            "Who's more likely to suggest \"one more episode\"?",
            "Who's more likely to suggest \"just five more minutes\" in bed?",
            "Who's more likely to leave wet towels on the bed?",
            "Who's more likely to reorganize the fridge?",
            "Who's more likely to become a plant parent?",
            "Who's more likely to binge a whole season alone?",
            "Who's more likely to spill a drink?",
            "Who's more likely to win trivia night?",
            "Who's more likely to get us lost on a hike?",
            "Who's more likely to book a spontaneous flight?",
            "Who's more likely to say yes to karaoke?",
            "Who's more likely to need coffee before speaking?",
            "Who's more likely to send a voice note instead of typing?",
            "Who's more likely to double-text?",
            "Who's more likely to leave a party early?",
            "Who's more likely to stay until the lights come on?",
            "Who's more likely to cry from laughing?",
            "Who's more likely to pick the restaurant?",
            "Who's more likely to change the restaurant last minute?",
            "Who's more likely to finish the other's sentence?",
            "Who's more likely to steal fries off the plate?",
            "Who's more likely to get emotional during a toast?",
            "Who's more likely to become obsessed with a new hobby?",
            "Who's more likely to convince the other to try something scary?",
            "Who's more likely to fake being fine?",
            "Who's more likely to plan a surprise that goes sideways?",
            "Who's more likely to become the group chat chaos?",
            "Who's more likely to fall asleep mid-conversation?",
            "Who's more likely to bring home a stray animal?",
            "Who's more likely to wear the other person's hoodie?",
            "Who's more likely to start decorating for the holidays too early?",
            "Who's more likely to forget why they walked into a room?",
            "Who's more likely to write a love note on a sticky?",
            "Who's more likely to turn a chore into a competition?",
            "Who's more likely to say \"I told you so\"?",
            "Who's more likely to suggest matching outfits?",
            "Who's more likely to cry during a proposal video?",
            "Who's more likely to become the couple that hosts every hangout?",
        ], prefix: "wml")
    }

    // MARK: Would You Rather (~70)

    private static var wouldYouRather: [GamePrompt] {
        [
            pair("wyr_1", "Relive our first date", "Fast-forward to our 10th anniversary"),
            pair("wyr_2", "Always know what I'm thinking", "Me always know what you're thinking"),
            pair("wyr_3", "Tiny house by the sea", "Penthouse downtown"),
            pair("wyr_4", "Give up coffee together", "Give up takeout together"),
            pair("wyr_5", "A surprise weekend trip", "A fully planned vacation"),
            pair("wyr_6", "Cook together every night", "Never cook and always eat out"),
            pair("wyr_7", "One big gift a year", "Lots of tiny gifts all year"),
            pair("wyr_8", "Live abroad for a year", "Stay put and travel often"),
            pair("wyr_9", "Talk through every fight immediately", "Cool off first, then talk"),
            pair("wyr_10", "A quiet night in", "A big night out"),
            pair("wyr_11", "Always share a bed on trips", "Separate beds when we need rest"),
            pair("wyr_12", "Never argue again", "Argue but always resolve stronger"),
            pair("wyr_13", "Be rich with little free time", "Have time but a tighter budget"),
            pair("wyr_14", "Our own wedding redo", "Renew vows on a mountain"),
            pair("wyr_15", "Only text for a month", "Only call for a month"),
            pair("wyr_16", "A cabin with no Wi‑Fi", "A city hotel with everything"),
            pair("wyr_17", "Always be early together", "Always fashionably late together"),
            pair("wyr_18", "Share one playlist forever", "Never share music taste"),
            pair("wyr_19", "Date night every week", "A big monthly adventure"),
            pair("wyr_20", "Morning cuddles", "Goodnight talks"),
            pair("wyr_21", "Tell each other everything", "Keep a few private thoughts"),
            pair("wyr_22", "Match tattoos", "Match jewelry"),
            pair("wyr_23", "Live near family", "Live wherever we want"),
            pair("wyr_24", "Road trip across the country", "Fly somewhere far and stay put"),
            pair("wyr_25", "Always cook my favorite", "Always cook yours"),
            pair("wyr_26", "Win the lottery and stay quiet", "Win and celebrate loudly"),
            pair("wyr_27", "Be known as the funny couple", "Be known as the romantic couple"),
            pair("wyr_28", "Never miss a sunrise together", "Never miss a sunset together"),
            pair("wyr_29", "One perfect week a year", "Small joy every day"),
            pair("wyr_30", "Always pick the movie", "Always pick the restaurant"),
            pair("wyr_31", "Dance in public", "Sing in public"),
            pair("wyr_32", "A pet that cuddles nonstop", "A pet that's independent"),
            pair("wyr_33", "Write love letters", "Leave voice notes"),
            pair("wyr_34", "Stay best friends first", "Stay lovers first"),
            pair("wyr_35", "Cancel a trip for comfort", "Push through for the memory"),
            pair("wyr_36", "Always hold hands in public", "Keep affection more private"),
            pair("wyr_37", "Share a bank account fully", "Keep money mostly separate"),
            pair("wyr_38", "Kids someday", "Just us forever"),
            pair("wyr_39", "Big wedding", "Tiny elopement"),
            pair("wyr_40", "Always vacation warm", "Always vacation cold"),
            pair("wyr_41", "Never delete old photos", "Keep only the best ones"),
            pair("wyr_42", "Surprise gifts", "Asked-for gifts"),
            pair("wyr_43", "Same bedtime forever", "Different sleep schedules, no guilt"),
            pair("wyr_44", "Be stuck in an elevator together", "Be stuck in a cabin in a storm"),
            pair("wyr_45", "Always order dessert", "Always skip dessert"),
            pair("wyr_46", "Re-watch our comfort show", "Try something brand new"),
            pair("wyr_47", "A year of no social media", "A year of posting everything"),
            pair("wyr_48", "Learn an instrument together", "Train for a race together"),
            pair("wyr_49", "Live in a tiny apartment we love", "A big house that feels empty"),
            pair("wyr_50", "Always be honest even if it hurts", "Be kind even if it softens the truth"),
            pair("wyr_51", "Meet as kids", "Meet exactly when we did"),
            pair("wyr_52", "A chef for a month", "A cleaner for a month"),
            pair("wyr_53", "Never fight about chores", "Never fight about money"),
            pair("wyr_54", "Go viral as a couple", "Stay completely offline"),
            pair("wyr_55", "Always pack light", "Always overpack \"just in case\""),
            pair("wyr_56", "Breakfast in bed", "Picnic under the stars"),
            pair("wyr_57", "A surprise party for me", "A surprise party for you"),
            pair("wyr_58", "Slow dance in the kitchen", "Dance party in the living room"),
            pair("wyr_59", "Always take the scenic route", "Always take the fastest route"),
            pair("wyr_60", "One incredible night abroad", "A cozy week at home"),
            pair("wyr_61", "Share every password", "Keep devices private"),
            pair("wyr_62", "Always say yes to adventure", "Always protect our rest"),
            pair("wyr_63", "Matching pajamas", "Matching travel mugs"),
            pair("wyr_64", "A rooftop dinner", "A backyard picnic"),
            pair("wyr_65", "Tell our kids how we met (truthfully)", "Tell a slightly better story"),
            pair("wyr_66", "Never watch shows alone", "Watch alone, then recommend"),
            pair("wyr_67", "Fight for the last slice", "Always leave it for the other"),
            pair("wyr_68", "A forever home", "A life of moving cities"),
            pair("wyr_69", "Be early grandparents someday", "Be late grandparents someday"),
            pair("wyr_70", "Whisper secrets in public", "Shout love across a room"),
        ]
    }

    // MARK: Never Have I Ever (~60)

    private static var neverHaveIEver: [GamePrompt] {
        [
            nhie("nhie_1", "Never have I ever pretended to like a gift from you."),
            nhie("nhie_2", "Never have I ever read your texts over your shoulder."),
            nhie("nhie_3", "Never have I ever let you win an argument on purpose."),
            nhie("nhie_4", "Never have I ever stalked your ex online."),
            nhie("nhie_5", "Never have I ever said \"I'm fine\" when I wasn't."),
            nhie("nhie_6", "Never have I ever deleted a text before sending it to you."),
            nhie("nhie_7", "Never have I ever checked if you were online."),
            nhie("nhie_8", "Never have I ever practiced what I'd say before a hard talk."),
            nhie("nhie_9", "Never have I ever snooped in your bag or pockets."),
            nhie("nhie_10", "Never have I ever lied about how late I'd be."),
            nhie("nhie_11", "Never have I ever laughed at you during a serious moment."),
            nhie("nhie_12", "Never have I ever stolen the last bite off your plate."),
            nhie("nhie_13", "Never have I ever pretended to be asleep."),
            nhie("nhie_14", "Never have I ever re-gifted something you gave me."),
            nhie("nhie_15", "Never have I ever compared us to another couple."),
            nhie("nhie_16", "Never have I ever kept a purchase secret from you."),
            nhie("nhie_17", "Never have I ever worn your clothes without asking."),
            nhie("nhie_18", "Never have I ever flipped your pillow to the cold side for myself."),
            nhie("nhie_19", "Never have I ever muted you by accident and panicked."),
            nhie("nhie_20", "Never have I ever Googled relationship advice about us."),
            nhie("nhie_21", "Never have I ever cried after a fight and not told you."),
            nhie("nhie_22", "Never have I ever planned a surprise that completely failed."),
            nhie("nhie_23", "Never have I ever blamed traffic when I left late."),
            nhie("nhie_24", "Never have I ever screenshot a chat just in case."),
            nhie("nhie_25", "Never have I ever pretended to like your cooking."),
            nhie("nhie_26", "Never have I ever fallen asleep while you were talking."),
            nhie("nhie_27", "Never have I ever hidden snacks from you."),
            nhie("nhie_28", "Never have I ever stalked our own couple photos."),
            nhie("nhie_29", "Never have I ever told a friend something private about us."),
            nhie("nhie_30", "Never have I ever rewritten a text five times."),
            nhie("nhie_31", "Never have I ever pretended I didn't see your message."),
            nhie("nhie_32", "Never have I ever checked your location out of worry."),
            nhie("nhie_33", "Never have I ever said \"whatever\" to end a fight."),
            nhie("nhie_34", "Never have I ever bought something just because you liked it."),
            nhie("nhie_35", "Never have I ever practiced a speech in the mirror for you."),
            nhie("nhie_36", "Never have I ever cried happy tears because of you."),
            nhie("nhie_37", "Never have I ever watched your favorite show without you."),
            nhie("nhie_38", "Never have I ever peed with the door open while you were home."),
            nhie("nhie_39", "Never have I ever left dishes \"to soak\" for days."),
            nhie("nhie_40", "Never have I ever used your toothbrush (oops)."),
            nhie("nhie_41", "Never have I ever liked an old photo of yours on purpose."),
            nhie("nhie_42", "Never have I ever made a playlist secretly about us."),
            nhie("nhie_43", "Never have I ever been jealous of your friends."),
            nhie("nhie_44", "Never have I ever pretended to know a celebrity you love."),
            nhie("nhie_45", "Never have I ever saved a cute text from you forever."),
            nhie("nhie_46", "Never have I ever almost said \"I love you\" too early."),
            nhie("nhie_47", "Never have I ever practiced how to introduce you to people."),
            nhie("nhie_48", "Never have I ever blamed the dog / cat for something I did."),
            nhie("nhie_49", "Never have I ever worn matching energy on purpose."),
            nhie("nhie_50", "Never have I ever counted how many days since we met."),
            nhie("nhie_51", "Never have I ever looked up flights we can't afford yet."),
            nhie("nhie_52", "Never have I ever written your name when I was bored."),
            nhie("nhie_53", "Never have I ever laughed so hard with you I snorted."),
            nhie("nhie_54", "Never have I ever ghosted a group chat to stay with you."),
            nhie("nhie_55", "Never have I ever kept the better half of the duvet."),
            nhie("nhie_56", "Never have I ever pretended I wasn't hungry so you could eat."),
            nhie("nhie_57", "Never have I ever changed outfits three times before seeing you."),
            nhie("nhie_58", "Never have I ever hoped you'd text first."),
            nhie("nhie_59", "Never have I ever told a white lie to protect your feelings."),
            nhie("nhie_60", "Never have I ever imagined our future house in detail."),
        ]
    }

    // MARK: This or That (~70)

    private static var thisOrThat: [GamePrompt] {
        [
            tot("tot_1", "Beach", "Mountains"),
            tot("tot_2", "Sweet", "Salty"),
            tot("tot_3", "Morning person", "Night owl"),
            tot("tot_4", "Texts", "Calls"),
            tot("tot_5", "Cats", "Dogs"),
            tot("tot_6", "Save", "Spend"),
            tot("tot_7", "Summer", "Winter"),
            tot("tot_8", "Movies at home", "Movies in theater"),
            tot("tot_9", "Spontaneous", "Planned"),
            tot("tot_10", "Big spoon", "Little spoon"),
            tot("tot_11", "Coffee", "Tea"),
            tot("tot_12", "Windows open", "AC blasting"),
            tot("tot_13", "City lights", "Starry sky"),
            tot("tot_14", "Board games", "Video games"),
            tot("tot_15", "Books", "Podcasts"),
            tot("tot_16", "Cook in", "Order in"),
            tot("tot_17", "Early flight", "Late flight"),
            tot("tot_18", "Window seat", "Aisle seat"),
            tot("tot_19", "Hot weather", "Cold weather"),
            tot("tot_20", "Rainy day in", "Sunny day out"),
            tot("tot_21", "Comedy", "Thriller"),
            tot("tot_22", "Romance movie", "Action movie"),
            tot("tot_23", "Pizza", "Burgers"),
            tot("tot_24", "Sushi", "Tacos"),
            tot("tot_25", "Chocolate", "Vanilla"),
            tot("tot_26", "Wine", "Cocktails"),
            tot("tot_27", "Soft music", "Loud music"),
            tot("tot_28", "Concert", "Museum"),
            tot("tot_29", "Hiking", "Brunch"),
            tot("tot_30", "Road trip", "Train trip"),
            tot("tot_31", "Camping", "Hotel"),
            tot("tot_32", "Minimalist home", "Cozy clutter"),
            tot("tot_33", "Clean as you go", "Clean once a week"),
            tot("tot_34", "Shared calendar", "Just text plans"),
            tot("tot_35", "Voice notes", "Long texts"),
            tot("tot_36", "Public affection", "Private affection"),
            tot("tot_37", "Matching outfits", "Completely different styles"),
            tot("tot_38", "Selfies together", "Candid photos"),
            tot("tot_39", "Post the date", "Keep it offline"),
            tot("tot_40", "Surprise visits", "Scheduled hangouts"),
            tot("tot_41", "Deep talks", "Silly talks"),
            tot("tot_42", "Problem-solve together", "Vent first, solve later"),
            tot("tot_43", "Apology gift", "Apology conversation"),
            tot("tot_44", "Quality time", "Acts of service"),
            tot("tot_45", "Words of affirmation", "Physical touch"),
            tot("tot_46", "Big anniversary", "Quiet anniversary"),
            tot("tot_47", "New Year's party", "New Year's couch"),
            tot("tot_48", "Halloween costumes", "Skip costumes"),
            tot("tot_49", "Christmas morning chaos", "Christmas calm"),
            tot("tot_50", "Host friends", "Be the guests"),
            tot("tot_51", "Group hangouts", "Just the two of us"),
            tot("tot_52", "Long walk", "Long drive"),
            tot("tot_53", "Sunrise date", "Midnight snack date"),
            tot("tot_54", "Farmers market", "Mall day"),
            tot("tot_55", "DIY gifts", "Store-bought gifts"),
            tot("tot_56", "Handwritten notes", "Cute memes"),
            tot("tot_57", "Slow mornings", "Packed mornings"),
            tot("tot_58", "Same shower playlist", "Silence in the shower"),
            tot("tot_59", "One TV in the house", "Screens in every room"),
            tot("tot_60", "Always make the bed", "Never make the bed"),
            tot("tot_61", "Leftovers for lunch", "Fresh lunch every day"),
            tot("tot_62", "Plant parents", "Pet parents"),
            tot("tot_63", "Candlelit dinner", "Picnic blanket"),
            tot("tot_64", "Slow dance", "Jump around dance"),
            tot("tot_65", "Truth or dare: truth", "Truth or dare: dare"),
            tot("tot_66", "Bucket list travel", "Return to favorite spots"),
            tot("tot_67", "Live downtown", "Live in the suburbs"),
            tot("tot_68", "Open floor plan", "Cozy separate rooms"),
            tot("tot_69", "Always say good morning", "Always say good night"),
            tot("tot_70", "Grow old loudly", "Grow old quietly"),
        ]
    }

    // MARK: Yes or No (~60)

    private static var yesOrNo: [GamePrompt] {
        [
            yn("yn_1", "Should we get matching tattoos someday?"),
            yn("yn_2", "Would you move to another country for us?"),
            yn("yn_3", "Are surprise visits a good idea?"),
            yn("yn_4", "Should phones be banned on date nights?"),
            yn("yn_5", "Do you believe in soulmates?"),
            yn("yn_6", "Would you tell me if my outfit was awful?"),
            yn("yn_7", "Should we have a shared savings goal this year?"),
            yn("yn_8", "Is pineapple on pizza acceptable?"),
            yn("yn_9", "Should we adopt a pet in the next two years?"),
            yn("yn_10", "Would you want a destination wedding?"),
            yn("yn_11", "Is it okay to check each other's phones?"),
            yn("yn_12", "Should we do a weekly check-in talk?"),
            yn("yn_13", "Would you rather stay home on New Year's Eve?"),
            yn("yn_14", "Should we learn to cook one signature dish together?"),
            yn("yn_15", "Is it romantic to plan five years ahead?"),
            yn("yn_16", "Would you do a silent day with me on purpose?"),
            yn("yn_17", "Should we keep a shared photo album forever?"),
            yn("yn_18", "Is jealousy ever useful?"),
            yn("yn_19", "Would you want matching pajamas?"),
            yn("yn_20", "Should we take a social-media break as a couple?"),
            yn("yn_21", "Do you want kids someday?"),
            yn("yn_22", "Should we live with roommates again?"),
            yn("yn_23", "Would you quit a job if it hurt our relationship?"),
            yn("yn_24", "Is it okay to have nights alone on purpose?"),
            yn("yn_25", "Should we always share location with each other?"),
            yn("yn_26", "Would you go camping with no bathroom for three days?"),
            yn("yn_27", "Should we write vows even if we never marry?"),
            yn("yn_28", "Is \"I need space\" allowed without panic?"),
            yn("yn_29", "Would you dance with me in a grocery store?"),
            yn("yn_30", "Should we celebrate monthly anniversaries?"),
            yn("yn_31", "Is it okay to skip family events for us?"),
            yn("yn_32", "Would you want a joint email for couple stuff?"),
            yn("yn_33", "Should we always be honest about money stress?"),
            yn("yn_34", "Would you try couples therapy even if things are good?"),
            yn("yn_35", "Is a \"no phones in bed\" rule worth it?"),
            yn("yn_36", "Would you move for my career?"),
            yn("yn_37", "Should we have a shared password vault?"),
            yn("yn_38", "Is it cute when we argue about nothing?"),
            yn("yn_39", "Would you want a house before a wedding?"),
            yn("yn_40", "Should we always split restaurant bills evenly?"),
            yn("yn_41", "Would you delete an old ex's number today?"),
            yn("yn_42", "Is it okay to cancel plans for mental health?"),
            yn("yn_43", "Would you want matching couple rings someday?"),
            yn("yn_44", "Should we keep some hobbies completely separate?"),
            yn("yn_45", "Would you try a language class with me?"),
            yn("yn_46", "Is brunch a personality?"),
            yn("yn_47", "Would you want to write each other yearly letters?"),
            yn("yn_48", "Should we always ask before posting photos of each other?"),
            yn("yn_49", "Would you rather be bored together than busy apart?"),
            yn("yn_50", "Is it romantic to grocery shop together?"),
            yn("yn_51", "Would you sleep in separate beds during a snoring war?"),
            yn("yn_52", "Should we have a \"no yelling\" rule?"),
            yn("yn_53", "Would you want a second honeymoon every five years?"),
            yn("yn_54", "Is it okay to have a celebrity crush?"),
            yn("yn_55", "Would you rather be late together than early alone?"),
            yn("yn_56", "Should we always celebrate small wins?"),
            yn("yn_57", "Would you move into a tiny home with me?"),
            yn("yn_58", "Is \"us time\" more important than \"me time\"?"),
            yn("yn_59", "Would you want a joint New Year's tradition?"),
            yn("yn_60", "Should we always say goodnight, even when mad?"),
        ]
    }

    // MARK: Do or Don't (~60)

    private static var doOrDont: [GamePrompt] {
        [
            dod("dod_1", "Skydiving together?"),
            dod("dod_2", "A two-week road trip with no plans?"),
            dod("dod_3", "Meet the parents' friends as a couple?"),
            dod("dod_4", "Open a joint bank account?"),
            dod("dod_5", "Write each other love letters every month?"),
            dod("dod_6", "Take a social-media break together for 30 days?"),
            dod("dod_7", "Learn a new language together?"),
            dod("dod_8", "Host a big party for our anniversary?"),
            dod("dod_9", "Get a couple's massage?"),
            dod("dod_10", "Run a 5K together?"),
            dod("dod_11", "Take a pottery class as a date?"),
            dod("dod_12", "Sleep under the stars in the backyard?"),
            dod("dod_13", "Book a last-minute weekend flight?"),
            dod("dod_14", "Try a spicy food challenge together?"),
            dod("dod_15", "Do a full digital detox Saturday?"),
            dod("dod_16", "Paint a room in our place together?"),
            dod("dod_17", "Adopt a plant and try not to kill it?"),
            dod("dod_18", "Write a bucket list of 50 things?"),
            dod("dod_19", "Start a shared journal?"),
            dod("dod_20", "Take dance lessons?"),
            dod("dod_21", "Go to a silent meditation retreat?"),
            dod("dod_22", "Volunteer together one weekend?"),
            dod("dod_23", "Cook a 5-course dinner at home?"),
            dod("dod_24", "Watch sunrise from a rooftop?"),
            dod("dod_25", "Trade phones for an hour (honor system)?"),
            dod("dod_26", "Make a time capsule for five years from now?"),
            dod("dod_27", "Try a week of only homemade meals?"),
            dod("dod_28", "Go thrift shopping for each other's outfits?"),
            dod("dod_29", "Do a photo scavenger hunt date?"),
            dod("dod_30", "Spend a day speaking only compliments?"),
            dod("dod_31", "Plan a surprise for each other on the same day?"),
            dod("dod_32", "Take a ceramics or woodworking class?"),
            dod("dod_33", "Go ice skating even if we're terrible?"),
            dod("dod_34", "Try karaoke in front of strangers?"),
            dod("dod_35", "Book a cabin with no Wi‑Fi?"),
            dod("dod_36", "Make matching playlists for each mood?"),
            dod("dod_37", "Do a 30-day kindness challenge for each other?"),
            dod("dod_38", "Host a game night for friends?"),
            dod("dod_39", "Take a cooking class abroad someday?"),
            dod("dod_40", "Start a small side project together?"),
            dod("dod_41", "Go to a drive-in movie?"),
            dod("dod_42", "Try indoor climbing?"),
            dod("dod_43", "Write each other future letters and seal them?"),
            dod("dod_44", "Do a \"yes day\" where we accept each other's ideas?"),
            dod("dod_45", "Spend a weekend without making plans?"),
            dod("dod_46", "Learn a magic trick to impress each other?"),
            dod("dod_47", "Build a blanket fort like kids?"),
            dod("dod_48", "Take a pottery date and keep the ugly mug?"),
            dod("dod_49", "Go stargazing with a thermos of something warm?"),
            dod("dod_50", "Try a new cuisine neither of us knows?"),
            dod("dod_51", "Make a scrapbook of our first year?"),
            dod("dod_52", "Do a weekly \"state of us\" walk?"),
            dod("dod_53", "Try couples yoga (and laugh through it)?"),
            dod("dod_54", "Take a ferry somewhere just because?"),
            dod("dod_55", "Leave sticky-note love notes around the house for a week?"),
            dod("dod_56", "Plan a \"poor date\" under $20?"),
            dod("dod_57", "Go to a farmer's market and cook whatever we buy?"),
            dod("dod_58", "Learn CPR together?"),
            dod("dod_59", "Pick a charity and donate monthly as a couple?"),
            dod("dod_60", "Renew a silly \"couple contract\" every year?"),
        ]
    }
}
