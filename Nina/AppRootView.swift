import SwiftUI
import Observation
#if canImport(UIKit)
import UIKit
#endif

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case nina
    case today
    case tasks
    case house

    var id: String { rawValue }

    @ViewBuilder
    func makeContentView() -> some View {
        switch self {
        case .nina:
            NinaChatView()
        case .today:
            TodayView()
        case .tasks:
            TasksView()
        case .house:
            HouseView()
        }
    }
}

enum Route: Hashable {
    case task(UUID)
    case member(UUID)
    case workload
    case memories
}

enum SheetDestination: Identifiable, Hashable {
    case settings
    case premium
    case addTask
    case addTaskInSection(String)
    case editTask(UUID)
    case plantSeed(UUID)
    case addShoppingItem
    case editShoppingItem(UUID)
    case inviteFamily
    case addMemberProfile
    case member(UUID)
    case suggestion(NinaSuggestion)

    var id: String {
        switch self {
        case .settings:
            "settings"
        case .premium:
            "premium"
        case .addTask:
            "add-task"
        case .addTaskInSection(let sectionID):
            "add-task-\(sectionID)"
        case .editTask(let id):
            "edit-task-\(id.uuidString)"
        case .plantSeed(let id):
            "plant-seed-\(id.uuidString)"
        case .addShoppingItem:
            "add-shopping"
        case .editShoppingItem(let id):
            "edit-shopping-\(id.uuidString)"
        case .inviteFamily:
            "invite-family"
        case .addMemberProfile:
            "add-member-profile"
        case .member(let id):
            "member-\(id.uuidString)"
        case .suggestion(let suggestion):
            "suggestion-\(suggestion.id.uuidString)"
        }
    }
}

@MainActor
@Observable
final class RouterPath {
    var path: [Route] = []
    var presentedSheet: SheetDestination?

    func navigate(to route: Route) {
        path.append(route)
    }
}

@MainActor
@Observable
final class TabRouter {
    private var routers: [AppTab: RouterPath] = [:]

    func router(for tab: AppTab) -> RouterPath {
        if let router = routers[tab] {
            return router
        }

        let router = RouterPath()
        routers[tab] = router
        return router
    }

    func binding(for tab: AppTab) -> Binding<[Route]> {
        let router = router(for: tab)
        return Binding(
            get: { router.path },
            set: { router.path = $0 }
        )
    }
}

@MainActor
@Observable
final class TabSwipeLock {
    var isLocked = false
}

private enum AppEntryPhase: Hashable {
    case signedOut
    case tutorial
    case homeLoading
    case invite
    case pendingApproval
    case accessDecision
    case homeSetup
    case homeUnavailable
    case app
}

private enum TabTransitionDirection {
    case forward
    case backward

    var insertionEdge: Edge {
        switch self {
        case .forward: .trailing
        case .backward: .leading
        }
    }

