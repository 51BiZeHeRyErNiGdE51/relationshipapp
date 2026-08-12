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
    /// Priority: process env → Info.plist `RevenueCatPublicAPIKey` → DEBUG Test Store.
    /// App Store archives MUST set the Apple key (`appl_…`) in Info.plist
    /// (RevenueCat → Project settings → API keys → Apple App Store).
    static var apiKey: String {
        if let env = ProcessInfo.processInfo.environment["REVENUECAT_API_KEY"], !env.isEmpty {
            return env
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "RevenueCatPublicAPIKey") as? String,
           !plist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !plist.hasPrefix("$(") {
            return plist
        }
        #if DEBUG
        return "test_NKYaJmNPYQDHQHnmuarVjdgzaKq"
        #else
        return ""
        #endif
    }

    static let entitlementID = "premium"

    /// True when we're on the Test Store key (or DEBUG without an Apple key).
    static var isTestStore: Bool {
        apiKey.hasPrefix("test_") || apiKey.isEmpty
    }

    /// Local fake / screenshot Premium is allowed only off the App Store binary.
    static var allowsFakePremium: Bool {
        #if DEBUG
        true
        #else
        isTestStore
        #endif
    }

    /// Configure at app LAUNCH (anonymous RevenueCat user). The onboarding
    /// paywall shows before our sign-in exists — without this it fell back to
    /// hardcoded demo prices, which made the app look like it had two
    /// different paywall designs with different prices.
    static func configureEarly() {
        guard !apiKey.isEmpty, !Purchases.isConfigured else {
            #if DEBUG
            if apiKey.isEmpty {
                print("RevenueCat: no API key — purchases will use demo fallback")
            }
            #endif
            return
        }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: apiKey)
    }

    /// Attach our platform-independent user ID once sign-in completes.
    static func configure(appUserID: UserID) {
        guard !apiKey.isEmpty else { return }
        if Purchases.isConfigured {
            Purchases.shared.logIn(appUserID) { _, _, _ in }
        } else {
            Purchases.logLevel = .warn
            Purchases.configure(with: Configuration.Builder(withAPIKey: apiKey)
                .with(appUserID: appUserID)
                .build())
        }
    }

    static var isConfigured: Bool { Purchases.isConfigured }
}

struct RevenueCatPremiumService: PremiumService {
    private var db: Firestore { Firestore.firestore() }

