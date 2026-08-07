import SwiftUI

// MARK: - Paywall
//
// Strategy: never lead with "$9.99/month". Premium is shared across the couple,
// so the anchor is always "per week · per person" — the honest math of a
// relationship-level subscription. Headline copy is A/B tested via Remote Config.

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

    // Design rules:
    // 1. NO scrolling — full prices, math and CTA all visible at once.
    // 2. Full price is the biggest number on each offer (App Review wants the
    //    real price unmissable); per-week-per-person is the supporting math.
    // 3. CTA sits at the exact same spot as the tutorial's Continue button.
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

            Spacer(minLength: 8)

            VStack(spacing: 10) {
                MissuoLogoMark(size: 64, shadow: false)

                Text(headline)
                    .font(Lovio.Type_.largeTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)

                Text("You subscribe once — \(model.partnerFirstName ?? "your partner") gets everything free.")
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Lovio.Metrics.screenPadding)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 10) {
                feature("square.grid.2x2.fill", "All 20+ widgets, on both phones")
                feature("sparkles", "AI coach, insights & date planner")
                feature("book.closed.fill", "Unlimited journal & voice memories")
                feature("hand.raised.slash.fill", "Zero ads, forever")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.12)))
            .padding(.horizontal, Lovio.Metrics.screenPadding)

            Spacer(minLength: 12)

            VStack(spacing: 10) {
                ForEach(offers) { offer in
                    offerRow(offer)
                }

                if let selected {
                    Text("= \(selected.formattedPerWeekPerPerson()) per week, per person — it covers both of you.")
                        .font(Lovio.Type_.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Lovio.Metrics.screenPadding)

            Spacer(minLength: 8)

            HStack(spacing: 20) {
                Button("Restore purchases") {
                    Task { await model.restorePurchases() }
                }
                Button("Terms") {}
                Button("Privacy") {}
            }
            .font(Lovio.Type_.caption)
            .foregroundStyle(.white.opacity(0.55))
            .padding(.bottom, 10)

            // CTA — same geometry as the tutorial's Continue button.
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
                    } else if let selected, selected.trialDays > 0 {
                        Text("Start Using Free")
                    } else {
                        Text("Continue")
                    }
                }
                .font(Lovio.Type_.headline)
                .foregroundStyle(Lovio.Palette.plum)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(.white))
            }
            .disabled(selected == nil || isPurchasing)
            .padding(.horizontal, Lovio.Metrics.screenPadding)
            .padding(.bottom, 24)
        }
    }

    // MARK: Secondary offer ("wait — a gift for you two")

    private func secondaryOfferContent(_ offer: PaywallOffer) -> some View {
        VStack(spacing: 22) {
            HStack {
                Spacer()
                Button { handleClose() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer()

            Image(systemName: "gift.fill")
                .font(.system(size: 54))
                .foregroundStyle(Lovio.Palette.gold)
                .shadow(color: Lovio.Palette.gold.opacity(0.6), radius: 18)

            Text("Wait — a gift\nfor you two 💝")
                .font(Lovio.Type_.display)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)

            Text("One time only: \(offer.title.lowercased()) — that's \(offer.formattedPerWeekPerPerson()) per week, per person. Still covers both of you.")
                .font(Lovio.Type_.body)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)

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

            VStack(spacing: 4) {
                Text(offer.totalPrice.formatted(.currency(code: offer.currencyCode)))
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("per year · both partners included")
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.white.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(Lovio.Palette.gold, lineWidth: 2))
            }

            Button {
                isPurchasing = true
                Task {
                    await model.purchase(offer: offer)
                    isPurchasing = false
                    if model.premium.isPremium { dismiss() }
                }
            } label: {
                Group {
                    if isPurchasing { ProgressView().tint(Lovio.Palette.plum) }
                    else { Text("Claim our offer") }
                }
                .font(Lovio.Type_.headline)
                .foregroundStyle(Lovio.Palette.plum)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(.white))
            }
            .disabled(isPurchasing)

            Button("No thanks") { handleClose() }
                .font(Lovio.Type_.caption)
                .foregroundStyle(.white.opacity(0.55))

            Spacer()
        }
        .padding(Lovio.Metrics.screenPadding)
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
        offer.id.contains("yearly") || offer.title.localizedCaseInsensitiveContains("year")
    }

    /// "/year", "/month" — or " once" for lifetime (one-time) products.
    private func priceSuffix(_ offer: PaywallOffer) -> String {
        if offer.title.localizedCaseInsensitiveContains("lifetime") { return " once" }
        return isYearly(offer) ? "/year" : "/month"
    }

    private func offerRow(_ offer: PaywallOffer) -> some View {
        Button {
            selected = offer
            Haptics.light()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(offer.title)
                            .font(Lovio.Type_.headline)
                            .foregroundStyle(.white)
                        if offer.isFeatured {
                            Text("BEST VALUE")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Lovio.Palette.gold))
                                .foregroundStyle(Lovio.Palette.plum)
                        }
                    }
                    if offer.trialDays > 0 {
                        Text("\(offer.trialDays) days free · cancel anytime")
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        Text("Cancel anytime")
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer()
                // Full price leads (App Review compliance); our per-person
                // framing is the caption underneath.
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(offer.totalPrice.formatted(.currency(code: offer.currencyCode)))\(priceSuffix(offer))")
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("≈ \(offer.formattedPerWeekPerPerson()) /week /person")
                        .font(Lovio.Type_.caption)
                        .foregroundStyle(.white.opacity(0.7))
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
    }
}
