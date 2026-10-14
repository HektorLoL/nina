import SwiftUI

// The tour reads no AppStore, so nothing it shows can reach the house.
struct OnboardingTutorialView: View {
    let context: TourContext
    let land: (AppTab) -> Void

    @Environment(AuthSessionStore.self) private var authSession
    @Environment(OnboardingStore.self) private var onboardingStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @State private var step: OnboardingTour.Step
    @State private var frozen: TourContext?
    @State private var sampleHouse: TourSample.House?
    @State private var phase: Int
    @State private var pillTab: AppTab?
    @State private var hop = 0
    @State private var stripHop = 0
    @State private var holdsFinalFrame: Bool
    @State private var hasExited = false
    @State private var scroll = ScrollPosition(edge: .top)
    @State private var stageHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var isScrolled = false
    @State private var flashes = 0
    @Namespace private var mapSpace
    @AccessibilityFocusState private var focusedLine: OnboardingTour.Step?

    init(
        context: TourContext,
        startingAt step: OnboardingTour.Step = .hello,
        onItsFinalFrame: Bool = false,
        land: @escaping (AppTab) -> Void
    ) {
        self.context = context
        self.land = land
        _step = State(initialValue: step)
        _phase = State(initialValue: onItsFinalFrame ? OnboardingTour.phaseCount(for: step) : 0)
        _pillTab = State(
            initialValue: onItsFinalFrame ? OnboardingTour.pillTab(for: step, context: context) : nil
        )
        _holdsFinalFrame = State(initialValue: onItsFinalFrame)
    }

    private var tour: TourContext {
        frozen ?? context
    }

    private var house: TourSample.House {
        sampleHouse ?? TourSample.house(for: tour, calendar: .current)
    }

    private var motionIsOff: Bool {
        reduceMotion || voiceOverEnabled
    }

    private var isLarge: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var strokesEdges: Bool {
        colorSchemeContrast == .increased
    }

    private static let fadeHeight: CGFloat = 32

    private var mapIsShown: Bool {
        step != .hello || reached(.map)
    }

    private func reached(_ moment: TourMoment) -> Bool {
        OnboardingTour.isReached(moment, on: step, phase: phase)
    }

