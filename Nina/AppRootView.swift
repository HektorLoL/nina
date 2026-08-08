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

    @ViewBuilder
    var label: some View {
        switch self {
        case .nina:
            Label("Nina", systemImage: "sparkles")
        case .today:
            Label("Hoje", systemImage: "sun.max.fill")
        case .tasks:
            Label("Tarefas", systemImage: "checklist")
        case .house:
            Label("Casa", systemImage: "house.fill")
        }
    }
}

enum Route: Hashable {
    case task(UUID)
    case member(UUID)
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
        .background(NinaTheme.screenGradient.ignoresSafeArea())
        .environment(tabSwipeLock)
        .tint(NinaTheme.mint)
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
        .alert(
            "Outra pessoa editou esta tarefa",
            isPresented: Binding(
                get: { store.taskEditConflict != nil },
                set: { isPresented in
                    if !isPresented {
                        store.acceptRemoteTaskConflict()
                    }
                }
            ),
            presenting: store.taskEditConflict
        ) { _ in
            Button("Manter minha edição") {
                store.keepLocalTaskConflict()
            }
            Button("Usar a edição mais recente", role: .cancel) {
                store.acceptRemoteTaskConflict()
            }
        } message: { conflict in
            Text("A tarefa “\(conflict.remoteTask.title)” mudou em outro aparelho. Escolha qual versão deve ficar.")
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
            NinaTheme.screenGradient
                .ignoresSafeArea()

            tabPager
                .ignoresSafeArea()

            KeyboardAwareBottomTabBar(selectedTab: selectedTab, select: selectTab)
        }
        .background(NinaTheme.screenGradient.ignoresSafeArea())
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

        NavigationStack(path: tabRouter.binding(for: tab)) {
            tab.makeContentView()
                .withAppRoutes()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            Haptics.lightImpact()
                            router.presentedSheet = .settings
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.title3.weight(.bold))
                        }
                        .accessibilityLabel("Abrir ajustes")
                    }
                }
        }
        .withSheetDestinations(
            sheet: Binding(
                get: { router.presentedSheet },
                set: { router.presentedSheet = $0 }
            )
        )
        .background(NinaTheme.screenGradient.ignoresSafeArea())
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
        VStack(spacing: 14) {
            ProgressView()
                .tint(NinaTheme.mint)

            Text("Verificando sua casa...")
                .font(.headline.weight(.heavy))
                .foregroundStyle(NinaTheme.ink)
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
        VStack(spacing: 18) {
            IconBubble(systemName: "wifi.exclamationmark", tone: .coral, size: 62)

            VStack(spacing: 8) {
                Text("Não foi possível verificar sua casa")
                    .font(.title2.weight(.black))
                    .foregroundStyle(NinaTheme.ink)
                    .multilineTextAlignment(.center)

                Text(store.syncErrorMessage ?? "Conecte-se à internet e tente novamente.")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(NinaTheme.muted)
                    .multilineTextAlignment(.center)
            }

            PrimaryCapsuleButton(title: "Tentar novamente", systemName: "arrow.clockwise") {
                Task {
                    await store.activateHomeContext(for: authSession.currentUser)
                }
            }
            .disabled(store.isSyncingHome)
            .opacity(store.isSyncingHome ? 0.6 : 1)

            Button("Sair") {
                Task {
                    onboardingStore.cancelReplay()
                    await authSession.signOut()
                }
            }
            .font(.headline.weight(.heavy))
            .foregroundStyle(NinaTheme.coral)
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
    @State private var activeDot = 0

    var body: some View {
        ZStack {
            NinaTheme.screenGradient
                .ignoresSafeArea()

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .stroke(NinaTheme.mint.opacity(0.14), lineWidth: 16)
                        .frame(width: 124, height: 124)
                        .scaleEffect(reduceMotion ? 1 : (isBreathing ? 1.04 : 0.96))
                        .opacity(reduceMotion ? 1 : (isBreathing ? 0.55 : 1))

                    NinaAvatarView(size: 88)
                        .scaleEffect(reduceMotion ? 1 : (isBreathing ? 1.02 : 0.98))
                }

                VStack(spacing: 7) {
                    Text("Nina")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(NinaTheme.ink)

                    Text("Organizando a casa...")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(NinaTheme.muted)
                }

                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index == activeDot ? NinaTheme.mint : NinaTheme.line.opacity(0.75))
                            .frame(width: index == activeDot ? 18 : 8, height: 8)
                    }
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: activeDot)
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 32)
            .background(NinaTheme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(NinaTheme.cardStroke, lineWidth: 1)
            )
            .cardShadow()
            .padding(24)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Nina está carregando")
        }
        .task {
            guard !reduceMotion else { return }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 320_000_000)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    activeDot = (activeDot + 1) % 3
                }
            }
        }
    }
}

private struct BottomTabBar: View {
    var selectedTab: AppTab
    var select: (AppTab) -> Void
    @Namespace private var sliderNamespace
    @Namespace private var glassNamespace

    var body: some View {
        tabButtons
            .frame(height: 60)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .bottomTabBarSurface()
            .padding(.horizontal, 18)
            .padding(.bottom, 6)
            .bottomTabBarShadow()
            .animation(.interactiveSpring(response: 0.44, dampingFraction: 0.86, blendDuration: 0.12), value: selectedTab)
    }