    var removalEdge: Edge {
        switch self {
        case .forward: .leading
        case .backward: .trailing
        }
    }
}

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(OnboardingStore.self) private var onboardingStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(PremiumSubscriptionStore.self) private var premiumSubscriptionStore
    @Environment(InviteLinkStore.self) private var inviteLinkStore

    @State private var selectedTab: AppTab = .nina
    @State private var tabRouter = TabRouter()
    @State private var tabSwipeLock = TabSwipeLock()
    @State private var isShowingLoadingScreen = true
    @State private var isAppShellMounted = false
    @State private var didFinishInitialLoad = false
    @State private var shouldRefreshWhenActive = false
    @State private var didDismissKeyboardForCurrentSwipe = false
    @State private var tabTransitionDirection: TabTransitionDirection = .forward

    var body: some View {
        ZStack {
            if isAppShellMounted {
                entryContent
                    .disabled(isShowingLoadingScreen)
            }

            if isShowingLoadingScreen {
                AppLoadingScreen()
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
                    .zIndex(1)
            }
        }
        .background(NinaTheme.ground.ignoresSafeArea())
        .environment(tabSwipeLock)
        .tint(NinaTheme.cobalt)
        .keyboardDismissesOnOutsideTap()
        .animation(.easeInOut(duration: 0.28), value: entryPhase)
        .onChange(of: authSession.currentUser?.id) { oldValue, newValue in
            guard oldValue != newValue else { return }
            Task {
                await profileStore.refreshProfile(for: authSession.currentUser)
                await store.activateHomeContext(for: authSession.currentUser)
                await premiumSubscriptionStore.configure(for: authSession.currentUser)
            }
            selectedTab = .nina
            tabRouter = TabRouter()
        }
        .onChange(of: store.hasActiveHome) { _, _ in
            selectedTab = .nina
            tabRouter = TabRouter()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                shouldRefreshWhenActive = didFinishInitialLoad
                return
            }

            guard newPhase == .active, shouldRefreshWhenActive else { return }
            shouldRefreshWhenActive = false

            Task {
                await authSession.restoreSession()
                await profileStore.refreshProfile(for: authSession.currentUser)
                await store.refreshHomeFromRemote(for: authSession.currentUser)
                await premiumSubscriptionStore.configure(for: authSession.currentUser)
                await store.refreshNotificationAuthorizationStatus()
                store.synchronizeLocalNotifications()
            }
        }
        .task {
            await authSession.restoreSession()
            await profileStore.refreshProfile(for: authSession.currentUser)
            await premiumSubscriptionStore.configure(for: authSession.currentUser)
            await store.activateHomeContext(for: authSession.currentUser)
            await store.refreshNotificationAuthorizationStatus()
            didFinishInitialLoad = true
            await Task.yield()
            guard !Task.isCancelled else { return }

            await MainActor.run {
                isAppShellMounted = true
            }

            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.36)) {
                    isShowingLoadingScreen = false
                }
            }
        }
        // A conflict has no dismissal. Swiping the old alert away silently chose
        // remote-wins, which threw away an edit the person had just typed.
        .sheet(
            item: Binding(
                get: { store.taskEditConflict },
                set: { _ in }
            )
        ) { conflict in
            TaskEditConflictSheet(conflict: conflict)
                .interactiveDismissDisabled()
        }
    }

    private var entryPhase: AppEntryPhase {
        if !authSession.isSignedIn {
            return .signedOut
        }

        if onboardingStore.shouldShowTutorial(for: authSession.currentUser) {
            return .tutorial
        }

        if store.homeAccessState == .loading {
            return .homeLoading
        }

        if inviteLinkStore.pendingCode != nil {
            return .invite
        }

        switch store.homeAccessState {
        case .loading:
            return .homeLoading
        case .noHome:
            return .homeSetup
        case .pendingApproval:
            return .pendingApproval
        case .accessDecision:
            return .accessDecision
        case .unavailable:
            return .homeUnavailable
        case .authorized:
            return .app
        }
    }

    @ViewBuilder
    private var entryContent: some View {
        switch entryPhase {
        case .signedOut:
            LoginView()
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .tutorial:
            OnboardingTutorialView()
                .transition(.opacity.combined(with: .scale(scale: 1.01)))
        case .homeLoading:
            HomeAccessLoadingView()
                .transition(.opacity)
        case .invite:
            InviteAcceptanceView()
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .pendingApproval:
            PendingHomeApprovalView()
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .accessDecision:
            FamilyAccessDecisionView()
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .homeSetup:
            HomeSetupView()
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .homeUnavailable:
            HomeAccessUnavailableView()
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .app:
            appShell
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var appShell: some View {
        ZStack(alignment: .bottom) {
            NinaTheme.ground
                .ignoresSafeArea()

            tabPager
                .ignoresSafeArea()

            // A pushed screen owns the whole viewport: it has its own back
            // affordance and a footer that would otherwise sit under the bar.
            if tabRouter.router(for: selectedTab).path.isEmpty {
                KeyboardAwareBottomTabBar(selectedTab: selectedTab, select: selectTab)
                    .transition(.opacity)
            }
        }
        .background(NinaTheme.ground.ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(for: .ninaSelectChatTab)) { _ in
            selectTab(.nina)
        }
    }

    @ViewBuilder
    private var tabPager: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)

            ZStack {
                tabContent(for: selectedTab)
                    .id(selectedTab)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: tabTransitionDirection.insertionEdge).combined(with: .opacity),
                            removal: .move(edge: tabTransitionDirection.removalEdge).combined(with: .opacity)
                        )
                    )
            }
            .frame(width: width, height: proxy.size.height)
            .clipped()
            .contentShape(Rectangle())
            .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.9, blendDuration: 0.08), value: selectedTab)
            .simultaneousGesture(tabSwipeGesture(width: width))
        }
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        let router = tabRouter.router(for: tab)

        // Each screen draws its own header, so the navigation bar never appears.
        NavigationStack(path: tabRouter.binding(for: tab)) {
            tab.makeContentView()
                .withAppRoutes()
                .toolbar(.hidden, for: .navigationBar)
        }
        .withSheetDestinations(
            sheet: Binding(
                get: { router.presentedSheet },
                set: { router.presentedSheet = $0 }
            )
        )
        .background(NinaTheme.ground.ignoresSafeArea())
        .environment(router)
    }

    private func selectTab(_ tab: AppTab) {
        dismissKeyboard()
        guard tab != selectedTab else { return }

        Haptics.selection()
        tabTransitionDirection = tab.index > selectedTab.index ? .forward : .backward
        withAnimation(.interactiveSpring(response: 0.44, dampingFraction: 0.86, blendDuration: 0.12)) {
            selectedTab = tab
        }
    }

    private func tabSwipeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .local)
            .onChanged { value in
                guard !tabSwipeLock.isLocked,
                      !didDismissKeyboardForCurrentSwipe,
                      isTabSwipe(value.translation) else {
                    return
                }

                didDismissKeyboardForCurrentSwipe = true
                dismissKeyboard()
            }
            .onEnded { value in
                didDismissKeyboardForCurrentSwipe = false
                guard !tabSwipeLock.isLocked, isTabSwipe(value.translation) else { return }

                let threshold = min(width * 0.26, 110)
                let predicted = value.predictedEndTranslation.width

                if value.translation.width < -threshold || predicted < -width * 0.35 {
                    selectRelativeTab(offset: 1)
                } else if value.translation.width > threshold || predicted > width * 0.35 {
                    selectRelativeTab(offset: -1)
                }
            }
    }

    private func selectRelativeTab(offset: Int) {
        let nextIndex = min(max(selectedTab.index + offset, 0), AppTab.allCases.count - 1)
        selectTab(AppTab.allCases[nextIndex])
    }

    private func isTabSwipe(_ translation: CGSize) -> Bool {
        abs(translation.width) > 42 && abs(translation.width) > abs(translation.height) * 1.9
    }

    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.dismissKeyboard()
        #endif
    }
}

