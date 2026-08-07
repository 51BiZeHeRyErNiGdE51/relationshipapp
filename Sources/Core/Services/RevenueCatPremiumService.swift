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
        guard let current = offerings.current else { return [] }
        return current.availablePackages.map { package in
            let product = package.storeProduct
            let months: Decimal = package.packageType == .annual ? 12 : 1
            let trialDays = product.introductoryDiscount
                .flatMap { $0.paymentMode == .freeTrial ? $0.subscriptionPeriod.value * 7 : 0 } ?? 0
            return PaywallOffer(
                id: package.identifier,
                title: package.packageType == .annual ? "Yearly" : "Monthly",
                monthlyEquivalent: product.price / months,
                totalPrice: product.price,
                currencyCode: product.currencyCode ?? "USD",
                trialDays: trialDays,
                isFeatured: package.packageType == .annual)
        }
    }

    /// Discounted decline offer. Configure a RevenueCat offering with
    /// identifier "secondary" holding one package (e.g. yearly at 50% off).
    func secondaryOffer() async throws -> PaywallOffer? {
        guard RevenueCatBootstrap.isConfigured else {
            return try await DemoPremiumService().secondaryOffer()
        }
        let offerings = try await Purchases.shared.offerings()
        guard let package = offerings.offering(identifier: "secondary")?.availablePackages.first
        else { return nil }
        let product = package.storeProduct
        let months: Decimal = package.packageType == .annual ? 12 : 1
        return PaywallOffer(id: package.identifier,
                            title: package.packageType == .annual ? "Yearly — special offer" : "Special offer",
                            monthlyEquivalent: product.price / months,
                            totalPrice: product.price,
                            currencyCode: product.currencyCode ?? "USD",
                            trialDays: 0,
                            isFeatured: true)
    }

    func purchase(offerID: String, me: UserID, relationship: RelationshipID?) async throws -> PremiumState {
        guard RevenueCatBootstrap.isConfigured else {
            return try await DemoPremiumService().purchase(offerID: offerID, me: me, relationship: relationship)
        }
        let offerings = try await Purchases.shared.offerings()
        let allPackages = (offerings.current?.availablePackages ?? [])
            + (offerings.offering(identifier: "secondary")?.availablePackages ?? [])
        guard let package = allPackages.first(where: { $0.identifier == offerID })
        else { return .free }

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
