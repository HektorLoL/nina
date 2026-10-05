import SwiftUI

// Kids mode changes only how a minor's own tasks look; what the server sends a minor and what a minor may do stay the same.
enum KidsMode {
    static let overrideKey = "nina.kidsMode.override"

    enum Override: String {
        case on
        case off
    }

    static func isOn(band: MinorBand?, override rawOverride: String) -> Bool {
        switch Override(rawValue: rawOverride) {
        case .on: true
        case .off: false
        case nil: band == .under12
        }
    }

    struct Tile: Equatable {
        let background: Color
        let foreground: Color
        let symbolName: String
    }

    static func tile(for symbolName: String) -> Tile {
        let base = symbolName.replacingOccurrences(of: ".fill", with: "")
        switch base {
        case "house":
            return Tile(background: NinaTheme.Kids.sun, foreground: NinaTheme.ink, symbolName: "house.fill")
        case "backpack":
            return Tile(background: NinaTheme.Kids.sky, foreground: .white, symbolName: "backpack.fill")
        case "cross.case":
            return Tile(background: NinaTheme.Kids.coral, foreground: .white, symbolName: "cross.case.fill")
        case "pawprint":
            return Tile(background: NinaTheme.Kids.grape, foreground: .white, symbolName: "pawprint.fill")
        case "fork.knife":
            return Tile(background: NinaTheme.Kids.tangerine, foreground: .white, symbolName: "fork.knife")
        case "heart":
            return Tile(background: NinaTheme.Kids.bubble, foreground: .white, symbolName: "heart.fill")
        case "creditcard":
            return Tile(background: NinaTheme.Kids.leaf, foreground: .white, symbolName: "creditcard.fill")
        default:
            return Tile(background: NinaTheme.Kids.leaf, foreground: .white, symbolName: "star.fill")
        }
    }

    static func progressLine(done: Int, total: Int) -> String {
        "\(done) de \(total) feitas"
    }

    static func greeting(firstName: String) -> String {
        let name = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Oi" : "Oi, \(name)"
    }
}

