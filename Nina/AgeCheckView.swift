import SwiftUI

// Seen by every age before anything else, so Nina is never the speaker here.
struct AgeCheckView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(AgeCheckCoordinator.self) private var ageCheck

    @State private var isShowingDeletion = false

    var body: some View {
        if isWaiting {
            AppWaitingScreen()
        } else {
            GateLayout {
                message
            } decision: {
                decision
            }
            .accountDeletionSheet(isPresented: $isShowingDeletion)
        }
    }

    private var isWaiting: Bool {
        switch ageCheck.phase {
        case .requesting, .recording: true
        case .idle, .prompt, .declined, .appleError, .attestFailure: false
        }
    }

    private var isPrompting: Bool {
        switch ageCheck.phase {
        case .idle, .prompt, .requesting, .recording: true
        case .declined, .appleError, .attestFailure: false
        }
    }

    @ViewBuilder
    private var message: some View {
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

    @ViewBuilder
    private var decision: some View {
        if isPrompting {
            VStack(spacing: 12) {
                NinaButton(title: "Continuar", fillsWidth: true) {
                    Haptics.lightImpact()
                    share()
                }

                GateAccountExits(isShowingDeletion: $isShowingDeletion)
                    .padding(.top, 2)
            }
        } else {
            GateAccountExits(isShowingDeletion: $isShowingDeletion)
        }
    }

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 0) {
            NinaMark(size: 48)
                .padding(.bottom, 16)

            Text("Antes, sua faixa de idade.")
                .ninaText(.screen)
                .fixedSize(horizontal: false, vertical: true)

            Text("A Apple informa só a faixa, nunca a data de nascimento.")
                .ninaText(.label, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
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

    var reason: Reason = .majority

    @State private var isShowingDeletion = false

    var body: some View {
        GateLayout {
            VStack(alignment: .leading, spacing: 0) {
                NinaMark(size: 48)
                    .padding(.bottom, 16)

                Text(reason.headline)
                    .ninaText(.screen)
                    .fixedSize(horizontal: false, vertical: true)

                Text(reason.line)
                    .ninaText(.label, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                if reason == .majority, let guardian = store.viewerAge.terms.firstFormerGuardianName {
                    Text("\(guardian) não acompanha mais sua conta.")
                        .ninaText(.label, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } decision: {
            VStack(spacing: 12) {
                TermsDocumentCard(
                    versionLabel: AppStore.termsVersionLabel(store.viewerAge.terms.currentTermsVersion)
                )

                if let message = store.syncErrorMessage {
                    NinaErrorNote(text: message)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                NinaButton(title: "Aceitar", fillsWidth: true, isPending: store.isSyncingHome) {
                    Haptics.lightImpact()
                    Task { _ = await store.acceptTermsAsAdult() }
                }

                GateAccountExits(isShowingDeletion: $isShowingDeletion)
                    .padding(.top, 2)
            }
        }
        .accountDeletionSheet(isPresented: $isShowingDeletion)
    }
}

// Ink, never cobalt: the commit beside it stays the screen's only cobalt control.
struct TermsDocumentCard: View {
    var versionLabel: String?

    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button {
            Haptics.selection()
            openURL(NinaLegalLinks.termsOfUse)
        } label: {
            NinaRow(
                title: "Termos de uso",
                subtitle: versionLabel,
                verticalPadding: dynamicTypeSize.isAccessibilitySize ? 14 : 8
            ) {
                CategoryGlyph(systemName: "text.book.closed", size: 18, tint: NinaTheme.ink)
            } trailing: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NinaTheme.faint)
            }
            .padding(.leading, 6)
            .padding(.trailing, 16)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(versionLabel.map { "Termos de uso, \($0)" } ?? "Termos de uso")
        }
        .buttonStyle(.plain)
        .ninaCard()
    }
}

private struct GateLayout<Message: View, Decision: View>: View {
    @ViewBuilder var message: Message
    @ViewBuilder var decision: Decision

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 32)
                    message
                    Spacer(minLength: 32)
                    decision
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .ninaScreenBackground()
    }
}

// A gate always leaves a way out: leaving and deleting stay reachable before anything is accepted.
private struct GateAccountExits: View {
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(OnboardingStore.self) private var onboardingStore

    @Binding var isShowingDeletion: Bool

    var body: some View {
        VStack(spacing: 4) {
            if let message = authSession.errorMessage {
                NinaErrorNote(text: message, alignment: .center)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 6)
            }

            NinaButton(title: "Sair da conta", kind: .quiet) {
                Haptics.selection()
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
}
