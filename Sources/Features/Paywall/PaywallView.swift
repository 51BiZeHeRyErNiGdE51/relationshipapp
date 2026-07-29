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

    @State private var offers: [PaywallOffer] = []
    @State private var selected: PaywallOffer?
    @State private var isPurchasing = false

    private var headline: String {
        switch model.services.experiments.variant(for: "paywall_headline") {
        case "b": "One subscription.\nTwo happier people."
        default: "Premium for your\nwhole relationship."
        }
    }

    var body: some View {
        ZStack {
            Lovio.Gradients.hero.ignoresSafeArea()
                .overlay(.black.opacity(0.15))

            ScrollView {
                VStack(spacing: 24) {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }

                    VStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Lovio.Palette.gold)
                            .shadow(color: Lovio.Palette.gold.opacity(0.6), radius: 16)

                        Text(headline)
                            .font(Lovio.Type_.display)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)

                        Text("You subscribe once — \(model.partnerName.split(separator: " ").first.map(String.init) ?? "your partner") gets everything free. Premium belongs to the relationship.")
                            .font(Lovio.Type_.body)
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                    }

                    // Feature list
                    VStack(alignment: .leading, spacing: 12) {
                        feature("square.grid.2x2.fill", "All 20+ widgets, on both phones")
                        feature("sparkles", "AI coach, weekly reports & date planner")
                        feature("leaf.fill", "Every companion world, exclusive evolutions")
                        feature("book.closed.fill", "Unlimited journal, voice memories & recaps")
                        feature("chart.xyaxis.line", "Mood analytics & relationship insights")
                        feature("rectangle.stack.badge.play.fill", "Live Activities & lock screen widgets")
                        feature("hand.raised.slash.fill", "Zero ads, forever")
                    }
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 24).fill(.white.opacity(0.12)))

                    // Offers — anchored on per-week-per-person
                    VStack(spacing: 12) {
                        ForEach(offers) { offer in
                            offerRow(offer)
                        }
                    }

                    // CTA
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
                                Text("Start \(selected.trialDays)-day free trial")
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

                    if let selected {
                        Text("That's \(selected.formattedPerWeekPerPerson()) per week, per person — less than half a coffee.")
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: 20) {
                        Button("Restore purchases") {
                            Task { await model.restorePurchases() }
                        }
                        Button("Terms") {}
                        Button("Privacy") {}
                    }
                    .font(Lovio.Type_.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.bottom, 16)
                }
                .padding(Lovio.Metrics.screenPadding)
            }
        }
        .task {
            model.services.analytics.track(.paywallImpression(
                source: source,
                variant: model.services.experiments.variant(for: "paywall_headline")))
            offers = (try? await model.services.premium.offers()) ?? []
            selected = offers.first { $0.isFeatured } ?? offers.first
        }
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
                        Text("\(offer.trialDays) days free, then \(offer.totalPrice.formatted(.currency(code: offer.currencyCode)))/year")
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        Text("Billed monthly · cancel anytime")
                            .font(Lovio.Type_.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(offer.formattedPerWeekPerPerson())
                        .font(Lovio.Type_.headline)
                        .foregroundStyle(.white)
                    Text("/ week / person")
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