    @ViewBuilder
    private var tabSelectionTrack: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 6) {
                tabSelectionPills
            }
        } else {
            tabSelectionPills
        }
        #else
        tabSelectionPills
        #endif
    }

    private var tabButtons: some View {
        ZStack {
            tabSelectionTrack
                .allowsHitTesting(false)

            HStack(spacing: 6) {
                ForEach(AppTab.allCases) { tab in
                    Button {
                        select(tab)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 19, weight: .black))

                            Text(tab.title)
                                .font(.caption2.weight(.black))
                        }
                        .foregroundStyle(selectedTab == tab ? NinaTheme.mintInk : NinaTheme.ink.opacity(0.72))
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Aba \(tab.title)")
                }
            }
        }
    }

    private var tabSelectionPills: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases) { tab in
                ZStack {
                    if selectedTab == tab {
                        TabSelectionPill()
                            .frame(height: 62)
                            .padding(.horizontal, -3)
                            .offset(y: 1)
                            .matchedGeometryEffect(id: "tab-slider", in: sliderNamespace)
                            .tabSliderGlassID(in: glassNamespace)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
            }
        }
    }
}

private struct TabSelectionPill: View {
    var body: some View {
        lens
            .compositingGroup()
            .shadow(color: NinaTheme.mint.opacity(0.18), radius: 12, x: 0, y: 6)
            .shadow(color: NinaTheme.shadow.opacity(0.22), radius: 16, x: 0, y: 10)
    }

    @ViewBuilder
    private var lens: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.02))
                .glassEffect(
                    .regular.tint(NinaTheme.mint.opacity(0.18)),
                    in: Capsule(style: .continuous)
                )
                .overlay(lensHighlights)
        } else {
            fallbackLens
        }
        #else
        fallbackLens
        #endif
    }

    private var fallbackLens: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.72), location: 0),
                            .init(color: Color.white.opacity(0.24), location: 0.46),
                            .init(color: NinaTheme.mint.opacity(0.16), location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Capsule(style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.86),
                            Color.white.opacity(0.18),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 3,
                        endRadius: 92
                    )
                )
                .blendMode(.screen)
        }
        .clipShape(Capsule(style: .continuous))
        .overlay(lensHighlights)
    }

    private var lensHighlights: some View {
        ZStack {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.78), lineWidth: 1)

            Capsule(style: .continuous)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.white.opacity(0),
                            NinaTheme.sky.opacity(0.55),
                            NinaTheme.lavender.opacity(0.5),
                            NinaTheme.gold.opacity(0.58),
                            NinaTheme.coral.opacity(0.38),
                            Color.white.opacity(0)
                        ],
                        center: .center
                    ),
                    lineWidth: 2.2
                )
                .blur(radius: 0.7)
                .opacity(0.9)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.88),
                            Color.white.opacity(0.24),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 18)
                .padding(.horizontal, 18)
                .offset(y: -19)
                .blur(radius: 1.3)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            NinaTheme.sky.opacity(0.24),
                            NinaTheme.gold.opacity(0.22),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 12)
                .padding(.horizontal, 10)
                .offset(y: 21)
                .blur(radius: 1.6)
        }
        .allowsHitTesting(false)
    }
}

private extension View {
    @ViewBuilder
    func bottomTabBarSurface() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self
                .background(bottomTabBarGlassBackground)
                .overlay(bottomTabBarStroke)
        } else {
            bottomTabBarFallbackSurface()
        }
        #else
        bottomTabBarFallbackSurface()
        #endif
    }

    private func bottomTabBarFallbackSurface() -> some View {
        background {
            bottomTabBarFallbackBackground
        }
        .overlay(bottomTabBarStroke)
    }

    @ViewBuilder
    private var bottomTabBarGlassBackground: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.01))
                .glassEffect(
                    .regular.tint(Color.white.opacity(0.08)),
                    in: RoundedRectangle(cornerRadius: 30, style: .continuous)
                )
        } else {
            bottomTabBarFallbackBackground
        }
        #else
        bottomTabBarFallbackBackground
        #endif
    }

    private var bottomTabBarFallbackBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(NinaTheme.bar.opacity(0.88))
        }
    }

    private var bottomTabBarStroke: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .stroke(NinaTheme.line.opacity(0.7), lineWidth: 1)
    }

    @ViewBuilder
    func tabSliderGlassID(in namespace: Namespace.ID) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffectID("tab-slider", in: namespace)
        } else {
            self
        }
        #else
        self
        #endif
    }

    func bottomTabBarShadow() -> some View {
        shadow(color: NinaTheme.shadow.opacity(0.28), radius: 6, x: 0, y: 2)
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
        case .nina: "sparkles"
        case .today: "sun.max.fill"
        case .tasks: "checklist"
        case .house: "house.fill"
        }
    }
}

private struct AppRoutesModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .task(let id):
                    TaskRouteDetail(taskID: id)
                case .member(let id):
                    MemberRouteDetail(memberID: id)
                }
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
            TaskDetailCard(task: task)
                .padding(20)
                .ninaScreenBackground()
                .navigationTitle("Tarefa")
                .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Tarefa não encontrada", systemImage: "checklist")
        }
    }
}

private struct MemberRouteDetail: View {
    @Environment(AppStore.self) private var store
    let memberID: UUID

    var body: some View {
        if let member = store.familyGroup.members.first(where: { $0.id == memberID }) {
            MemberDetailContent(member: member)
                .padding(20)
                .ninaScreenBackground()
                .navigationTitle(member.name)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Pessoa não encontrada", systemImage: "person.crop.circle")
        }
    }
}
