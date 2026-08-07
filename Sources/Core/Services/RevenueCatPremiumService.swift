import Foundation
import FirebaseFirestore
import RevenueCat

// MARK: - RevenueCat adapter
//
// Premium belongs to the RELATIONSHIP, anchored to the purchaser:
//
//   1. RevenueCat is configured with `appUserID == our platform-independent UserID`,
//      so entitlements follow the person across devices AND platforms (Android later).
//   2. After purchase/renewal the client mirrors the entitlement into
//      `relationships/{id}/premium/state`. In production a RevenueCat webhook →
//      Cloud Function keeps this mirror authoritative (billing retry, grace, refunds).
//   3. Partner resolution: relationship is premium when EITHER member's
//      entitlement is active. If the relationship ends, the mirror dies with it,
//      but the purchaser's entitlement survives and re-mirrors on reconnection.

enum RevenueCatBootstrap {
    /// RevenueCat PUBLIC SDK key — safe to ship in the binary.
    /// Currently the Test Store key (fake purchases, no App Store needed).
    /// Before release: replace with the Apple App Store key ("appl_…") from
    /// RevenueCat → Project Settings → API Keys.
    static let apiKey = ProcessInfo.processInfo.environment["REVENUECAT_API_KEY"]
        ?? "test_NKYaJmNPYQDHQHnmuarVjdgzaKq"
    static let entitlementID = "premium"

    static func configure(appUserID: UserID) {
        guard !apiKey.isEmpty else { return }
        Purchases.logLevel = .warn
        Purchases.configure(with: Configuration.Builder(withAPIKey: apiKey)
            .with(appUserID: appUserID)
            .build())
    }

    static var isConfigured: Bool { Purchases.isConfigured }
}

struct RevenueCatPremiumService: PremiumService {
    private var db: Firestore { Firestore.firestore() }

    func premiumState(relationship: Relationship?, me: UserID) async -> PremiumState {
        // Fake-purchase mode while RevenueCat is not wired: state persists
        // locally so paid/unpaid flows are fully testable.
        guard RevenueCatBootstrap.isConfigured else {
            return await DemoPremiumService().premiumState(relationship: relationship, me: me)
        }

        // 1. My own entitlement (purchaser keeps premium across relationships).
        if RevenueCatBootstrap.isConfigured,
           let info = try? await Purchases.shared.customerInfo(),
           let entitlement = info.entitlements[RevenueCatBootstrap.entitlementID],
           entitlement.isActive {
            let state = PremiumState(
                isPremium: true,
                inheritedFromPartner: false,
                entitlement: PremiumEntitlement(purchaserID: me,
                                                productID: entitlement.productIdentifier,
                                                expiresAt: entitlement.expirationDate,
                                                willRenew: entitlement.willRenew))
            if let relationship { await mirror(state.entitlement!, to: relationship.id) }
            return state
        }

        // 2. Partner-inherited premium via the relationship mirror document.
        if let relationship,
           let doc = try? await db.collection("relationships").document(relationship.id)
                .collection("premium").document("state").getDocument(),
           let entitlement = try? doc.data(as: PremiumEntitlement.self),
           entitlement.isActive,
           relationship.memberIDs.contains(entitlement.purchaserID) {
            return PremiumState(isPremium: true,
                                inheritedFromPartner: entitlement.purchaserID != me,
                                entitlement: entitlement)
        }

        return .free
    }

    func offers() async throws -> [PaywallOffer] {
        guard RevenueCatBootstrap.isConfigured else {
            return try await DemoPremiumService().offers()
        }
        let offerings = try await Purchases.shared.offerings()
        guard let current = offerings.current, !current.availablePackages.isEmpty else {
            // Dashboard has no "Current" offering (yet) — keep the paywall
            // renderable with the local fake flow instead of a dead screen.
            // purchase() falls back the same way for these offer IDs.
            print("RevenueCat: no current offering with packages — using demo offers")
            return try await DemoPremiumService().offers()
        }
        // The decline-offer package lives in the same offering (Yearly_2) —
        // never show it on the FIRST paywall. Most expensive plan leads.
        return current.availablePackages
            .filter { !Self.isSecondaryPackage($0) }
            .map(Self.offer(from:))
            .sorted { $0.totalPrice > $1.totalPrice }
    }

    /// The "wait, don't go" package: either any package in a dedicated
    /// "secondary" offering, or — as configured in our dashboard — a package
    /// in the main offering named like "Yearly_2" / "…second…".
    private static func isSecondaryPackage(_ package: Package) -> Bool {
        let id = package.identifier.lowercased()
        return id.hasSuffix("_2") || id.contains("second")
    }

