import SwiftUI

@main
struct NinaApp: App {
    @State private var store: AppStore
    @State private var authSession: AuthSessionStore
    @State private var onboardingStore = OnboardingStore()
    @State private var profileStore: ProfileStore
    @State private var premiumSubscriptionStore: PremiumSubscriptionStore
    @State private var backendDiagnostics: BackendDiagnosticsStore
    @State private var inviteLinkStore = InviteLinkStore()

    init() {
        let diagnostics = BackendDiagnosticsStore(environment: BackendServices.environment)
        _backendDiagnostics = State(initialValue: diagnostics)
        _store = State(
            initialValue: AppStore(
                remoteHomeBackend: BackendServices.makeRemoteHomeBackend(diagnostics: diagnostics),
                ninaEngine: BackendServices.makeNinaEngine(diagnostics: diagnostics)
            )
        )
        _authSession = State(
            initialValue: AuthSessionStore(
                authClient: BackendServices.makeAuthClient(diagnostics: diagnostics)
            )
        )
        _profileStore = State(
            initialValue: ProfileStore(
                remoteProfileBackend: BackendServices.makeRemoteProfileBackend(diagnostics: diagnostics)
            )
        )
        _premiumSubscriptionStore = State(
            initialValue: PremiumSubscriptionStore(
                backend: BackendServices.makePremiumSubscriptionBackend(diagnostics: diagnostics)
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(store)
                .environment(authSession)
                .environment(onboardingStore)
                .environment(profileStore)
                .environment(premiumSubscriptionStore)
                .environment(backendDiagnostics)
                .environment(inviteLinkStore)
                .onOpenURL { url in
                    inviteLinkStore.receive(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    inviteLinkStore.receive(url)
                }
        }
    }
}