private struct HomeAccessLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            NinaMark(size: 84, presence: .reading)
            Text("Vendo se a casa ainda é sua.")
                .ninaText(.label, NinaTheme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ninaScreenBackground()
    }
}

private struct HomeAccessUnavailableView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(OnboardingStore.self) private var onboardingStore

    var body: some View {
        // Nina is the subject here, so she renders without pigment rather than
        // beside an alarm colour: losing the connection is not lateness.
        VStack(spacing: 0) {
            ZeroState(
                headline: "Não deu para confirmar a sua casa.",
                body_: store.syncErrorMessage
                    ?? "Sem conexão, a Nina não consegue checar se você ainda faz parte desta casa. Nada foi perdido.",
                presence: .unavailable
            ) {
                VStack(spacing: 10) {
                    NinaButton(
                        title: "Tentar de novo",
                        systemName: "arrow.clockwise",
                        isEnabled: !store.isSyncingHome
                    ) {
                        Task { await store.activateHomeContext(for: authSession.currentUser) }
                    }

                    NinaButton(title: "Sair da conta", kind: .quiet) {
                        Task {
                            onboardingStore.cancelReplay()
                            await authSession.signOut()
                        }
                    }
                }
            }
        }
        .padding(28)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ninaScreenBackground()
    }
}

