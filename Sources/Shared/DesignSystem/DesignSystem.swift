import SwiftUI

// MARK: - Lovio Design Language
//
// Premium, minimal, warm. Inspired by Apple Health / Journal / Calm.
// No cartoon assets — soft gradients, glass, generous type, restrained color.

public enum Lovio {

    // MARK: Colors

    public enum Palette {
        /// Primary brand rose — warm, not saccharine.
        public static let rose = Color(red: 0.94, green: 0.35, blue: 0.44)
        /// Deep plum for dark surfaces and gradient anchors.
        public static let plum = Color(red: 0.32, green: 0.14, blue: 0.35)
        /// Soft peach highlight.
        public static let peach = Color(red: 0.99, green: 0.72, blue: 0.60)
        /// Lavender secondary accent.
        public static let lavender = Color(red: 0.66, green: 0.58, blue: 0.98)
        /// Midnight for dark-mode gradient anchors.
        public static let midnight = Color(red: 0.07, green: 0.05, blue: 0.13)
        /// Warm gold for streaks, XP and celebration moments.
        public static let gold = Color(red: 0.98, green: 0.75, blue: 0.30)
        /// Calm teal for mood / health surfaces.
        public static let teal = Color(red: 0.30, green: 0.76, blue: 0.72)

        public static let textPrimary = Color.primary
        public static let textSecondary = Color.secondary
    }

    // MARK: Gradients

    public enum Gradients {
        /// The hero brand gradient used on onboarding, paywall, celebration moments.
        public static let hero = LinearGradient(
            colors: [Palette.rose, Palette.lavender.opacity(0.9), Palette.plum],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Ambient background wash — subtle enough to sit behind content.
        public static func ambient(_ scheme: ColorScheme) -> LinearGradient {
            scheme == .dark
                ? LinearGradient(
                    colors: [Palette.midnight, Palette.plum.opacity(0.55), Palette.midnight],
                    startPoint: .top, endPoint: .bottom)
                : LinearGradient(
                    colors: [Palette.peach.opacity(0.22), Color(.systemBackground), Palette.lavender.opacity(0.16)],
                    startPoint: .top, endPoint: .bottom)
        }

        public static let streak = LinearGradient(
            colors: [Palette.gold, Palette.rose],
            startPoint: .topLeading, endPoint: .bottomTrailing)

        public static let mood = LinearGradient(
            colors: [Palette.teal, Palette.lavender],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Typography
    // Rounded SF for warmth, tight tracking on display sizes.

    public enum Type_ {
        public static let display = Font.system(size: 40, weight: .bold, design: .rounded)
        public static let largeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
        public static let title = Font.system(.title2, design: .rounded, weight: .semibold)
        public static let headline = Font.system(.headline, design: .rounded)
        public static let body = Font.system(.body, design: .rounded)
        public static let caption = Font.system(.caption, design: .rounded, weight: .medium)
        public static let numeric = Font.system(size: 34, weight: .bold, design: .rounded)
    }

    public enum Metrics {
        public static let cornerRadius: CGFloat = 24
        public static let cardPadding: CGFloat = 18
        public static let screenPadding: CGFloat = 20
        public static let sectionSpacing: CGFloat = 24
    }
}

// MARK: - Glass Card

/// Frosted glass surface used across the app. Falls back gracefully inside widgets.
public struct GlassCard<Content: View>: View {
    private let content: Content
    private let padding: CGFloat
    private let tint: Color?

    public init(padding: CGFloat = Lovio.Metrics.cardPadding,
                tint: Color? = nil,
                @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.tint = tint
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Lovio.Metrics.cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: Lovio.Metrics.cornerRadius, style: .continuous)
                            .fill((tint ?? .clear).opacity(0.10))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Lovio.Metrics.cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.35), .white.opacity(0.05)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 0.8)
                    }
            }
            .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
    }
}

// MARK: - Primary Button

public struct LovioPrimaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Lovio.Type_.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                Capsule().fill(Lovio.Gradients.hero)
            }
            .shadow(color: Lovio.Palette.rose.opacity(0.35), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

public struct LovioSecondaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Lovio.Type_.headline)
            .foregroundStyle(Lovio.Palette.rose)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(Lovio.Palette.rose.opacity(0.35), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Brand mark

/// App icon artwork — home screen, splash, loading, onboarding.
public struct MissuoLogoMark: View {
    public var size: CGFloat
    public var shadow: Bool

    public init(size: CGFloat = 72, shadow: Bool = true) {
        self.size = size
        self.shadow = shadow
    }

    public var body: some View {
        Image("MissuoLogo")
            .resizable()
            .aspectRatio(1, contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.223, style: .continuous))
            .shadow(color: .black.opacity(shadow ? 0.14 : 0), radius: size * 0.06, y: size * 0.03)
            .accessibilityLabel("Missuo")
    }
}

// MARK: - Heart Pulse

/// The animated heartbeat used across Home + Love Pulse widget contexts.
public struct HeartPulse: View {
    public var size: CGFloat
    public var isActive: Bool
    @State private var beat = false

    public init(size: CGFloat = 44, isActive: Bool = true) {
        self.size = size
        self.isActive = isActive
    }

    public var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size))
            .foregroundStyle(Lovio.Gradients.hero)
            .scaleEffect(beat ? 1.12 : 0.94)
            .shadow(color: Lovio.Palette.rose.opacity(beat ? 0.5 : 0.15), radius: beat ? 18 : 6)
            .onAppear {
                guard isActive else { return }
                withAnimation(.easeInOut(duration: 0.62).repeatForever(autoreverses: true)) {
                    beat = true
                }
            }
            .accessibilityLabel("Heartbeat")
    }
}

// MARK: - Avatar Pair

public struct AvatarPair: View {
    let left: String
    let right: String
    var size: CGFloat = 44

    public init(left: String, right: String, size: CGFloat = 44) {
        self.left = left
        self.right = right
        self.size = size
    }

    public var body: some View {
        HStack(spacing: -size * 0.28) {
            avatar(initials: left, colors: [Lovio.Palette.rose, Lovio.Palette.peach])
            avatar(initials: right, colors: [Lovio.Palette.lavender, Lovio.Palette.plum])
        }
    }

    private func avatar(initials: String, colors: [Color]) -> some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)))
            .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 2))
    }
}
