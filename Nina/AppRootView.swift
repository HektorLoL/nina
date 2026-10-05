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
    case addSeed
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
        case .addSeed:
            "add-seed"
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
    // Created up front, never lazily: filling this dictionary from inside `body`
    // mutates observed state during a view update.
    private var routers: [AppTab: RouterPath] = Dictionary(
        uniqueKeysWithValues: AppTab.allCases.map { ($0, RouterPath()) }
    )

    func router(for tab: AppTab) -> RouterPath {
        routers[tab] ?? RouterPath()
    }

    func binding(for tab: AppTab) -> Binding<[Route]> {
        let router = router(for: tab)
        return Binding(
            get: { router.path },
            set: { router.path = $0 }
        )
    }
}

enum AppEntryPhase: Hashable {
    case signedOut
    case ageCheck
    case homeLoading
    case homeUnavailable
    case minorRoot
    case majority
    case termsAcceptance
    case invite
    case tutorial
    case pendingApproval
    case accessDecision
    case homeSetup
    case app
}

struct AppEntryInputs {
    var isSignedIn: Bool
    var needsAgeCheck: Bool
    var homeAccessState: HomeAccessState
    var viewerIsAdult: Bool
    var reachedMajority: Bool = false
    var needsTermsAcceptance: Bool = false
    var hasPendingInvite: Bool
    var shouldShowTutorial: Bool
}

