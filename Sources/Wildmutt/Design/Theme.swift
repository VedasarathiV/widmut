import SwiftUI

/// Modern Pro palette for Widmut, grounded in the iconic alien logo's warm amber glow.
/// Tech accents: Solar Amber (brand), Vivid Violet, Rose, Mint Emerald, and Slate.
enum Glow: CaseIterable {
    case magenta, violet, blue, ember, sage, lime, graphite

    var color: Color {
        switch self {
        case .magenta: Color(red: 0.94, green: 0.28, blue: 0.52) // Vibrant Rose
        case .violet: Color(red: 0.55, green: 0.40, blue: 0.98) // Electric Violet
        case .blue: Color(red: 0.20, green: 0.50, blue: 0.98) // Royal Azure
        case .ember: Color(red: 0.98, green: 0.58, blue: 0.13) // Widmut Solar Amber (#FA9322)
        case .sage: Color(red: 0.35, green: 0.75, blue: 0.75) // Cool Slate Teal
        case .lime: Color(red: 0.10, green: 0.80, blue: 0.50) // Vivid Emerald Mint
        case .graphite: Color(red: 0.45, green: 0.50, blue: 0.60) // Refined Slate
        }
    }
}

enum Theme {
    static let background = Color(red: 0.045, green: 0.048, blue: 0.058) // Deep Obsidian (#0B0C0F)
    static let surface = Color(red: 0.086, green: 0.094, blue: 0.114) // Elevated Slate Card
    static let hairline = Color.white.opacity(0.08)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.65)
    static let tertiaryText = Color.white.opacity(0.40)
    /// Widmut's primary brand accent (matching original alien logo #FA9322)
    static let accent = Color(red: 0.98, green: 0.58, blue: 0.13)
    static let danger = Color(red: 0.95, green: 0.30, blue: 0.35)
    static let radius: CGFloat = 16
}

// MARK: - Modern Pro Card Surface (Replacing blurry glassmorphism)

enum GlowStyle { case rim, core, plain }

