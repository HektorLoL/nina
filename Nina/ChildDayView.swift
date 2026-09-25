import SwiftUI
import UIKit

struct ChildTodaySection: View {
    @Environment(AppStore.self) private var store

    let member: HouseholdMember

    @State private var didFailToPrint = false

    var body: some View {
        let now = Date.now
        let dayTasks = ChildDay.tasks(
            for: member,
            in: store.tasks,
            members: store.familyGroup.members,
            now: now
        )
        let rows = ChildDay.rows(for: dayTasks, now: now)
        let name = ChildDay.displayName(for: member, among: store.familyGroup.members)
        let dateLine = ChildDay.dateLine(for: now)

        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: dayTasks.isEmpty ? "Hoje" : "Hoje · \(dayTasks.count)")

            if dayTasks.isEmpty {
                Text("Nada para hoje.")
                    .ninaText(.label, NinaTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(dayTasks) { task in
                        TaskRowView(task: task)
                        if task.id != dayTasks.last?.id {
                            NinaDivider(inset: 36)
                        }
                    }
                }

                NinaButton(title: "Mostrar para \(name)", fillsWidth: true) {
                    Haptics.lightImpact()
                    store.presentChildDay(for: member)
                }
                .padding(.top, 4)

                ViewThatFits(in: .horizontal) {
                    EqualWidthRow(spacing: 12) {
                        printControl(name: name, dateLine: dateLine, rows: rows)
                        shareControl(name: name, dateLine: dateLine, rows: rows)
                    }
                    VStack(spacing: 12) {
                        printControl(name: name, dateLine: dateLine, rows: rows)
                        shareControl(name: name, dateLine: dateLine, rows: rows)
                    }
                }

                if didFailToPrint {
                    Text("Não deu para imprimir agora.")
                        .ninaText(.caption, NinaTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func printControl(name: String, dateLine: String, rows: [ChildDayRow]) -> some View {
        if ChildDayPrinting.isAvailable {
            NinaButton(title: "Imprimir", kind: .outline, systemName: "printer", fillsWidth: true) {
                Haptics.lightImpact()
                let document = ChildDayPrinting.document(name: name, dateLine: dateLine, rows: rows)
                let jobName = ChildDay.heading(name: name, dateLine: dateLine)
                let didPresent = document.map { ChildDayPrinting.present($0, jobName: jobName) } ?? false
                didFailToPrint = !didPresent
                if !didPresent {
                    AccessibilityNotification.Announcement("Não deu para imprimir agora.").post()
                }
            }
        }
    }

    private func shareControl(name: String, dateLine: String, rows: [ChildDayRow]) -> some View {
        ShareLink(
            item: ChildDay.shareText(name: name, dateLine: dateLine, rows: rows),
            subject: Text(ChildDay.heading(name: name, dateLine: dateLine))
        ) {
            NinaButtonFace(
                title: "Compartilhar",
                kind: .outline,
                systemName: "square.and.arrow.up",
                fillsWidth: true
            )
        }
        .buttonStyle(.plain)
    }
}

// Side by side only when every label fits at an equal width, so no label ever wraps mid-word.
private struct EqualWidthRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let gaps = spacing * CGFloat(subviews.count - 1)
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let width = proposal.width ?? widest * CGFloat(subviews.count) + gaps
        let column = max((width - gaps) / CGFloat(subviews.count), 0)
        let height = subviews
            .map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let gaps = spacing * CGFloat(subviews.count - 1)
        let column = max((bounds.width - gaps) / CGFloat(subviews.count), 0)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + CGFloat(index) * (column + spacing), y: bounds.minY),
                proposal: ProposedViewSize(width: column, height: bounds.height)
            )
        }
    }
}

// Leaving takes a held press, never a tap: the phone is in a child's hands.
struct ChildDayView: View {
    private static let allDoneID = "allDone"

    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let childID: HouseholdMember.ID

    @State private var session: ChildDaySession
    @State private var isCoveredForPrivacy = false
    @State private var unseenSyncError: String?

    init(childID: HouseholdMember.ID, session: ChildDaySession) {
        self.childID = childID
        _session = State(initialValue: session)
    }

    private var child: HouseholdMember? {
        store.familyGroup.members.first { $0.id == childID }
    }