    func premiumState(relationship: Relationship?, me: UserID) async -> PremiumState {
        // Screenshot / Test Store unlock only — never honor UserDefaults fake
        // Premium in App Store binaries (would be a free unlock exploit).
        if RevenueCatBootstrap.allowsFakePremium {
            let demo = await DemoPremiumService().premiumState(relationship: relationship, me: me)
            if demo.isPremium { return demo }
        }

        guard RevenueCatBootstrap.isConfigured else {
            return RevenueCatBootstrap.allowsFakePremium
                ? await DemoPremiumService().premiumState(relationship: relationship, me: me)
                : .free
        }

        // 1. My own entitlement (purchaser keeps premium across relationships).
        if let info = try? await Purchases.shared.customerInfo(),
           let entitlement = info.entitlements[RevenueCatBootstrap.entitlementID],
           entitlement.isActive {
            let state = PremiumState(
                isPremium: true,
                inheritedFromPartner: false,
                entitlement: PremiumEntitlement(purchaserID: me,
                                                productID: entitlement.productIdentifier,
                                                expiresAt: entitlement.expirationDate,
                                                willRenew: entitlement.willRenew))
            if let relationship { await Self.mirror(state.entitlement!, to: relationship.id) }
            return state
        }

        // 2. Partner-inherited premium via the relationship mirror document.
        // Only while the couple is actively paired — ended relationships must
        // never keep granting inherited premium after a split.
        if let relationship,
           relationship.status == .active || relationship.status == .pendingPartner,
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
            guard RevenueCatBootstrap.allowsFakePremium else {
                throw LovioError.notSignedIn
            }
            return try await DemoPremiumService().offers()
        }
        let offerings = try await Purchases.shared.offerings()
        guard let current = offerings.current, !current.availablePackages.isEmpty else {
            print("RevenueCat: no current offering with packages — using demo offers")
            guard RevenueCatBootstrap.allowsFakePremium else {
                throw LovioError.notSignedIn
            }
            return try await DemoPremiumService().offers()
        }
        // Paywall 1 ONLY: yearly_1 + monthly. yearly_2 is reserved for the
        // decline / secondary paywall — never list it here.
        return current.availablePackages
            .filter { !Self.isSecondaryPackage($0) }
            .map(Self.offer(from:))
            .sorted { lhs, rhs in
                // Yearly (featured) first, then monthly.
                if lhs.isFeatured != rhs.isFeatured { return lhs.isFeatured && !rhs.isFeatured }
                return lhs.totalPrice > rhs.totalPrice
            }
    }

    /// yearly_2 / "second" / product id containing yearly_2 — the decline offer.
    /// Checks package id AND store product id (RevenueCat package slots can be
    /// `$rc_annual` while the product is still `yearly_2`).
    private static func isSecondaryPackage(_ package: Package) -> Bool {
        let ids = [
            package.identifier.lowercased(),
            package.storeProduct.productIdentifier.lowercased(),
        ]
        return ids.contains { id in
            id == "yearly_2" || id.hasSuffix("_2") || id.contains("second")
                || id.contains("yearly2") || id.contains("yearly_2")
        }
    }

    /// True for the main yearly (yearly_1) — used as the discount anchor.
    private static func isPrimaryYearly(_ package: Package) -> Bool {
        if isSecondaryPackage(package) { return false }
        let product = package.storeProduct
        if product.subscriptionPeriod?.unit == .year { return true }
        let id = product.productIdentifier.lowercased()
        return id.contains("yearly") && !id.contains("2")
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
            guard RevenueCatBootstrap.allowsFakePremium else { return nil }
            return try await DemoPremiumService().secondaryOffer()
        }
        let offerings = try await Purchases.shared.offerings()
        let package = offerings.offering(identifier: "secondary")?.availablePackages.first
            ?? offerings.current?.availablePackages.first(where: Self.isSecondaryPackage)
        guard let package else { return nil }

        // Anchor = yearly_1 full price (for SAVE % and strikethrough).
        let anchor = offerings.current?.availablePackages
            .first(where: Self.isPrimaryYearly)
            .map { $0.storeProduct.price }

        var offer = Self.offer(from: package)
        offer.isFeatured = true
        // yearly_2 never has a free trial — even if the store product was
        // misconfigured with one, the decline paywall must not advertise it.
        offer.trialDays = 0
        offer.anchorPrice = anchor
        return offer
    }

    func purchase(offerID: String, me: UserID, relationship: RelationshipID?) async throws -> PremiumState {
        guard RevenueCatBootstrap.isConfigured else {
            guard RevenueCatBootstrap.allowsFakePremium else {
                throw LovioError.purchaseUnavailable
            }
            return try await DemoPremiumService().purchase(offerID: offerID, me: me, relationship: relationship)
        }
        let offerings = try await Purchases.shared.offerings()
        let allPackages = (offerings.current?.availablePackages ?? [])
            + (offerings.offering(identifier: "secondary")?.availablePackages ?? [])
        guard let package = allPackages.first(where: { $0.identifier == offerID }) else {
            // Demo fallback only while Test Store / products are unfinished.
            if RevenueCatBootstrap.allowsFakePremium {
                print("RevenueCat: package \(offerID) not found — demo purchase fallback")
                return try await DemoPremiumService().purchase(offerID: offerID, me: me, relationship: relationship)
            }
            throw LovioError.purchaseUnavailable
        }

        let result = try await Purchases.shared.purchase(package: package)
        guard !result.userCancelled,
              let entitlement = result.customerInfo.entitlements[RevenueCatBootstrap.entitlementID],
              entitlement.isActive else { return .free }

        let premium = PremiumEntitlement(purchaserID: me,
                                         productID: entitlement.productIdentifier,
                                         expiresAt: entitlement.expirationDate,
                                         willRenew: entitlement.willRenew)
        if let relationship { await Self.mirror(premium, to: relationship) }
        return PremiumState(isPremium: true, entitlement: premium)
    }

    func restorePurchases(me: UserID) async throws -> PremiumState {
        guard RevenueCatBootstrap.isConfigured else {
            guard RevenueCatBootstrap.allowsFakePremium else { return .free }
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

    /// Writes the couple's shared premium doc so the partner unlocks within
    /// one refresh. Public so demo/fallback purchases use the same path.
    static func mirror(_ entitlement: PremiumEntitlement, to relationship: RelationshipID) async {
        guard FirebaseBootstrap.isConfigured else { return }
        do {
            try Firestore.firestore().collection("relationships").document(relationship)
                .collection("premium").document("state").setData(from: entitlement)
        } catch {
            print("Premium mirror failed: \(error.localizedDescription)")
        }
    }

    /// Called when a relationship ends so the ex-partner stops inheriting.
    static func clearMirror(on relationship: RelationshipID) async {
        guard FirebaseBootstrap.isConfigured else { return }
        try? await Firestore.firestore().collection("relationships").document(relationship)
            .collection("premium").document("state").delete()
    }

    private func mirror(_ entitlement: PremiumEntitlement, to relationship: RelationshipID) async {
        await Self.mirror(entitlement, to: relationship)
    }
}