    /// Package → PaywallOffer. Labels/math come from the PRODUCT's real
    /// subscription period, not the package slot — so a monthly product
    /// accidentally mapped to the "$rc_lifetime" slot still says "Monthly".
    private static func offer(from package: Package) -> PaywallOffer {
        let product = package.storeProduct
        let title: String
        let months: Decimal
        if let period = product.subscriptionPeriod {
            switch period.unit {
            case .year:
                title = period.value == 1 ? "Yearly" : "\(period.value) Years"
                months = Decimal(period.value) * 12
            case .month:
                title = period.value == 1 ? "Monthly" : "\(period.value) Months"
                months = Decimal(period.value)
            case .week:
                title = period.value == 1 ? "Weekly" : "\(period.value) Weeks"
                months = Decimal(period.value) * 7 / 30
            case .day:
                title = "\(period.value) Days"
                months = Decimal(period.value) / 30
            }
        } else {
            // One-time purchase: per-week framing amortized over 3 years.
            title = "Lifetime"
            months = 36
        }
        return PaywallOffer(
            id: package.identifier,
            title: title,
            monthlyEquivalent: product.price / months,
            totalPrice: product.price,
            currencyCode: product.currencyCode ?? "USD",
            trialDays: trialDays(of: product),
            isFeatured: product.subscriptionPeriod?.unit == .year || product.subscriptionPeriod == nil)
    }

    /// Free-trial length in DAYS regardless of how the store expresses the
    /// period (the old math assumed weeks — a 7-day trial showed as 49 days).
    private static func trialDays(of product: StoreProduct) -> Int {
        guard let intro = product.introductoryDiscount, intro.paymentMode == .freeTrial
        else { return 0 }
        let period = intro.subscriptionPeriod
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        }
    }

    /// Discounted decline offer. Configure a RevenueCat offering with
    /// identifier "secondary" holding one package (e.g. yearly at 50% off).
    func secondaryOffer() async throws -> PaywallOffer? {
        guard RevenueCatBootstrap.isConfigured else {
            return try await DemoPremiumService().secondaryOffer()
        }
        let offerings = try await Purchases.shared.offerings()
        // Preferred: a dedicated "secondary" offering. Fallback: the
        // "Yearly_2"-style package inside the current offering.
        let package = offerings.offering(identifier: "secondary")?.availablePackages.first
            ?? offerings.current?.availablePackages.first(where: Self.isSecondaryPackage)
        guard let package else { return nil }
        var offer = Self.offer(from: package)
        offer.isFeatured = true
        return offer
    }

    func purchase(offerID: String, me: UserID, relationship: RelationshipID?) async throws -> PremiumState {
        guard RevenueCatBootstrap.isConfigured else {
            return try await DemoPremiumService().purchase(offerID: offerID, me: me, relationship: relationship)
        }
        let offerings = try await Purchases.shared.offerings()
        let allPackages = (offerings.current?.availablePackages ?? [])
            + (offerings.offering(identifier: "secondary")?.availablePackages ?? [])
        guard let package = allPackages.first(where: { $0.identifier == offerID }) else {
            // The offer on screen came from the demo fallback (no Current
            // offering configured yet) — complete it as a fake purchase so
            // the button always works during setup.
            print("RevenueCat: package \(offerID) not found — demo purchase fallback")
            return try await DemoPremiumService().purchase(offerID: offerID, me: me, relationship: relationship)
        }

        let result = try await Purchases.shared.purchase(package: package)
        guard !result.userCancelled,
              let entitlement = result.customerInfo.entitlements[RevenueCatBootstrap.entitlementID],
              entitlement.isActive else { return .free }

        let premium = PremiumEntitlement(purchaserID: me,
                                         productID: entitlement.productIdentifier,
                                         expiresAt: entitlement.expirationDate,
                                         willRenew: entitlement.willRenew)
        if let relationship { await mirror(premium, to: relationship) }
        return PremiumState(isPremium: true, entitlement: premium)
    }

    func restorePurchases(me: UserID) async throws -> PremiumState {
        guard RevenueCatBootstrap.isConfigured else {
            return try await DemoPremiumService().restorePurchases(me: me)
        }
        let info = try await Purchases.shared.restorePurchases()
        guard let entitlement = info.entitlements[RevenueCatBootstrap.entitlementID],
              entitlement.isActive else { return .free }
        return PremiumState(isPremium: true,
                            entitlement: PremiumEntitlement(purchaserID: me,
                                                            productID: entitlement.productIdentifier,
                                                            expiresAt: entitlement.expirationDate,
                                                            willRenew: entitlement.willRenew))
    }

    private func mirror(_ entitlement: PremiumEntitlement, to relationship: RelationshipID) async {
        try? db.collection("relationships").document(relationship)
            .collection("premium").document("state").setData(from: entitlement)
    }
}
