import Foundation
#if canImport(ActivityKit)
import ActivityKit

// MARK: - Live Activities
//
// Shared between the app (which starts/updates activities) and the widget
// extension (which renders them on Lock Screen + Dynamic Island).

/// Countdown to a shared moment: date night, trip departure, anniversary.
public struct CountdownActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var targetDate: Date
        public var subtitle: String
        public init(targetDate: Date, subtitle: String) {
            self.targetDate = targetDate
            self.subtitle = subtitle
        }
    }

    public var title: String
    public var kind: String   // "date" | "trip" | "anniversary" | "timer"
    public var partnerInitials: String
    public var myInitials: String

    public init(title: String, kind: String, myInitials: String, partnerInitials: String) {
        self.title = title
        self.kind = kind
        self.myInitials = myInitials
        self.partnerInitials = partnerInitials
    }
}

/// Partner on the way home / distance closing.
public struct PartnerArrivingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var distanceKilometers: Double
        public var etaMinutes: Int
        public init(distanceKilometers: Double, etaMinutes: Int) {
            self.distanceKilometers = distanceKilometers
            self.etaMinutes = etaMinutes
        }
    }

    public var partnerName: String
    public init(partnerName: String) {
        self.partnerName = partnerName
    }
}
#endif