#if canImport(UIKit)
struct KeyboardVisibilityModifier: ViewModifier {
    @Binding var isVisible: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                if !isVisible {
                    isVisible = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                if isVisible {
                    isVisible = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                if isVisible {
                    isVisible = false
                }
            }
    }
}

private struct KeyboardDismissTapModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay {
            KeyboardDismissTapInstaller()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
    }
}

private struct KeyboardDismissTapInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.isUserInteractionEnabled = false
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.install(in: window)
        }
        return view
    }

    func updateUIView(_ view: InstallerView, context: Context) {
        context.coordinator.install(in: view.window)
    }

    final class InstallerView: UIView {
        var windowDidChange: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            windowDidChange?(window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var installedWindow: UIWindow?
        private var recognizer: UITapGestureRecognizer?

        func install(in window: UIWindow?) {
            guard let window, window !== installedWindow else { return }

            if let recognizer, let installedWindow {
                installedWindow.removeGestureRecognizer(recognizer)
            }

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)

            self.recognizer = recognizer
            installedWindow = window
        }

        @objc private func dismissKeyboard() {
            UIApplication.shared.dismissKeyboard()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let window = installedWindow,
                  let firstResponder = window.firstResponder,
                  !touch.startedInsideTextInput,
                  !touch.startedInside(view: firstResponder) else {
                return false
            }

            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        deinit {
            if let recognizer, let installedWindow {
                installedWindow.removeGestureRecognizer(recognizer)
            }
        }
    }
}

private extension UITouch {
    var startedInsideTextInput: Bool {
        var view = self.view

        while let currentView = view {
            if currentView is UITextField || currentView is UITextView || currentView is UISearchBar {
                return true
            }

            view = currentView.superview
        }

        return false
    }

    func startedInside(view: UIView) -> Bool {
        guard let touchView = self.view else { return false }
        let location = self.location(in: view)
        return touchView.window === view.window && view.bounds.contains(location)
    }
}

private extension UIApplication {
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private extension UIWindow {
    var firstResponder: UIView? {
        findFirstResponder(in: self)
    }

    func findFirstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder {
            return view
        }

        for subview in view.subviews {
            if let responder = findFirstResponder(in: subview) {
                return responder
            }
        }

        return nil
    }
}
#else
struct KeyboardVisibilityModifier: ViewModifier {
    @Binding var isVisible: Bool

    func body(content: Content) -> some View {
        content
    }
}

private struct KeyboardDismissTapModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}
#endif

extension View {
    func tracksKeyboardVisibility(_ isVisible: Binding<Bool>) -> some View {
        modifier(KeyboardVisibilityModifier(isVisible: isVisible))
    }
}

private extension View {
    func keyboardDismissesOnOutsideTap() -> some View {
        modifier(KeyboardDismissTapModifier())
    }
}

private struct KeyboardAwareBottomTabBar: View {
    var selectedTab: AppTab
    var select: (AppTab) -> Void
    @State private var isKeyboardVisible = false

    var body: some View {
        BottomTabBar(selectedTab: selectedTab, select: select)
            .opacity(isKeyboardVisible ? 0 : 1)
            .allowsHitTesting(!isKeyboardVisible)
            .accessibilityHidden(isKeyboardVisible)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .animation(nil, value: isKeyboardVisible)
            .tracksKeyboardVisibility($isKeyboardVisible)
    }
}

private struct AppLoadingScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            NinaTheme.ground.ignoresSafeArea()

            VStack(spacing: 20) {
                NinaMark(size: 96, presence: .listening)
                    .scaleEffect(reduceMotion ? 1 : (isBreathing ? 1.02 : 0.98))

                Text("Nina").ninaText(.display)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Nina")
        }
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}