    private var exampleDescription: String? {
        OnboardingTour.exampleDescription(for: step, context: tour, house: house)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { proxy in
                ScrollView {
                    stage(viewport: proxy.size.height)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            stageHeight = height
                        }
                }
                .scrollPosition($scroll)
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicatorsFlash(trigger: flashes)
                .onChange(of: proxy.size.height, initial: true) { _, height in
                    viewportHeight = height
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > 1
                } action: { _, scrolled in
                    isScrolled = scrolled
                }
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [NinaTheme.ground, NinaTheme.ground.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: Self.fadeHeight)
                    .opacity(isScrolled ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: isScrolled)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .ninaScreenBackground()
        .accessibilityAction(.escape) { escape() }
        .accessibilityAction(.magicTap) { advance() }
        .onAppear {
            guard frozen == nil else { return }
            frozen = context
            sampleHouse = TourSample.house(for: context, calendar: .current)
        }
        .task(id: step) {
            await play(step)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                demonstrationTag
                Spacer(minLength: 12)
                skipButton
            }

            VStack(alignment: .leading, spacing: 6) {
                demonstrationTag
                if step != .done {
                    skipButton
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var demonstrationTag: some View {
        Text(OnboardingTour.header)
            .ninaText(.eyebrow, NinaTheme.muted, weight: .bold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(minHeight: 24)
            .background(NinaTheme.grout, in: Capsule())
            .accessibilityAddTraits(.isHeader)
            .accessibilityShowsLargeContentViewer()
    }

    private var skipButton: some View {
        let title = OnboardingTour.skipTitle(isReplay: tour.isReplay)
        let label = OnboardingTour.skipLabel(isReplay: tour.isReplay)
        return NinaButton(title: title, kind: .quiet) {
            skip()
        }
        .accessibilityShowsLargeContentViewer {
            Text(title)
        }
        .accessibilityLabel(label)
        .accessibilityInputLabels([title, label])
        .opacity(step == .done ? 0 : 1)
        .disabled(step == .done)
        .accessibilityHidden(step == .done)
    }

    private func stage(viewport: CGFloat) -> some View {
        ZStack(alignment: .top) {
            if step.isCentred {
                centred(viewport: viewport)
                    .transition(centredTransition)
                    .id(step)
            } else {
                // Crossing between the centred closed line and a line over an example replaces the step, so the mark never glides.
                tabStep(viewport: viewport)
                    .transition(tabStepTransition)
                    .id(exampleDescription == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private func centred(viewport: CGFloat) -> some View {
        let line = OnboardingTour.line(for: step, context: tour)
        let markHasArrived = reached(.markArrives)
        let bubbleHasArrived = reached(.bubble)

        return VStack(spacing: 16) {
            NinaMark(
                size: isLarge ? 64 : 96,
                presence: reached(.markRests) ? .rest : .waiting,
                hops: hop
            )
            .opacity(markHasArrived ? 1 : 0)
            .scaleEffect(step == .done && !markHasArrived ? 0.6 : 1)

            speechBubble(OnboardingTour.drawnLine(for: step, context: tour), style: .title, fillsRow: false)
                .frame(maxWidth: isLarge ? .infinity : 320)
                .opacity(bubbleHasArrived ? 1 : 0)
                .offset(y: bubbleHasArrived ? 0 : 10)
                .scaleEffect(bubbleHasArrived ? 1 : 0.97, anchor: .top)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nina: \(line)")
        .accessibilityFocused($focusedLine, equals: step)
        .frame(maxWidth: .infinity, minHeight: max(viewport - 36, 0))
    }

    private func tabStep(viewport: CGFloat) -> some View {
        let description = exampleDescription

        return VStack(alignment: .leading, spacing: 16) {
            speechRow

            ZStack(alignment: .top) {
                if let description {
                    TourTray(description: description, strokesEdge: strokesEdges) {
                        example
                    }
                    .opacity(reached(.tray) ? 1 : 0)
                    .offset(y: reached(.tray) ? 0 : 12)
                    .transition(stepTransition)
                    .id(step)
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: description == nil ? max(viewport - 36, 0) : nil,
            alignment: description == nil ? .center : .top
        )
    }

    private var speechRow: some View {
        let line = OnboardingTour.line(for: step, context: tour)
        let bubbleHasArrived = reached(.bubble)
        let layout = isLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))

        return layout {
            NinaMark(size: isLarge ? 32 : 40, hops: hop)
                .padding(.top, isLarge ? 0 : 4)

            ZStack(alignment: .topLeading) {
                speechBubble(
                    OnboardingTour.drawnLine(for: step, context: tour),
                    style: .section,
                    fillsRow: true
                )
                    .opacity(bubbleHasArrived ? 1 : 0)
                    .offset(y: bubbleHasArrived ? 0 : 10)
                    .scaleEffect(bubbleHasArrived ? 1 : 0.97, anchor: .topLeading)
                    .transition(stepTransition)
                    .id(step)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nina: \(line)")
        .accessibilityFocused($focusedLine, equals: step)
    }

    private func speechBubble(_ line: String, style: NinaText, fillsRow: Bool) -> some View {
        Text(line)
            .ninaText(style, NinaTheme.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: fillsRow ? .infinity : nil, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                NinaTheme.cobaltWash,
                in: RoundedRectangle(cornerRadius: NinaTheme.Radius.card, style: .continuous)
            )
    }

    @ViewBuilder
    private var example: some View {
        let house = self.house
        switch step {
        case .nina:
            TourChatExample(
                proposalLabel: house.proposalLabel,
                showsMessage: reached(.said),
                showsMark: reached(.reading),
                isReading: reached(.reading) && !reached(.readingEnds),
                showsProposal: reached(.proposal),
                showsDisclaimer: reached(.disclaimer),
                slides: !motionIsOff
            )
        case .today:
            TourTodayExample(
                house: house,
                showsLate: reached(.firstRow),
                showsSecond: reached(.secondRow),
                showsThird: reached(.thirdRow),
                isWarm: reached(.late)
            )
        case .tasks:
            TourTasksExample(
                house: house,
                showsCategory: reached(.firstRow),
                showsLists: reached(.secondRow),
                showsSeed: reached(.seedPill),
                leafHasGrown: reached(.leaf)
            )
        case .house:
            TourHouseExample(
                house: house,
                stripHop: stripHop,
                showsStrip: reached(.strip),
                showsPortrait: reached(.portrait),
                filledBands: (reached(.firstBand) ? 1 : 0) + (reached(.secondBand) ? 1 : 0)
            )
        case .hello, .done:
            EmptyView()
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            NinaButton(
                title: OnboardingTour.advanceTitle(for: step, isReplay: tour.isReplay),
                fillsWidth: true
            ) {
                advance()
            }
            .accessibilityValue(OnboardingTour.progressValue(for: step))
            .accessibilityHint(OnboardingTour.advanceHint(for: step, context: tour) ?? "")
            .padding(.horizontal, 20)

            TourTabMap(
                selected: pillTab,
                marksSelection: step != .done,
                hint: OnboardingTour.mapHint(on: step),
                namespace: mapSpace,
                slides: !motionIsOff,
                strokesPill: strokesEdges,
                select: tapMap(_:)
            )
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .opacity(mapIsShown ? 1 : 0)
            .allowsHitTesting(mapIsShown)
            .accessibilityHidden(!mapIsShown)
        }
        .padding(.top, 10)
        .background(NinaTheme.ground.ignoresSafeArea(edges: .bottom))
        .background(alignment: .top) {
            LinearGradient(
                colors: [NinaTheme.ground.opacity(0), NinaTheme.ground],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Self.fadeHeight)
            .offset(y: -Self.fadeHeight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var stepTransition: AnyTransition {
        motionIsOff
            ? .opacity
            : .asymmetric(insertion: .identity, removal: .opacity.combined(with: .offset(y: -8)))
    }

    private var tabStepTransition: AnyTransition {
        motionIsOff
            ? .opacity
            : .asymmetric(
                insertion: AnyTransition.opacity.animation(.easeOut(duration: 0.15)),
                removal: .opacity.combined(with: .offset(y: -8))
            )
    }

    private var centredTransition: AnyTransition {
        motionIsOff
            ? .opacity
            : .asymmetric(
                insertion: .identity,
                removal: AnyTransition.opacity
                    .combined(with: .scale(scale: 0.42, anchor: .topLeading))
                    .animation(.easeIn(duration: 0.25))
            )
    }

    private func play(_ current: OnboardingTour.Step) async {
        let target = OnboardingTour.pillTab(for: current, context: tour)
        let beats = OnboardingTour.beats(for: current, reduceMotion: motionIsOff)

        if holdsFinalFrame || beats.isEmpty {
            holdsFinalFrame = false
            phase = OnboardingTour.phaseCount(for: current)
            pillTab = target
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, step == current, !hasExited else { return }
            focusedLine = current
            flashIfItOverflows()
            return
        }

        var clock = 0.0
        for (index, beat) in beats.enumerated() {
            if beat.delay > clock {
                try? await Task.sleep(for: .seconds(beat.delay - clock))
                clock = beat.delay
            }
            guard !Task.isCancelled, step == current, !hasExited else { return }

            withAnimation(animation(for: beat, on: current)) {
                phase = index + 1
                switch beat.moment {
                case .pill: pillTab = target
                case .hop: hop &+= 1
                case .stripHop: stripHop &+= 1
                default: break
                }
            }
            if beat.moment == .bubble {
                focusedLine = current
            }
        }

        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled, step == current, !hasExited else { return }
        flashIfItOverflows()
    }

    // A step that ends under the footer's fade by a few points reads complete, so only a real overflow flashes.
    private func flashIfItOverflows() {
        if stageHeight - viewportHeight > Self.fadeHeight {
            flashes &+= 1
        }
    }

    private func animation(for beat: TourBeat, on current: OnboardingTour.Step) -> Animation {
        switch beat.moment {
        case .pill: .spring(response: 0.35, dampingFraction: 0.9)
        case .bubble: .spring(response: 0.38, dampingFraction: 0.86)
        case .markArrives:
            current == .done
                ? .spring(response: 0.5, dampingFraction: 0.85)
                : .easeOut(duration: beat.duration)
        case .proposal: .spring(response: 0.4, dampingFraction: 0.85)
        case .leaf: .spring(response: 0.45, dampingFraction: 0.6)
        case .strip: .spring(response: 0.35, dampingFraction: 0.8)
        case .late: .easeInOut(duration: beat.duration)
        default: .easeOut(duration: beat.duration)
        }
    }

    private func go(to next: OnboardingTour.Step) {
        guard next != step, !hasExited else { return }
        let settles = motionIsOff
        withAnimation(settles ? .easeInOut(duration: 0.2) : .easeIn(duration: 0.18)) {
            scroll.scrollTo(edge: .top)
            step = next
            if settles {
                phase = OnboardingTour.phaseCount(for: next)
                pillTab = OnboardingTour.pillTab(for: next, context: tour)
            } else {
                phase = 0
            }
        }
    }

    private func tapMap(_ tab: AppTab) {
        guard !hasExited else { return }
        switch OnboardingTour.mapAction(for: tab, on: step) {
        case .show(let target):
            guard target != step else { return }
            Haptics.selection()
            go(to: target)
        case .open(let landing):
            if tour.isReplay {
                Haptics.selection()
            } else {
                Haptics.success()
            }
            leave(landingOn: landing)
        }
    }

    private func advance() {
        guard !hasExited else { return }
        if let next = step.next {
            Haptics.selection()
            go(to: next)
            return
        }
        if tour.isReplay {
            Haptics.selection()
        } else {
            Haptics.success()
        }
        leave(landingOn: tour.isReplay ? nil : tour.chat.landingTab)
    }

    private func skip() {
        guard !hasExited, step != .done else { return }
        Haptics.selection()
        leave(landingOn: tour.isReplay ? nil : tour.chat.landingTab)
    }

    private func escape() {
        if step == .done {
            advance()
        } else {
            skip()
        }
    }

    private func leave(landingOn tab: AppTab?) {
        hasExited = true
        withAnimation(.easeInOut(duration: 0.26)) {
            if let tab {
                land(tab)
            }
            onboardingStore.finishTour(for: authSession.currentUser)
        }
    }
}

struct TourContext: Equatable {
    var name: String?
    var houseNames: [String] = []
    var chat: TourChatState
    var isReplay: Bool
    var now: Date

    var namesToAvoid: [String] {
        (name.map { [$0] } ?? []) + houseNames
    }
}

enum TourChatState: CaseIterable, Equatable {
    case open
    case needsConsent
    case awaitingAge
    case closed

    // Read in NinaChatView.body's order, so the tour never describes a different chat from the one the tab shows.
    init(
        canUseNinaAI: Bool,
        requiresConsent: Bool,
        hasConsent: Bool,
        isBlocked: Bool,
        isAdult: Bool,
        needsConfirmedAge: Bool
    ) {
        if canUseNinaAI {
            self = requiresConsent && !hasConsent ? .needsConsent : .open
        } else if isBlocked && isAdult {
            self = .closed
        } else if needsConfirmedAge {
            self = .awaitingAge
        } else {
            self = .closed
        }
    }

    var landingTab: AppTab {
        self == .open || self == .needsConsent ? .nina : .today
    }

    var showsChatExample: Bool {
        self != .closed
    }
}

enum TourMoment: Equatable {
    case markArrives
    case markRests
    case map
    case pill
    case hop
    case bubble
    case tray
    case said
    case reading
    case readingEnds
    case proposal
    case disclaimer
    case firstRow
    case secondRow
    case thirdRow
    case late
    case seedPill
    case leaf
    case strip
    case stripHop
    case portrait
    case firstBand
    case secondBand
}

struct TourBeat: Equatable {
    var moment: TourMoment
    var delay: Double
    var duration: Double
}

enum OnboardingTour {
    enum Step: Int, CaseIterable, Hashable {
        case hello
        case nina
        case today
        case tasks
        case house
        case done

        init(tab: AppTab) {
            switch tab {
            case .nina: self = .nina
            case .today: self = .today
            case .tasks: self = .tasks
            case .house: self = .house
            }
        }

        var tab: AppTab? {
            switch self {
            case .hello, .done: nil
            case .nina: .nina
            case .today: .today
            case .tasks: .tasks
            case .house: .house
            }
        }

        var next: Step? {
            Step(rawValue: rawValue + 1)
        }

        var isCentred: Bool {
            self == .hello || self == .done
        }
    }

    static let header = "Demonstração"
    static let exampleLegend = "Exemplo"

    enum MapAction: Equatable {
        case show(Step)
        case open(AppTab)
    }

    // On the close a tab in the map is the app's own, so a tap there leaves the tour on it.
    static func mapAction(for tab: AppTab, on step: Step) -> MapAction {
        step == .done ? .open(tab) : .show(Step(tab: tab))
    }

    static func mapHint(on step: Step) -> String {
        step == .done ? "Abre esta aba." : "Mostra esta aba na demonstração."
    }

    static func greetingName(displayName: String?, sharedGivenName: String?) -> String? {
        for candidate in [displayName, sharedGivenName] {
            let word = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).firstWord
            if !ProfileNaming.isPlaceholder(word) {
                return word
            }
        }
        return nil
    }

    static func line(for step: Step, context: TourContext) -> String {
        switch step {
        case .hello:
            let promise = "Vou mostrar as quatro abas em um minuto, só com exemplos."
            if context.isReplay {
                return context.name.map { "Oi de novo, \($0). \(promise)" } ?? "Oi de novo. \(promise)"
            }
            return context.name.map { "Oi, \($0), eu sou a Nina. \(promise)" } ?? "Oi, eu sou a Nina. \(promise)"
        case .nina:
            switch context.chat {
            case .open:
                return "Na minha aba, você me conta o que pesa, do jeito que vier. Eu leio e proponho o que fazer."
            case .needsConsent:
                return "Na minha aba, você decide se eu posso ler. Depois me conta o que pesa e eu proponho o que fazer."
            case .awaitingAge:
                return "Na minha aba, quando a Apple confirmar sua idade, você me conta o que pesa e eu proponho o que fazer."
            case .closed:
                return "Na minha aba, a conversa comigo não abre nesta conta. Tarefas, compras e a casa continuam com você."
            }
        case .today:
            return "Em Hoje fica o dia da casa. O que atrasou vem primeiro, sem bronca."
        case .tasks:
            return "Em Tarefas fica tudo por categoria, e as compras também. Semente é vontade sem data e nunca atrasa."
        case .house:
            return "Em Casa ficam as pessoas, os pets e um retrato de quem carrega mais. É para conversar, não para cobrar."
        case .done:
            return "Pronto, agora é com você. Nada do que você viu entrou na sua casa."
        }
    }

    // No drawn line ends on one word, and no line of the bubble ends on a word that leans on the next one.
    static func drawnLine(for step: Step, context: TourContext) -> String {
        let line = line(for: step, context: context)
        let rows = step.isCentred ? line.replacingOccurrences(of: ". ", with: ".\n") : line
        return rows
            .components(separatedBy: "\n")
            .map(bindingShortWords(in:))
            .joined(separator: "\n")
    }

    static let wordsBoundToTheNext: Set<String> = ["um", "na", "no", "de", "da", "do", "eu"]

    static func bindsToTheNextWord(_ word: String) -> Bool {
        (word.count == 1 && word.first?.isLetter == true) || wordsBoundToTheNext.contains(word.lowercased())
    }

    private static func bindingShortWords(in row: String) -> String {
        let words = row.components(separatedBy: " ")
        guard var drawn = words.first, words.count > 1 else { return row }
        for index in words.indices.dropFirst() {
            let binds = index == words.count - 1 || bindsToTheNextWord(words[index - 1])
            drawn += (binds ? "\u{00A0}" : " ") + words[index]
        }
        return drawn
    }

    static func advanceTitle(for step: Step, isReplay: Bool) -> String {
        guard step == .done else { return "Continuar" }
        return isReplay ? "Fechar" : "Começar"
    }

    static func advanceHint(for step: Step, context: TourContext) -> String? {
        guard step == .done, !context.isReplay else { return nil }
        return "Abre a aba \(context.chat.landingTab.title)."
    }

    static func skipTitle(isReplay: Bool) -> String {
        isReplay ? "Fechar" : "Pular"
    }

    static func skipLabel(isReplay: Bool) -> String {
        isReplay ? "Fechar a demonstração" : "Pular a demonstração"
    }

    static func progressValue(for step: Step) -> String {
        "Etapa \(step.rawValue + 1) de \(Step.allCases.count)"
    }

    // A replay hands back the tab the person left, so its close points at no tab.
    static func pillTab(for step: Step, context: TourContext) -> AppTab? {
        switch step {
        case .hello: nil
        case .done: context.isReplay ? nil : context.chat.landingTab
        default: step.tab
        }
    }

    static func exampleDescription(for step: Step, context: TourContext, calendar: Calendar) -> String? {
        exampleDescription(
            for: step,
            context: context,
            house: TourSample.house(for: context, calendar: calendar)
        )
    }

    static func exampleDescription(for step: Step, context: TourContext, house: TourSample.House) -> String? {
        guard let tab = step.tab else { return nil }
        let opening = "Exemplo da aba \(tab.title):"

        switch step {
        case .nina:
            guard context.chat.showsChatExample else { return nil }
            let category = TourSample.proposalCategory.title
            return "\(opening) você escreve \(TourSample.message). A Nina propõe \(TourSample.proposalTitle), "
                + "\(category), \(house.proposalLabel), sem dono. \(NinaProposalCopy.pending). "
                + NinaProposalCopy.disclaimer
        case .today:
            let rows = house.agenda.map { house.spokenRow($0) }.joined(separator: " ")
            return "\(opening) atrasadas, \(house.lateCount). \(rows)"
        case .tasks:
            let group = "categoria \(TourSample.groupCategory.title), \(house.groupTasks.count)."
            let rows = house.groupTasks.map { house.spokenRow($0) }.joined(separator: " ")
            let lists = "Listas \(TaskListFilter.seeds.title), \(house.openSeeds.count), "
                + "e \(TaskListFilter.shopping.title), \(house.pendingShopping.count)."
            return "\(opening) \(group) \(rows) \(lists) \(house.seed.title), plante depois."
        case .house:
            let cast = house.cast
            let people = "\(cast.owner) e \(cast.partner), adultos; \(cast.child), criança; \(cast.pet), pet; e a Nina."
            let bands = house.portraitRows.map { "\($0.name), \($0.band.title)." }.joined(separator: " ")
            return "\(opening) \(people) Sinal de sobrecarga: \(bands)"
        case .hello, .done:
            return nil
        }
    }

    static func beats(for step: Step, reduceMotion: Bool) -> [TourBeat] {
        guard !reduceMotion else { return [] }
        switch step {
        case .hello:
            return [
                TourBeat(moment: .markArrives, delay: 0.30, duration: 0.20),
                TourBeat(moment: .markRests, delay: 0.45, duration: 0.45),
                TourBeat(moment: .bubble, delay: 0.70, duration: 0.38),
                TourBeat(moment: .map, delay: 0.90, duration: 0.20)
            ]
        case .nina:
            return arrival + [
                TourBeat(moment: .said, delay: 0.80, duration: 0.28),
                TourBeat(moment: .reading, delay: 1.20, duration: 0.20),
                TourBeat(moment: .readingEnds, delay: 2.20, duration: 0.18),
                TourBeat(moment: .proposal, delay: 2.42, duration: 0.40),
                TourBeat(moment: .disclaimer, delay: 2.72, duration: 0.20)
            ]
        case .today:
            return arrival + [
                TourBeat(moment: .firstRow, delay: 0.80, duration: 0.20),
                TourBeat(moment: .secondRow, delay: 0.92, duration: 0.26),
                TourBeat(moment: .thirdRow, delay: 1.04, duration: 0.26),
                TourBeat(moment: .late, delay: 1.50, duration: 0.30)
            ]
        case .tasks:
            return arrival + [
                TourBeat(moment: .firstRow, delay: 0.80, duration: 0.20),
                TourBeat(moment: .secondRow, delay: 1.05, duration: 0.24),
                TourBeat(moment: .seedPill, delay: 1.25, duration: 0.30),
                TourBeat(moment: .leaf, delay: 1.35, duration: 0.50)
            ]
        case .house:
            return arrival + [
                TourBeat(moment: .strip, delay: 0.80, duration: 0.55),
                TourBeat(moment: .stripHop, delay: 1.10, duration: 0.66),
                TourBeat(moment: .portrait, delay: 1.25, duration: 0.25),
                TourBeat(moment: .firstBand, delay: 1.55, duration: 0.25),
                TourBeat(moment: .secondBand, delay: 1.70, duration: 0.25)
            ]
        case .done:
            return [
                TourBeat(moment: .pill, delay: 0.10, duration: 0.35),
                TourBeat(moment: .markArrives, delay: 0.12, duration: 0.50),
                TourBeat(moment: .hop, delay: 0.55, duration: 0.66),
                TourBeat(moment: .bubble, delay: 0.60, duration: 0.38)
            ]
        }
    }

    static func phaseCount(for step: Step) -> Int {
        beats(for: step, reduceMotion: false).count
    }

    static func isReached(_ moment: TourMoment, on step: Step, phase: Int) -> Bool {
        let motion = beats(for: step, reduceMotion: false)
        guard let index = motion.firstIndex(where: { $0.moment == moment }) else { return true }
        return phase > index
    }

    private static let arrival = [
        TourBeat(moment: .pill, delay: 0.10, duration: 0.35),
        TourBeat(moment: .hop, delay: 0.18, duration: 0.66),
        TourBeat(moment: .bubble, delay: 0.24, duration: 0.38),
        TourBeat(moment: .tray, delay: 0.50, duration: 0.30)
    ]
}

enum TourSample {
    struct Cast: Equatable {
        var owner: String
        var partner: String
        var child: String
        var pet: String

        var adults: [String] {
            [owner, partner]
        }

        var names: [String] {
            [owner, partner, child, pet]
        }
    }

    struct House {
        var cast: Cast
        var members: [HouseholdMember]
        var tasks: [TaskItem]
        var shopping: [ShoppingItem]
        var lateBill: TaskItem
        var seed: TaskItem
        var now: Date
        var sampleNow: Date
        var calendar: Calendar
        var proposalDate: Date?

        var agenda: [TaskItem] {
            tasks
                .filter { $0.belongsOnAgenda(for: sampleNow, calendar: calendar) }
                .sorted { lhs, rhs in
                    let lhsLate = isLate(lhs)
                    let rhsLate = isLate(rhs)
                    if lhsLate != rhsLate { return lhsLate }
                    return (lhs.dueAt ?? .distantFuture) < (rhs.dueAt ?? .distantFuture)
                }
        }

        var lateCount: Int {
            agenda.count { isLate($0) }
        }

        var openSeeds: [TaskItem] {
            tasks.filter { $0.kind == .seed && !$0.isDone }
        }

        var groupTasks: [TaskItem] {
            tasks.filter { $0.kind == .task && !$0.isDone && $0.category == TourSample.groupCategory }
        }

        var pendingShopping: [ShoppingItem] {
            shopping.filter { !$0.isChecked }
        }

        var people: [HouseholdMember] {
            members.filter { $0.role != .assistant }
        }

        var portrait: HouseholdWorkloadSnapshot {
            HouseholdWorkload.snapshot(tasks: tasks, members: members)
        }

        var portraitRows: [HouseholdWorkloadEntry] {
            let adultIDs = Set(members.filter { $0.role == .adult }.map(\.id))
            return portrait.entries.filter { entry in
                entry.memberID.map(adultIDs.contains) ?? false
            }
        }

        var proposalLabel: String {
            guard let proposalDate else { return "Sem data" }
            return AppStore.taskDueLabel(for: proposalDate, relativeTo: now, calendar: calendar)
        }

        func isLate(_ task: TaskItem) -> Bool {
            task.isOverdue(relativeTo: sampleNow, calendar: calendar)
        }

        func label(for task: TaskItem) -> String {
            task.effectiveDueLabel(relativeTo: now, calendar: calendar)
        }

        func owner(of task: TaskItem) -> HouseholdMember? {
            members.first { $0.id == task.ownerMemberID }
        }

        func spokenRow(_ task: TaskItem) -> String {
            let ownerName = owner(of: task)?.name ?? "sem dono"
            let lateness = isLate(task) ? "atrasada, " : ""
            return "\(task.title), \(lateness)\(label(for: task)), \(ownerName)."
        }
    }

    static let primaryCast = Cast(owner: "Dani", partner: "Cris", child: "Lia", pet: "Paçoca")
    static let otherCast = Cast(owner: "Rafa", partner: "Alex", child: "Nico", pet: "Pipoca")
    static let thirdCast = Cast(owner: "Tati", partner: "Juca", child: "Bento", pet: "Farofa")
    static let roleCast = Cast(owner: "Adulto 1", partner: "Adulto 2", child: "Criança", pet: "Pet")

    static let message = "Autorização da escola até sexta"
    static let proposalTitle = "Assinar a autorização"
    static let proposalCategory = TaskCategory.school
    static let proposalWord = "sexta"
    static let groupCategory = TaskCategory.pet

    // An inner shape sits 12 pt inside the radius-16 example card, so it never curves wider than the card.
    static let innerRadius: CGFloat = 12

    // The example house never borrows a word of any name in the real house, so no real person is drawn in a band.
    static func cast(avoiding names: [String]) -> Cast {
        let taken = Set(names.flatMap(foldedWords(in:)))
        let named = [primaryCast, otherCast, thirdCast].first { cast in
            cast.names.allSatisfy { taken.isDisjoint(with: foldedWords(in: $0)) }
        }
        return named ?? roleCast
    }

    static func foldedWords(in name: String) -> [String] {
        name
            .components(separatedBy: CharacterSet.letters.inverted)
            .map(HouseholdWorkload.normalized)
            .filter { !$0.isEmpty }
    }

    static func house(for context: TourContext, calendar: Calendar) -> House {
        house(avoiding: context.namesToAvoid, now: context.now, calendar: calendar)
    }

    static func house(avoiding names: [String], now: Date, calendar: Calendar) -> House {
        let chosen = cast(avoiding: names)
        let owner = HouseholdMember(
            id: sampleID(1), name: chosen.owner, relationship: "", role: .adult,
            permissionRole: .owner, tone: .mint, taskCount: 0, memoryNote: ""
        )
        let partner = HouseholdMember(
            id: sampleID(2), name: chosen.partner, relationship: "", role: .adult,
            tone: .sky, taskCount: 0, memoryNote: ""
        )
        let child = HouseholdMember(
            id: sampleID(3), name: chosen.child, relationship: "", role: .child,
            tone: .lavender, taskCount: 0, memoryNote: ""
        )
        let pet = HouseholdMember(
            id: sampleID(4), name: chosen.pet, relationship: "", role: .pet,
            tone: .amber, taskCount: 0, memoryNote: ""
        )
        let nina = HouseholdMember(
            id: sampleID(5), name: "Nina", relationship: "", role: .assistant,
            tone: .mint, taskCount: 0, memoryNote: ""
        )

        let today = calendar.startOfDay(for: now)
        func at(day: Int, hour: Int, minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: day, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }
        let (firstOnTime, secondOnTime) = onTimeInstants(now: now, calendar: calendar)

        func task(
            _ number: UInt8,
            _ title: String,
            _ category: TaskCategory,
            _ member: HouseholdMember,
            _ due: Date
        ) -> TaskItem {
            TaskItem(
                id: sampleID(number),
                title: title,
                subtitle: "",
                owner: member.name,
                ownerMemberID: member.id,
                dueLabel: AppStore.taskDueLabel(for: due, relativeTo: now, calendar: calendar),
                dueAt: due,
                category: category,
                isDone: false,
                createdBy: "Exemplo"
            )
        }

        let lateBill = task(11, "Pagar a luz", .bills, owner, at(day: -1, hour: 18))
        let seed = TaskItem(
            id: sampleID(18),
            kind: .seed,
            title: "Pintar a sala",
            subtitle: "",
            owner: HouseholdWorkload.sharedOwnerLabel,
            dueLabel: "Sem data",
            category: .home,
            isDone: false,
            createdBy: "Exemplo"
        )
        let tasks = [
            lateBill,
            task(12, "Levar o lixo", .home, partner, firstOnTime),
            task(13, "Lavar a louça", .home, owner, secondOnTime),
            task(14, "Trocar a lâmpada", .home, owner, at(day: 1, hour: 9)),
            task(15, "Vacina", groupCategory, owner, at(day: 2, hour: 9)),
            task(16, "Reunião da escola", .school, owner, at(day: 4, hour: 19)),
            task(17, "Arrumar a mochila", .school, child, at(day: 1, hour: 7)),
            seed
        ]

        return House(
            cast: chosen,
            members: [owner, partner, child, pet, nina],
            tasks: tasks,
            shopping: [
                ShoppingItem(id: sampleID(19), title: "Café", amount: "1 pacote", owner: "", isChecked: false)
            ],
            lateBill: lateBill,
            seed: seed,
            now: now,
            sampleNow: sampleNow(now: now, calendar: calendar),
            calendar: calendar,
            proposalDate: proposalDate(now: now, calendar: calendar)
        )
    }

    // Late at night the example clock stops at 23:40, so exactly one row is ever late.
    static func sampleNow(now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let latest = calendar.date(bySettingHour: 23, minute: 40, second: 0, of: today) ?? now
        return min(now, latest)
    }

    static func onTimeInstants(now: Date, calendar: Calendar) -> (Date, Date) {
        let today = calendar.startOfDay(for: now)
        func todayAt(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
        }
        let soonest = sampleNow(now: now, calendar: calendar).addingTimeInterval(30 * 60)
        var hourStart = calendar.date(
            from: calendar.dateComponents([.year, .month, .day, .hour], from: soonest)
        ) ?? soonest
        if hourStart < soonest {
            hourStart = calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? soonest
        }
        let first = min(max(todayAt(20, 0), hourStart), todayAt(23, 50))
        let second = min(first.addingTimeInterval(60 * 60), todayAt(23, 55))
        return (first, second)
    }

    static func proposalDate(now: Date, calendar: Calendar) -> Date? {
        AppStore.inferredDueAt(from: proposalWord, now: now, calendar: calendar)
    }

    private static func sampleID(_ number: UInt8) -> UUID {
        UUID(uuid: (0x7E, 0x0D, 0x7E, 0x0D, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, number))
    }
}

// The tray hugs its example under Nina's line, so the legend always heads the frame it labels.
private struct TourTray<Content: View>: View {
    var description: String
    var strokesEdge: Bool
    @ViewBuilder var content: Content

    private var inset: CGFloat { 12 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: OnboardingTour.exampleLegend)

            content
                .padding(inset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ninaCard(radius: NinaTheme.Radius.sheet - inset)
        }
        .padding(inset)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            NinaTheme.grout,
            in: RoundedRectangle(cornerRadius: NinaTheme.Radius.sheet, style: .continuous)
        )
        .overlay {
            if strokesEdge {
                RoundedRectangle(cornerRadius: NinaTheme.Radius.sheet, style: .continuous)
                    .strokeBorder(NinaTheme.control, lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
    }
}

// The proposal holds its room from the first frame, so the card never grows and nothing is drawn past its edge.
private struct TourChatExample: View {
    var proposalLabel: String
    var showsMessage: Bool
    var showsMark: Bool
    var isReading: Bool
    var showsProposal: Bool
    var showsDisclaimer: Bool
    var slides: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                Spacer(minLength: 16)

                Text(TourSample.message)
                    .ninaText(.body, NinaTheme.ground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        NinaTheme.ink,
                        in: RoundedRectangle(cornerRadius: TourSample.innerRadius, style: .continuous)
                    )
            }
            .opacity(showsMessage ? 1 : 0)
            .offset(x: showsMessage ? 0 : 16)

            HStack(alignment: .top, spacing: 10) {
                // The mark enters the tree as a reading mark, so its capsule breathes from the first frame Nina reads.
                NinaMark(size: 22, presence: isReading ? .reading : .rest)
                    .padding(.top, 4)
                    .opacity(showsMark ? 1 : 0)
                    .id(showsMark)

                ZStack(alignment: .topLeading) {
                    NinaReadingCapsule()
                        .opacity(isReading ? 1 : 0)

                    VStack(alignment: .leading, spacing: 10) {
                        TourProposalFace(dateLabel: proposalLabel)

                        Text(NinaProposalCopy.disclaimer)
                            .ninaText(.meta, NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(showsDisclaimer ? 1 : 0)
                    }
                    .opacity(showsProposal ? 1 : 0)
                    .scaleEffect(showsProposal || !slides ? 1 : 0.96, anchor: .topLeading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct TourProposalFace: View {
    var dateLabel: String

    @ScaledMetric(relativeTo: .caption) private var tagGlyphSize: CGFloat = 11
    @ScaledMetric(relativeTo: .subheadline) private var metaGlyphSize: CGFloat = 13

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: tagGlyphSize, weight: .semibold))
                        .foregroundStyle(NinaTheme.faint)

                    Eyebrow(text: NinaProposalCopy.pending)
                }

                HStack(alignment: .top, spacing: 10) {
                    CategoryGlyph(
                        systemName: TourSample.proposalCategory.symbolName,
                        size: 18,
                        tint: NinaTheme.ink,
                        label: TourSample.proposalCategory.title
                    )

                    Text(TourSample.proposalTitle)
                        .ninaText(.body, NinaTheme.ink, weight: .semibold)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { metaPairs }
                VStack(alignment: .leading, spacing: 8) { metaPairs }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NinaTheme.ground)
        .clipShape(RoundedRectangle(cornerRadius: TourSample.innerRadius, style: .continuous))
        .ninaCard(radius: TourSample.innerRadius)
    }

    @ViewBuilder
    private var metaPairs: some View {
        metaPair(glyph: "calendar", value: dateLabel)
        metaPair(glyph: "person", value: "Sem dono")
    }

    private func metaPair(glyph: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: glyph)
                .font(.system(size: metaGlyphSize, weight: .regular))
                .foregroundStyle(NinaTheme.muted)

            Text(value)
                .ninaText(.label, NinaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// Every row of an example takes one layout, so a list never mixes one-line rows with stacked ones.
private struct TourRowLayout<Rows: View>: View {
    @ViewBuilder var rows: (_ isStacked: Bool) -> Rows

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            rows(true)
        } else {
            ViewThatFits(in: .horizontal) {
                rows(false)
                rows(true)
            }
        }
    }
}

private struct TourTaskRow: View {
    var task: TaskItem
    var label: String
    var isLate: Bool
    var isWarm: Bool
    var owner: HouseholdMember?
    var isStacked: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var showsLateness: Bool {
        isLate && isWarm
    }

    var body: some View {
        HStack(spacing: 12) {
            NinaCheckbox(isOn: false, isOverdue: showsLateness)
            rowLabel
        }
        .padding(.vertical, 5)
        .frame(minHeight: 48)
    }

    @ViewBuilder
    private var rowLabel: some View {
        if isStacked {
            VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 6 : 4) {
                title.lineLimit(3)
                HStack(spacing: 10) {
                    trailing
                    Spacer(minLength: 0)
                }
            }
        } else {
            HStack(spacing: 10) {
                title.lineLimit(1)
                Spacer(minLength: 8)
                trailing
            }
        }
    }

    private var title: some View {
        Text(task.title)
            .ninaText(.body, NinaTheme.ink, weight: .medium)
            .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var trailing: some View {
        Text(label)
            .ninaText(
                .meta,
                showsLateness ? NinaTheme.terracotta : NinaTheme.muted,
                weight: isLate ? .semibold : .regular
            )
            .lineLimit(1)

        CategoryGlyph(systemName: task.category.symbolName, size: 15, tint: NinaTheme.muted)

        if let owner {
            MemberAvatar(initials: owner.name.ninaInitials, tone: owner.tone, size: 24)
        } else {
            Color.clear.frame(width: 24, height: 24)
        }
    }
}

private struct TourTodayExample: View {
    var house: TourSample.House
    var showsLate: Bool
    var showsSecond: Bool
    var showsThird: Bool
    var isWarm: Bool

    private var lateRows: [TaskItem] {
        house.agenda.filter { house.isLate($0) }
    }

    private var onTimeRows: [TaskItem] {
        house.agenda.filter { !house.isLate($0) }
    }

    var body: some View {
        TourRowLayout { isStacked in
            list(isStacked: isStacked)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func list(isStacked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isWarm ? NinaTheme.terracotta : NinaTheme.faint)

                    Text("ATRASADAS · \(lateRows.count)")
                        .ninaText(.eyebrow, isWarm ? NinaTheme.terracotta : NinaTheme.faint, weight: .bold)
                }
                .padding(.bottom, 8)

                ForEach(lateRows) { task in
                    row(task, isStacked: isStacked)
                }
            }
            .opacity(showsLate ? 1 : 0)

            ForEach(Array(onTimeRows.enumerated()), id: \.element.id) { index, task in
                let isShown = index == 0 ? showsSecond : showsThird
                VStack(spacing: 0) {
                    NinaDivider(inset: index == 0 ? 0 : 36)
                    row(task, isStacked: isStacked)
                }
                .opacity(isShown ? 1 : 0)
                .offset(y: isShown ? 0 : 6)
            }
        }
    }

    private func row(_ task: TaskItem, isStacked: Bool) -> some View {
        TourTaskRow(
            task: task,
            label: house.label(for: task),
            isLate: house.isLate(task),
            isWarm: isWarm,
            owner: house.owner(of: task),
            isStacked: isStacked
        )
    }
}

// "Tudo" groups by category; Sementes and Compras are lists behind their own chips, so they are drawn as chips.
private struct TourTasksExample: View {
    var house: TourSample.House
    var showsCategory: Bool
    var showsLists: Bool
    var showsSeed: Bool
    var leafHasGrown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                groupHeader(
                    "\(TourSample.groupCategory.title.uppercased()) · \(house.groupTasks.count)"
                )

                TourRowLayout { isStacked in
                    VStack(spacing: 0) {
                        ForEach(house.groupTasks) { task in
                            TourTaskRow(
                                task: task,
                                label: house.label(for: task),
                                isLate: false,
                                isWarm: false,
                                owner: house.owner(of: task),
                                isStacked: isStacked
                            )
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .opacity(showsCategory ? 1 : 0)

            VStack(alignment: .leading, spacing: 8) {
                listChips
                    .opacity(showsLists ? 1 : 0)
                    .offset(y: showsLists ? 0 : 6)

                seedPill
                    .opacity(showsSeed ? 1 : 0)
                    .offset(y: showsSeed ? 0 : 10)
            }
        }
    }

    private func groupHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NinaTheme.faint)

            Text(title)
                .ninaText(.eyebrow, NinaTheme.faint, weight: .bold)
        }
        .padding(.bottom, 8)
    }

    private var listChips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips }
            VStack(alignment: .leading, spacing: 8) { chips }
        }
    }

    @ViewBuilder
    private var chips: some View {
        NinaChip(text: "\(TaskListFilter.seeds.title) \(house.openSeeds.count)")
        NinaChip(text: "\(TaskListFilter.shopping.title) \(house.pendingShopping.count)")
    }

    private var seedPill: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                leaf
                seedTitle
                Spacer(minLength: 8)
                plantLater
            }

            HStack(alignment: .top, spacing: 12) {
                leaf
                VStack(alignment: .leading, spacing: 4) {
                    seedTitle
                    plantLater
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard(radius: TourSample.innerRadius, fill: NinaTheme.grout, stroke: .clear)
    }

    private var leaf: some View {
        CategoryGlyph(systemName: "leaf", size: 18, tint: NinaTheme.ink)
            .scaleEffect(leafHasGrown ? 1 : 0.6)
    }

    private var seedTitle: some View {
        Text(house.seed.title)
            .ninaText(.body, NinaTheme.ink, weight: .medium)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var plantLater: some View {
        Text("Plante depois").ninaText(.meta, NinaTheme.muted)
    }
}

private struct TourHouseExample: View {
    var house: TourSample.House
    var stripHop: Int
    var showsStrip: Bool
    var showsPortrait: Bool
    var filledBands: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let bands: [WorkloadBand] = [.light, .similar, .heavier]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { index in
                    stripItem(index)
                        .scaleEffect(showsStrip ? 1 : 0.85)
                        .opacity(showsStrip ? 1 : 0)
                        .animation(
                            .spring(response: 0.35, dampingFraction: 0.8).delay(Double(index) * 0.05),
                            value: showsStrip
                        )
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                NinaDivider(inset: 0)

                Eyebrow(text: "Sinal de sobrecarga")

                if dynamicTypeSize.isAccessibilitySize {
                    portraitRows(sayBands: true)
                } else {
                    ViewThatFits(in: .horizontal) {
                        VStack(alignment: .leading, spacing: 14) {
                            axis
                            portraitRows(sayBands: false)
                        }

                        portraitRows(sayBands: true)
                    }
                }
            }
            .opacity(showsPortrait ? 1 : 0)
        }
    }

    // The axis shows only over three equal thirds; where it cannot, each row says its band.
    private var axis: some View {
        EqualWidthRow(spacing: 6) {
            ForEach(Self.bands, id: \.self) { band in
                Text(band.title.uppercased())
                    .ninaText(.eyebrow, NinaTheme.faint, weight: .bold)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: axisAlignment(band))
            }
        }
    }

    private func portraitRows(sayBands: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(house.portraitRows.enumerated()), id: \.element.id) { index, entry in
                portraitRow(entry, isFilled: index < filledBands, saysBand: sayBands)
            }
        }
    }

    @ViewBuilder
    private func stripItem(_ index: Int) -> some View {
        let people = house.members.filter { $0.role != .assistant && $0.role != .pet }
        switch index {
        case 0..<people.count:
            MemberAvatar(initials: people[index].name.ninaInitials, tone: people[index].tone, size: 32)
        case people.count:
            Circle()
                .fill(NinaTheme.grout)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "pawprint")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(NinaTheme.ink)
                )
        default:
            NinaMark(size: 32, hops: stripHop)
        }
    }

    private func portraitRow(_ entry: HouseholdWorkloadEntry, isFilled: Bool, saysBand: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                MemberAvatar(initials: entry.name.ninaInitials, tone: entry.tone, size: 22)

                if saysBand {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            memberName(entry)
                            bandWord(" · \(entry.band.title)")
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            memberName(entry)
                            bandWord(entry.band.title)
                        }
                    }
                } else {
                    memberName(entry)
                }
            }

            HStack(spacing: 6) {
                ForEach(Self.bands, id: \.self) { band in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isFilled && entry.band == band ? NinaTheme.cobalt : NinaTheme.grout)
                        .frame(height: 20)
                }
            }
        }
    }

    private func memberName(_ entry: HouseholdWorkloadEntry) -> some View {
        Text(entry.name)
            .ninaText(.body, NinaTheme.ink, weight: .medium)
            .fixedSize(horizontal: false, vertical: true)
    }

    // The band is said beside the name but never as loud as it, as the live axis keeps it quiet over the bars.
    private func bandWord(_ text: String) -> some View {
        Text(text)
            .ninaText(.label, NinaTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func axisAlignment(_ band: WorkloadBand) -> Alignment {
        switch band {
        case .light: .leading
        case .similar: .center
        case .heavier: .trailing
        }
    }
}

private struct TourTabMap: View {
    var selected: AppTab?
    var marksSelection: Bool
    var hint: String
    var namespace: Namespace.ID
    var slides: Bool
    var strokesPill: Bool
    var select: (AppTab) -> Void

    @ScaledMetric(relativeTo: .footnote) private var pillWidth: CGFloat = 76
    @State private var meetsDisplayEdge = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    select(tab)
                } label: {
                    VStack(spacing: 4) {
                        icon(for: tab)

                        Text(tab.title)
                            .ninaText(.meta, tint(for: tab), weight: tab == selected ? .semibold : .regular)
                    }
                    .foregroundStyle(tint(for: tab))
                    .frame(maxWidth: .infinity)
                    .background { pill(for: tab) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityHint(hint)
                .accessibilityAddTraits(marksSelection && tab == selected ? [.isSelected] : [])
                .accessibilityShowsLargeContentViewer {
                    Image(systemName: tab.systemImage)
                    Text(tab.title)
                }
            }
        }
        .padding(.top, 9)
        .padding(.bottom, TabBarClearance.bottomPadding(meetsDisplayEdge: meetsDisplayEdge))
        .background(alignment: .top) {
            NinaTheme.ground
                .overlay(alignment: .top) {
                    Rectangle().fill(NinaTheme.line).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
        .onGeometryChange(for: Bool.self) { $0.safeAreaInsets.bottom < 1 } action: { meets in
            meetsDisplayEdge = meets
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Abas")
    }

    private func tint(for tab: AppTab) -> Color {
        tab == selected ? NinaTheme.ink : NinaTheme.muted
    }

    @ViewBuilder
    private func icon(for tab: AppTab) -> some View {
        if tab == .nina {
            NinaMark(size: 24, tint: tint(for: tab))
        } else {
            Image(systemName: tab.systemImage)
                .font(.system(size: 22, weight: .regular))
                .frame(height: 24)
        }
    }

    // One width under every tab, clear of the display's corners, and never past the bar's own bottom edge.
    @ViewBuilder
    private func pill(for tab: AppTab) -> some View {
        if tab == selected {
            GeometryReader { item in
                let below = TabBarClearance.tourPillReachBelowTitle
                capsule(width: min(pillWidth, item.size.width - 16), height: item.size.height + 4 + below)
                    .position(x: item.size.width / 2, y: (item.size.height + below - 4) / 2)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func capsule(width: CGFloat, height: CGFloat) -> some View {
        let shape = Capsule()
            .fill(NinaTheme.grout)
            .overlay {
                if strokesPill {
                    Capsule().strokeBorder(NinaTheme.control, lineWidth: 1)
                }
            }
            .frame(width: width, height: height)

        if slides {
            shape.matchedGeometryEffect(id: "pill", in: namespace)
        } else {
            shape
        }
    }
}

#Preview("Demonstração") {
    let auth = AuthSessionStore()
    auth.currentUser = AuthUser(id: "preview", displayName: "Ana", email: nil, provider: .apple)

    return OnboardingTutorialView(
        context: TourContext(name: "Ana", chat: .needsConsent, isReplay: false, now: .now)
    ) { _ in }
        .environment(auth)
        .environment(OnboardingStore())
}

#Preview("Casa, quadro final") {
    let auth = AuthSessionStore()
    auth.currentUser = AuthUser(id: "preview", displayName: "Ana", email: nil, provider: .apple)

    return OnboardingTutorialView(
        context: TourContext(name: "Ana", chat: .open, isReplay: false, now: .now),
        startingAt: .house,
        onItsFinalFrame: true
    ) { _ in }
        .environment(auth)
        .environment(OnboardingStore())
}