// The age step precedes everything a signed-in person can reach, and a non-adult never meets the invite,
// the tutorial or the four tabs: their whole app is minorRoot.
enum AppEntryRouting {
    static func phase(for inputs: AppEntryInputs) -> AppEntryPhase {
        guard inputs.isSignedIn else { return .signedOut }
        if inputs.needsAgeCheck { return .ageCheck }
        if inputs.homeAccessState == .loading { return .homeLoading }
        // A failed verification says nothing about age, so it is never read as a minor's screen.
        if inputs.homeAccessState == .unavailable { return .homeUnavailable }
        if !inputs.viewerIsAdult { return .minorRoot }
        if inputs.reachedMajority { return .majority }
        if inputs.needsTermsAcceptance { return .termsAcceptance }
        if inputs.hasPendingInvite { return .invite }
        if inputs.shouldShowTutorial { return .tutorial }

        switch inputs.homeAccessState {
        case .loading:
            return .homeLoading
        case .noHome:
            return .homeSetup
        case .pendingApproval:
            return .pendingApproval
        case .accessDecision:
            return .accessDecision
        case .unavailable, .minorMember:
            return .homeUnavailable
        case .authorized:
            return .app
        }
    }
}

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(OnboardingStore.self) private var onboardingStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(PremiumSubscriptionStore.self) private var premiumSubscriptionStore
    @Environment(InviteLinkStore.self) private var inviteLinkStore
    @Environment(AgeCheckCoordinator.self) private var ageCheck

    @State private var selectedTab: AppTab = .nina
    @State private var tabRouter = TabRouter()
    @State private var isShowingLoadingScreen = true
    @State private var isCoveringForPrivacy = false
    @State private var isAppShellMounted = false
    @State private var didFinishInitialLoad = false
    @State private var shouldRefreshWhenActive = false

    var body: some View {
        ZStack {
            if isAppShellMounted {
                entryContent
                    .disabled(isShowingLoadingScreen)
            }

            if isShowingLoadingScreen {
                AppLoadingScreen()
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.015)))
                    .zIndex(1)
            }

            if isCoveringForPrivacy {
                AppLoadingScreen(showsRating: false)
                    .transition(.opacity)
                    .zIndex(4)
            }
        }
        .background(NinaTheme.ground.ignoresSafeArea())
        .tint(NinaTheme.cobalt)
        .keyboardDismissesOnOutsideTap()
        .animation(.easeInOut(duration: 0.28), value: entryPhase)
        .onChange(of: authSession.currentUser?.id) { oldValue, newValue in
            guard oldValue != newValue else { return }
            // Signing out takes the household off this phone; the server holds it for the next sign-in.
            if let oldValue, newValue == nil {
                store.clearHouseholdCopy(for: oldValue)
                profileStore.clearLocalData(for: oldValue)
            }
            if let newValue, authSession.interactiveSignInUserID == newValue {
                store.noteTermsFootnoteShown(for: newValue)
            }
            Task {
                await profileStore.refreshProfile(for: authSession.currentUser)
                await loadHomeAndAge()
                await premiumSubscriptionStore.configure(for: authSession.currentUser)
            }
            selectedTab = .nina
            tabRouter = TabRouter()
        }
        .onChange(of: store.ageCheckRequested) { _, requested in
            guard requested else { return }
            store.ageCheckRequested = false
            ageCheck.requestPrompt()
        }
        .onChange(of: store.homeAccessState) { _, newState in
            guard newState == .minorMember, scenePhase == .active else { return }
            store.minorSceneBecameActive()
        }
        .onChange(of: store.hasActiveHome) { _, _ in
            selectedTab = .nina
            tabRouter = TabRouter()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // The app-switcher snapshot is taken while inactive; a boleto reading
            // in the chat must not be what it captures.
            isCoveringForPrivacy = newPhase != .active && isAppShellMounted

            if newPhase == .background {
                shouldRefreshWhenActive = didFinishInitialLoad
                Task { await store.minorSceneLeftForeground() }
                return
            }

            guard newPhase == .active else { return }
            store.minorSceneBecameActive()
            guard shouldRefreshWhenActive else { return }
            shouldRefreshWhenActive = false

            Task {
                await authSession.restoreSession()
                await profileStore.refreshProfile(for: authSession.currentUser)
                await store.refreshHomeFromRemote(for: authSession.currentUser)
                await evaluateAge(for: authSession.currentUser)
                await premiumSubscriptionStore.configure(for: authSession.currentUser)
                await store.refreshNotificationAuthorizationStatus()
                store.synchronizeLocalNotifications()
            }
        }
        .task {
            ageCheck.onRejection = { message in store.reportSyncError(message) }
            await authSession.restoreSession()
            await profileStore.refreshProfile(for: authSession.currentUser)
            await premiumSubscriptionStore.configure(for: authSession.currentUser)
            await loadHomeAndAge()
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
        // Presented from the root: neither a lost home nor a tab reset can close a child's list without the hold.
        .fullScreenCover(
            item: Binding(
                get: { store.childDayPresentation },
                set: { presentation in
                    if presentation == nil { store.dismissChildDay() }
                }
            )
        ) { presentation in
            ChildDayView(childID: presentation.childID, session: presentation.session)
        }
    }

    private var entryPhase: AppEntryPhase {
        AppEntryRouting.phase(
            for: AppEntryInputs(
                isSignedIn: authSession.isSignedIn,
                needsAgeCheck: ageCheck.needsAgeCheck,
                homeAccessState: store.homeAccessState,
                viewerIsAdult: store.viewerAge.isAdult,
                reachedMajority: store.viewerAge.terms.reachedMajority,
                needsTermsAcceptance: store.needsTermsAcceptance,
                hasPendingInvite: inviteLinkStore.pendingCode != nil,
                shouldShowTutorial: onboardingStore.shouldShowTutorial(for: authSession.currentUser)
            )
        )
    }

    private func loadHomeAndAge() async {
        let user = authSession.currentUser
        await store.activateHomeContext(for: user)
        await evaluateAge(for: user)
    }

    private func evaluateAge(for user: AuthUser?) async {
        let isVerified = store.homeAccessState != .loading && store.homeAccessState != .unavailable
        guard let status = await ageCheck.evaluate(
            user: user,
            age: store.viewerAge,
            isVerified: isVerified,
            isLocalContext: store.isUsingLocalContext
        ) else { return }
        await store.applyRecordedAge(status, for: user)
    }

    @ViewBuilder
    private var entryContent: some View {
        switch entryPhase {
        case .signedOut:
            LoginView()
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .ageCheck:
            AgeCheckView()
                .transition(.opacity)
        case .minorRoot:
            MinorRootView()
                .transition(.opacity)
        case .majority:
            AgeMajorityView()
                .transition(.opacity)
        case .termsAcceptance:
            AgeMajorityView(reason: store.hasUnrecordedTermsFootnote ? .termsNotYetRecorded : .termsChanged)
                .transition(.opacity)
        case .tutorial:
            OnboardingTutorialView()
                .transition(.opacity.combined(with: .scale(scale: 1.01)))
        case .homeLoading:
            AppWaitingScreen()
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

    private var syncErrorToastBottomPadding: CGFloat {
        let base: CGFloat = tabRouter.router(for: selectedTab).path.isEmpty ? 164 : 16
        let undoIsVisible = store.undoableCompletionID.map { id in
            store.tasks.contains { $0.id == id }
        } ?? false
        return undoIsVisible ? base + 62 : base
    }

    @ViewBuilder
    private var appShell: some View {
        ZStack(alignment: .bottom) {
            NinaTheme.ground
                .ignoresSafeArea()

            tabPager
                .ignoresSafeArea()

            if let id = store.undoableCompletionID,
               let task = store.tasks.first(where: { $0.id == id }) {
                UndoCompletionToast(title: task.title)
                    .padding(.bottom, tabRouter.router(for: selectedTab).path.isEmpty ? 164 : 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(2)
            }

            // A write that fails after the screen moved on must still be reported
            // where the person is, not on whichever tab happens to read the string.
            if let message = store.syncErrorMessage {
                SyncErrorToast(message: message)
                    .padding(.bottom, syncErrorToastBottomPadding)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(3)
            }

            // A pushed screen owns the whole viewport: it has its own back
            // affordance and a footer that would otherwise sit under the bar.
            if tabRouter.router(for: selectedTab).path.isEmpty {
                KeyboardAwareBottomTabBar(selectedTab: selectedTab, select: selectTab)
                    .transition(.opacity)
            }
        }
        .background(NinaTheme.ground.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: store.undoableCompletionID)
        .onReceive(NotificationCenter.default.publisher(for: .ninaSelectChatTab)) { _ in
            travel(to: .nina)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ninaShowUnowned)) { _ in
            travel(to: .tasks)
        }
        .onAppear(perform: followReminder)
        .onChange(of: selectedTab, initial: true) { _, tab in
            if tab == .house { store.markInsightsSeen() }
        }
        .onChange(of: store.insights.first?.id) { _, _ in
            if selectedTab == .house { store.markInsightsSeen() }
        }
        .onChange(of: TaskNotificationRoute.shared.pending) { _, _ in
            followReminder()
        }
    }

    // A reminder's tap lands on its task in Hoje; a task that is gone by then opens nothing.
    // A finished task stays on Hoje under the undo toast; anything else shows the task itself.
    private func followReminder() {
        guard let route = TaskNotificationRoute.shared.pending else { return }
        TaskNotificationRoute.shared.pending = nil
        guard let task = store.tasks.first(where: { $0.id == route.taskID }) else { return }
        dismissKeyboard()
        selectedTab = .today
        let router = tabRouter.router(for: .today)
        router.presentedSheet = nil
        switch route.action {
        case .complete where route.completes(task):
            router.path = []
            store.toggleTask(task)
            Haptics.success()
        case .snooze:
            if let target = route.snoozeTarget(for: task, now: .now) {
                store.snoozeTask(task.id, until: target)
                Haptics.success()
            }
            router.path = [.task(task.id)]
        case .open, .complete:
            router.path = [.task(task.id)]
        }
    }

    @ViewBuilder
    private var tabPager: some View {
        GeometryReader { proxy in
            // Every tab stays mounted: each owns a navigation stack and a scroll position.
            ZStack {
                ForEach(AppTab.allCases) { tab in
                    tabContent(for: tab)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .opacity(tab == selectedTab ? 1 : 0)
                        .offset(x: restingOffset(for: tab))
                        .zIndex(tab == selectedTab ? 1 : 0)
                        .allowsHitTesting(tab == selectedTab)
                        .accessibilityHidden(tab != selectedTab)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
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
        selectedTab = tab
    }

    // A tap on the bar switches instantly; only a jump from inside a screen travels.
    private func travel(to tab: AppTab) {
        dismissKeyboard()
        guard tab != selectedTab else { return }

        Haptics.selection()
        withAnimation(.smooth(duration: 0.36)) {
            selectedTab = tab
        }
    }

    private func restingOffset(for tab: AppTab) -> CGFloat {
        guard tab != selectedTab, !reduceMotion else { return 0 }
        let order = AppTab.allCases
        let isBehind = (order.firstIndex(of: tab) ?? 0) < (order.firstIndex(of: selectedTab) ?? 0)
        return isBehind ? -32 : 32
    }

    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.dismissKeyboard()
        #endif
    }
}

private struct HomeAccessUnavailableView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(OnboardingStore.self) private var onboardingStore
    @State private var isShowingDeletion = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                // Nina is the subject here, so she renders without pigment rather than
                // beside an alarm colour: losing the connection is not lateness.
                ZeroState(
                    headline: "Não deu para abrir a casa.",
                    body_: "Nada foi perdido.",
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
                            Haptics.warning()
                            Task {
                                onboardingStore.cancelReplay()
                                await authSession.signOut()
                            }
                        }

                        NinaButton(title: "Apagar conta", kind: .quiet) {
                            Haptics.lightImpact()
                            isShowingDeletion = true
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .ninaScreenBackground()
        .accountDeletionSheet(isPresented: $isShowingDeletion)
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

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    // A pop begun on a root screen or mid-transition leaves the whole stack frozen.
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1 && transitionCoordinator == nil
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

// Ink and weight, never a hue: this is a neutral confirmation, not a state.
private struct SyncErrorToast: View {
    @Environment(AppStore.self) private var store
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NinaTheme.alert)
                .padding(.top, 1)

            Text(message)
                .ninaText(.caption, NinaTheme.ink, weight: .medium)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button {
                Haptics.selection()
                store.dismissSyncError(ifStill: message)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NinaTheme.muted)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fechar aviso")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard(fill: NinaTheme.alertWash, stroke: NinaTheme.alert.opacity(0.35))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .task(id: message) {
            AccessibilityNotification.Announcement(message).post()
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            store.dismissSyncError(ifStill: message)
        }
    }
}

private struct UndoCompletionToast: View {
    @Environment(AppStore.self) private var store
    var title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(NinaTheme.ground)
                .frame(width: 24, height: 24)
                .background(NinaTheme.moss, in: Circle())
                .accessibilityHidden(true)

            Text(title)
                .ninaText(.label, NinaTheme.ground, weight: .medium)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                Haptics.selection()
                store.undoLastCompletion()
            } label: {
                Text("Desfazer")
                    .ninaText(.label, NinaTheme.ground, weight: .semibold)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .frame(minHeight: 50)
        .background(NinaTheme.ink, in: Capsule())
        .padding(.horizontal, 20)
    }
}

