import StoreKit
import SwiftUI
import UIKit

enum TaskEditorMode: Hashable {
    case add(sectionID: String)
    case edit(UUID)
    case plant(UUID)
}

private struct SheetHeader: View {
    var eyebrow: String
    var alignsCloseTrailing: Bool = false
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Text(eyebrow).ninaText(.eyebrow, NinaTheme.faint, weight: .bold)

            HStack {
                if alignsCloseTrailing {
                    Spacer()
                }

                Button {
                    Haptics.selection()
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NinaTheme.ink)
                        .frame(width: 32, height: 32)
                        .background(NinaTheme.grout, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fechar")

                if !alignsCloseTrailing {
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}

private struct BackHeader: View {
    var onBack: () -> Void

    var body: some View {
        HStack {
            Button {
                Haptics.selection()
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NinaTheme.ink)
                    .frame(width: 40, height: 40, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voltar")

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }
}

private struct SheetField<Field: View>: View {
    var label: String
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).ninaText(.meta, NinaTheme.muted)
            field
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(NinaTheme.ink)
                .tint(NinaTheme.cobalt)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            NinaTheme.grout,
            in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
        )
    }
}

private struct NoteCard: View {
    var eyebrow: String?
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let eyebrow {
                Eyebrow(text: eyebrow)
            }
            Text(text)
                .ninaText(.label, NinaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard(fill: NinaTheme.grout, stroke: .clear)
    }
}

// Destruction is carried by weight and terminal position, never by hue.
private struct InkButton: View {
    var title: String
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.1)
                .foregroundStyle(NinaTheme.ground)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    NinaTheme.ink,
                    in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

private struct ShareButtonFace: View {
    var title: String
    var isProminent: Bool = false

    var body: some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .tracking(-0.1)
            .foregroundStyle(isProminent ? NinaTheme.onCobalt : NinaTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                isProminent ? NinaTheme.cobalt : Color.clear,
                in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
                    .strokeBorder(isProminent ? Color.clear : NinaTheme.line, lineWidth: 1)
            )
    }
}

private struct SettingsSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: title)
            VStack(spacing: 0) {
                content
            }
        }
    }
}

private struct SettingsLinkRow: View {
    var title: String
    var subtitle: String?
    var systemName: String

    var body: some View {
        NinaRow(title: title, subtitle: subtitle) {
            CategoryGlyph(systemName: systemName, size: 18, tint: NinaTheme.ink)
        } trailing: {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NinaTheme.faint)
        }
        .contentShape(Rectangle())
    }
}

private struct SettingsValueRow: View {
    var title: String
    var subtitle: String?
    var value: String?
    var systemName: String

    var body: some View {
        NinaRow(title: title, subtitle: subtitle) {
            CategoryGlyph(systemName: systemName, size: 18, tint: NinaTheme.ink)
        } trailing: {
            if let value {
                Text(value).ninaText(.meta, NinaTheme.muted)
            }
        }
    }
}

private struct SettingsToggleRow: View {
    var title: String
    var subtitle: String
    var systemName: String
    @Binding var isOn: Bool

    var body: some View {
        NinaRow(title: title, subtitle: subtitle) {
            CategoryGlyph(systemName: systemName, size: 18, tint: NinaTheme.ink)
        } trailing: {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(NinaTheme.ink)
        }
        .onChange(of: isOn) { oldValue, newValue in
            guard oldValue != newValue else { return }
            Haptics.selection()
        }
    }
}