struct KidsHomeContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let firstName: String
    let syncError: String?
    let todayRows: [ChildDayRow]
    let upcoming: [KidsUpcomingItem]
    let onTapToday: (TaskItem.ID) -> Void
    let onTapUpcoming: (TaskItem.ID) -> Void

    private var doneCount: Int {
        todayRows.count(where: \.isDone)
    }

    private var isAllDone: Bool {
        !todayRows.isEmpty && todayRows.allSatisfy(\.isDone)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            if let syncError {
                Text(syncError)
                    .ninaText(.caption, NinaTheme.ink, weight: .medium)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if todayRows.isEmpty && upcoming.isEmpty {
                ZeroState(
                    headline: "Nada para hoje.",
                    body_: "Quando combinarem uma tarefa, ela aparece aqui."
                )
                .padding(.top, 24)
            } else {
                if !todayRows.isEmpty {
                    VStack(spacing: 14) {
                        ForEach(todayRows) { row in
                            KidsTaskCard(row: row) { onTapToday(row.id) }
                        }
                    }
                }

                if isAllDone {
                    KidsCelebration()
                        .transition(reduceMotion ? .identity : .scale(scale: 0.9).combined(with: .opacity))
                }

                if !upcoming.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Próximos dias")
                        ForEach(upcoming) { item in
                            KidsUpcomingRow(item: item) { onTapUpcoming(item.id) }
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: isAllDone)
        .onChange(of: isAllDone) { _, done in
            guard done else { return }
            AccessibilityNotification.Announcement("Tudo feito por hoje.").post()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(KidsMode.greeting(firstName: firstName))
                .ninaText(.display)
                .accessibilityAddTraits(.isHeader)

            if !todayRows.isEmpty {
                HStack(spacing: 10) {
                    KidsStars(done: doneCount, total: todayRows.count)
                    Text(KidsMode.progressLine(done: doneCount, total: todayRows.count))
                        .ninaText(.label, NinaTheme.muted, weight: .semibold)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(KidsMode.progressLine(done: doneCount, total: todayRows.count))
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            KidsShapes()
                .frame(width: 150, height: 110)
                .offset(x: 6, y: -6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

struct KidsUpcomingItem: Identifiable, Hashable {
    let id: TaskItem.ID
    let title: String
    let time: String?
    let symbolName: String
    let isDone: Bool
    let canToggle: Bool
}

struct KidsTaskCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let row: ChildDayRow
    let action: () -> Void

    @State private var burst = 0

    var body: some View {
        let tile = KidsMode.tile(for: row.symbolName)
        Button(action: action) {
            HStack(spacing: 14) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: tile.symbolName)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(tile.foreground)
                        .frame(width: 60, height: 60)
                        .background(tile.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .opacity(row.isDone ? 0.45 : 1)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(row.title)
                        .ninaText(.kids, row.isDone ? NinaTheme.muted : NinaTheme.ink, weight: .bold)
                        .strikethrough(row.isDone, color: NinaTheme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let time = row.time {
                        Label(time, systemImage: "clock.fill")
                            .ninaText(.caption, NinaTheme.ink, weight: .semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(NinaTheme.Kids.sunWash, in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                KidsCheck(isOn: row.isDone)
                    .overlay {
                        if !reduceMotion {
                            KidsConfetti(trigger: burst)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(
                row.isDone ? NinaTheme.grout : NinaTheme.ground,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(row.isDone ? Color.clear : tile.background.opacity(0.55), lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(row.state == .doneElsewhere)
        .opacity(row.state == .doneElsewhere ? 0.6 : 1)
        .onChange(of: row.isDone) { wasDone, isDone in
            if isDone, !wasDone { burst += 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.time.map { "\(row.title), \($0)" } ?? row.title)
        .accessibilityValue(row.isDone ? "Feita" : "Por fazer")
        .accessibilityAddTraits(.isButton)
    }
}

private struct KidsUpcomingRow: View {
    let item: KidsUpcomingItem
    let action: () -> Void

    var body: some View {
        let tile = KidsMode.tile(for: item.symbolName)
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tile.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tile.foreground)
                    .frame(width: 40, height: 40)
                    .background(tile.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .opacity(item.isDone ? 0.45 : 1)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .ninaText(.body, item.isDone ? NinaTheme.muted : NinaTheme.ink, weight: .semibold)
                        .strikethrough(item.isDone, color: NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let time = item.time {
                        Text(time).ninaText(.caption, NinaTheme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                KidsCheck(isOn: item.isDone, size: 32)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.canToggle)
        .opacity(item.canToggle ? 1 : 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.time.map { "\(item.title), \($0)" } ?? item.title)
        .accessibilityValue(item.isDone ? "Feita" : "Por fazer")
        .accessibilityAddTraits(.isButton)
    }
}

private struct KidsCheck: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var isOn: Bool
    var size: CGFloat = 46

    @State private var pop: CGFloat = 1

    var body: some View {
        ZStack {
            Circle()
                .fill(isOn ? NinaTheme.Kids.leaf : Color.clear)
            Circle()
                .strokeBorder(isOn ? NinaTheme.Kids.leaf : NinaTheme.control, lineWidth: 2.5)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.42, weight: .heavy))
                    .foregroundStyle(.white)
                    .transition(reduceMotion ? .identity : .scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(pop)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: isOn)
        .onChange(of: isOn) { wasOn, nowOn in
            guard nowOn, !wasOn, !reduceMotion else { return }
            pop = 1.25
            withAnimation(.spring(response: 0.35, dampingFraction: 0.4)) {
                pop = 1
            }
        }
    }
}

private struct KidsStars: View {
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0 ..< min(total, 8), id: \.self) { index in
                Image(systemName: index < done ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(index < done ? NinaTheme.Kids.sun : NinaTheme.control)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
    }
}

private struct KidsCelebration: View {
    var body: some View {
        VStack(spacing: 12) {
            KidsShapes(isCelebrating: true)
                .frame(width: 180, height: 110)
                .accessibilityHidden(true)
            Text("Tudo feito por hoje.")
                .ninaText(.zero)
                .multilineTextAlignment(.center)
            Text("Muito bem.")
                .ninaText(.label, NinaTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(NinaTheme.Kids.sunWash, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

// Decoration only: a few flat shapes in the kids palette, never a face and never a character.
private struct KidsShapes: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var isCelebrating = false

    @State private var isFloating = false

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Circle()
                    .fill(NinaTheme.Kids.sun.opacity(isCelebrating ? 1 : 0.55))
                    .frame(width: h * 0.42, height: h * 0.42)
                    .position(x: w * 0.78, y: h * 0.32 + drift(-4))
                Image(systemName: "star.fill")
                    .font(.system(size: h * 0.26))
                    .foregroundStyle(NinaTheme.Kids.sky.opacity(isCelebrating ? 1 : 0.5))
                    .rotationEffect(.degrees(isFloating && !reduceMotion ? 12 : -8))
                    .position(x: w * 0.42, y: h * 0.28 + drift(3))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(NinaTheme.Kids.coral.opacity(isCelebrating ? 1 : 0.45))
                    .frame(width: h * 0.2, height: h * 0.2)
                    .rotationEffect(.degrees(20))
                    .position(x: w * 0.6, y: h * 0.72 + drift(-3))
                Capsule()
                    .fill(NinaTheme.Kids.leaf.opacity(isCelebrating ? 1 : 0.45))
                    .frame(width: h * 0.32, height: h * 0.13)
                    .rotationEffect(.degrees(-25))
                    .position(x: w * 0.2, y: h * 0.62 + drift(4))
                Circle()
                    .fill(NinaTheme.Kids.grape.opacity(isCelebrating ? 1 : 0.45))
                    .frame(width: h * 0.13, height: h * 0.13)
                    .position(x: w * 0.92, y: h * 0.78 + drift(-2))
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                isFloating = true
            }
        }
    }

    private func drift(_ amount: CGFloat) -> CGFloat {
        isFloating && !reduceMotion ? amount : 0
    }
}

private struct KidsConfetti: View {
    let trigger: Int

    @State private var progress: CGFloat = 1

    private static let pieces: [(angle: Double, distance: CGFloat, size: CGFloat, spin: Double)] = (0 ..< 14).map { index in
        let angle = Double(index) / 14 * 2 * .pi + (index.isMultiple(of: 2) ? 0.2 : -0.15)
        let distance: CGFloat = index.isMultiple(of: 3) ? 58 : 44
        let size: CGFloat = index.isMultiple(of: 4) ? 9 : 7
        return (angle, distance, size, Double(index * 47 % 360))
    }

    var body: some View {
        ZStack {
            ForEach(Array(Self.pieces.enumerated()), id: \.offset) { index, piece in
                confettiPiece(index: index, size: piece.size)
                    .rotationEffect(.degrees(piece.spin * Double(progress)))
                    .offset(
                        x: cos(piece.angle) * piece.distance * progress,
                        y: sin(piece.angle) * piece.distance * progress + 18 * progress * progress
                    )
                    .opacity(progress >= 1 ? 0 : 1 - Double(progress) * 0.8)
            }
        }
        .onChange(of: trigger) { _, _ in
            progress = 0
            withAnimation(.easeOut(duration: 0.85)) {
                progress = 1
            }
        }
    }

    @ViewBuilder
    private func confettiPiece(index: Int, size: CGFloat) -> some View {
        let color = NinaTheme.Kids.confetti[index % NinaTheme.Kids.confetti.count]
        switch index % 3 {
        case 0:
            Circle().fill(color).frame(width: size, height: size)
        case 1:
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: size, height: size * 0.6)
        default:
            Image(systemName: "star.fill").font(.system(size: size + 2)).foregroundStyle(color)
        }
    }
}
