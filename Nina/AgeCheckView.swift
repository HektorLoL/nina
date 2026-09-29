import SwiftUI

// Seen by every age before anything else, so Nina is never the speaker here.
struct AgeCheckView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(AgeCheckCoordinator.self) private var ageCheck

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 32)
                    content
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .ninaScreenBackground()
    }

    @ViewBuilder
    private var content: some View {
        switch ageCheck.phase {
        case .idle where ageCheck.pendingSignal != nil:
            progress
        case .idle, .prompt:
            prompt
        case .requesting, .recording:
            progress
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

    private var progress: some View {
        VStack(spacing: 16) {
            NinaMark(size: 64, presence: .reading)
            Text("Só um instante.").ninaText(.label, NinaTheme.muted)
        }
        .accessibilityElement(children: .combine)
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

                    Text(reason == .majority ? "Agora a conta é sua." : "Os Termos mudaram.")
                        .ninaText(.screen)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(reason == .majority
                        ? "A Apple informou que você tem 18 anos ou mais."
                        : "Para continuar, leia e aceite a nova versão.")
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