struct SettingsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(OnboardingStore.self) private var onboardingStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(PremiumSubscriptionStore.self) private var premiumStore
    #if DEBUG
    @Environment(BackendDiagnosticsStore.self) private var backendDiagnostics
    #endif
    @Environment(RouterPath.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var inviteURL: URL {
        store.inviteURL
    }

    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(eyebrow: "Ajustes") {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    titleBlock
                    premiumBlock
                    accountSection
                    ninaSection
                    houseSection
                    privacySection
                    aboutSection
                    #if DEBUG
                    developerSection
                    #endif
                    signOutButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 34)
            }
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ajustes").ninaText(.screen)
            Text("Sua conta, a casa e o que a Nina pode ler.")
                .ninaText(.label, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var premiumBlock: some View {
        if store.householdPremium.isActive {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Premium")
                Text(PremiumTeaserCopy.activeTitle)
                    .ninaText(.label, NinaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(PremiumTeaserCopy.activeSubtitle)
                    .ninaText(.caption, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(premiumStore.entitlement.renewalSummary)
                    .ninaText(.caption, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                NinaButton(title: "Ver a assinatura", kind: .outline) {
                    Haptics.lightImpact()
                    router.presentedSheet = .premium
                }
                .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ninaCard(fill: NinaTheme.grout, stroke: .clear)
        } else {
            PremiumGateCard(
                title: premiumPriceTitle,
                detail: "Documento por foto, mais conversa por dia e o resumo semanal da casa."
            ) {
                Haptics.lightImpact()
                router.presentedSheet = .premium
            }
        }
    }

    private var premiumPriceTitle: String {
        guard let priceLabel = premiumStore.primaryPriceLabel else { return "Ver o Premium" }
        return "Ver o Premium · \(priceLabel)"
    }

    @ViewBuilder
    private var accountSection: some View {
        SettingsSection(title: "Conta") {
            if let user = authSession.currentUser {
                let profile = profileStore.profile(for: user)

                NavigationLink {
                    ProfileEditorView(user: user)
                } label: {
                    NinaRow(
                        title: profile.displayName,
                        subtitle: user.email ?? user.provider.title
                    ) {
                        ProfileAvatarView(
                            profile: profile,
                            photoData: profileStore.photoData(for: profile),
                            size: 36
                        )
                    } trailing: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NinaTheme.faint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                NinaDivider()

                NavigationLink {
                    EmailAccessView()
                } label: {
                    SettingsLinkRow(
                        title: user.linkedProviders.contains(.email) ? "Email de acesso" : "Vincular um email",
                        subtitle: user.linkedProviders.contains(.email)
                            ? (user.email ?? "Email verificado")
                            : "Outra forma de entrar, se você perder a Apple.",
                        systemName: "envelope"
                    )
                }
                .buttonStyle(.plain)

                NinaDivider()
            }

            Button {
                Haptics.lightImpact()
                onboardingStore.replayTutorial()
                dismiss()
            } label: {
                SettingsLinkRow(
                    title: "Ver o tutorial de novo",
                    subtitle: "Como a Nina funciona, do começo.",
                    systemName: "play.circle"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var ninaSection: some View {
        SettingsSection(title: "Nina") {
            NavigationLink {
                NotificationPreferencesView()
            } label: {
                SettingsLinkRow(
                    title: "Lembretes e avisos",
                    subtitle: notificationStatusSubtitle,
                    systemName: "bell"
                )
            }
            .buttonStyle(.plain)

            NinaDivider()

            weeklyDigestRow
        }
    }

    @ViewBuilder
    private var weeklyDigestRow: some View {
        if store.canManageFamily {
            SettingsToggleRow(
                title: "Resumo semanal",
                subtitle: weeklyDigestSubtitle,
                systemName: "calendar",
                isOn: weeklyDigestBinding
            )
        } else {
            SettingsValueRow(
                title: "Resumo semanal",
                subtitle: weeklyDigestSubtitle,
                value: store.isWeeklyDigestEnabled ? "ligado" : "desligado",
                systemName: "calendar"
            )
        }
    }

    private var weeklyDigestBinding: Binding<Bool> {
        Binding(
            get: { store.isWeeklyDigestEnabled },
            set: { store.setWeeklyDigestEnabled($0) }
        )
    }

    private var weeklyDigestSubtitle: String {
        if !store.householdPremium.isActive {
            return "Uma leitura curta da semana da casa. Vem no Premium."
        }
        if !store.canManageFamily {
            return "Quem cuida da casa escolhe se ele sai."
        }
        return "Uma leitura curta da semana, para todo mundo daqui."
    }

    private var houseSection: some View {
        SettingsSection(title: "Casa") {
            SettingsValueRow(
                title: store.familyGroup.name,
                subtitle: store.familyLimitLabel,
                value: "\(store.remainingFamilySlots) vagas",
                systemName: "house"
            )

            NinaDivider()

            if store.canManageFamily, store.canInviteMorePeople, store.inviteStatus?.isActive ?? true {
                Button {
                    Haptics.lightImpact()
                    router.presentedSheet = .inviteFamily
                } label: {
                    SettingsLinkRow(
                        title: "Chamar alguém para a casa",
                        subtitle: "O link pede entrada. Alguém daqui aprova.",
                        systemName: "person.badge.plus"
                    )
                }
                .buttonStyle(.plain)
            } else if store.canManageFamily {
                SettingsValueRow(
                    title: "Convite pausado",
                    subtitle: store.canInviteMorePeople
                        ? "Gere um link novo na tela Casa."
                        : "A casa chegou no limite de pessoas.",
                    value: nil,
                    systemName: "person.badge.plus"
                )
            } else {
                SettingsValueRow(
                    title: store.currentPermissionRole.title,
                    subtitle: store.currentPermissionRole.summary,
                    value: "acesso",
                    systemName: store.currentPermissionRole.symbolName
                )
            }
        }
    }

    private var privacySection: some View {
        SettingsSection(title: "Privacidade") {
            NavigationLink {
                PrivacyAndDataView()
            } label: {
                SettingsLinkRow(
                    title: "Privacidade e dados",
                    subtitle: store.hasAIMemoryConsent
                        ? "A Nina pode ler o que você escreve."
                        : "A conversa online está desligada.",
                    systemName: "lock"
                )
            }
            .buttonStyle(.plain)

            NinaDivider()

            Button {
                Haptics.selection()
                openURL(NinaLegalLinks.privacyPolicy)
            } label: {
                SettingsLinkRow(
                    title: "Política de privacidade",
                    subtitle: "O texto completo, no site.",
                    systemName: "doc.text"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var notificationStatusSubtitle: String {
        switch store.notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            "Avisos ligados, com horário de silêncio."
        case .denied:
            "O iPhone está bloqueando. Toque para resolver."
        case .notDetermined:
            "Ligue quando fizer sentido para você."
        case .unavailable:
            "Configure os avisos deste aparelho."
        }
    }

    private var aboutSection: some View {
        SettingsSection(title: "Sobre") {
            SettingsValueRow(
                title: "Versão",
                subtitle: nil,
                value: versionLabel,
                systemName: "info.circle"
            )

            NinaDivider()

            Button {
                Haptics.selection()
                openURL(NinaLegalLinks.termsOfUse)
            } label: {
                SettingsLinkRow(
                    title: "Termos de uso",
                    subtitle: "Condições da assinatura e do serviço.",
                    systemName: "text.book.closed"
                )
            }
            .buttonStyle(.plain)

            NinaDivider()

            Button {
                Haptics.selection()
                openURL(NinaLegalLinks.support)
            } label: {
                SettingsLinkRow(
                    title: "Falar com o suporte",
                    subtitle: "oi@ninai.app",
                    systemName: "envelope.open"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var signOutButton: some View {
        NinaButton(title: "Sair desta conta", kind: .quiet, isEnabled: !authSession.isSigningIn) {
            Haptics.warning()
            Task {
                await authSession.signOut()
                onboardingStore.cancelReplay()
                dismiss()
            }
        }
        .frame(maxWidth: .infinity)
    }

    #if DEBUG
    private var developerSection: some View {
        SettingsSection(title: "Desenvolvimento") {
            NavigationLink {
                BackendDebugView()
            } label: {
                SettingsLinkRow(
                    title: "Debug do backend",
                    subtitle: "\(backendDiagnostics.environment.title) · \(backendDiagnostics.activeRequestCount) ativa(s)",
                    systemName: "ladybug"
                )
            }
            .buttonStyle(.plain)
        }
    }
    #endif
}

#if DEBUG
private struct BackendDebugView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(ProfileStore.self) private var profileStore
    @Environment(BackendDiagnosticsStore.self) private var diagnostics
    @Environment(\.dismiss) private var dismiss

    @State private var isRefreshing = false

    private var userID: String {
        authSession.currentUser?.id ?? "Sem sessão"
    }

    private var familyID: String {
        store.hasActiveHome ? store.familyGroup.id.uuidString : "Sem casa ativa"
    }

    private var lastSyncLabel: String {
        guard let date = diagnostics.lastSyncAt else { return "Ainda não sincronizou" }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    private var lastErrorLabel: String {
        diagnostics.lastError ?? "Nenhum erro registrado"
    }

    private var isBusy: Bool {
        isRefreshing || store.isSyncingHome
    }

    var body: some View {
        VStack(spacing: 0) {
            BackHeader { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Debug do backend").ninaText(.screen)

                    VStack(spacing: 0) {
                        DebugValueRow(title: "User ID", value: userID)
                        NinaDivider(inset: 0)
                        DebugValueRow(title: "Family ID", value: familyID)
                        NinaDivider(inset: 0)
                        DebugValueRow(
                            title: "Ambiente",
                            value: diagnostics.environment.title,
                            detail: diagnostics.environment.detail
                        )
                        NinaDivider(inset: 0)
                        DebugValueRow(
                            title: "Último sync",
                            value: lastSyncLabel,
                            detail: diagnostics.lastOperation
                        )
                        NinaDivider(inset: 0)
                        DebugValueRow(
                            title: "Requisições ativas",
                            value: "\(diagnostics.activeRequestCount)"
                        )
                        NinaDivider(inset: 0)
                        DebugValueRow(
                            title: diagnostics.lastErrorAt?.formatted(date: .abbreviated, time: .standard)
                                ?? "Sem falhas",
                            value: lastErrorLabel
                        )
                    }

                    NinaButton(
                        title: isRefreshing ? "Atualizando" : "Atualizar agora",
                        kind: .outline,
                        fillsWidth: true,
                        isEnabled: !isBusy
                    ) {
                        refresh()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func refresh() {
        guard !isBusy else { return }

        Haptics.selection()
        isRefreshing = true
        Task {
            await profileStore.refreshProfile(for: authSession.currentUser)
            await store.refreshHomeFromRemote(for: authSession.currentUser)
            isRefreshing = false
        }
    }
}

private struct DebugValueRow: View {
    var title: String
    var value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).ninaText(.meta, NinaTheme.muted)

            Text(value)
                .ninaText(.label, NinaTheme.ink, weight: .semibold)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .ninaText(.micro, NinaTheme.muted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}
#endif

private struct EmailAccessView: View {
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var code = ""
    @State private var didComplete = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case code
    }

    private var isWaitingForCode: Bool {
        authSession.pendingEmailChange != nil
    }

    private var currentEmailLine: String {
        guard authSession.currentUser?.linkedProviders.contains(.email) == true else {
            return "Hoje você entra só com a Apple."
        }
        return authSession.currentUser?.email ?? "Email verificado"
    }

    var body: some View {
        VStack(spacing: 0) {
            BackHeader { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email de acesso").ninaText(.screen)
                        Text("Um email confirmado deixa você entrar por código, sem depender da Apple.")
                            .ninaText(.label, NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(currentEmailLine)
                        .ninaText(.caption, NinaTheme.muted)

                    SheetField(label: "Novo email") {
                        TextField("voce@exemplo.com", text: $email)
                            .focused($focusedField, equals: .email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.emailAddress)
                            .submitLabel(.done)
                    }
                    .disabled(isWaitingForCode)
                    .opacity(isWaitingForCode ? 0.5 : 1)

                    if isWaitingForCode {
                        SheetField(label: "Código") {
                            TextField("000000", text: $code)
                                .focused($focusedField, equals: .code)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .submitLabel(.done)
                        }
                        .onChange(of: code) { _, newValue in
                            code = String(newValue.filter(\.isNumber).prefix(6))
                        }
                    }

                    if let errorMessage = authSession.errorMessage {
                        NoteCard(eyebrow: nil, text: errorMessage)
                    }

                    if didComplete {
                        Text("Email confirmado. Dá para entrar por código agora.")
                            .ninaText(.caption, NinaTheme.moss, weight: .semibold)
                    }

                    NinaButton(
                        title: isWaitingForCode ? "Confirmar o email" : "Enviar o código",
                        fillsWidth: true,
                        isEnabled: !(authSession.isRequestingCode || authSession.isSigningIn)
                    ) {
                        isWaitingForCode ? verifyChange() : requestChange()
                    }

                    if isWaitingForCode {
                        NinaButton(title: "Usar outro email", kind: .quiet) {
                            Haptics.selection()
                            authSession.pendingEmailChange = nil
                            code = ""
                            focusedField = .email
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if didComplete {
                        NinaButton(title: "Concluir", kind: .quiet) {
                            Haptics.selection()
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            email = authSession.pendingEmailChange ?? authSession.currentUser?.email ?? ""
        }
    }

    private func requestChange() {
        focusedField = nil
        Task {
            if await authSession.requestEmailChange(email: email) {
                email = authSession.pendingEmailChange ?? email
                focusedField = .code
            }
        }
    }

    private func verifyChange() {
        focusedField = nil
        Task {
            didComplete = await authSession.verifyEmailChange(email: email, code: code)
        }
    }
}

private struct PrivacyAndDataView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirmingHistoryDeletion = false

    private var acceptedLabel: String {
        guard let acceptedAt = store.aiMemoryConsent?.acceptedAt else {
            return "Ainda não ligado"
        }
        return "Aceito em \(acceptedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private var consentBinding: Binding<Bool> {
        Binding(
            get: { store.hasAIMemoryConsent },
            set: { isOn in
                if isOn {
                    Haptics.success()
                    Task { _ = await store.grantAIMemoryConsent() }
                } else {
                    Haptics.warning()
                    Task { _ = await store.revokeAIMemoryConsent() }
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            BackHeader { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Privacidade e dados").ninaText(.screen)

                    consentCard

                    Text("Desligar aqui vale só para você. A conversa de outro adulto da casa continua, e o resumo semanal continua saindo se outro adulto ainda tiver aceitado.")
                        .ninaText(.caption, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    NoteCard(
                        eyebrow: "Onde ficam os seus dados",
                        text: "Em São Paulo. Os seus registros ficam em servidores brasileiros. Para a Nina entender o que você escreve e o que está nas fotos, o conteúdo vai para um modelo fora do Brasil e volta — usado só para responder, sem ficar guardado lá."
                    )

                    if let error = store.syncErrorMessage {
                        NoteCard(eyebrow: nil, text: error)
                    }

                    dataRows
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 34)
            }
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var consentCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("A Nina pode me ler")
                    .font(.system(size: 17, weight: .medium))
                    .tracking(-0.1)
                    .foregroundStyle(NinaTheme.ink)
                Text(acceptedLabel).ninaText(.caption, NinaTheme.muted)
            }

            Spacer(minLength: 12)

            Toggle("A Nina pode me ler", isOn: consentBinding)
                .labelsHidden()
                .tint(NinaTheme.ink)
                .disabled(store.isSyncingHome)
                .opacity(store.isSyncingHome ? 0.5 : 1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard()
    }

    private var dataRows: some View {
        VStack(spacing: 0) {
            NavigationLink {
                PrivacyExportView()
            } label: {
                SettingsLinkRow(
                    title: "Baixar tudo o que é meu",
                    subtitle: "Um arquivo JSON gerado neste aparelho.",
                    systemName: "arrow.down.to.line"
                )
            }
            .buttonStyle(.plain)

            NinaDivider()

            SettingsValueRow(
                title: "O que some com o tempo",
                subtitle: "A conversa com a Nina apaga depois de 30 dias. Conclusões saem da lista depois de \(CompletedTaskRetention.visibleDays) dias, mas seguem guardadas.",
                value: nil,
                systemName: "clock.arrow.circlepath"
            )

            NinaDivider()

            // The thread is per-adult, so erasing it is a decision only you can
            // make about your own conversation — separate from deleting the account.
            Button {
                Haptics.warning()
                isConfirmingHistoryDeletion = true
            } label: {
                SettingsLinkRow(
                    title: "Apagar a minha conversa com a Nina",
                    subtitle: "Só a sua. A conversa do outro adulto continua.",
                    systemName: "bubble.left.and.exclamationmark.bubble.right"
                )
            }
            .buttonStyle(.plain)

            NinaDivider()

            NavigationLink {
                AccountDeletionView()
            } label: {
                SettingsLinkRow(
                    title: "Apagar a minha conta",
                    subtitle: nil,
                    systemName: "trash"
                )
            }
            .buttonStyle(.plain)
        }
        .alert("Apagar a sua conversa?", isPresented: $isConfirmingHistoryDeletion) {
            Button("Apagar", role: .destructive) {
                Task { _ = await store.deleteNinaChatHistory() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Some tudo o que você já escreveu para a Nina. As tarefas e as memórias que você confirmou ficam.")
        }
    }
}

private struct PrivacyExportView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var exportError: String?

    private let contents = [
        "O seu perfil e a foto salva, se houver.",
        "A casa, quem mora nela, tarefas com horário, compras e retratos.",
        "A sua conversa com a Nina carregada neste aparelho.",
        "O estado do seu consentimento de leitura."
    ]

    var body: some View {
        VStack(spacing: 0) {
            BackHeader { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Baixar tudo o que é meu").ninaText(.screen)
                        Text("O arquivo é montado aqui no aparelho, em JSON, e você escolhe para onde ele vai.")
                            .ninaText(.label, NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "O que vai no arquivo")
                        ForEach(contents, id: \.self) { line in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(NinaTheme.line)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 8)
                                Text(line)
                                    .ninaText(.caption, NinaTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if let exportError {
                        NoteCard(eyebrow: nil, text: exportError)
                    }

                    NinaButton(title: "Gerar o arquivo", fillsWidth: true) {
                        generateExport()
                    }

                    if let exportURL {
                        ShareLink(item: exportURL) {
                            ShareButtonFace(title: "Compartilhar o arquivo")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear {
            discardExport()
        }
    }

    private func generateExport() {
        discardExport()
        do {
            let profile = authSession.currentUser.map { profileStore.profile(for: $0) }
            let profilePhotoData = profile.flatMap { profileStore.photoData(for: $0) }
            let data = try store.makePrivacyExportData(
                profile: profile,
                profilePhotoData: profilePhotoData
            )
            let url = try PrivacyExportFileStore.write(
                data,
                filename: store.privacyExportFilename
            )
            exportURL = url
            exportError = nil
            Haptics.success()
        } catch {
            exportURL = nil
            exportError = "Não foi possível gerar a exportação agora."
            Haptics.error()
        }
    }

    private func discardExport() {
        guard let exportURL else { return }
        PrivacyExportFileStore.remove(exportURL)
        self.exportURL = nil
    }
}

private struct AccountDeletionView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(OnboardingStore.self) private var onboardingStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(InviteLinkStore.self) private var inviteLinkStore
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingConfirmation = false
    @State private var confirmation = ""
    @FocusState private var isConfirmationFocused: Bool

    private static let confirmationWord = "apagar"

    private var isConfirmed: Bool {
        confirmation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            == Self.confirmationWord
    }

    var body: some View {
        VStack(spacing: 0) {
            BackHeader { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Apagar a minha conta").ninaText(.screen)
                        Text("Isso não tem volta. Antes de você decidir, veja exatamente o que some e o que continua na casa.")
                            .ninaText(.label, NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Some para sempre")
                        Text("A sua conversa com a Nina. As suas memórias privadas. A sua foto e o seu perfil. O seu acesso a \(store.familyGroup.name).")
                            .ninaText(.label, NinaTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ninaCard()

                    NoteCard(
                        eyebrow: "Continua com a casa",
                        text: "As tarefas que você criou continuam lá, sem dono. As compras continuam. As memórias que você compartilhou continuam com quem já podia ler."
                    )

                    if let errorMessage = authSession.errorMessage {
                        NoteCard(eyebrow: nil, text: errorMessage)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Escreva \(Self.confirmationWord) para confirmar")
                            .ninaText(.caption, NinaTheme.muted)

                        SheetField(label: "Confirmação") {
                            TextField(Self.confirmationWord, text: $confirmation)
                                .focused($isConfirmationFocused)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                        }
                    }
                    .padding(.top, 6)

                    InkButton(
                        title: authSession.isDeletingAccount ? "Apagando" : "Apagar a minha conta",
                        isEnabled: isConfirmed && !authSession.isDeletingAccount
                    ) {
                        Haptics.warning()
                        isConfirmationFocused = false
                        isShowingConfirmation = true
                    }

                    NinaButton(title: "Deixa pra lá", kind: .quiet) {
                        Haptics.selection()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 34)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
        .alert("Apagar a sua conta Nina?", isPresented: $isShowingConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Apagar conta", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("Remove a sua conta e os dados pessoais ligados a ela. Não dá para desfazer.")
        }
    }

    private func deleteAccount() {
        guard let userID = authSession.currentUser?.id else { return }
        Task {
            if await authSession.deleteAccount() {
                store.clearLocalData(for: userID)
                profileStore.clearLocalData(for: userID)
                onboardingStore.clearLocalData(for: userID)
                inviteLinkStore.clear()
                try? PrivacyExportFileStore.removeAll()
                dismiss()
            }
        }
    }
}

private struct NotificationPreferencesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage(LocalHomeNotificationScheduler.notificationsEnabledKey)
    private var notificationsEnabled = true
    @AppStorage(LocalHomeNotificationScheduler.quietHoursEnabledKey)
    private var quietHoursEnabled = true
    @AppStorage(LocalHomeNotificationScheduler.quietHoursStartMinutesKey)
    private var quietHoursStartMinutes = LocalHomeNotificationScheduler.defaultQuietHoursStartMinutes
    @AppStorage(LocalHomeNotificationScheduler.quietHoursEndMinutesKey)
    private var quietHoursEndMinutes = LocalHomeNotificationScheduler.defaultQuietHoursEndMinutes

    var body: some View {
        VStack(spacing: 0) {
            BackHeader { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Lembretes e avisos").ninaText(.screen)
                        Text("A Nina avisa na hora combinada e respeita o descanso da casa.")
                            .ninaText(.label, NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    authorizationBlock

                    VStack(spacing: 0) {
                        SettingsToggleRow(
                            title: "Avisos neste aparelho",
                            subtitle: "Tarefas com horário e o empurrão de véspera.",
                            systemName: "bell",
                            isOn: notificationToggle
                        )

                        NinaDivider()

                        SettingsToggleRow(
                            title: "Silenciar à noite",
                            subtitle: quietHoursSummary,
                            systemName: "moon",
                            isOn: $quietHoursEnabled
                        )

                        NinaDivider()

                        timePickerRow(
                            title: "Começa",
                            systemName: "moon.stars",
                            selection: quietHoursStartBinding
                        )

                        NinaDivider()

                        timePickerRow(
                            title: "Termina",
                            systemName: "sunrise",
                            selection: quietHoursEndBinding
                        )
                    }

                    // Quiet hours silence the alert; they never move it, because the
                    // app must not show one time and deliver another.
                    Text("No silêncio o aviso chega sem som, na hora marcada. Ele não muda de horário.")
                        .ninaText(.caption, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await store.refreshNotificationAuthorizationStatus()
        }
        .onChange(of: quietHoursEnabled) { _, _ in
            store.synchronizeLocalNotifications()
        }
        .onChange(of: quietHoursStartMinutes) { _, _ in
            store.synchronizeLocalNotifications()
        }
        .onChange(of: quietHoursEndMinutes) { _, _ in
            store.synchronizeLocalNotifications()
        }
    }

    @ViewBuilder
    private var authorizationBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(authorizationTitle)
                .ninaText(.section)
                .fixedSize(horizontal: false, vertical: true)

            Text(authorizationMessage)
                .ninaText(.caption, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            switch store.notificationAuthorizationStatus {
            case .notDetermined:
                NinaButton(title: "Permitir os avisos", kind: .outline) {
                    Haptics.lightImpact()
                    Task {
                        _ = await store.requestNotificationAuthorization()
                    }
                }
                .padding(.top, 2)
            case .denied:
                NinaButton(title: "Abrir os Ajustes do iPhone", kind: .outline) {
                    Haptics.selection()
                    guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                    openURL(url)
                }
                .padding(.top, 2)
            case .authorized, .provisional, .ephemeral, .unavailable:
                EmptyView()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard(fill: NinaTheme.grout, stroke: .clear)
    }

    private var notificationToggle: Binding<Bool> {
        Binding(
            get: { notificationsEnabled },
            set: { isEnabled in
                notificationsEnabled = isEnabled
                if isEnabled, store.notificationAuthorizationStatus == .notDetermined {
                    Task {
                        _ = await store.requestNotificationAuthorization()
                    }
                } else {
                    store.synchronizeLocalNotifications()
                }
            }
        )
    }

    private var quietHoursStartBinding: Binding<Date> {
        timeBinding(minutes: $quietHoursStartMinutes)
    }

    private var quietHoursEndBinding: Binding<Date> {
        timeBinding(minutes: $quietHoursEndMinutes)
    }

    private func timeBinding(minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    byAdding: .minute,
                    value: minutes.wrappedValue,
                    to: Calendar.current.startOfDay(for: .now)
                ) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    private func timePickerRow(
        title: String,
        systemName: String,
        selection: Binding<Date>
    ) -> some View {
        NinaRow(title: title, subtitle: nil) {
            CategoryGlyph(systemName: systemName, size: 18, tint: NinaTheme.ink)
        } trailing: {
            DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .tint(NinaTheme.ink)
        }
        .disabled(!quietHoursEnabled)
        .opacity(quietHoursEnabled ? 1 : 0.5)
    }

    private var quietHoursSummary: String {
        "Entre \(formattedTime(quietHoursStartMinutes)) e \(formattedTime(quietHoursEndMinutes))."
    }

    private func formattedTime(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private var authorizationTitle: String {
        switch store.notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            "Os avisos estão liberados"
        case .notDetermined:
            "Você escolhe quando ligar"
        case .denied:
            "O iPhone está bloqueando os avisos"
        case .unavailable:
            "Estado desconhecido"
        }
    }

    private var authorizationMessage: String {
        switch store.notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            "Os próximos avisos são agendados neste aparelho."
        case .notDetermined:
            "Ligue depois de criar uma tarefa com horário. A Nina pede permissão só nesse momento."
        case .denied:
            "Dá para mudar isso nos Ajustes do iPhone."
        case .unavailable:
            "Este aparelho não informou o estado dos avisos."
        }
    }
}

private enum PremiumPeriod: Hashable {
    case monthly
    case yearly

    var title: String {
        switch self {
        case .monthly: "Mensal"
        case .yearly: "Anual"
        }
    }
}

struct PremiumBenefitsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(PremiumSubscriptionStore.self) private var premiumStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var isManagingSubscription = false
    @State private var selectedPeriod: PremiumPeriod = .yearly

    private let plan = PremiumPlan.mock

    private var monthlyProduct: Product? {
        premiumStore.products.first { $0.subscription?.subscriptionPeriod.unit == .month }
    }

    private var yearlyProduct: Product? {
        premiumStore.products.first { $0.subscription?.subscriptionPeriod.unit == .year }
    }

    private var selectedProduct: Product? {
        switch selectedPeriod {
        case .monthly: monthlyProduct ?? premiumStore.products.first
        case .yearly: yearlyProduct ?? premiumStore.products.first
        }
    }

    private var isBusy: Bool {
        premiumStore.isPurchasing || premiumStore.isSyncingBackend
    }

    private var isCurrentPlan: Bool {
        guard let product = selectedProduct else { return false }
        return premiumStore.entitlement.isActive && premiumStore.entitlement.productID == product.id
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(eyebrow: "Premium", alignsCloseTrailing: true) {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heading
                    periodControl
                    comparison
                    ceilingNote
                    NoteCard(
                        eyebrow: "O que o Premium não muda",
                        text: "A Nina continua propondo e esperando você confirmar. Nenhum plano dá a ela permissão de mexer na casa sozinha."
                    )
                    statusArea
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 24)
            }

            purchaseArea
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
        .task {
            await premiumStore.configure(for: authSession.currentUser)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(plan.name).ninaText(.display)
            Text("Três limites reais somem. É só isso.")
                .ninaText(.label, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var periodControl: some View {
        HStack(spacing: 4) {
            periodButton(.monthly, badge: nil)
            periodButton(.yearly, badge: yearlySavingsLabel)
        }
        .padding(4)
        .background(NinaTheme.grout, in: Capsule())
    }

    private func periodButton(_ period: PremiumPeriod, badge: String?) -> some View {
        Button {
            Haptics.selection()
            selectedPeriod = period
        } label: {
            HStack(spacing: 6) {
                Text(period.title)
                    .font(.system(size: 15, weight: selectedPeriod == period ? .semibold : .medium))
                    .foregroundStyle(selectedPeriod == period ? NinaTheme.ink : NinaTheme.muted)

                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NinaTheme.ground)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(NinaTheme.ink, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(selectedPeriod == period ? NinaTheme.ground : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedPeriod == period ? [.isSelected] : [])
    }

    private var yearlySavingsLabel: String? {
        guard let monthly = monthlyProduct, let yearly = yearlyProduct else { return nil }
        let twelveMonths = monthly.price * 12
        guard twelveMonths > 0 else { return nil }
        let ratio = NSDecimalNumber(decimal: yearly.price / twelveMonths).doubleValue
        let saving = Int(((1 - ratio) * 100).rounded())
        guard saving > 0 else { return nil }
        return "-\(saving)%"
    }

    // Each row is a ceiling the server actually enforces; nothing else is sold here.
    private var comparison: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text("Grátis")
                    .ninaText(.eyebrow, NinaTheme.faint, weight: .bold)
                    .frame(width: 76)
                Text("Premium")
                    .ninaText(.eyebrow, NinaTheme.cobalt, weight: .bold)
                    .frame(width: 76)
            }
            .padding(.horizontal, 14)
            .frame(height: 38)

            NinaDivider(inset: 0)

            comparisonRow("Ler documento por foto", free: nil, premium: nil)
            NinaDivider(inset: 0)
            comparisonRow("Conversa com a Nina", free: "10/dia", premium: "30/hora")
            NinaDivider(inset: 0)
            comparisonRow("Resumo semanal", free: nil, premium: nil)
        }
        .ninaCard()
    }

    private func comparisonRow(_ title: String, free: String?, premium: String?) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(NinaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            comparisonCell(free, isPremium: false)
            comparisonCell(premium, isPremium: true)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
    }

    @ViewBuilder
    private func comparisonCell(_ text: String?, isPremium: Bool) -> some View {
        Group {
            if let text {
                Text(text)
                    .font(.system(size: 13, weight: isPremium ? .semibold : .regular))
                    .foregroundStyle(isPremium ? NinaTheme.cobalt : NinaTheme.muted)
            } else {
                Image(systemName: isPremium ? "checkmark" : "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isPremium ? NinaTheme.cobalt : NinaTheme.faint)
            }
        }
        .frame(width: 76)
        .accessibilityLabel(text ?? (isPremium ? "incluído" : "não incluído"))
    }

    private var ceilingNote: some View {
        Text("Mesmo no Premium a casa inteira tem um teto de 100 conversas por dia.")
            .ninaText(.caption, NinaTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var statusArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            if premiumStore.isLoadingProducts {
                Text("Carregando os planos.").ninaText(.caption, NinaTheme.muted)
            } else if premiumStore.products.isEmpty {
                NoteCard(
                    eyebrow: "Planos indisponíveis",
                    text: premiumStore.productLoadMessage
                        ?? "Configure os produtos Premium no App Store Connect ou em um arquivo StoreKit local."
                )
            }

            if store.householdPremium.isActive {
                NinaButton(title: "Gerenciar na App Store", kind: .outline) {
                    Haptics.lightImpact()
                    isManagingSubscription = true
                }
            }

            if let statusMessage = premiumStore.statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .ninaText(.caption, NinaTheme.moss, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage = premiumStore.errorMessage, !errorMessage.isEmpty {
                NoteCard(eyebrow: nil, text: errorMessage)
            }

            Text(subscriptionDisclosure)
                .ninaText(.micro, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                legalLink("Termos de uso", url: NinaLegalLinks.termsOfUse)
                legalLink("Privacidade", url: NinaLegalLinks.privacyPolicy)
            }
        }
    }

    private var subscriptionDisclosure: String {
        guard let product = selectedProduct,
              let period = product.subscription?.subscriptionPeriod else {
            return plan.subscriptionDisclosure
        }
        return "\(plan.name): assinatura de \(period.localizedTitle) por \(product.displayPrice). \(plan.renewalLabel)."
    }

    private func legalLink(_ title: String, url: URL) -> some View {
        Button {
            Haptics.selection()
            openURL(url)
        } label: {
            Text(title).ninaText(.caption, NinaTheme.muted, weight: .semibold)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var purchaseArea: some View {
        VStack(spacing: 10) {
            if let product = selectedProduct {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(product.displayPrice).ninaText(.display)
                    if let priceDetail = priceDetail(for: product) {
                        Text(priceDetail).ninaText(.caption, NinaTheme.muted)
                    }
                    Spacer(minLength: 0)
                }

                NinaButton(
                    title: isCurrentPlan ? "Este já é o seu plano" : "Assinar o Premium",
                    fillsWidth: true,
                    isEnabled: !isCurrentPlan && !isBusy
                ) {
                    Task {
                        Haptics.lightImpact()
                        await premiumStore.purchase(product)
                    }
                }

                Text("Renova sozinho. Dá para cancelar quando quiser, direto na App Store.")
                    .ninaText(.micro, NinaTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            NinaButton(
                title: premiumStore.isRestoring ? "Restaurando" : "Restaurar compras",
                kind: .quiet,
                isEnabled: !premiumStore.isRestoring
            ) {
                Task {
                    Haptics.lightImpact()
                    await premiumStore.restorePurchases()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func priceDetail(for product: Product) -> String? {
        guard let period = product.subscription?.subscriptionPeriod else { return nil }
        guard period.unit == .year, period.value == 1 else {
            return "por \(period.localizedTitle)"
        }
        let perMonth = (product.price / 12).formatted(product.priceFormatStyle)
        return "por ano · \(perMonth)/mês"
    }
}

private extension Product.SubscriptionPeriod {
    var localizedTitle: String {
        let unitTitle: String
        switch unit {
        case .day:
            unitTitle = value == 1 ? "dia" : "dias"
        case .week:
            unitTitle = value == 1 ? "semana" : "semanas"
        case .month:
            unitTitle = value == 1 ? "mês" : "meses"
        case .year:
            unitTitle = value == 1 ? "ano" : "anos"
        @unknown default:
            unitTitle = "período"
        }

        return value == 1 ? unitTitle : "\(value) \(unitTitle)"
    }
}

private enum TaskEditorPanel: Hashable {
    case date
    case category
}

struct TaskEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var mode: TaskEditorMode
    @State private var title = ""
    @State private var subtitle = ""
    @State private var owner = "Casa"
    @State private var ownerMemberID: UUID?
    @State private var dueDate = Date()
    @State private var kind: TaskKind = .task
    @State private var category: TaskCategory = .home
    @State private var priority: TaskPriority = .normal
    @State private var recurrence: TaskRecurrence = .none
    @State private var reminderLead: TaskReminderLead = .atTime
    @State private var localTaskCategories: [TaskCategory] = []
    @State private var activePanel: TaskEditorPanel?
    @State private var isCreatingCategory = false
    @State private var newCategoryTitle = ""
    @State private var didLoad = false
    @State private var loadedTaskVersion: Int?
    @State private var isShowingDeleteConfirmation = false
    @FocusState private var isTitleFocused: Bool

    private var isEditing: Bool {
        switch mode {
        case .edit, .plant:
            true
        case .add:
            false
        }
    }

    private var isPlantingSeed: Bool {
        if case .plant = mode { true } else { false }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSeed: Bool {
        kind == .seed
    }

    private var ownerOptions: [TaskOwnerChoice] {
        TaskOwnerChoice.options(
            members: store.familyGroup.members,
            selectedName: owner,
            selectedMemberID: ownerMemberID
        )
    }

    private var selectedOwnerLabel: String {
        ownerOptions.first(where: isSelectedOwner)?.label ?? owner
    }

    private func isSelectedOwner(_ option: TaskOwnerChoice) -> Bool {
        option.memberID == ownerMemberID && option.name == owner
    }

    private var categoryOptions: [TaskCategory] {
        let categories = store.availableTaskCategories + localTaskCategories
        return categories.contains(where: { $0.id == category.id }) ? categories : categories + [category]
    }

    private var reminderLeadOptions: [TaskReminderLead] {
        let options = TaskReminderLead.editorOptions
        guard !options.contains(reminderLead) else { return options }
        return (options + [reminderLead]).sorted { $0.minutes < $1.minutes }
    }

    private var isReminderLeadDisabled: Bool {
        store.notificationAuthorizationStatus == .denied
    }

    // The house owns unassigned work and it is never given a face; the chip says
    // so in the words the person reading it would use.
    private var isOwnerAssigned: Bool {
        ownerMemberID != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(eyebrow: editorTitle) {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    titleField
                    subtitleField
                    hintLine
                    notificationNote

                    if isEditing {
                        NinaButton(title: "Apagar esta tarefa", kind: .quiet) {
                            Haptics.warning()
                            isShowingDeleteConfirmation = true
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)

            bottomBar
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: loadIfNeeded)
        .task {
            await store.refreshNotificationAuthorizationStatus()
        }
        .task {
            guard case .add = mode else { return }
            await Task.yield()
            isTitleFocused = true
        }
        .alert("Apagar esta tarefa?", isPresented: $isShowingDeleteConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Apagar", role: .destructive) {
                deleteTask()
            }
        } message: {
            Text("A tarefa e o aviso agendado saem para todo mundo da casa.")
        }
    }

    private var titleField: some View {
        TextField("O que precisa ser feito?", text: $title, axis: .vertical)
            .lineLimit(1...3)
            .font(.system(size: 27, weight: .semibold))
            .tracking(-0.4)
            .foregroundStyle(NinaTheme.ink)
            .tint(NinaTheme.cobalt)
            .textFieldStyle(.plain)
            .focused($isTitleFocused)
            .submitLabel(.done)
    }

    private var subtitleField: some View {
        TextField("Um detalhe, se ajudar", text: $subtitle, axis: .vertical)
            .lineLimit(1...3)
            .font(.system(size: 19, weight: .regular))
            .foregroundStyle(NinaTheme.muted)
            .tint(NinaTheme.cobalt)
            .textFieldStyle(.plain)
    }

    @ViewBuilder
    private var hintLine: some View {
        if let hintText {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(NinaTheme.cobalt)
                    .frame(width: 8, height: 8)
                    .padding(.top, 7)
                    .accessibilityHidden(true)

                Text(hintText)
                    .ninaText(.label, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        }
    }

    private var hintText: String? {
        if isPlantingSeed {
            return "Uma semente vira tarefa quando ganha dia e hora."
        }
        if isSeed {
            return "Semente não tem data. É isso mesmo."
        }
        return nil
    }

    @ViewBuilder
    private var notificationNote: some View {
        if !isSeed {
            switch store.notificationAuthorizationStatus {
            case .notDetermined:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ligue os avisos para receber isto na hora marcada.")
                        .ninaText(.caption, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    NinaButton(title: "Ligar os avisos", kind: .quiet) {
                        Haptics.lightImpact()
                        Task {
                            _ = await store.requestNotificationAuthorization()
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ninaCard(fill: NinaTheme.grout, stroke: .clear)
                .padding(.top, 8)
            case .denied:
                VStack(alignment: .leading, spacing: 8) {
                    Text("O iPhone está bloqueando os avisos da Nina.")
                        .ninaText(.caption, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    NinaButton(title: "Abrir os Ajustes", kind: .quiet) {
                        Haptics.selection()
                        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                        openURL(url)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ninaCard(fill: NinaTheme.grout, stroke: .clear)
                .padding(.top, 8)
            case .authorized, .provisional, .ephemeral, .unavailable:
                EmptyView()
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if activePanel == .date {
                datePanel
            }

            if activePanel == .category {
                categoryPanel
            }

            chipRow

            HStack(spacing: 12) {
                Text("Só o título é obrigatório")
                    .ninaText(.caption, NinaTheme.muted)

                Spacer(minLength: 8)

                Button {
                    save()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(NinaTheme.onCobalt)
                        .frame(width: 52, height: 52)
                        .background(NinaTheme.cobalt, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(trimmedTitle.isEmpty)
                .opacity(trimmedTitle.isEmpty ? 0.4 : 1)
                .accessibilityLabel(primaryActionTitle)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(NinaTheme.ground)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    Haptics.lightImpact()
                    let nextKind: TaskKind = isSeed ? .task : .seed
                    kind = nextKind
                    if nextKind == .seed {
                        closePanel()
                    }
                } label: {
                    NinaChip(
                        text: kind.title,
                        isSet: true,
                        systemName: "checkmark",
                        isDisabled: isPlantingSeed
                    )
                }
                .buttonStyle(.plain)
                .disabled(isPlantingSeed)

                dateChip

                Menu {
                    ForEach(ownerOptions) { option in
                        Button {
                            Haptics.selection()
                            owner = option.name
                            ownerMemberID = option.memberID
                        } label: {
                            Label(
                                option.label,
                                systemImage: isSelectedOwner(option) ? "checkmark" : "person"
                            )
                        }
                    }
                } label: {
                    NinaChip(
                        text: isOwnerAssigned ? selectedOwnerLabel : "Ninguém ainda",
                        isSet: isOwnerAssigned
                    )
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.lightImpact()
                    togglePanel(.category)
                } label: {
                    NinaChip(text: category.title, isSet: true)
                }
                .buttonStyle(.plain)

                if !isSeed {
                    Menu {
                        ForEach(TaskRecurrence.allCases) { option in
                            Button {
                                Haptics.selection()
                                recurrence = option
                            } label: {
                                Label(
                                    option.title,
                                    systemImage: recurrence == option ? "checkmark" : "repeat"
                                )
                            }
                        }
                    } label: {
                        NinaChip(
                            text: recurrence == .none ? "Não repete" : recurrence.shortTitle,
                            isSet: recurrence != .none
                        )
                    }
                    .buttonStyle(.plain)

                    Menu {
                        ForEach(reminderLeadOptions) { option in
                            Button {
                                Haptics.selection()
                                reminderLead = option
                            } label: {
                                Label(
                                    option.title,
                                    systemImage: reminderLead == option ? "checkmark" : "bell"
                                )
                            }
                        }
                    } label: {
                        NinaChip(
                            text: reminderLead.title,
                            isSet: reminderLead != .atTime,
                            isDisabled: isReminderLeadDisabled
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isReminderLeadDisabled)
                }

                Menu {
                    ForEach(TaskPriority.allCases) { option in
                        Button {
                            Haptics.selection()
                            priority = option
                        } label: {
                            Label(
                                option.title,
                                systemImage: priority == option ? "checkmark" : "flag"
                            )
                        }
                    }
                } label: {
                    NinaChip(
                        text: priority == .normal ? "Prioridade normal" : priority.title,
                        isSet: priority != .normal
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    // A seed's date chip is present and dead: the primitive is taught where the
    // control would have been, not in a paragraph somewhere else.
    @ViewBuilder
    private var dateChip: some View {
        if isSeed {
            NinaChip(text: "Sem data", isDisabled: true)
        } else {
            Button {
                Haptics.lightImpact()
                togglePanel(.date)
            } label: {
                NinaChip(text: Self.dateLabel(for: dueDate), isSet: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var datePanel: some View {
        HStack(spacing: 12) {
            Text("Quando").ninaText(.label, NinaTheme.muted)

            Spacer(minLength: 8)

            DatePicker(
                "Quando",
                selection: $dueDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .tint(NinaTheme.cobalt)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var categoryPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(categoryOptions) { item in
                        Button {
                            Haptics.selection()
                            category = item
                            closePanel()
                        } label: {
                            categoryChoiceRow(item, isSelected: category.id == item.id)
                        }
                        .buttonStyle(.plain)

                        NinaDivider(inset: 34)
                    }

                    Button {
                        Haptics.lightImpact()
                        newCategoryTitle = ""
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            isCreatingCategory = true
                        }
                    } label: {
                        categoryChoiceRow(
                            TaskCategory.custom(id: "new-category", title: "Nova categoria", tone: .mint),
                            isSelected: false,
                            overrideSymbolName: "plus"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxHeight: 208)

            if isCreatingCategory {
                HStack(spacing: 10) {
                    TextField("Nome da categoria", text: $newCategoryTitle)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(NinaTheme.ink)
                        .tint(NinaTheme.cobalt)
                        .textFieldStyle(.plain)
                        .submitLabel(.done)

                    Button {
                        createCategory()
                    } label: {
                        Text("Criar")
                            .ninaText(.label, NinaTheme.cobalt, weight: .semibold)
                    }
                    .buttonStyle(.plain)
                    .disabled(newCategoryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(newCategoryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)

                    Button {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            isCreatingCategory = false
                        }
                        newCategoryTitle = ""
                    } label: {
                        Text("Cancelar")
                            .ninaText(.label, NinaTheme.muted, weight: .semibold)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .frame(minHeight: 52)
            }
        }
        .padding(.vertical, 4)
    }

    private func categoryChoiceRow(
        _ item: TaskCategory,
        isSelected: Bool,
        overrideSymbolName: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            CategoryGlyph(
                systemName: overrideSymbolName ?? item.symbolName,
                size: 17,
                tint: NinaTheme.ink
            )

            Text(item.title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(NinaTheme.ink)

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NinaTheme.cobalt)
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    private func togglePanel(_ panel: TaskEditorPanel) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            activePanel = activePanel == panel ? nil : panel
        }
    }

    private func closePanel() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            activePanel = nil
            isCreatingCategory = false
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        let taskID: UUID
        switch mode {
        case .edit(let id), .plant(let id):
            taskID = id
        case .add:
            dueDate = Self.defaultDueDate()
            return
        }

        guard let task = store.tasks.first(where: { $0.id == taskID }) else {
            dueDate = Self.defaultDueDate()
            return
        }

        title = task.title
        subtitle = task.subtitle
        owner = task.owner
        ownerMemberID = task.ownerMemberID
        kind = isPlantingSeed ? .task : task.kind
        dueDate = isPlantingSeed
            ? Self.defaultDueDate()
            : (task.dueAt ?? Self.date(fromDueLabel: task.dueLabel))
        category = task.category
        priority = task.priority
        recurrence = task.recurrence
        reminderLead = isPlantingSeed ? .atTime : task.reminderLead
        loadedTaskVersion = task.version
    }

    private func save() {
        guard !trimmedTitle.isEmpty else {
            Haptics.error()
            return
        }

        let dueLabel = isSeed ? "Sem data" : Self.dateLabel(for: dueDate)
        let dueAt = isSeed ? nil : dueDate
        let recurrenceForSave: TaskRecurrence = isSeed ? .none : recurrence
        let reminderLeadForSave: TaskReminderLead = isSeed ? .atTime : reminderLead
        let categoryForSave = persistedCategoryIfNeeded(category)
        Haptics.success()
        switch mode {
        case .add(let sectionID):
            store.addTask(
                title: title,
                subtitle: subtitle,
                owner: owner,
                ownerMemberID: ownerMemberID,
                dueLabel: dueLabel,
                dueAt: dueAt,
                category: categoryForSave,
                priority: priority,
                recurrence: recurrenceForSave,
                reminderLead: reminderLeadForSave,
                kind: kind,
                sectionID: sectionID
            )
        case .edit(let id):
            store.updateTask(
                id: id,
                title: title,
                subtitle: subtitle,
                owner: owner,
                ownerMemberID: ownerMemberID,
                dueLabel: dueLabel,
                dueAt: dueAt,
                category: categoryForSave,
                priority: priority,
                recurrence: recurrenceForSave,
                reminderLead: reminderLeadForSave,
                kind: kind,
                expectedVersion: loadedTaskVersion
            )
        case .plant(let id):
            store.updateTask(
                id: id,
                title: title,
                subtitle: subtitle,
                owner: owner,
                ownerMemberID: ownerMemberID,
                dueLabel: dueLabel,
                dueAt: dueAt,
                category: categoryForSave,
                priority: priority,
                recurrence: recurrenceForSave,
                reminderLead: reminderLeadForSave,
                kind: .task,
                expectedVersion: loadedTaskVersion
            )
        }

        dismiss()
    }

    private var editorTitle: String {
        if isPlantingSeed {
            return "Plantar semente"
        }
        if isEditing {
            return isSeed ? "Editar semente" : "Editar tarefa"
        }
        return isSeed ? "Nova semente" : "Nova tarefa"
    }

    private var primaryActionTitle: String {
        if isPlantingSeed {
            return "Plantar como tarefa"
        }
        if isEditing {
            return isSeed ? "Salvar semente" : "Salvar tarefa"
        }
        return isSeed ? "Guardar semente" : "Criar tarefa"
    }

    private func deleteTask() {
        let id: UUID
        switch mode {
        case .edit(let taskID), .plant(let taskID):
            id = taskID
        case .add:
            return
        }
        store.deleteTask(id)
        Haptics.success()
        dismiss()
    }

    private func createCategory() {
        let trimmedTitle = newCategoryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            Haptics.error()
            return
        }

        if let existing = categoryOptions.first(where: { $0.title.caseInsensitiveCompare(trimmedTitle) == .orderedSame }) {
            Haptics.selection()
            category = existing
            newCategoryTitle = ""
            closePanel()
            return
        }

        let newCategory = TaskCategory.custom(
            id: "custom-local-\(UUID().uuidString)",
            title: trimmedTitle,
            tone: nextLocalCategoryTone
        )

        Haptics.success()
        localTaskCategories.append(newCategory)
        category = newCategory
        newCategoryTitle = ""
        closePanel()
    }

    private var nextLocalCategoryTone: MemberTone {
        let tones: [MemberTone] = [.lavender, .amber, .sky, .coral, .mint]
        return tones[(store.customTaskCategories.count + localTaskCategories.count) % tones.count]
    }

    private func persistedCategoryIfNeeded(_ selectedCategory: TaskCategory) -> TaskCategory {
        if store.availableTaskCategories.contains(where: { $0.id == selectedCategory.id }) {
            return selectedCategory
        }

        return store.addTaskCategory(title: selectedCategory.title) ?? selectedCategory
    }

    static func dateLabel(
        for date: Date,
        relativeTo referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        AppStore.taskDueLabel(
            for: date,
            relativeTo: referenceDate,
            calendar: calendar
        )
    }

    static func defaultDueDate(
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        let nextHour = calendar.date(byAdding: .hour, value: 1, to: now) ?? now
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: nextHour)
        return calendar.date(from: components) ?? nextHour
    }

    private static func date(fromDueLabel label: String) -> Date {
        let normalized = label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        if normalized.contains("amanha"),
           let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) {
            return tomorrow
        }

        if normalized.contains("hoje") {
            return .now
        }

        if let date = dueDateFormatter.date(from: label) {
            return date
        }

        return .now
    }

    private static let dueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

}

struct TaskOwnerChoice: Identifiable, Hashable {
    var memberID: UUID?
    var name: String
    var label: String

    var id: String { memberID?.uuidString ?? "label:\(name)" }

    static func options(
        members: [HouseholdMember],
        selectedName: String,
        selectedMemberID: UUID?
    ) -> [TaskOwnerChoice] {
        let people = members.filter { $0.role != .assistant }
        var options = [
            TaskOwnerChoice(
                memberID: nil,
                name: HouseholdWorkload.sharedOwnerLabel,
                label: HouseholdWorkload.sharedOwnerLabel
            )
        ]

        for person in people {
            let namesakes = people.count { HouseholdWorkload.isSameOwner($0.name, person.name) }
            let relationship = person.relationship.trimmingCharacters(in: .whitespacesAndNewlines)
            options.append(
                TaskOwnerChoice(
                    memberID: person.id,
                    name: person.name,
                    label: namesakes > 1 && !relationship.isEmpty
                        ? "\(person.name) · \(relationship)"
                        : person.name
                )
            )
        }

        guard selectedMemberID == nil,
              !HouseholdWorkload.isSharedOwner(selectedName),
              !options.contains(where: { HouseholdWorkload.isSameOwner($0.name, selectedName) }) else {
            return options
        }

        return options + [TaskOwnerChoice(memberID: nil, name: selectedName, label: selectedName)]
    }
}

enum ShoppingEditorMode: Hashable {
    case add
    case edit(UUID)
}

struct ShoppingEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var mode: ShoppingEditorMode
    @State private var title = ""
    @State private var amount = ""
    @State private var owner = "Casa"
    @State private var ownerMemberID: UUID?
    @State private var didLoad = false
    @State private var addedCount = 0
    @State private var isShowingDeleteConfirmation = false
    @FocusState private var isTitleFocused: Bool

    private var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var ownerOptions: [TaskOwnerChoice] {
        TaskOwnerChoice.options(
            members: store.familyGroup.members,
            selectedName: owner,
            selectedMemberID: ownerMemberID
        )
    }

    private func isSelectedOwner(_ option: TaskOwnerChoice) -> Bool {
        option.memberID == ownerMemberID && option.name == owner
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(eyebrow: isEditing ? "Editar item" : "Novo item") {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("O que está faltando?", text: $title)
                        .font(.system(size: 27, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(NinaTheme.ink)
                        .tint(NinaTheme.cobalt)
                        .textFieldStyle(.plain)
                        .focused($isTitleFocused)
                        .submitLabel(.done)

                    TextField("Quantidade, se importar", text: $amount)
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(NinaTheme.muted)
                        .tint(NinaTheme.cobalt)
                        .textFieldStyle(.plain)

                    if !isEditing {
                        NinaButton(title: "Adicionar e continuar", kind: .quiet, isEnabled: !trimmedTitle.isEmpty) {
                            save(keepingSheetOpen: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)

                        if addedCount > 0 {
                            Text(
                                addedCount == 1
                                    ? "1 item entrou na lista."
                                    : "\(addedCount) itens entraram na lista."
                            )
                            .ninaText(.caption, NinaTheme.muted)
                        }
                    }

                    if isEditing {
                        NinaButton(title: "Apagar este item", kind: .quiet) {
                            Haptics.warning()
                            isShowingDeleteConfirmation = true
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)

            bottomBar
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
        .alert("Apagar este item?", isPresented: $isShowingDeleteConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Apagar", role: .destructive) {
                deleteItem()
            }
        } message: {
            Text("O item sai da lista para todo mundo da casa.")
        }
        .onAppear(perform: loadIfNeeded)
        .task {
            guard case .add = mode else { return }
            await Task.yield()
            isTitleFocused = true
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(ownerOptions) { option in
                            Button {
                                Haptics.selection()
                                owner = option.name
                                ownerMemberID = option.memberID
                            } label: {
                                Label(
                                    option.label,
                                    systemImage: isSelectedOwner(option) ? "checkmark" : "person"
                                )
                            }
                        }
                    } label: {
                        NinaChip(
                            text: ownerMemberID == nil
                                ? "Ninguém ainda"
                                : (ownerOptions.first(where: isSelectedOwner)?.label ?? owner),
                            isSet: ownerMemberID != nil
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()

            HStack(spacing: 12) {
                Text("Só o nome é obrigatório")
                    .ninaText(.caption, NinaTheme.muted)

                Spacer(minLength: 8)

                Button {
                    save(keepingSheetOpen: false)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(NinaTheme.onCobalt)
                        .frame(width: 52, height: 52)
                        .background(NinaTheme.cobalt, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(trimmedTitle.isEmpty)
                .opacity(trimmedTitle.isEmpty ? 0.4 : 1)
                .accessibilityLabel(isEditing ? "Salvar item" : "Adicionar item")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(NinaTheme.ground)
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        guard case .edit(let id) = mode,
              let item = store.shoppingItems.first(where: { $0.id == id }) else {
            return
        }

        title = item.title
        amount = item.amount
        owner = item.owner
        ownerMemberID = item.ownerMemberID
    }

    private func save(keepingSheetOpen: Bool) {
        guard !trimmedTitle.isEmpty else {
            Haptics.error()
            return
        }

        Haptics.success()
        switch mode {
        case .add:
            store.addShoppingItem(
                title: title,
                amount: amount,
                owner: owner,
                ownerMemberID: ownerMemberID
            )
        case .edit(let id):
            store.updateShoppingItem(
                id: id,
                title: title,
                amount: amount,
                owner: owner,
                ownerMemberID: ownerMemberID
            )
        }

        guard keepingSheetOpen else {
            dismiss()
            return
        }

        addedCount += 1
        title = ""
        amount = ""
        isTitleFocused = true
    }

    private func deleteItem() {
        guard case .edit(let id) = mode else { return }
        Haptics.success()
        store.deleteShoppingItem(id)
        dismiss()
    }
}

struct InviteFamilySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var inviteURL: URL {
        store.inviteURL
    }

    private var inviteIsActive: Bool {
        store.inviteStatus?.isActive ?? true
    }

    private var inviterName: String {
        store.currentFamilyMember?.name.firstWord ?? "Alguém"
    }

    // What the invite says is what the invite does: the link opens a request,
    // and someone in the house still has to approve it.
    private var messageText: String {
        "\(inviterName) quer dividir a \(store.familyGroup.name) com você na Nina. Tocar no link só pede entrada — alguém da casa ainda precisa aprovar."
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(eyebrow: "Convite") {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Chamar alguém para a casa").ninaText(.screen)
                        Text("O link não dá acesso. Ele pede entrada, e alguém daqui aprova. Isto é o que vai chegar:")
                            .ninaText(.label, NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(messageText)
                            .ninaText(.label, NinaTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(inviteURL.absoluteString)
                            .ninaText(.caption, NinaTheme.cobalt, weight: .semibold)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ninaCard(fill: NinaTheme.grout, stroke: .clear)

                    inviteFacts

                    if store.canManageFamily, store.canInviteMorePeople, inviteIsActive {
                        ShareLink(item: inviteURL, message: Text(messageText)) {
                            ShareButtonFace(title: "Enviar convite", isProminent: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(
                            store.canInviteMorePeople
                                ? "O link atual não vale mais. Gere um novo na tela Casa."
                                : "A casa chegou no limite de 8 pessoas. A Nina não ocupa vaga."
                        )
                        .ninaText(.caption, NinaTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .ninaCard(fill: NinaTheme.grout, stroke: .clear)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var inviteFacts: some View {
        VStack(spacing: 0) {
            factRow(
                "Vagas na casa",
                store.canInviteMorePeople ? "\(store.remainingFamilySlots)" : "nenhuma"
            )

            if let invite = store.inviteStatus {
                NinaDivider(inset: 0)
                factRow("Situação do link", invite.status.title)
                NinaDivider(inset: 0)
                factRow("Usos restantes", "\(invite.usesRemaining) de \(invite.maxUses)")
                NinaDivider(inset: 0)
                factRow("Vale até", invite.expiresAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .ninaText(.caption, NinaTheme.muted)
                .frame(width: 120, alignment: .leading)
            Text(value).ninaText(.label)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
    }
}

struct MemberDetailSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var memberID: UUID

    var body: some View {
        Group {
            if let member = store.familyGroup.members.first(where: { $0.id == memberID }) {
                MemberDetailView(member: member)
            } else {
                VStack(spacing: 0) {
                    SheetHeader(eyebrow: "Pessoa") {
                        dismiss()
                    }

                    ZeroState(
                        headline: "Essa pessoa não está mais na casa.",
                        body_: "Alguém com permissão pode ter removido o perfil.",
                        showsMark: false
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 40)

                    Spacer()
                }
                .ninaSheetBackground()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct SuggestionDetailSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var suggestion: NinaSuggestion

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(eyebrow: "Proposta") {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(suggestion.title).ninaText(.screen)

                    Text(suggestion.detail)
                        .ninaText(.label, NinaTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        CategoryGlyph(systemName: suggestion.symbolName, size: 17, tint: NinaTheme.muted)
                        Text("\(suggestion.payloadOwner) · \(suggestion.payloadDueLabel)")
                            .ninaText(.caption, NinaTheme.muted)
                    }

                    Text(suggestion.payloadDetail)
                        .ninaText(.caption, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    // Nothing enters the house until a person taps this.
                    NinaButton(title: suggestion.actionTitle, fillsWidth: true) {
                        Haptics.success()
                        store.applySuggestion(suggestion)
                        dismiss()
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

// The horizontal drag belongs to the tab pager, so a row cannot carry swipe
// actions. Long press opens this instead, and the sheet says so out loud.
struct TaskQuickActionsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router
    @Environment(\.dismiss) private var dismiss

    let task: TaskItem

    private var isOverdue: Bool { task.isOverdue() }

    private var me: HouseholdMember? {
        store.currentFamilyMember
    }

    private var canTakeOver: Bool {
        guard let me else { return false }
        return me.id != task.ownerMemberID
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(eyebrow: "Ações rápidas") {
                dismiss()
            }

            VStack(spacing: 0) {
                taskLine

                NinaDivider(inset: 0)

                actionRow(
                    title: task.isDone ? "Marcar como não feita" : "Marcar como feita",
                    systemName: "checkmark",
                    tint: task.isDone ? NinaTheme.ink : NinaTheme.moss
                ) {
                    task.isDone ? Haptics.selection() : Haptics.success()
                    store.toggleTask(task)
                    dismiss()
                }

                if task.kind == .task {
                    NinaDivider(inset: 52)

                    actionRow(title: "Empurrar pra amanhã", systemName: "clock") {
                        Haptics.success()
                        pushToTomorrow()
                        dismiss()
                    }
                }

                if canTakeOver, let me {
                    NinaDivider(inset: 52)

                    actionRow(title: "Chamar pra mim", systemName: "person") {
                        Haptics.success()
                        takeOver(as: me)
                        dismiss()
                    }
                }

                NinaDivider(inset: 52)

                if task.kind == .task {
                    actionRow(title: "Virar semente", systemName: "leaf") {
                        Haptics.success()
                        turnIntoSeed()
                        dismiss()
                    }
                } else {
                    actionRow(title: "Plantar", systemName: "calendar") {
                        Haptics.lightImpact()
                        dismiss()
                        router.presentedSheet = .plantSeed(task.id)
                    }
                }
            }
            .padding(.horizontal, 20)

            Text("Toque e segure numa linha para abrir isto. A Nina não usa deslize lateral — esse gesto é de trocar de aba.")
                .ninaText(.caption, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)

            Spacer(minLength: 0)
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
        .presentationDetents([.medium])
    }

    private var taskLine: some View {
        HStack(spacing: 12) {
            NinaCheckbox(isOn: task.isDone, isOverdue: isOverdue)

            Text(task.title)
                .font(.system(size: 17, weight: .medium))
                .tracking(-0.1)
                .foregroundStyle(NinaTheme.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            if task.kind == .task {
                Text(task.effectiveDueLabel())
                    .font(.system(size: 13, weight: isOverdue ? .semibold : .regular))
                    .foregroundStyle(isOverdue ? NinaTheme.terracotta : NinaTheme.muted)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 52)
    }

    private func actionRow(
        title: String,
        systemName: String,
        tint: Color = NinaTheme.ink,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            NinaRow(title: title, subtitle: nil) {
                CategoryGlyph(systemName: systemName, size: 18, tint: tint)
            } trailing: {
                EmptyView()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pushToTomorrow() {
        let base = max(task.dueAt ?? .now, .now)
        let target = Calendar.current.date(byAdding: .day, value: 1, to: base) ?? base
        store.updateTask(
            id: task.id,
            title: task.title,
            subtitle: task.subtitle,
            owner: task.owner,
            ownerMemberID: task.ownerMemberID,
            dueLabel: AppStore.taskDueLabel(for: target),
            dueAt: target,
            category: task.category,
            priority: task.priority
        )
    }

    private func takeOver(as member: HouseholdMember) {
        store.updateTask(
            id: task.id,
            title: task.title,
            subtitle: task.subtitle,
            owner: member.name,
            ownerMemberID: member.id,
            dueLabel: task.dueLabel,
            dueAt: task.dueAt,
            category: task.category,
            priority: task.priority
        )
    }

    private func turnIntoSeed() {
        store.updateTask(
            id: task.id,
            title: task.title,
            subtitle: task.subtitle,
            owner: task.owner,
            ownerMemberID: task.ownerMemberID,
            dueLabel: "Sem data",
            dueAt: nil,
            category: task.category,
            priority: task.priority,
            kind: .seed
        )
    }
}

// Dismissing this used to mean the remote version won in silence. There is no
// dismissal now: both versions exist and one of them has to be chosen.
struct TaskEditConflictSheet: View {
    @Environment(AppStore.self) private var store

    let conflict: TaskEditConflict

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Outra pessoa mexeu nesta tarefa enquanto você escrevia.")
                        .ninaText(.caption, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("As duas versões existem. Escolha uma.")
                        .ninaText(.zero)
                        .fixedSize(horizontal: false, vertical: true)

                    versionCard(
                        eyebrow: "A sua",
                        task: conflict.localTask,
                        isMine: true
                    )

                    versionCard(
                        eyebrow: "A que chegou",
                        task: conflict.remoteTask,
                        isMine: false
                    )

                    VStack(spacing: 8) {
                        NinaButton(title: "Ficar com a minha", fillsWidth: true) {
                            Haptics.success()
                            store.keepLocalTaskConflict()
                        }

                        NinaButton(title: "Ficar com a que chegou", kind: .outline, fillsWidth: true) {
                            Haptics.selection()
                            store.acceptRemoteTaskConflict()
                        }
                    }
                    .padding(.top, 4)

                    Text("Não dá para fechar isto sem escolher. Sair daqui sem responder apagaria a sua edição sem você saber.")
                        .ninaText(.caption, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
        .interactiveDismissDisabled(true)
    }

    private func versionCard(eyebrow: String, task: TaskItem, isMine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: eyebrow)

            Text(task.title)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.1)
                .foregroundStyle(NinaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(task.kind == .seed ? "Sem data" : task.effectiveDueLabel()) · dono: \(task.owner)")
                .ninaText(.caption, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard(
            fill: isMine ? NinaTheme.cobaltWash : NinaTheme.ground,
            stroke: isMine ? NinaTheme.cobalt : NinaTheme.line
        )
    }
}

#Preview("Task sheet") {
    NavigationStack {
        TaskEditorSheet(mode: .add(sectionID: AppStore.houseTasksSectionID))
            .environment(AppStore())
    }
}