private struct KeyboardAwareBottomTabBar: View {
    var selectedTab: AppTab
    var select: (AppTab) -> Void
    @State private var isKeyboardVisible = false

    var body: some View {
        BottomTabBar(selectedTab: selectedTab, select: select)
            // Tab titles grow with the reader's setting up to the largest non-accessibility size;
            // past that, a four-word bar has no room, so it stops where UIKit's own tab bar stops.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .opacity(isKeyboardVisible ? 0 : 1)
            .allowsHitTesting(!isKeyboardVisible)
            .accessibilityHidden(isKeyboardVisible)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .animation(nil, value: isKeyboardVisible)
            .tracksKeyboardVisibility($isKeyboardVisible)
    }
}

struct AppLoadingScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var showsRating = true
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            // The rating is shown at login and startup, and nowhere else in the app.
            if showsRating {
                ClassIndMark()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 16)
            }
        }
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}

// A wait never borrows Nina's reading state; that bar belongs to a turn in flight.
struct AppWaitingScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        VStack(spacing: 16) {
            NinaMark(size: 64, presence: .rest)
                .scaleEffect(reduceMotion ? 1 : (isBreathing ? 1.02 : 0.98))
            Text("Só um instante.")
                .ninaText(.label, NinaTheme.muted)
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .ninaScreenBackground()
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

