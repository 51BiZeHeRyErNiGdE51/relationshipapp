import SwiftUI

// MARK: - Paywall
//
// App Review 3.1.2(c): the billed App Store amount is the primary, most
// conspicuous price. Per-week / per-person math and trial copy stay subordinate.
// Premium is still sold as a relationship-level unlock (one purchase → both).

struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let source: String
    /// Opens directly on the discounted decline offer (e.g. from the Home chip).
    var startOnSecondary: Bool = false

    @State private var offers: [PaywallOffer] = []
    @State private var selected: PaywallOffer?
    @State private var secondaryOffer: PaywallOffer?
    @State private var showSecondary = false
    @State private var isPurchasing = false

    private var headline: String {
        switch model.services.experiments.variant(for: "paywall_headline") {
        case "b": "One subscription.\nTwo happier people."
        default: "Premium for your\nwhole relationship."
        }
    }

    /// Remote Config `paywall_cta` (main) / `paywall_cta_secondary` (decline offer):
    /// - `control` / empty → billed amount is the button (App Review 3.1.2(c))
    /// - any other one-line string (e.g. "Try Free", "Claim offer") → that label
    private func remoteCTA(forKey key: String) -> String? {
        let raw = model.services.experiments.variant(for: key)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || raw.lowercased() == "control" || raw.lowercased() == "compliant" {
            return nil
        }
        return raw
    }

    private func ctaLabel(for offer: PaywallOffer?, key: String = "paywall_cta") -> String {
        if let remote = remoteCTA(forKey: key) { return remote }
        if let offer { return billedPrice(offer) }
        return "Continue"
    }

    /// Close: first decline reroutes to the secondary offer (while its 7-day
    /// window is open); closing that — or an expired window — really dismisses.
    private func handleClose() {
        if !showSecondary, !model.premium.isPremium,
           model.isSecondaryOfferActive, secondaryOffer != nil {
            model.registerPaywallDecline()   // starts the 7-day window on first decline
            withAnimation(.smooth) { showSecondary = true }
            model.services.analytics.track(.paywallImpression(
                source: "secondary_offer", variant: "decline"))
        } else {
            if !model.premium.isPremium { model.registerPaywallDecline() }
            dismiss()
        }
    }

    var body: some View {
        ZStack {
            Lovio.Gradients.hero.ignoresSafeArea()
                .overlay(.black.opacity(showSecondary ? 0.35 : 0.15))

            if showSecondary, let offer = secondaryOffer {
                secondaryOfferContent(offer)
            } else {
                mainContent
            }
        }
        .task {
            model.services.analytics.track(.paywallImpression(
                source: source,
                variant: model.services.experiments.variant(for: "paywall_headline")))
            offers = (try? await model.services.premium.offers()) ?? []
            selected = offers.first { $0.isFeatured } ?? offers.first
            secondaryOffer = try? await model.services.premium.secondaryOffer()
            if startOnSecondary, model.isSecondaryOfferActive, secondaryOffer != nil {
                showSecondary = true
            }
        }
    }

    // MARK: Main paywall

    // Design rules (App Review 3.1.2(c)):
    // 1. Billed amount ($X/year or $X/month) is largest + highest contrast.
    // 2. Per-week / per-person and trial lines are smaller / lower opacity.
    // 3. Couple unlock stays bold and sticky above the plans.
    // 4. CTA restates the billed amount.
    private var mainContent: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    handleClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, Lovio.Metrics.screenPadding)
            .padding(.top, 8)

            Spacer(minLength: 4)

            VStack(spacing: 8) {
                MissuoLogoMark(size: 56, shadow: false)

                Text(headline)
                    .font(Lovio.Type_.largeTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, Lovio.Metrics.screenPadding)

            Spacer(minLength: 8)

            couplePremiumSticky
                .padding(.horizontal, Lovio.Metrics.screenPadding)

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 8) {
                feature("square.grid.2x2.fill", "All 20+ widgets, on both phones")
                feature("sparkles", "AI coach, insights & date planner")
                feature("book.closed.fill", "Unlimited journal & voice memories")
                feature("hand.raised.slash.fill", "Zero ads, forever")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.12)))
            .padding(.horizontal, Lovio.Metrics.screenPadding)

            Spacer(minLength: 10)

            VStack(spacing: 10) {
                ForEach(offers) { offer in
                    offerRow(offer)
                }

                if let selected {
                    Text("≈ \(selected.formattedPerWeekPerPerson()) / week / person · covers both of you")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Lovio.Metrics.screenPadding)

            Spacer(minLength: 6)

            HStack(spacing: 20) {
                Button("Restore purchases") {
                    Task { await model.restorePurchases() }
                }
                Link("Terms", destination: URL(string: "https://bsekapps.com/terms-of-service")!)
                Link("Privacy", destination: URL(string: "https://bsekapps.com/privacy-policy")!)
            }
            .font(Lovio.Type_.caption)
            .foregroundStyle(.white.opacity(0.55))
            .padding(.bottom, 8)

            Group {
                if let selected, selected.trialDays > 0 {
                    Text("Includes \(selected.trialDays)-day free trial · then \(billedPrice(selected)) · cancel anytime")
                } else if let selected {
                    Text("Billed \(billedPrice(selected)) · renews automatically · cancel anytime")
                } else {
                    Text("Renews automatically · cancel anytime in the App Store")
                }
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.62))
            .multilineTextAlignment(.center)
            .padding(.horizontal, Lovio.Metrics.screenPadding)
            .padding(.bottom, 8)

            // Same geometry as tutorial Continue — thumb stays put.
            Button {
                guard let selected else { return }
                isPurchasing = true
                Task {
                    await model.purchase(offer: selected)
                    isPurchasing = false
                    if model.premium.isPremium { dismiss() }
                }
            } label: {
                Group {
                    if isPurchasing {
                        ProgressView().tint(Lovio.Palette.plum)
                    } else {
                        Text(ctaLabel(for: selected))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .font(Lovio.Type_.headline)
                .foregroundStyle(Lovio.Palette.plum)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Lovio.Metrics.ctaVerticalPadding)
                .background(Capsule().fill(.white))
            }
            .disabled(selected == nil || isPurchasing)
            .padding(.horizontal, Lovio.Metrics.screenPadding)
            .padding(.bottom, Lovio.Metrics.ctaBottomPadding)
        }
    }

    /// Bold, high-contrast reminder that Premium unlocks the whole couple.
    private var couplePremiumSticky: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Lovio.Palette.plum)
                .frame(width: 36, height: 36)
                .background(Circle().fill(.white))

            VStack(alignment: .leading, spacing: 2) {
                Text("When you buy Premium, your couple becomes Premium too!")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Lovio.Palette.plum)
                    .fixedSize(horizontal: false, vertical: true)
                Text("One purchase · \(model.partnerFirstName ?? "your partner") gets everything free")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Lovio.Palette.plum.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Lovio.Palette.gold)
                .shadow(color: Lovio.Palette.gold.opacity(0.45), radius: 12, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.55), lineWidth: 1)
        }
        .accessibilityLabel("When you buy Premium, your couple becomes Premium too. One purchase covers both of you.")
    }

    // MARK: Secondary offer ("wait — a gift for you two")

    private func secondaryOfferContent(_ offer: PaywallOffer) -> some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()
                Button { handleClose() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer(minLength: 4)

            Image(systemName: "gift.fill")
                .font(.system(size: 48))
                .foregroundStyle(Lovio.Palette.gold)
                .shadow(color: Lovio.Palette.gold.opacity(0.6), radius: 18)

            Text("Wait — a gift\nfor you two 💝")
                .font(Lovio.Type_.display)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)

            couplePremiumSticky

            if let deadline = model.secondaryOfferDeadline {
                Label {
                    Text("Offer ends \(deadline, style: .relative) from now")
                } icon: {
                    Image(systemName: "clock.fill")
                }
                .font(Lovio.Type_.caption)
                .foregroundStyle(Lovio.Palette.gold)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.white.opacity(0.12)))
            }

            VStack(spacing: 6) {
                let full = offer.anchorPrice
                    ?? offers.first(where: isYearly)?.totalPrice
                if let full, full > offer.totalPrice {
                    HStack(spacing: 8) {
                        Text(full.formatted(.currency(code: offer.currencyCode)))
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .strikethrough()
                            .foregroundStyle(.white.opacity(0.55))
                        if let percent = offer.discountPercentVsAnchor
                            ?? discountPercent(offer, against: full) {
                            Text("SAVE \(percent)%")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Lovio.Palette.gold))
                                .foregroundStyle(Lovio.Palette.plum)
                        }
                    }
                }

                // Primary: billed amount (App Review).
                Text(billedPrice(offer))
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("billed once a year · auto-renews")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))

                // Subordinate: calculated week/person framing.
                Text("≈ \(offer.formattedPerWeekPerPerson()) / week / person · covers both of you")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 2)
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.white.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(Lovio.Palette.gold, lineWidth: 2))
            }

            HStack(spacing: 20) {
                Button("Restore purchases") { Task { await model.restorePurchases() } }
                Link("Terms", destination: URL(string: "https://bsekapps.com/terms-of-service")!)
                Link("Privacy", destination: URL(string: "https://bsekapps.com/privacy-policy")!)
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.45))

            Button("No thanks") { handleClose() }
                .font(Lovio.Type_.caption)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.bottom, 8)

            Button {
                isPurchasing = true
                Task {
                    await model.purchase(offer: offer)
                    isPurchasing = false
                    if model.premium.isPremium { dismiss() }
                }
            } label: {
                Group {
                    if isPurchasing {
                        ProgressView().tint(Lovio.Palette.plum)
                    } else {
                        Text(ctaLabel(for: offer, key: "paywall_cta_secondary"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .font(Lovio.Type_.headline)
                .foregroundStyle(Lovio.Palette.plum)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Lovio.Metrics.ctaVerticalPadding)
                .background(Capsule().fill(.white))
            }
            .disabled(isPurchasing)
        }
        .padding(.horizontal, Lovio.Metrics.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, Lovio.Metrics.ctaBottomPadding)
    }

    private func discountPercent(_ offer: PaywallOffer, against full: Decimal) -> Int? {
        guard full > 0 else { return nil }
        let fraction = 1 - NSDecimalNumber(decimal: offer.totalPrice).doubleValue
            / NSDecimalNumber(decimal: full).doubleValue
        let percent = Int((fraction * 100).rounded())
        return percent >= 5 ? percent : nil
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Lovio.Palette.gold)
                .frame(width: 26)
            Text(text)
                .font(Lovio.Type_.body)
                .foregroundStyle(.white)
        }
    }

    private func isYearly(_ offer: PaywallOffer) -> Bool {
        offer.id.lowercased().contains("yearly")
            || offer.title.localizedCaseInsensitiveContains("year")
    }

    /// % saved vs the most expensive per-month plan on screen (the classic
    /// yearly-vs-monthly anchor). Nil when under 5% — a tiny badge cheapens it.
    private func savingsPercent(_ offer: PaywallOffer) -> Int? {
        guard let base = offers.map(\.monthlyEquivalent).max(), base > 0,
              offer.monthlyEquivalent < base else { return nil }
        let fraction = 1 - NSDecimalNumber(decimal: offer.monthlyEquivalent).doubleValue
            / NSDecimalNumber(decimal: base).doubleValue
        let percent = Int((fraction * 100).rounded())
        return percent >= 5 ? percent : nil
    }

    /// "/year", "/month" — or " once" for lifetime (one-time) products.
    private func priceSuffix(_ offer: PaywallOffer) -> String {
        if offer.title.localizedCaseInsensitiveContains("lifetime") { return " once" }
        return isYearly(offer) ? "/year" : "/month"
    }

    /// Clear billed amount string for Apple 3.1.2(c).
    private func billedPrice(_ offer: PaywallOffer) -> String {
        "\(offer.totalPrice.formatted(.currency(code: offer.currencyCode)))\(priceSuffix(offer))"
    }

    private func offerRow(_ offer: PaywallOffer) -> some View {
        Button {
            selected = offer
            Haptics.light()
        } label: {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(offer.title)
                            .font(Lovio.Type_.headline)
                            .foregroundStyle(.white)
                        if let percent = savingsPercent(offer) {
                            Text("SAVE \(percent)%")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Lovio.Palette.gold))
                                .foregroundStyle(Lovio.Palette.plum)
                        } else if offer.isFeatured {
                            Text("BEST VALUE")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Lovio.Palette.gold))
                                .foregroundStyle(Lovio.Palette.plum)
                        }
                    }
                    if offer.trialDays > 0 {
                        Text("Includes \(offer.trialDays)-day free trial")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                    } else {
                        Text("Cancel anytime")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                Spacer(minLength: 8)
                // Primary: billed amount. Subordinate: week/person framing.
                VStack(alignment: .trailing, spacing: 2) {
                    Text(billedPrice(offer))
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    Text("≈ \(offer.formattedPerWeekPerPerson()) /wk /person")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.white.opacity(selected?.id == offer.id ? 0.22 : 0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(selected?.id == offer.id ? Lovio.Palette.gold : .clear,
                                          lineWidth: 2)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(offer.title), \(billedPrice(offer))")
    }
}
