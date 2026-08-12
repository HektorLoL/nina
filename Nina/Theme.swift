import SwiftUI

// The palette is light-only by construction: the azulejo direction is a fired tin
// glaze, and no dark counterpart has been designed or reviewed.
enum NinaTheme {
    static let ground = Color(hex: 0xFBFCFD)
    static let grout = Color(hex: 0xEDF0F4)
    static let line = Color(hex: 0xDFE4EB)
    static let ink = Color(hex: 0x131A24)
    static let muted = Color(hex: 0x5C6675)
    static let faint = Color(hex: 0x6A7482)
    static let cobalt = Color(hex: 0x1B4FD8)
    static let cobaltDeep = Color(hex: 0x153CA6)
    static let cobaltWash = Color(hex: 0xE6EDFC)
    static let terracotta = Color(hex: 0xC2410C)
    static let terracottaWash = Color(hex: 0xFBEAE1)
    static let moss = Color(hex: 0x3F6B4A)
    static let onCobalt = Color.white

    enum Radius {
        static let chip: CGFloat = 999
        static let field: CGFloat = 14
        static let card: CGFloat = 20
        static let sheet: CGFloat = 28
    }

    static let shadow = Color(hex: 0x131A24).opacity(0.06)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// Fraunces carries brand voice — screen titles, Nina's own speech, the one big
// number. Anything monolinear is interface and stays on the system face.
enum NinaText {
    case hero
    case display
    case screen
    case zero
    case title
    case section
    case body
    case label
    case caption
    case meta
    case micro
    case eyebrow

    fileprivate var isDisplay: Bool {
        switch self {
        case .hero, .display, .screen, .zero, .title, .section: true
        default: false
        }
    }

    fileprivate var size: CGFloat {
        switch self {
        case .hero: 44
        case .display: 34
        case .screen: 31
        case .zero: 29
        case .title: 22
        case .section: 19
        case .body: 17
        case .label: 15
        case .caption: 14
        case .meta: 13
        case .micro: 12
        case .eyebrow: 12
        }
    }

    fileprivate var leading: CGFloat {
        switch self {
        case .hero: 50
        case .display: 40
        case .screen: 37
        case .zero: 36
        case .title: 29
        case .section: 25
        case .body: 25
        case .label: 22
        case .caption: 21
        case .meta: 19
        case .micro: 17
        case .eyebrow: 16
        }
    }

    fileprivate var tracking: CGFloat {
        switch self {
        case .hero, .display, .screen, .zero: -0.5
        case .title, .section: -0.2
        case .eyebrow: 1.1
        default: -0.1
        }
    }
}

private struct NinaTextModifier: ViewModifier {
    let style: NinaText
    let color: Color
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content
            .font(
                style.isDisplay
                    ? .custom("Fraunces", size: style.size)
                    : .system(size: style.size, weight: weight)
            )
            .tracking(style.tracking)
            .lineSpacing(style.leading - style.size)
            .foregroundStyle(color)
            .textCase(style == .eyebrow ? .uppercase : nil)
    }
}

extension View {
    func ninaText(
        _ style: NinaText,
        _ color: Color = NinaTheme.ink,
        weight: Font.Weight = .regular
    ) -> some View {
        modifier(NinaTextModifier(style: style, color: color, weight: weight))
    }

    func ninaScreenBackground() -> some View {
        background(NinaTheme.ground.ignoresSafeArea())
    }

    func ninaSheetBackground() -> some View {
        background(NinaTheme.ground.ignoresSafeArea())
    }

    func cardShadow() -> some View {
        shadow(color: NinaTheme.shadow, radius: 14, x: 0, y: 6)
    }

    // Every surface in the system is a stroked card on the glaze, never a fill.
    func ninaCard(
        radius: CGFloat = NinaTheme.Radius.card,
        fill: Color = NinaTheme.ground,
        stroke: Color = NinaTheme.line
    ) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
    }
}

// The raw values are wire values on synced rows, so the case names outlive the
// hues they were originally named for. Members are told apart by initials and
// weight, never by colour: colour is spent on lateness alone.
extension MemberTone {
    var fill: Color {
        switch self {
        case .mint: NinaTheme.ink
        case .coral: Color(hex: 0x3A4553)
        case .sky: Color(hex: 0x5C6675)
        case .amber: Color(hex: 0x8A94A3)
        case .lavender: Color(hex: 0xB4BDC9)
        }
    }

    var onFill: Color {
        switch self {
        case .mint, .coral, .sky: NinaTheme.ground
        case .amber, .lavender: NinaTheme.ink
        }
    }
}