struct GlowCard<Content: View>: View {
    var glow: Glow = .graphite
    var style: GlowStyle = .core
    var padding: CGFloat = 20
    var busy = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { GlowSurface(glow: glow, style: style, busy: busy) }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(cardBorder, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.30), radius: 10, y: 4)
            .accessibilityElement(children: .contain)
            .reveal()
    }

    private var cardBorder: LinearGradient {
        switch style {
        case .rim:
            LinearGradient(
                colors: [glow.color.opacity(0.85), glow.color.opacity(0.25), Color.white.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .core:
            LinearGradient(
                colors: [Color.white.opacity(0.14), Color.white.opacity(0.04), Color.white.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .plain:
            LinearGradient(
                colors: [Color.white.opacity(0.08), Color.white.opacity(0.04)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct GlowSurface: View {
    let glow: Glow
    let style: GlowStyle
    var busy = false
    @ViewState private var lit = Motion.reduced
    @ViewState private var pulse = false

    var body: some View {
        ZStack {
            // Clean elevated solid/semi-translucent slate background
            Theme.surface

            // Subtle top highlight sheen (replaces heavy glassmorphism blur)
            LinearGradient(
                colors: [Color.white.opacity(0.04), Color.clear],
                startPoint: .top,
                endPoint: .center
            )

            switch style {
            case .rim:
                // Subtle top edge ambient accent
                LinearGradient(
                    colors: [glow.color.opacity(lit ? 0.12 : 0.05), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
            case .core:
                // Gentle ambient core glow
                LinearGradient(
                    colors: [glow.color.opacity(lit ? 0.06 : 0.02), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .center
                )
            case .plain:
                EmptyView()
            }

            if busy {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .stroke(glow.color.opacity(pulse ? 0.6 : 0.15), lineWidth: 1.5)
            }
        }
        .onAppear {
            guard !lit else { return }
            withAnimation(.easeOut(duration: 0.8)) { lit = true }
        }
        .onChange(of: busy, initial: true) { _, isBusy in
            guard !Motion.reduced else { return }
            withAnimation(isBusy ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .easeOut(duration: 0.5)) {
                pulse = isBusy
            }
        }
    }
}

// MARK: - Clean Background

struct DotGrid: View {
    private static let tile: NSImage = {
        let spacing: CGFloat = 20, dot: CGFloat = 1.2
        return NSImage(size: NSSize(width: spacing, height: spacing), flipped: false) { _ in
            NSColor.white.withAlphaComponent(0.035).setFill()
            NSBezierPath(ovalIn: NSRect(x: spacing / 2, y: spacing / 2, width: dot, height: dot)).fill()
            return true
        }
    }()

    var body: some View {
        Image(nsImage: Self.tile).resizable(resizingMode: .tile).allowsHitTesting(false)
    }
}

/// Refined ambient background with subtle, non-intrusive accent lighting
struct AmbientBackground: View {
    var tint: Glow = .ember

    var body: some View {
        ZStack {
            Theme.background
            // Very soft, refined micro-lighting
            Circle()
                .fill(RadialGradient(colors: [tint.color.opacity(0.08), Color.clear],
                                     center: .center, startRadius: 0, endRadius: 360))
                .frame(width: 720, height: 720)
                .offset(x: 320, y: -240)
            DotGrid()
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: tint)
    }
}

// MARK: - Buttons

struct Pill: InsettableShape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        return RoundedRectangle(cornerRadius: min(r.width, r.height) / 2, style: .circular).path(in: r)
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.inset += amount
        return copy
    }
}

struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger }
    var kind: Kind = .primary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(kind: kind, fill: fill, compact: compact, configuration: configuration)
    }

    private var fill: Color {
        switch kind {
        case .primary: Theme.accent
        case .secondary: Color.white.opacity(0.07)
        case .danger: Theme.danger.opacity(0.9)
        }
    }
}

private struct PillBody: View {
    let kind: PillButtonStyle.Kind
    let fill: Color
    let compact: Bool
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var enabled
    @ViewState private var hover = false

    var body: some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .padding(.horizontal, compact ? 12 : 18)
            .frame(height: compact ? 26 : 34)
            .foregroundStyle(kind == .primary ? Color(red: 0.08, green: 0.05, blue: 0.02) : Color.white)
            .background {
                Capsule().fill(fill)
                if kind == .secondary { Pill().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
            }
            .brightness(hover && enabled ? (kind == .primary ? 0.05 : 0.08) : 0)
            .opacity(!enabled ? 0.38 : configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
            .animation(Motion.quick, value: hover)
            .contentShape(Capsule())
            .onHover { hover = $0 }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { .init() }
    static var pillSecondary: PillButtonStyle { .init(kind: .secondary) }
    static var pillDanger: PillButtonStyle { .init(kind: .danger) }
}

struct CircleIconButton: View {
    let symbol: String
    var help: String = ""
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @ViewState private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(hover && enabled ? 0.12 : 0.06)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hover = $0 }
        .animation(Motion.quick, value: hover)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct PillPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(String, Value)]
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.1) { title, value in
                let on = selection == value
                Button { withAnimation(Motion.quick) { selection = value } } label: {
                    Text(title).font(.system(size: 12.5, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Color(red: 0.08, green: 0.05, blue: 0.02) : Color.white.opacity(0.70))
                        .padding(.horizontal, 14).frame(height: 28)
                        .background { if on { Capsule().fill(Theme.accent).matchedGeometryEffect(id: "pill", in: pill) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Pill().strokeBorder(Theme.hairline))
    }
}

struct Tag: View {
    let text: String
    var color: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9)
            .frame(height: 20)
            .foregroundStyle(color.opacity(0.95))
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

// MARK: - Typography helpers

extension View {
    func cardTitle() -> some View {
        font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.primaryText)
    }

    func caption() -> some View {
        font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
    }
}

extension Int64 {
    var bytesText: String { ByteSize.format(self) }
}

typealias ViewState<Value> = SwiftUI.State<Value>
