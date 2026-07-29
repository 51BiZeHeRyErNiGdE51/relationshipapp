import Foundation

// MARK: - Analytics taxonomy
//
// One typed event enum → fanned out to GA4 (Firebase Analytics) and,
// when configured, the Meta SDK adapter. Names are snake_case GA4 style.

public enum AnalyticsEvent: Sendable {
    // Funnel
    case appOpened
    case onboardingStarted
    case signInCompleted(provider: String)
    case invitationCreated
    case invitationRedeemed
    case relationshipActivated

    // Engagement
    case questionViewed(category: String)
    case questionAnswered(category: String)
    case answersRevealed
    case journalEntryCreated(mediaCount: Int)
    case moodLogged(mood: String)
    case missYouSent(source: String)      // "app" | "widget"
    case gamePlayed(game: String)
    case companionEvolved(kind: String, stage: Int)
    case streakExtended(days: Int)

    // Widgets — the primary engagement surface
    case widgetGalleryViewed
    case widgetInteraction(widget: String, action: String)

    // Monetization
    case paywallImpression(source: String, variant: String)
    case paywallOfferSelected(offerID: String)
    case trialStarted(offerID: String)
    case purchaseCompleted(offerID: String)
    case purchaseRestored
    case premiumInherited                  // partner joined a premium relationship

    public var name: String {
        switch self {
        case .appOpened: "app_opened"
        case .onboardingStarted: "onboarding_started"
        case .signInCompleted: "sign_in_completed"
        case .invitationCreated: "invitation_created"
        case .invitationRedeemed: "invitation_redeemed"
        case .relationshipActivated: "relationship_activated"
        case .questionViewed: "question_viewed"
        case .questionAnswered: "question_answered"
        case .answersRevealed: "answers_revealed"
        case .journalEntryCreated: "journal_entry_created"
        case .moodLogged: "mood_logged"
        case .missYouSent: "miss_you_sent"
        case .gamePlayed: "game_played"
        case .companionEvolved: "companion_evolved"
        case .streakExtended: "streak_extended"
        case .widgetGalleryViewed: "widget_gallery_viewed"
        case .widgetInteraction: "widget_interaction"
        case .paywallImpression: "paywall_impression"
        case .paywallOfferSelected: "paywall_offer_selected"
        case .trialStarted: "trial_started"
        case .purchaseCompleted: "purchase_completed"
        case .purchaseRestored: "purchase_restored"
        case .premiumInherited: "premium_inherited"
        }
    }

    public var parameters: [String: String] {
        switch self {
        case .signInCompleted(let provider): ["provider": provider]
        case .questionViewed(let c), .questionAnswered(let c): ["category": c]
        case .journalEntryCreated(let n): ["media_count": String(n)]
        case .moodLogged(let mood): ["mood": mood]
        case .missYouSent(let source): ["source": source]
        case .gamePlayed(let game): ["game": game]
        case .companionEvolved(let kind, let stage): ["kind": kind, "stage": String(stage)]
        case .streakExtended(let days): ["days": String(days)]
        case .widgetInteraction(let widget, let action): ["widget": widget, "action": action]
        case .paywallImpression(let source, let variant): ["source": source, "variant": variant]
        case .paywallOfferSelected(let id), .trialStarted(let id), .purchaseCompleted(let id): ["offer_id": id]
        default: [:]
        }
    }
}

/// Fans a single event out to every configured sink (GA4, Meta, console).
public struct CompositeAnalytics: AnalyticsClient {
    private let sinks: [AnalyticsClient]
    public init(sinks: [AnalyticsClient]) { self.sinks = sinks }

    public func track(_ event: AnalyticsEvent) {
        for sink in sinks { sink.track(event) }
    }

    public func setUserProperty(_ value: String?, forName name: String) {
        for sink in sinks { sink.setUserProperty(value, forName: name) }
    }
}

/// Debug sink — prints events so engagement flows are inspectable in demo mode.
public struct ConsoleAnalytics: AnalyticsClient {
    public init() {}
    public func track(_ event: AnalyticsEvent) {
        #if DEBUG
        print("📊 \(event.name) \(event.parameters)")
        #endif
    }
    public func setUserProperty(_ value: String?, forName name: String) {
        #if DEBUG
        print("📊 user_property \(name)=\(value ?? "nil")")
        #endif
    }
}

/// Placeholder adapter for the Meta (Facebook) SDK. Wire `FBSDKCoreKit`'s
/// `AppEvents.shared.logEvent` here once the app has a Meta App ID; keep
/// purchase/subscription events mirrored for Instagram ad attribution.
public struct MetaAnalyticsAdapter: AnalyticsClient {
    public init() {}
    public func track(_ event: AnalyticsEvent) { /* AppEvents.shared.logEvent(...) */ }
    public func setUserProperty(_ value: String?, forName name: String) {}
}