private struct BottomTabBar: View {
    @Environment(AppStore.self) private var store
    var selectedTab: AppTab
    var select: (AppTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    select(tab)
                } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 22, weight: .regular))
                                .frame(height: 24)

                            if tab == .house, store.pendingJoinRequestCount > 0 {
                                Circle()
                                    .fill(NinaTheme.cobalt)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 6, y: -1)
                            }
                        }

                        Text(tab.title)
                            .font(.system(size: 12, weight: tab == selectedTab ? .semibold : .regular))
                    }
                    .foregroundStyle(tab == selectedTab ? NinaTheme.cobalt : NinaTheme.muted)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(tab == selectedTab ? [.isSelected] : [])
            }
        }
        .padding(.top, 9)
        .padding(.bottom, 2)
        .background(alignment: .top) {
            NinaTheme.ground
                .overlay(alignment: .top) {
                    Rectangle().fill(NinaTheme.line).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

private extension AppTab {
    var index: Int {
        AppTab.allCases.firstIndex(of: self) ?? 0
    }

    var title: String {
        switch self {
        case .nina: "Nina"
        case .today: "Hoje"
        case .tasks: "Tarefas"
        case .house: "Casa"
        }
    }

    var systemImage: String {
        switch self {
        case .nina: "bubble.left"
        case .today: "clock"
        case .tasks: "text.alignleft"
        case .house: "house"
        }
    }
}

private struct AppRoutesModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Route.self) { route in
                Group {
                    switch route {
                    case .task(let id):
                        TaskRouteDetail(taskID: id)
                    case .member(let id):
                        MemberRouteDetail(memberID: id)
                    case .workload:
                        WorkloadView()
                    case .memories:
                        MemoriesView()
                    }
                }
                // Pushed screens draw their own back affordance, so the system
                // bar would be a second one sitting on top of it.
                .toolbar(.hidden, for: .navigationBar)
            }
    }
}

private struct SheetDestinationsModifier: ViewModifier {
    @Binding var sheet: SheetDestination?

    func body(content: Content) -> some View {
        content.sheet(item: $sheet) { destination in
            NavigationStack {
                switch destination {
                case .settings:
                    SettingsSheet()
                case .premium:
                    PremiumBenefitsSheet()
                case .addTask:
                    TaskEditorSheet(mode: .add(sectionID: AppStore.houseTasksSectionID))
                case .addTaskInSection(let sectionID):
                    TaskEditorSheet(mode: .add(sectionID: sectionID))
                case .editTask(let id):
                    TaskEditorSheet(mode: .edit(id))
                case .plantSeed(let id):
                    TaskEditorSheet(mode: .plant(id))
                case .addShoppingItem:
                    ShoppingEditorSheet(mode: .add)
                case .editShoppingItem(let id):
                    ShoppingEditorSheet(mode: .edit(id))
                case .inviteFamily:
                    InviteFamilySheet()
                case .addMemberProfile:
                    MemberEditorSheet(mode: .addProfile)
                case .member(let id):
                    MemberEditorSheet(mode: .edit(id))
                case .suggestion(let suggestion):
                    SuggestionDetailSheet(suggestion: suggestion)
                }
            }
            .presentationDragIndicator(.visible)
        }
    }
}

extension View {
    func withAppRoutes() -> some View {
        modifier(AppRoutesModifier())
    }

    func withSheetDestinations(sheet: Binding<SheetDestination?>) -> some View {
        modifier(SheetDestinationsModifier(sheet: sheet))
    }
}

#Preview("Loading") {
    AppLoadingScreen()
}

private struct TaskRouteDetail: View {
    @Environment(AppStore.self) private var store
    let taskID: UUID

    var body: some View {
        if let task = store.tasks.first(where: { $0.id == taskID }) {
            TaskDetailView(task: task)
        } else {
            ZeroState(
                headline: "Essa tarefa não está mais aqui.",
                body_: "Alguém da casa pode ter concluído ou apagado.",
                showsMark: false
            )
            .padding(24)
            .frame(maxHeight: .infinity)
            .ninaScreenBackground()
        }
    }
}

private struct MemberRouteDetail: View {
    @Environment(AppStore.self) private var store
    let memberID: UUID

    var body: some View {
        if let member = store.familyGroup.members.first(where: { $0.id == memberID }) {
            MemberDetailView(member: member)
        } else {
            ZeroState(
                headline: "Essa pessoa não está mais na casa.",
                body_: "Alguém com permissão pode ter removido o perfil.",
                showsMark: false
            )
            .padding(24)
            .frame(maxHeight: .infinity)
            .ninaScreenBackground()
        }
    }
}
