import SwiftUI

// Nothing in this file knows about a screen. A component that needs to know which
// screen it is on belongs on that screen instead.

struct Eyebrow: View {
    var text: String

    var body: some View {
        Text(text).ninaText(.eyebrow, NinaTheme.faint, weight: .bold)
    }
}

// A mark, not a control: it names a state the house is in, so it takes the wash and
// never competes with the screen's one cobalt control.
struct PremiumBadge: View {
    var body: some View {
        Text("Premium")
            .ninaText(.eyebrow, NinaTheme.cobalt, weight: .bold)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(NinaTheme.cobaltWash, in: Capsule())
            .accessibilityLabel("Premium ativo na casa")
    }
}

struct CategoryGlyph: View {
    var systemName: String
    var size: CGFloat = 20
    var tint: Color = NinaTheme.ink

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: size + 4, height: size + 4)
    }
}

struct MemberAvatar: View {
    var initials: String
    var tone: MemberTone
    var size: CGFloat = 40
    var isAssistant: Bool = false

    var body: some View {
        if isAssistant {
            NinaMark(size: size)
        } else {
            Circle()
                .fill(tone.fill)
                .frame(width: size, height: size)
                .overlay(
                    Text(initials)
                        .font(.system(size: size * 0.42, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(tone.onFill)
                )
        }
    }
}

// Circles carry things with an owner and a moment. Squares carry stock.
struct NinaCheckbox: View {
    var isOn: Bool
    var isOverdue: Bool = false
    var isSquare: Bool = false
    var size: CGFloat = 24

    private var stroke: Color {
        isOverdue ? NinaTheme.terracotta : NinaTheme.control
    }

    var body: some View {
        ZStack {
            if isSquare {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isOn ? NinaTheme.moss : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(isOn ? NinaTheme.moss : stroke, lineWidth: 1.6)
                    )
            } else {
                Circle()
                    .fill(isOn ? NinaTheme.moss : Color.clear)
                    .overlay(Circle().strokeBorder(isOn ? NinaTheme.moss : stroke, lineWidth: 1.6))
            }

            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(NinaTheme.ground)
            }
        }
        .frame(width: size, height: size)
    }
}

struct NinaChip: View {
    var text: String
    var isSet: Bool = false
    var systemName: String?
    var isDisabled: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(text)
                .ninaText(.caption, isSet ? NinaTheme.ink : NinaTheme.muted, weight: isSet ? .semibold : .medium)
        }
        // Selection is weight, not cobalt: cobalt stays with the screen's one commit,
        // and an unset chip is a control, so its edge uses the control stroke.
        .foregroundStyle(isSet ? NinaTheme.ink : NinaTheme.muted)
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background(
            isSet ? NinaTheme.grout : Color.clear,
            in: Capsule()
        )
        .overlay(
            Capsule().strokeBorder(isSet ? NinaTheme.ink : NinaTheme.control, lineWidth: 1)
        )
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityAddTraits(isSet ? .isSelected : [])
    }
}

enum NinaButtonKind {
    case primary
    case outline
    case quiet
}

struct NinaButton: View {
    var title: String
    var kind: NinaButtonKind = .primary
    var systemName: String?
    var fillsWidth: Bool = false
    var isEnabled: Bool = true
    // Pending is not disabled: the label stays legible while the work happens.
    var isPending: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            NinaButtonFace(
                title: title,
                kind: kind,
                systemName: systemName,
                fillsWidth: fillsWidth,
                isPending: isPending
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isPending)
        .opacity(isEnabled || isPending ? 1 : 0.4)
    }
}

struct NinaButtonFace: View {
    var title: String
    var kind: NinaButtonKind = .primary
    var systemName: String?
    var fillsWidth: Bool = false
    var isPending: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if isPending {
                ProgressView()
                    .controlSize(.small)
                    .tint(foreground)
            } else if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
            }
            Text(title)
                .ninaText(.body, foreground, weight: .semibold)
        }
        .foregroundStyle(foreground)
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .frame(minHeight: kind == .quiet ? 26 : 50)
        .padding(.horizontal, kind == .quiet ? 0 : 24)
        .background(background, in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
                .strokeBorder(kind == .outline ? NinaTheme.control : Color.clear, lineWidth: 1)
        )
        // A quiet button keeps its 26pt look but answers to a 44pt finger.
        .padding(.vertical, kind == .quiet ? 9 : 0)
        .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch kind {
        case .primary: NinaTheme.onCobalt
        case .outline: NinaTheme.ink
        case .quiet: NinaTheme.muted
        }
    }

    private var background: Color {
        switch kind {
        case .primary: NinaTheme.cobalt
        case .outline, .quiet: Color.clear
        }
    }
}

// The zero-state shape every empty screen composes. The mark is drawn as the cup
// alone, holding nothing — the literal state of the house, not a pose.
struct ZeroState<Actions: View>: View {
    var headline: String
    var body_: String
    var showsMark: Bool = true
    var presence: NinaPresence = .rest
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 12) {
            if showsMark {
                NinaMark(size: 100, presence: presence)
                    .padding(.bottom, 2)
            }
            Text(headline)
                .ninaText(.zero)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
            if !body_.isEmpty {
                Text(body_)
                    .ninaText(.label, NinaTheme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 306)
            }
            actions.padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }
}

extension ZeroState where Actions == EmptyView {
    init(headline: String, body_: String, showsMark: Bool = true, presence: NinaPresence = .rest) {
        self.init(headline: headline, body_: body_, showsMark: showsMark, presence: presence) {
            EmptyView()
        }
    }
}

// A row's geometry is fixed so repeated rows share vertical lanes: a leading slot
// that is always the same width, then title/subtitle, then a trailing slot.
struct NinaRow<Leading: View, Trailing: View>: View {
    var title: String
    var subtitle: String?
    var titleColor: Color = NinaTheme.ink
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            leading.frame(width: 40, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .ninaText(.body, titleColor, weight: .medium)
                if let subtitle {
                    Text(subtitle).ninaText(.caption, NinaTheme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .frame(minHeight: 56)
    }
}

struct NinaDivider: View {
    var inset: CGFloat = 52

    var body: some View {
        Rectangle()
            .fill(NinaTheme.line)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

// A household that already pays is never sold to again, so the active copy is
// its own string and never the paywall's selling line with a badge on it.
enum PremiumTeaserCopy {
    static let activeTitle = "Premium ativo na casa."
    static let activeSubtitle = "Vale para a casa toda."
}

// Premium is named where the resource is spent, never as a nag. Every gate says
// which of the three ceilings it is, and routes.
struct PremiumGateCard: View {
    var title: String
    var detail: String
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NinaTheme.cobalt)
                    .accessibilityHidden(true)
                Text(detail)
                    .ninaText(.label, NinaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            NinaButton(title: title, fillsWidth: true, action: action)
                .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard()
    }
}