                            if showsDot(on: tab) {
                                Circle()
                                    .fill(NinaTheme.cobalt)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 6, y: -1)
                            }
                        }

                        Text(tab.title)
                            .ninaText(.meta, tab == selectedTab ? NinaTheme.ink : NinaTheme.muted, weight: tab == selectedTab ? .semibold : .regular)
                    }
                    .foregroundStyle(tab == selectedTab ? NinaTheme.ink : NinaTheme.muted)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityValue(dotValue(for: tab))
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

    private func showsDot(on tab: AppTab) -> Bool {
        switch tab {
        case .house: store.pendingJoinRequestCount > 0 || (tab != selectedTab && store.hasUnseenInsight)
        case .nina: tab != selectedTab && store.waitingProposalCount > 0
        case .today, .tasks: false
        }
    }

    private func dotValue(for tab: AppTab) -> String {
        guard showsDot(on: tab) else { return "" }
        switch tab {
        case .house:
            return store.pendingJoinRequestCount > 0
                ? "\(store.pendingJoinRequestCount) pedindo para entrar"
                : "Resumo semanal novo"
        case .nina: return ProposalBacklog.line(count: store.waitingProposalCount)
        case .today, .tasks: return ""
        }
    }
}

private extension AppTab {
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
                    PremiumEntryView()
                case .addTask:
                    TaskEditorSheet(mode: .add(sectionID: AppStore.houseTasksSectionID))
                case .addSeed:
                    TaskEditorSheet(
                        mode: .add(sectionID: AppStore.houseTasksSectionID),
                        initialKind: .seed
                    )
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

#Preview("Waiting") {
    AppWaitingScreen()
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
                headline: "Essa pessoa não está mais aqui.",
                body_: "Alguém pode ter removido este perfil.",
                showsMark: false
            )
            .padding(24)
            .frame(maxHeight: .infinity)
            .ninaScreenBackground()
        }
    }
}
