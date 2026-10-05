import SwiftUI

// Seen by every age before anything else, so Nina is never the speaker here.
struct AgeCheckView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(AgeCheckCoordinator.self) private var ageCheck
    @Environment(OnboardingStore.self) private var onboardingStore

    @State private var isShowingDeletion = false

    var body: some View {
        if isWaiting {
            AppWaitingScreen()
        } else {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 32)
                        content
                        Spacer(minLength: 32)
                        accountExits
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .ninaScreenBackground()
            .accountDeletionSheet(isPresented: $isShowingDeletion)
        }
    }

    // The first screen after sign-in still lets a person leave or delete before answering Apple.
    private var accountExits: some View {
        VStack(spacing: 4) {
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
        .frame(maxWidth: .infinity)
    }

    private var isWaiting: Bool {
        switch ageCheck.phase {
        case .requesting, .recording: true
        case .idle, .prompt, .declined, .appleError, .attestFailure: false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch ageCheck.phase {
        case .idle, .prompt, .requesting, .recording:
            prompt
        case .declined:
            failure(
                headline: "Falta sua faixa de idade.",
                line: "Sem ela, só um responsável aprova sua entrada.",
                retryTitle: "Compartilhar faixa"
            )
        case .appleError:
            failure(
                headline: "A Apple não respondeu agora.",
                line: "Tente de novo em instantes.",
                retryTitle: "Tentar de novo"
            )
        case .attestFailure:
            failure(
                headline: "Não deu para confirmar este iPhone.",
                line: "Tente de novo em instantes.",
                retryTitle: "Tentar de novo"
            )
        }
    }

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 16) {
            NinaMark(size: 48)

            Text("Antes, sua faixa de idade.")
                .ninaText(.screen)
                .fixedSize(horizontal: false, vertical: true)

            Text("A Apple informa só a faixa, nunca a data de nascimento.")
                .ninaText(.label, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            NinaButton(title: "Continuar", fillsWidth: true) {
                Haptics.lightImpact()
                share()
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func failure(headline: String, line: String, retryTitle: String) -> some View {
        ZeroState(headline: headline, body_: line, presence: .unavailable) {
            VStack(spacing: 10) {
                NinaButton(title: retryTitle, fillsWidth: true) {
                    Haptics.lightImpact()
                    share()
                }

                NinaButton(title: "Continuar assim", kind: .quiet) {
                    Haptics.selection()
                    ageCheck.continueWithout(for: authSession.currentUser)
                }
            }
            .frame(maxWidth: 320)
        }
    }

    private func share() {
        guard let user = authSession.currentUser else { return }
        Task {
            guard let status = await ageCheck.requestAndRecord(for: user) else { return }
            await store.applyRecordedAge(status, for: user)
        }
    }
}

// Shown once when Apple reports that a former minor is now an adult, or when the Terms changed since
// this adult last accepted them. Accepting is the only way in, so leaving and deleting stay one tap away.
struct AgeMajorityView: View {
    enum Reason {
        case majority
        case termsChanged
        // This phone's welcome footnote was accepted but never recorded, so nothing here may say the Terms changed.
        case termsNotYetRecorded

        var headline: String {
            switch self {
            case .majority: "Agora a conta é sua."
            case .termsChanged: "Os Termos mudaram."
            case .termsNotYetRecorded: "Antes, os Termos."
            }
        }

        var line: String {
            switch self {
            case .majority: "A Apple informou que você tem 18 anos ou mais."
            case .termsChanged: "Para continuar, leia e aceite a nova versão."
            case .termsNotYetRecorded: "Para continuar, leia e aceite os Termos."
            }
        }
    }

    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(OnboardingStore.self) private var onboardingStore
    @Environment(\.openURL) private var openURL

    var reason: Reason = .majority

    @State private var isShowingDeletion = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Spacer(minLength: 32)

                    NinaMark(size: 48)

                    Text(reason.headline)
                        .ninaText(.screen)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(reason.line)
                        .ninaText(.label, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if reason == .majority, let guardian = store.viewerAge.terms.firstFormerGuardianName {
                        Text("\(guardian) não acompanha mais sua conta.")
                            .ninaText(.label, NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let message = store.syncErrorMessage {
                        Text(message)
                            .ninaText(.caption, NinaTheme.ink, weight: .medium)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    NinaButton(title: "Aceitar", fillsWidth: true, isPending: store.isSyncingHome) {
                        Haptics.lightImpact()
                        Task { _ = await store.acceptTermsAsAdult() }
                    }
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 4) {
                        NinaButton(title: "Ler os Termos", kind: .quiet) {
                            Haptics.selection()
                            openURL(NinaLegalLinks.termsOfUse)
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

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .ninaScreenBackground()
        .accountDeletionSheet(isPresented: $isShowingDeletion)
    }
}
