import SwiftUI

enum Theme {
    static let bgTop = Color(red: 0.05, green: 0.04, blue: 0.12)
    static let bgBottom = Color(red: 0.09, green: 0.05, blue: 0.19)
    static let accent = Color(red: 0.55, green: 0.45, blue: 1.0)
    static let accent2 = Color(red: 0.25, green: 0.86, blue: 0.86)
    static let warm = Color(red: 1.0, green: 0.56, blue: 0.46)
    static let card = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.12)
    static let dim = Color.white.opacity(0.62)

    static let brandGradient = LinearGradient(
        colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Deterministic gradient for a book without a cover.
    static func coverGradient(seed: Int) -> LinearGradient {
        let palettes: [[Color]] = [
            [Color(red: 0.42, green: 0.30, blue: 0.95), Color(red: 0.95, green: 0.45, blue: 0.65)],
            [Color(red: 0.10, green: 0.55, blue: 0.70), Color(red: 0.30, green: 0.90, blue: 0.70)],
            [Color(red: 0.95, green: 0.55, blue: 0.25), Color(red: 0.85, green: 0.25, blue: 0.40)],
            [Color(red: 0.20, green: 0.25, blue: 0.55), Color(red: 0.55, green: 0.75, blue: 0.98)],
            [Color(red: 0.55, green: 0.20, blue: 0.55), Color(red: 0.98, green: 0.75, blue: 0.40)],
        ]
        let p = palettes[abs(seed) % palettes.count]
        return LinearGradient(colors: p, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Slowly drifting aurora blobs behind every screen.
struct AuroraBackground: View {
    var tint: Color = Theme.accent

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom)
                    Circle()
                        .fill(tint.opacity(0.35))
                        .frame(width: w * 0.9)
                        .blur(radius: 90)
                        .offset(x: CGFloat(sin(t / 7)) * w * 0.25, y: -h * 0.30 + CGFloat(cos(t / 9)) * 40)
                    Circle()
                        .fill(Theme.accent2.opacity(0.22))
                        .frame(width: w * 0.8)
                        .blur(radius: 100)
                        .offset(x: CGFloat(cos(t / 8)) * w * 0.3, y: h * 0.25 + CGFloat(sin(t / 6)) * 50)
                    Circle()
                        .fill(Theme.warm.opacity(0.12))
                        .frame(width: w * 0.6)
                        .blur(radius: 90)
                        .offset(x: -w * 0.3 + CGFloat(sin(t / 5)) * 30, y: CGFloat(cos(t / 11)) * h * 0.2)
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct GlassCard: ViewModifier {
    var radius: CGFloat = 22
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial.opacity(0.7), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }
}

extension View {
    func glass(radius: CGFloat = 22) -> some View { modifier(GlassCard(radius: radius)) }
}

struct Chip: View {
    let text: String
    var symbol: String? = nil
    var selected = false

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.caption.weight(.bold)) }
            Text(text).font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(selected ? Color.black : Color.white)
        .background(
            Capsule().fill(selected ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.white.opacity(0.08)))
        )
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: selected ? 0 : 1))
    }
}

struct GradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(Theme.brandGradient, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: Theme.accent.opacity(0.45), radius: 18, y: 8)
            .animation(.spring(response: 0.3), value: configuration.isPressed)
    }
}
