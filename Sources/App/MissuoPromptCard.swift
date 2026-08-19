import SwiftUI

// MARK: - Branded prompt card
//
// Used for Rate Us and the push pre-permission (iOS system sheets cannot be
// restyled — this is the chic screen *before* the system dialog).

struct MissuoPromptCard: View {
    let symbol: String
    let title: String
    let message: String
    let primaryTitle: String
    var secondaryTitle: String = "Not now"
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(Lovio.Gradients.hero.opacity(0.28).ignoresSafeArea())

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Lovio.Palette.gold.opacity(0.35))
                        .frame(width: 92, height: 92)
                        .blur(radius: 18)
                    Image(systemName: symbol)
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(Lovio.Gradients.hero)
                        .symbolEffect(.pulse)
                }

                Text(title)
                    .font(.system(.title, design: .rounded, weight: .heavy))
                    .foregroundStyle(Lovio.Palette.plum)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(Lovio.Type_.body)
                    .foregroundStyle(Lovio.Palette.plum.opacity(0.75))
                    .multilineTextAlignment(.center)

                Button(action: {
                    Haptics.light()
                    onPrimary()
                }) {
                    Text(primaryTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(LovioPrimaryButtonStyle())

                Button(secondaryTitle, action: onSecondary)
                    .font(Lovio.Type_.caption.weight(.semibold))
                    .foregroundStyle(Lovio.Palette.plum.opacity(0.55))
            }
            .padding(24)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.white)
                    .shadow(color: Lovio.Palette.plum.opacity(0.22), radius: 28, y: 14)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Lovio.Palette.gold, Lovio.Palette.rose.opacity(0.6)],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.2)
            }
            .padding(.horizontal, 28)
        }
    }
}
