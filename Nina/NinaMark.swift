import SwiftUI

// How present Nina is. Every state is a position or a fill, never an expression —
// she has no face, because a face watching a household is the thing this product
// refuses. Three of these must survive a screenshot, a notification and
// reduceMotion; listening and stored are transient and live in the movement.
enum NinaPresence {
    case rest
    case listening
    case reading
    case waiting
    case stored
    case unavailable
}

// The mark: an open cup holding a single disc it never closes over. The floor gap
// is the critical dimension — holding requires not gripping — and it is the one
// value that grows, proportionally, as the mark shrinks.
struct NinaMark: View {
    var size: CGFloat
    var presence: NinaPresence = .rest
    var tint: Color = NinaTheme.cobalt
    var label: String?
    // Each change lifts the disc and lets it fall back into the cup; the rest position never moves.
    var hops: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasSettled = false
    @State private var isBreathing = false

    // Below this the cup is unresolvable and the disc ships alone. Its own
    // ancestor is the degradation path, so nothing ever looks broken.
    private static let retirementFloor: CGFloat = 18
    // Two masters, differing by measurement rather than by eye.
    private static let smallMaster: CGFloat = 34

    private var metrics: Metrics {
        size < Self.smallMaster ? .small : .large
    }

    private struct Metrics {
        let centerY: CGFloat
        let radius: CGFloat
        let band: CGFloat
        let discRadius: CGFloat
        let restY: CGFloat

        static let large = Metrics(
            centerY: 23.8 / 64, radius: 22.5 / 64, band: 10 / 64,
            discRadius: 8.4 / 64, restY: 27.8 / 64
        )
        static let small = Metrics(
            centerY: 9.0 / 24, radius: 8.2 / 24, band: 4.0 / 24,
            discRadius: 2.7 / 24, restY: 10.5 / 24
        )
    }

    private var discCenterY: CGFloat {
        let m = metrics
        switch presence {
        case .rest, .unavailable, .reading: return m.restY
        case .stored: return arrives && !hasSettled ? m.restY - (10.2 / 64) : m.restY
        case .listening: return m.restY - (2.2 / 64)
        case .waiting: return m.restY - (10.2 / 64)
        }
    }

    // Something put away arrives from above and settles: the drop is movement on top of the stored position, never instead of it.
    private var arrives: Bool {
        presence == .stored && !reduceMotion && size >= Self.retirementFloor
    }

    private var readingWidth: CGFloat {
        guard presence == .reading, !reduceMotion else { return 1.29 }
        return isBreathing ? 1.45 : 1.15
    }

    private var discTint: Color {
        switch presence {
        case .stored: NinaTheme.moss
        case .unavailable: NinaTheme.muted
        default: tint
        }
    }

    private var cupTint: Color {
        presence == .unavailable ? NinaTheme.muted : tint
    }

    var body: some View {
        Group {
            if size < Self.retirementFloor {
                Circle()
                    .fill(discTint)
                    .frame(width: size * 0.7, height: size * 0.7)
            } else {
                ZStack {
                    cup
                    held
                        .keyframeAnimator(initialValue: CGFloat.zero, trigger: hops) { disc, lift in
                            disc.offset(y: reduceMotion ? 0 : -lift * size)
                        } keyframes: { _ in
                            CubicKeyframe(0.16, duration: 0.16)
                            SpringKeyframe(0, duration: 0.5, spring: Spring(response: 0.4, dampingRatio: 0.5))
                        }
                }
            }
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.7), value: presence)
        .onAppear {
            if arrives, !hasSettled {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.5).delay(0.25)) {
                    hasSettled = true
                }
            }
            if presence == .reading, !reduceMotion {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
        }
        .accessibilityHidden(label == nil)
        .accessibilityLabel(label ?? "")
    }

    private var cup: some View {
        let m = metrics
        return Path { path in
            path.addArc(
                center: CGPoint(x: size / 2, y: m.centerY * size),
                radius: m.radius * size,
                startAngle: .degrees(-20),
                endAngle: .degrees(200),
                clockwise: false
            )
        }
        // Flattened to a filled outline: the mark ships as a shape, never as a
        // stroke, so nothing downstream can trim or spin it.
        .strokedPath(StrokeStyle(lineWidth: m.band * size, lineCap: .round))
        .fill(cupTint)
    }

    @ViewBuilder
    private var held: some View {
        let m = metrics
        let d = m.discRadius * size * 2
        if presence == .reading {
            Capsule()
                .fill(discTint)
                .frame(width: d * readingWidth, height: d)
                .position(x: size / 2, y: discCenterY * size)
        } else {
            Circle()
                .fill(discTint)
                .frame(width: d, height: d)
                .position(x: size / 2, y: discCenterY * size)
        }
    }
}

// The mark beside her name. Never stacked: stacked, the cup contains the word and
// the claim becomes that she holds your name.
struct NinaWordmark: View {
    var size: CGFloat = 28

    var body: some View {
        // The lockup never shows the retired disc. Below the floor the mark is
        // unresolvable on its own, but beside the word it still reads — and a
        // brand signature that degrades to a dot is not a signature.
        HStack(spacing: size * 0.42) {
            NinaMark(size: max(size * 1.15, 20))
            Text("Nina").ninaText(.title)
        }
    }
}