    var body: some View {
        let now = Date.now
        let rows = child.map {
            session.rows(child: $0, tasks: store.tasks, members: store.familyGroup.members, now: now)
        } ?? []
        let isAllDone = !rows.isEmpty && rows.allSatisfy(\.isDone)

        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                HoldToLeaveButton(action: leave)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)

            GeometryReader { proxy in
                ScrollViewReader { scroller in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            header(now)

                            if rows.isEmpty {
                                ZeroState(headline: "Nada para hoje.", body_: "Pode devolver o celular.")
                                    .centeredBelowHeader(minimumGap: 40)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(rows) { row in
                                        ChildDayCard(row: row) { tap(row) }
                                    }
                                }

                                if isAllDone {
                                    ZeroState(
                                        headline: "Tudo feito por hoje.",
                                        body_: "Pode devolver o celular.",
                                        presence: .stored
                                    )
                                    .padding(.top, 16)
                                    .transition(reduceMotion ? .identity : .opacity)
                                    .id(Self.allDoneID)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                        .frame(minHeight: rows.isEmpty ? proxy.size.height : nil, alignment: .top)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: isAllDone) { _, done in
                        guard done else { return }
                        AccessibilityNotification.Announcement("Tudo feito por hoje.").post()
                        Task {
                            await Task.yield()
                            if reduceMotion {
                                scroller.scrollTo(Self.allDoneID, anchor: .bottom)
                            } else {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    scroller.scrollTo(Self.allDoneID, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
        }
        .ninaScreenBackground()
        .overlay {
            // The root app-switcher cover sits under every full-screen cover, so this list draws its own.
            if isCoveredForPrivacy {
                AppLoadingScreen()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
        .accessibilityAction(.escape) { leave() }
        .onChange(of: store.tasks) { _, _ in absorb() }
        .onChange(of: scenePhase) { _, phase in
            isCoveredForPrivacy = phase != .active
            if phase == .active { absorb() }
        }
        // A write that fails while the child holds the phone is told to the adult who takes it back.
        .onChange(of: store.syncErrorMessage) { _, message in
            if let message { unseenSyncError = message }
        }
    }

    private func header(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: ChildDay.dateLine(for: now))

            HStack(spacing: 12) {
                if !dynamicTypeSize.isAccessibilitySize, let child {
                    MemberAvatar(initials: child.name.ninaInitials, tone: child.tone, size: 44)
                        .accessibilityHidden(true)
                }
                Text(child.map { ChildDay.displayName(for: $0, among: store.familyGroup.members) } ?? "")
                    .ninaText(.display)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    private func tap(_ row: ChildDayRow) {
        let now = Date.now
        let animation: Animation? = reduceMotion ? nil : .easeOut(duration: 0.2)
        switch session.tap(on: row.id, tasks: store.tasks, now: now) {
        case .ignore:
            return
        case .markDone(let id):
            withAnimation(animation) {
                guard let mark = store.markChildTaskDone(id, now: now) else { return }
                session.record(mark)
                Haptics.success()
            }
        case .reopen(let mark):
            withAnimation(animation) {
                guard store.reopenChildTask(mark) else { return }
                session.release(mark.written.id, at: now)
                Haptics.selection()
            }
        }
    }

    private func leave() {
        if let unseenSyncError {
            store.reportSyncError(unseenSyncError)
        } else {
            Haptics.selection()
        }
        store.dismissChildDay()
    }

    private func absorb() {
        guard let child else { return }
        session.absorb(child: child, tasks: store.tasks, members: store.familyGroup.members, now: .now)
    }
}

private struct ChildDayCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let row: ChildDayRow
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                NinaCheckbox(isOn: row.isDone, size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title)
                        .ninaText(.compose, row.isDone ? NinaTheme.muted : NinaTheme.ink, weight: .semibold)
                        .strikethrough(row.isDone, color: NinaTheme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let time = row.time {
                        Text(time).ninaText(.body, NinaTheme.muted, weight: .medium)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !dynamicTypeSize.isAccessibilitySize {
                    CategoryGlyph(systemName: row.symbolName, size: 26, tint: NinaTheme.muted)
                        .accessibilityHidden(true)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .ninaCard(
                fill: row.isDone ? NinaTheme.grout : NinaTheme.ground,
                stroke: row.isDone ? .clear : NinaTheme.line
            )
            .contentShape(RoundedRectangle(cornerRadius: NinaTheme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(row.state == .doneElsewhere)
        .opacity(row.state == .doneElsewhere ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.time.map { "\(row.title), \($0)" } ?? row.title)
        .accessibilityValue(row.isDone ? "Feita" : "")
        .accessibilityAddTraits(.isButton)
    }
}

private struct HoldToLeaveButton: View {
    static let holdDuration: Double = 2

    let action: () -> Void

    @State private var progress: CGFloat = 0

    // The ring is the hold's only feedback and moves only under the finger, so Reduce Motion keeps it.
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(NinaTheme.line, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(NinaTheme.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)

            Text("Segure para sair").ninaText(.caption, NinaTheme.ink, weight: .semibold)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .overlay(Capsule().strokeBorder(NinaTheme.control, lineWidth: 1))
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: Self.holdDuration, maximumDistance: 40) {
            progress = 0
            action()
        } onPressingChanged: { isPressing in
            withAnimation(isPressing ? .linear(duration: Self.holdDuration) : .easeOut(duration: 0.2)) {
                progress = isPressing ? 1 : 0
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sair")
        .accessibilityInputLabels(["Sair", "Segure para sair"])
        .accessibilityAddTraits(.isButton)
        // VoiceOver and Switch Control cannot perform the hold, so they leave in one step.
        .accessibilityAction { action() }
    }
}

@MainActor
enum ChildDayPrinting {
    static let pageSize = CGSize(width: 595.28, height: 841.89)
    static var isAvailable: Bool { UIPrintInteractionController.isPrintingAvailable }

    static func document(name: String, dateLine: String, rows: [ChildDayRow]) -> Data? {
        let pages = ChildDay.pages(rows)
        guard !pages.isEmpty else { return nil }
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        for (index, pageRows) in pages.enumerated() {
            let renderer = ImageRenderer(
                content: ChildDayPrintPage(
                    name: name,
                    dateLine: dateLine,
                    rows: pageRows,
                    pageNumber: index + 1,
                    pageCount: pages.count
                )
            )
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data as Data
    }

    static func present(_ document: Data, jobName: String) -> Bool {
        let info = UIPrintInfo.printInfo()
        info.outputType = .grayscale
        info.orientation = .portrait
        info.jobName = jobName
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = document
        return controller.present(animated: true) { controller, _, _ in
            controller.printingItem = nil
        }
    }
}

private struct ChildDayPrintPage: View {
    let name: String
    let dateLine: String
    let rows: [ChildDayRow]
    let pageNumber: Int
    let pageCount: Int

    // Paper has no Dynamic Type: fixed sizes keep ten rows on one A4 sheet whatever the phone reads at.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(dateLine.uppercased(with: Locale(identifier: "pt_BR")))
                .font(.system(size: 12, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(NinaTheme.faint)

            Text(name)
                .font(.custom("Fraunces", fixedSize: 44))
                .tracking(-0.5)
                .foregroundStyle(NinaTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 6)
                .padding(.bottom, 28)

            ForEach(rows) { row in
                hairline
                HStack(spacing: 16) {
                    Circle()
                        .strokeBorder(NinaTheme.ink, lineWidth: 1.5)
                        .frame(width: 26, height: 26)
                    Text(row.title)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(NinaTheme.ink)
                        .lineLimit(2)
                    Spacer(minLength: 12)
                    if let time = row.time {
                        Text(time)
                            .font(.system(size: 16))
                            .monospacedDigit()
                            .foregroundStyle(NinaTheme.muted)
                    }
                    Image(systemName: row.symbolName)
                        .font(.system(size: 17))
                        .foregroundStyle(NinaTheme.muted)
                        .frame(width: 24)
                }
                .frame(height: 56)
            }
            hairline

            Spacer(minLength: 0)

            HStack {
                NinaMark(size: 24)
                Spacer()
                if pageCount > 1 {
                    Text("\(pageNumber) de \(pageCount)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NinaTheme.muted)
                }
            }
        }
        .padding(56)
        .frame(
            width: ChildDayPrinting.pageSize.width,
            height: ChildDayPrinting.pageSize.height,
            alignment: .topLeading
        )
    }

    private var hairline: some View {
        Rectangle()
            .fill(NinaTheme.control)
            .frame(height: 0.75)
    }
}
