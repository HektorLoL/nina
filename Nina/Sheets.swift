import StoreKit
import SwiftUI
import UIKit

enum TaskEditorMode: Hashable {
    case add(sectionID: String)
    case edit(UUID)
    case plant(UUID)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                premiumSection
                accountSection
                ninaSection
                houseSection
                privacySection
                aboutSection
                #if DEBUG
                developerSection
                #endif
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .ninaSheetBackground()
        .navigationTitle("Ajustes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Fechar") {
                    Haptics.selection()
                    dismiss()
                }
            }
        }
    }

    private var header: some View {
        SoftCard(padding: 18) {
            HStack(spacing: 16) {
                NinaAvatarView(size: 68)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Nina")
                        .font(.title2.weight(.black))
                        .foregroundStyle(NinaTheme.ink)

                    Text("Ajustes da casa, privacidade e lembretes.")
                        .font(.subheadline)
                        .foregroundStyle(NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var premiumSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Premium")
                .font(.subheadline.weight(.black))
                .foregroundStyle(NinaTheme.muted)
                .padding(.horizontal, 2)

            PremiumTeaserCard(
                style: .settings,
                entitlement: premiumStore.entitlement,
                priceLabel: premiumStore.primaryPriceLabel
            ) {
                router.presentedSheet = .premium
            }
        }
    }

    private var accountSection: some View {
        SettingsGroup(title: "Conta") {
            if let user = authSession.currentUser {
                let profile = profileStore.profile(for: user)

                NavigationLink {
                    ProfileEditorView(user: user)
                } label: {
                    ProfileSettingsRow(
                        profile: profile,
                        user: user,
                        photoData: profileStore.photoData(for: profile)
                    )
                }
                .buttonStyle(.plain)

                SettingsDivider()

                NavigationLink {
                    EmailAccessView()
                } label: {
                    SettingsActionRow(
                        title: user.linkedProviders.contains(.email) ? "Email de acesso" : "Vincular email",
                        subtitle: user.linkedProviders.contains(.email)
                            ? (user.email ?? "Email verificado")
                            : "Adicione uma forma alternativa de entrar.",
                        systemName: "envelope.badge.shield.half.filled",
                        tone: .lavender
                    )
                }
                .buttonStyle(.plain)

                SettingsDivider()

                NavigationLink {
                    AccountDeletionView()
                } label: {
                    SettingsActionRow(
                        title: "Apagar conta",
                        subtitle: "Remove sua conta e dados pessoais associados.",
                        systemName: "trash.fill",
                        tone: .coral
                    )
                }
                .buttonStyle(.plain)

                SettingsDivider()
            }

            Button {
                Haptics.lightImpact()
                onboardingStore.replayTutorial()
                dismiss()
            } label: {
                SettingsActionRow(
                    title: "Ver tutorial",
                    subtitle: "Rever como usar a Nina.",
                    systemName: "play.circle.fill",
                    tone: .sky
                )
            }
            .buttonStyle(.plain)

            SettingsDivider()

            Button {
                Haptics.warning()
                Task {
                    await authSession.signOut()
                    onboardingStore.cancelReplay()
                    dismiss()
                }
            } label: {
                SettingsActionRow(
                    title: "Sair",
                    subtitle: "Encerrar a sessão neste aparelho.",
                    systemName: "rectangle.portrait.and.arrow.right.fill",
                    tone: .coral
                )
            }
            .buttonStyle(.plain)
            .disabled(authSession.isSigningIn)
            .opacity(authSession.isSigningIn ? 0.62 : 1)
        }
    }

    private var ninaSection: some View {
        SettingsGroup(title: "Nina") {
            NavigationLink {
                NotificationPreferencesView()
            } label: {
                SettingsActionRow(
                    title: "Lembretes e notificações",
                    subtitle: notificationStatusSubtitle,
                    systemName: "bell.badge.fill",
                    tone: .amber
                )
            }
            .buttonStyle(.plain)

            SettingsDivider()

            weeklyDigestRow
        }
    }

    @ViewBuilder
    private var weeklyDigestRow: some View {
        if store.canManageFamily {
            SettingsToggleRow(
                title: "Resumo semanal",
                subtitle: weeklyDigestSubtitle,
                systemName: "calendar.badge.clock",
                tone: .sky,
                isOn: weeklyDigestBinding
            )
        } else {
            SettingsInfoRow(
                title: "Resumo semanal",
                subtitle: weeklyDigestSubtitle,
                value: store.isWeeklyDigestEnabled ? "ativo" : "desligado",
                systemName: "calendar.badge.clock",
                tone: .sky
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
            return "Uma visão curta da semana da casa, incluída no Premium."
        }
        if !store.canManageFamily {
            return "Quem cuida da casa escolhe se o resumo é gerado."
        }
        return "Uma visão curta da semana da casa, para todo mundo daqui."
    }

    private var houseSection: some View {
        SettingsGroup(title: "Casa") {
            SettingsInfoRow(
                title: store.familyGroup.name,
                subtitle: store.familyLimitLabel,
                value: "\(store.remainingFamilySlots) vagas",
                systemName: "house.and.flag.fill",
                tone: .mint
            )

            SettingsDivider()

            if store.canManageFamily, store.canInviteMorePeople, store.inviteStatus?.isActive ?? true {
                ShareLink(item: inviteURL) {
                    SettingsActionRow(
                        title: "Compartilhar convite",
                        subtitle: store.familyGroup.inviteCode,
                        systemName: "square.and.arrow.up.fill",
                        tone: .sky
                    )
                }
                .buttonStyle(.plain)
            } else if store.canManageFamily {
                SettingsInfoRow(
                    title: "Convites pausados",
                    subtitle: store.canInviteMorePeople
                        ? "Gere um novo link na tela Casa."
                        : "A casa já chegou ao limite de pessoas.",
                    value: "limite",
                    systemName: "person.crop.circle.badge.exclamationmark",
                    tone: .coral
                )
            } else {
                SettingsInfoRow(
                    title: store.currentPermissionRole.title,
                    subtitle: store.currentPermissionRole.summary,
                    value: "acesso",
                    systemName: store.currentPermissionRole.symbolName,
                    tone: .lavender
                )
            }
        }
    }

    private var privacySection: some View {
        SettingsGroup(title: "Privacidade") {
            NavigationLink {
                PrivacyConsentSettingsView()
            } label: {
                SettingsActionRow(
                    title: "Consentimento de IA",
                    subtitle: store.hasAIMemoryConsent ? "Ativo para conversas e memórias." : "Necessário antes da conversa online.",
                    systemName: store.hasAIMemoryConsent ? "checkmark.shield.fill" : "lock.shield.fill",
                    tone: store.hasAIMemoryConsent ? .mint : .lavender
                )
            }
            .buttonStyle(.plain)

            SettingsDivider()

            NavigationLink {
                PrivacyExportView()
            } label: {
                SettingsActionRow(
                    title: "Exportar meus dados",
                    subtitle: "Gera um arquivo JSON com os dados desta casa.",
                    systemName: "square.and.arrow.up.fill",
                    tone: .sky
                )
            }
            .buttonStyle(.plain)

            SettingsDivider()

            Button {
                Haptics.selection()
                openURL(NinaLegalLinks.privacyPolicy)
            } label: {
                SettingsActionRow(
                    title: "Política de privacidade",
                    subtitle: "Como a Nina trata os dados da sua casa.",
                    systemName: "doc.text.fill",
                    tone: .lavender
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var notificationStatusSubtitle: String {
        switch store.notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            "Avisos ativos e horário silencioso configurável."
        case .denied:
            "Bloqueadas pelo sistema. Toque para corrigir."
        case .notDetermined:
            "Ative os avisos quando fizer sentido para você."
        case .unavailable:
            "Configure os avisos deste aparelho."
        }
    }

    private var aboutSection: some View {
        SettingsGroup(title: "Sobre") {
            SettingsInfoRow(
                title: "Versão",
                subtitle: "Nina para organização da casa",
                value: versionLabel,
                systemName: "info.circle.fill",
                tone: .mint
            )

            SettingsDivider()

            Button {
                Haptics.selection()
                openURL(NinaLegalLinks.termsOfUse)
            } label: {
                SettingsActionRow(
                    title: "Termos de uso",
                    subtitle: "Condições da assinatura e do serviço.",
                    systemName: "text.book.closed.fill",
                    tone: .sky
                )
            }
            .buttonStyle(.plain)

            SettingsDivider()

            Button {
                Haptics.selection()
                openURL(NinaLegalLinks.support)
            } label: {
                SettingsActionRow(
                    title: "Falar com o suporte",
                    subtitle: "oi@ninai.app",
                    systemName: "envelope.fill",
                    tone: .amber
                )
            }
            .buttonStyle(.plain)
        }
    }

    #if DEBUG
    private var developerSection: some View {
        SettingsGroup(title: "Desenvolvimento") {
            NavigationLink {
                BackendDebugView()
            } label: {
                SettingsActionRow(
                    title: "Debug do backend",
                    subtitle: "\(backendDiagnostics.environment.title) · \(backendDiagnostics.activeRequestCount) ativa(s)",
                    systemName: "ladybug.fill",
                    tone: .coral
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(
                    title: "Diagnóstico do backend",
                    subtitle: "Estado local desta instalação de desenvolvimento."
                )

                SettingsGroup(title: "Identidade") {
                    DebugValueRow(title: "User ID", value: userID)
                    SettingsDivider()
                    DebugValueRow(title: "Family ID", value: familyID)
                }

                SettingsGroup(title: "Conexão") {
                    DebugValueRow(
                        title: "Ambiente",
                        value: diagnostics.environment.title,
                        detail: diagnostics.environment.detail
                    )
                    SettingsDivider()
                    DebugValueRow(
                        title: "Último sync",
                        value: lastSyncLabel,
                        detail: diagnostics.lastOperation
                    )
                    SettingsDivider()
                    DebugValueRow(
                        title: "Requisições ativas",
                        value: "\(diagnostics.activeRequestCount)"
                    )
                }

                SettingsGroup(title: "Último erro") {
                    DebugValueRow(
                        title: diagnostics.lastErrorAt?.formatted(date: .abbreviated, time: .standard)
                            ?? "Sem falhas",
                        value: lastErrorLabel,
                        isError: diagnostics.lastError != nil
                    )
                }

                PrimaryCapsuleButton(
                    title: isRefreshing ? "Atualizando..." : "Atualizar agora",
                    systemName: "arrow.clockwise"
                ) {
                    refresh()
                }
                .disabled(isBusy)
                .opacity(isBusy ? 0.62 : 1)

                Text("Atualiza o perfil e os dados compartilhados da casa usando o usuário autenticado atual.")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .ninaSheetBackground()
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
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
    var isError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(NinaTheme.muted)

            Text(value)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(isError ? NinaTheme.coral : NinaTheme.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(NinaTheme.muted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(
                    title: "Email de acesso",
                    subtitle: "Confirme um email pessoal para entrar com um código quando não usar a Apple."
                )

                SoftCard(padding: 16) {
                    VStack(spacing: 14) {
                        SettingsInfoRow(
                            title: "Email atual",
                            subtitle: authSession.currentUser?.linkedProviders.contains(.email) == true
                                ? (authSession.currentUser?.email ?? "Email verificado")
                                : "Somente Apple",
                            value: authSession.currentUser?.linkedProviders.contains(.email) == true
                                ? "verificado"
                                : "Apple",
                            systemName: "person.badge.key.fill",
                            tone: .mint
                        )

                        Divider()

                        LoginLikeField(
                            title: "Novo email",
                            systemName: "envelope.fill",
                            text: $email,
                            placeholder: "voce@exemplo.com",
                            keyboardType: .emailAddress
                        )
                        .focused($focusedField, equals: .email)
                        .disabled(isWaitingForCode)

                        if isWaitingForCode {
                            Divider()

                            LoginLikeField(
                                title: "Código",
                                systemName: "number.circle.fill",
                                text: $code,
                                placeholder: "000000",
                                keyboardType: .numberPad
                            )
                            .focused($focusedField, equals: .code)
                            .onChange(of: code) { _, newValue in
                                code = String(newValue.filter(\.isNumber).prefix(6))
                            }
                        }
                    }
                }

                if let errorMessage = authSession.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(NinaTheme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if didComplete {
                    Label("Email confirmado e pronto para login por código.", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(NinaTheme.mint)
                }

                PrimaryCapsuleButton(
                    title: isWaitingForCode ? "Confirmar email" : "Enviar código",
                    systemName: isWaitingForCode ? "checkmark" : "paperplane.fill"
                ) {
                    isWaitingForCode ? verifyChange() : requestChange()
                }
                .disabled(authSession.isRequestingCode || authSession.isSigningIn)
                .opacity(authSession.isRequestingCode || authSession.isSigningIn ? 0.6 : 1)

                if isWaitingForCode {
                    Button("Usar outro email") {
                        authSession.pendingEmailChange = nil
                        code = ""
                        focusedField = .email
                    }
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(NinaTheme.sky)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(18)
        }
        .ninaSheetBackground()
        .navigationTitle("Email de acesso")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            email = authSession.pendingEmailChange ?? authSession.currentUser?.email ?? ""
        }
        .toolbar {
            if didComplete {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Concluir") {
                        dismiss()
                    }
                }
            }
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

private struct PrivacyConsentSettingsView: View {
    @Environment(AppStore.self) private var store

    private var acceptedLabel: String {
        guard let acceptedAt = store.aiMemoryConsent?.acceptedAt else {
            return "Ainda não aceito"
        }
        return acceptedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(
                    title: "Consentimento de IA",
                    subtitle: "Controle quando a Nina pode processar conversas, anexos e memórias confirmadas para recursos de IA."
                )

                SettingsGroup(title: "Status") {
                    SettingsInfoRow(
                        title: store.hasAIMemoryConsent ? "Consentimento ativo" : "Consentimento pendente",
                        subtitle: acceptedLabel,
                        value: store.hasAIMemoryConsent ? "ativo" : "pausado",
                        systemName: store.hasAIMemoryConsent ? "checkmark.shield.fill" : "lock.shield.fill",
                        tone: store.hasAIMemoryConsent ? .mint : .lavender
                    )
                }

                SoftCard(padding: 16) {
                    PrivacyBulletRow(
                        systemName: "sparkles",
                        text: "A Nina usa mensagens, fotos, documentos e dados confirmados da casa para responder e propor organização."
                    )
                    PrivacyBulletRow(
                        systemName: "checkmark.circle.fill",
                        text: "Tarefas e memórias só entram na casa depois da sua confirmação."
                    )
                    PrivacyBulletRow(
                        systemName: "person.fill",
                        text: "Memórias pessoais começam privadas; compartilhar com a casa exige escolha explícita."
                    )
                    PrivacyBulletRow(
                        systemName: "trash.fill",
                        text: "Revogar pausa novas conversas online. Dados já criados podem ser apagados nas telas de memória e histórico."
                    )
                }

                if let error = store.syncErrorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NinaTheme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if store.hasAIMemoryConsent {
                    Button(role: .destructive) {
                        Haptics.warning()
                        Task {
                            await store.revokeAIMemoryConsent()
                        }
                    } label: {
                        Label("Revogar consentimento", systemImage: "xmark.shield.fill")
                            .font(.headline.weight(.black))
                            .foregroundStyle(NinaTheme.coral)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(NinaTheme.coral.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isSyncingHome)
                    .opacity(store.isSyncingHome ? 0.5 : 1)
                } else {
                    PrimaryCapsuleButton(title: "Aceitar processamento da Nina", systemName: "checkmark.shield.fill") {
                        Haptics.success()
                        Task {
                            await store.grantAIMemoryConsent()
                        }
                    }
                    .disabled(store.isSyncingHome)
                    .opacity(store.isSyncingHome ? 0.5 : 1)
                }
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .ninaSheetBackground()
        .navigationTitle("Consentimento")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacyExportView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(ProfileStore.self) private var profileStore
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(
                    title: "Exportar dados",
                    subtitle: "Gere um arquivo JSON com os dados locais sincronizados desta casa."
                )

                SoftCard(padding: 16) {
                    PrivacyBulletRow(systemName: "person.text.rectangle.fill", text: "Inclui seu perfil e a foto salva, quando houver.")
                    PrivacyBulletRow(systemName: "house.fill", text: "Inclui casa, participantes, tarefas com horários, compras e insights.")
                    PrivacyBulletRow(systemName: "bubble.left.and.bubble.right.fill", text: "Inclui o histórico privado da Nina carregado neste aparelho.")
                    PrivacyBulletRow(systemName: "lock.fill", text: "Inclui o status do consentimento de IA salvo para esta conta.")
                }

                if let exportError {
                    Label(exportError, systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NinaTheme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }

                PrimaryCapsuleButton(title: "Gerar exportação", systemName: "doc.badge.arrow.up.fill") {
                    generateExport()
                }

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Compartilhar arquivo JSON", systemImage: "square.and.arrow.up.fill")
                            .font(.headline.weight(.black))
                            .foregroundStyle(NinaTheme.sky)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(NinaTheme.sky.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .ninaSheetBackground()
        .navigationTitle("Exportar")
        .navigationBarTitleDisplayMode(.inline)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(
                    title: "Apagar conta",
                    subtitle: "Remove sua conta Nina e dados pessoais associados que não precisem ser mantidos por obrigação legal."
                )

                SoftCard(padding: 16) {
                    PrivacyBulletRow(systemName: "person.crop.circle.badge.xmark", text: "Sua sessão, perfil, foto e acesso às casas serão removidos.")
                    PrivacyBulletRow(systemName: "lock.fill", text: "Conversas privadas, propostas pendentes e memórias pessoais da Nina serão apagadas.")
                    PrivacyBulletRow(systemName: "person.2.fill", text: "Em casas compartilhadas, tarefas e registros da casa podem continuar para os demais participantes sem sua conta vinculada.")
                }

                if let errorMessage = authSession.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NinaTheme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(role: .destructive) {
                    Haptics.warning()
                    isShowingConfirmation = true
                } label: {
                    Label(
                        authSession.isDeletingAccount ? "Apagando..." : "Apagar minha conta",
                        systemImage: "trash.fill"
                    )
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(NinaTheme.coral, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(authSession.isDeletingAccount)
                .opacity(authSession.isDeletingAccount ? 0.62 : 1)
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .ninaSheetBackground()
        .navigationTitle("Apagar conta")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Apagar sua conta Nina?", isPresented: $isShowingConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Apagar conta", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("Esta ação remove sua conta e dados pessoais associados. Ela não pode ser desfeita.")
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

private struct PrivacyBulletRow: View {
    var systemName: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemName)
                .font(.caption.weight(.black))
                .foregroundStyle(NinaTheme.mint)
                .frame(width: 20, height: 20)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LoginLikeField: View {
    var title: String
    var systemName: String
    @Binding var text: String
    var placeholder: String
    var keyboardType: UIKeyboardType

    var body: some View {
        HStack(spacing: 12) {
            IconBubble(systemName: systemName, tone: .lavender, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(NinaTheme.muted)

                TextField(placeholder, text: $text)
                    .font(.headline.weight(.semibold))
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(keyboardType == .emailAddress ? .emailAddress : .oneTimeCode)
            }
        }
    }
}

private struct NotificationPreferencesView: View {
    @Environment(AppStore.self) private var store
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(
                    title: "Lembretes e notificações",
                    subtitle: "A Nina avisa no horário certo, respeitando o descanso da casa."
                )

                authorizationCard

                SettingsGroup(title: "Avisos") {
                    SettingsToggleRow(
                        title: "Notificações neste aparelho",
                        subtitle: "Tarefas com horário e avisos próximos.",
                        systemName: "bell.badge.fill",
                        tone: .amber,
                        isOn: notificationToggle
                    )
                }

                SettingsGroup(title: "Horário silencioso") {
                    SettingsToggleRow(
                        title: "Silenciar avisos à noite",
                        subtitle: quietHoursSummary,
                        systemName: "moon.fill",
                        tone: .sky,
                        isOn: $quietHoursEnabled
                    )

                    SettingsDivider()

                    timePickerRow(
                        title: "Começa",
                        systemName: "moon.stars.fill",
                        selection: quietHoursStartBinding
                    )

                    SettingsDivider()

                    timePickerRow(
                        title: "Termina",
                        systemName: "sunrise.fill",
                        selection: quietHoursEndBinding
                    )
                }
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .ninaSheetBackground()
        .navigationTitle("Notificações")
        .navigationBarTitleDisplayMode(.inline)
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
    private var authorizationCard: some View {
        SoftCard {
            HStack(alignment: .top, spacing: 12) {
                IconBubble(
                    systemName: authorizationSystemName,
                    tone: authorizationTone,
                    size: 44
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(authorizationTitle)
                        .font(.headline.weight(.black))
                        .foregroundStyle(NinaTheme.ink)

                    Text(authorizationMessage)
                        .font(.subheadline)
                        .foregroundStyle(NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            switch store.notificationAuthorizationStatus {
            case .notDetermined:
                Button {
                    Haptics.lightImpact()
                    Task {
                        _ = await store.requestNotificationAuthorization()
                    }
                } label: {
                    Label("Permitir notificações", systemImage: "bell.badge.fill")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(NinaTheme.mint, in: Capsule())
                }
                .buttonStyle(.plain)
            case .denied:
                Button {
                    guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                    openURL(url)
                } label: {
                    Label("Abrir Ajustes do iPhone", systemImage: "gearshape.fill")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(NinaTheme.sky)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(NinaTheme.sky.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            case .authorized, .provisional, .ephemeral, .unavailable:
                EmptyView()
            }
        }
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
        HStack(spacing: 12) {
            IconBubble(systemName: systemName, tone: .sky, size: 40)

            Text(title)
                .font(.headline.weight(.heavy))
                .foregroundStyle(NinaTheme.ink)

            Spacer()

            DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
        .padding(14)
        .disabled(!quietHoursEnabled)
        .opacity(quietHoursEnabled ? 1 : 0.55)
    }

    private var quietHoursSummary: String {
        "Entre \(formattedTime(quietHoursStartMinutes)) e \(formattedTime(quietHoursEndMinutes)) os avisos chegam sem som, no horário que você escolheu."
    }

    private func formattedTime(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private var authorizationTitle: String {
        switch store.notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            "Notificações permitidas"
        case .notDetermined:
            "Você escolhe quando ativar"
        case .denied:
            "Notificações bloqueadas"
        case .unavailable:
            "Status indisponível"
        }
    }

    private var authorizationMessage: String {
        switch store.notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            "Os próximos avisos serão agendados neste aparelho."
        case .notDetermined:
            "Ative depois de criar tarefas com horário. A Nina só pede permissão neste momento."
        case .denied:
            "O iPhone não permite avisos da Nina. Você pode mudar isso nos Ajustes."
        case .unavailable:
            "Este aparelho não informou o estado das notificações."
        }
    }

    private var authorizationSystemName: String {
        switch store.notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            "checkmark.circle.fill"
        case .notDetermined:
            "bell.fill"
        case .denied:
            "bell.slash.fill"
        case .unavailable:
            "questionmark.circle.fill"
        }
    }

    private var authorizationTone: MemberTone {
        switch store.notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            .mint
        case .notDetermined:
            .amber
        case .denied:
            .coral
        case .unavailable:
            .lavender
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.black))
                .foregroundStyle(NinaTheme.muted)
                .padding(.horizontal, 2)

            SoftCard(padding: 0) {
                VStack(spacing: 0) {
                    content
                }
            }
        }
    }
}

private struct SettingsToggleRow: View {
    var title: String
    var subtitle: String
    var systemName: String
    var tone: MemberTone
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            IconBubble(systemName: systemName, tone: tone, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(NinaTheme.ink)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(NinaTheme.mint)
        }
        .padding(14)
        .accessibilityElement(children: .combine)
        .onChange(of: isOn) { oldValue, newValue in
            guard oldValue != newValue else { return }
            Haptics.selection()
        }
    }
}

private struct ProfileSettingsRow: View {
    var profile: UserProfile
    var user: AuthUser
    var photoData: Data?

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatarView(profile: profile, photoData: photoData, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(NinaTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text("Meu perfil · \(user.email ?? "Email não vinculado")")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NinaTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }

            Spacer(minLength: 12)

            Text(user.provider.title)
                .font(.caption.weight(.black))
                .foregroundStyle(profile.avatar.tone.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.black))
                .foregroundStyle(NinaTheme.muted)
        }
        .padding(14)
        .contentShape(Rectangle())
    }
}

private struct SettingsInfoRow: View {
    var title: String
    var subtitle: String
    var value: String
    var systemName: String
    var tone: MemberTone

    var body: some View {
        HStack(spacing: 12) {
            IconBubble(systemName: systemName, tone: tone, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(NinaTheme.ink)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.caption.weight(.black))
                .foregroundStyle(tone.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
    }
}

private struct SettingsActionRow: View {
    var title: String
    var subtitle: String
    var systemName: String
    var tone: MemberTone

    var body: some View {
        HStack(spacing: 12) {
            IconBubble(systemName: systemName, tone: tone, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(NinaTheme.ink)

                Text(subtitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NinaTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.black))
                .foregroundStyle(NinaTheme.muted)
        }
        .padding(14)
        .contentShape(Rectangle())
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 66)
    }
}

struct PremiumBenefitsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(PremiumSubscriptionStore.self) private var premiumStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var isManagingSubscription = false

    private let plan = PremiumPlan.mock

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                statusCard
                productsSection
                benefitsSection
                restoreArea
            }
            .padding(18)
            .padding(.bottom, 28)
        }
        .ninaSheetBackground()
        .navigationTitle("Premium")
        .navigationBarTitleDisplayMode(.inline)
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Fechar") {
                    Haptics.selection()
                    dismiss()
                }
            }
        }
        .task {
            await premiumStore.configure(for: authSession.currentUser)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                PremiumHeroMedallion()

                VStack(alignment: .leading, spacing: 8) {
                    Label(premiumStore.entitlement.statusTitle, systemImage: premiumStore.entitlement.isActive ? "checkmark.seal.fill" : "sparkles")
                        .font(.caption.weight(.black))
                        .foregroundStyle(NinaTheme.premiumInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.36), in: Capsule())

                    Text(plan.name)
                        .font(.system(size: 31, weight: .black, design: .rounded))
                        .foregroundStyle(NinaTheme.premiumInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(plan.heroTitle)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(NinaTheme.premiumInk.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(plan.heroSubtitle)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(NinaTheme.premiumInk.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NinaTheme.premiumGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.58), lineWidth: 1)
        )
        .shadow(color: NinaTheme.gold.opacity(0.30), radius: 24, x: 0, y: 14)
        .accessibilityElement(children: .combine)
    }

    private var statusCard: some View {
        SoftCard(padding: 18) {
            HStack(alignment: .center, spacing: 14) {
                IconBubble(
                    systemName: premiumStore.entitlement.statusSymbolName,
                    tone: premiumStore.entitlement.statusTone,
                    size: 48
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(premiumStore.entitlement.statusTitle)
                        .font(.title3.weight(.black))
                        .foregroundStyle(NinaTheme.ink)

                    Text(premiumStore.entitlement.renewalSummary)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                Text(premiumStore.entitlement.environment ?? "App Store")
                    .font(.caption.weight(.black))
                    .foregroundStyle(NinaTheme.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(NinaTheme.gold.opacity(0.16), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var productsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Planos", subtitle: "A assinatura é processada com segurança pelo App Store.")

            if premiumStore.isLoadingProducts {
                SoftCard(padding: 18) {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(NinaTheme.mint)

                        Text("Carregando planos Premium...")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(NinaTheme.muted)
                    }
                }
            } else if premiumStore.products.isEmpty {
                SoftCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Planos indisponíveis", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline.weight(.black))
                            .foregroundStyle(NinaTheme.ink)

                        Text(premiumStore.productLoadMessage ?? "Configure os produtos Premium no App Store Connect ou em um arquivo StoreKit local.")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                SoftCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(premiumStore.products, id: \.id) { product in
                            PremiumProductRow(
                                product: product,
                                isCurrent: premiumStore.entitlement.isActive
                                    && premiumStore.entitlement.productID == product.id,
                                isBusy: premiumStore.isPurchasing || premiumStore.isSyncingBackend
                            ) {
                                Task {
                                    Haptics.lightImpact()
                                    await premiumStore.purchase(product)
                                }
                            }

                            if product.id != premiumStore.products.last?.id {
                                Divider()
                                    .padding(.leading, 66)
                            }
                        }
                    }
                }
            }
        }
    }

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Benefícios premium", subtitle: "Pensado para deixar a organização da casa mais leve.")

            SoftCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(plan.benefits) { benefit in
                        PremiumBenefitRow(benefit: benefit)

                        if benefit.id != plan.benefits.last?.id {
                            Divider()
                                .padding(.leading, 66)
                        }
                    }
                }
            }
        }
    }

    private var restoreArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task {
                    Haptics.lightImpact()
                    await premiumStore.restorePurchases()
                }
            } label: {
                Label(premiumStore.isRestoring ? "Restaurando..." : "Restaurar compras", systemImage: "arrow.clockwise")
                    .font(.headline.weight(.black))
                    .foregroundStyle(NinaTheme.premiumInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(NinaTheme.premiumGradient, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.62), lineWidth: 1)
                    )
                    .shadow(color: NinaTheme.gold.opacity(0.24), radius: 16, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(premiumStore.isRestoring)
            .opacity(premiumStore.isRestoring ? 0.62 : 1)

            if store.householdPremium.isActive {
                manageSubscriptionRow
            }

            if let statusMessage = premiumStore.statusMessage, !statusMessage.isEmpty {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(NinaTheme.mint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage = premiumStore.errorMessage, !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(NinaTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Ao assinar, o App Store confirma o pagamento e a Nina registra a transação verificada no servidor para manter seu acesso Premium atualizado.")
                .font(.caption.weight(.bold))
                .foregroundStyle(NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            subscriptionTermsArea
        }
    }

    private var manageSubscriptionRow: some View {
        Button {
            Haptics.lightImpact()
            isManagingSubscription = true
        } label: {
            SoftCard(padding: 0) {
                HStack(alignment: .center, spacing: 12) {
                    IconBubble(systemName: "creditcard.fill", tone: .mint, size: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gerenciar assinatura")
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(NinaTheme.ink)

                        Text("Trocar de plano ou cancelar a renovação pela sua conta Apple.")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 10)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.black))
                        .foregroundStyle(NinaTheme.muted)
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
    }

    private var subscriptionTermsArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(plan.subscriptionDisclosure)
                .font(.caption.weight(.bold))
                .foregroundStyle(NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Text("A assinatura renova automaticamente até você cancelar. A cobrança é feita pelo App Store e a renovação pode ser cancelada a qualquer momento nos ajustes da sua conta Apple.")
                .font(.caption.weight(.bold))
                .foregroundStyle(NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                legalLink("Termos de uso", url: NinaLegalLinks.termsOfUse)
                legalLink("Privacidade", url: NinaLegalLinks.privacyPolicy)
            }
            .padding(.top, 2)
        }
        .padding(.top, 6)
    }

    private func legalLink(_ title: String, url: URL) -> some View {
        Button(title) {
            Haptics.selection()
            openURL(url)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(NinaTheme.muted)
        .buttonStyle(.plain)
    }
}

private struct PremiumProductRow: View {
    var product: Product
    var isCurrent: Bool
    var isBusy: Bool
    var action: () -> Void

    private var renewalLabel: String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return "Assinatura Premium"
        }
        return "Renova a cada \(period.localizedTitle)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IconBubble(systemName: isCurrent ? "checkmark.seal.fill" : "crown.fill", tone: isCurrent ? .mint : .amber, size: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(product.displayName)
                    .font(.headline.weight(.black))
                    .foregroundStyle(NinaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(renewalLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NinaTheme.muted)
            }

            Spacer(minLength: 10)

            Button(action: action) {
                Text(isCurrent ? "Atual" : product.displayPrice)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(isCurrent ? NinaTheme.mint : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(isCurrent ? NinaTheme.mint.opacity(0.14) : NinaTheme.mint, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isCurrent || isBusy)
            .opacity(isBusy && !isCurrent ? 0.62 : 1)
        }
        .padding(14)
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

private struct PremiumHeroMedallion: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.36))

            Circle()
                .stroke(.white.opacity(0.64), lineWidth: 1)

            Image(systemName: "crown.fill")
                .font(.system(size: 29, weight: .black))
                .foregroundStyle(NinaTheme.premiumInk)

            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(.white)
                .offset(x: 20, y: -20)
        }
        .frame(width: 66, height: 66)
        .shadow(color: NinaTheme.premiumInk.opacity(0.14), radius: 12, x: 0, y: 8)
    }
}

private struct PremiumBenefitRow: View {
    var benefit: PremiumBenefit

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBubble(systemName: benefit.systemName, tone: benefit.tone, size: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(benefit.title)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(NinaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(benefit.detail)
                    .font(.subheadline)
                    .foregroundStyle(NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
    }
}

struct TaskEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var mode: TaskEditorMode
    @State private var title = ""
    @State private var subtitle = ""
    @State private var owner = "Casa"
    @State private var dueDate = Date()
    @State private var kind: TaskKind = .task
    @State private var category: TaskCategory = .home
    @State private var priority: TaskPriority = .normal
    @State private var recurrence: TaskRecurrence = .none
    @State private var localTaskCategories: [TaskCategory] = []
    @State private var isCategoryDropdownExpanded = false
    @State private var isCreatingCategory = false
    @State private var newCategoryTitle = ""
    @State private var didLoad = false
    @State private var loadedTaskVersion: Int?
    @State private var isShowingDeleteConfirmation = false

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

    private var ownerOptions: [String] {
        var options = ["Casa"]
        for member in store.familyGroup.members where member.role != .assistant {
            if !options.contains(member.name) {
                options.append(member.name)
            }
        }

        if !owner.isEmpty, !options.contains(owner) {
            options.append(owner)
        }

        return options
    }

    private var categoryOptions: [TaskCategory] {
        let categories = store.availableTaskCategories + localTaskCategories
        return categories.contains(where: { $0.id == category.id }) ? categories : categories + [category]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(
                    title: editorTitle,
                    subtitle: isSeed
                        ? "Guarde a intenção agora. Escolha quando fazer depois."
                        : "Mantenha simples. A casa precisa lembrar, não complicar."
                )

                editorFields
                permissionCard

                PrimaryCapsuleButton(title: primaryActionTitle, systemName: isSeed ? "leaf.fill" : "checkmark") {
                    save()
                }
                .disabled(trimmedTitle.isEmpty)
                .opacity(trimmedTitle.isEmpty ? 0.5 : 1)

                if isEditing {
                    Button(role: .destructive) {
                        Haptics.warning()
                        isShowingDeleteConfirmation = true
                    } label: {
                        Label("Apagar tarefa", systemImage: "trash.fill")
                            .font(.headline.weight(.black))
                            .foregroundStyle(NinaTheme.coral)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(NinaTheme.coral.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
        }
        .scrollDismissesKeyboard(.interactively)
        .ninaSheetBackground()
        .navigationTitle(isEditing ? "Editar" : "Adicionar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Fechar") {
                    Haptics.selection()
                    dismiss()
                }
            }
        }
        .onAppear(perform: loadIfNeeded)
        .task {
            await store.refreshNotificationAuthorizationStatus()
        }
        .alert("Apagar esta tarefa?", isPresented: $isShowingDeleteConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Apagar", role: .destructive) {
                deleteTask()
            }
        } message: {
            Text("A tarefa e o aviso agendado serão removidos.")
        }
    }

    private var editorFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            SoftCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Tipo", systemImage: kind.symbolName)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(NinaTheme.muted)

                    Picker("Tipo", selection: $kind) {
                        ForEach(TaskKind.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isPlantingSeed)

                    Text(kind.editorDescription)
                        .font(.caption)
                        .foregroundStyle(NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SoftCard {
                TextField("O que precisa ser feito?", text: $title, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.headline)
                    .textFieldStyle(.plain)

                Divider()

                TextField("Detalhe opcional", text: $subtitle, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
            }

            SoftCard {
                ownerMenu

                if !isSeed {
                    Divider()

                    DatePicker(
                        "Data e hora",
                        selection: $dueDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)

                    Divider()

                    HStack(spacing: 12) {
                        Label("Repetição", systemImage: "repeat")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(NinaTheme.muted)

                        Spacer()

                        Picker("Repetição", selection: $recurrence) {
                            ForEach(TaskRecurrence.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(NinaTheme.ink)
                    }

                    if recurrence != .none {
                        Label(recurrence.explicitTitle, systemImage: "repeat.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(NinaTheme.mint)
                    }
                } else {
                    Divider()

                    Label(
                        "Sem data por enquanto. Transforme em tarefa quando quiser reservar um horário.",
                        systemImage: "sparkles"
                    )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NinaTheme.mint)
                }
            }

            SoftCard {
                categoryMenu
            }

            SoftCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Prioridade", systemImage: priority.symbolName)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(NinaTheme.muted)

                    Picker("Prioridade", selection: $priority) {
                        ForEach(TaskPriority.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    @ViewBuilder
    private var permissionCard: some View {
        if isSeed {
            EmptyView()
        } else {
            switch store.notificationAuthorizationStatus {
            case .notDetermined:
            SoftCard(padding: 14) {
                Label(
                    "Ative notificações para receber os avisos no horário escolhido.",
                    systemImage: "bell.badge.fill"
                )
                .font(.subheadline.weight(.bold))
                .foregroundStyle(NinaTheme.muted)

                Button("Ativar notificações") {
                    Task {
                        _ = await store.requestNotificationAuthorization()
                    }
                }
                .font(.subheadline.weight(.black))
                .foregroundStyle(NinaTheme.mint)
            }
            case .denied:
            SoftCard(padding: 14) {
                Label("Notificações estão bloqueadas nos Ajustes do iPhone.", systemImage: "bell.slash.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(NinaTheme.coral)

                Button("Abrir Ajustes") {
                    guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                    openURL(url)
                }
                .font(.subheadline.weight(.black))
                .foregroundStyle(NinaTheme.sky)
            }
            case .authorized, .provisional, .ephemeral, .unavailable:
                EmptyView()
            }
        }
    }

    private var ownerMenu: some View {
        Menu {
            ForEach(ownerOptions, id: \.self) { option in
                Button {
                    owner = option
                } label: {
                    Label(option, systemImage: owner == option ? "checkmark" : "person.fill")
                }
            }
        } label: {
            TaskEditorMenuRow(
                title: "Responsável",
                value: owner,
                systemName: "person.fill",
                tone: .sky
            )
        }
        .buttonStyle(.plain)
    }

    private var categoryMenu: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Categoria")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(NinaTheme.muted)

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isCategoryDropdownExpanded.toggle()
                }
            } label: {
                TaskEditorMenuRow(
                    title: "Tipo da tarefa",
                    value: category.title,
                    systemName: category.symbolName,
                    tone: category.tone
                )
            }
            .buttonStyle(.plain)

            if isCategoryDropdownExpanded {
                Divider()

                VStack(spacing: 0) {
                    ForEach(categoryOptions) { item in
                        Button {
                            category = item
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                isCategoryDropdownExpanded = false
                            }
                        } label: {
                            TaskCategoryChoiceRow(
                                category: item,
                                isSelected: category.id == item.id
                            )
                        }
                        .buttonStyle(.plain)

                        if item.id != categoryOptions.last?.id {
                            Divider()
                                .padding(.leading, 30)
                        }
                    }

                    Divider()

                    Button {
                        newCategoryTitle = ""
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            isCategoryDropdownExpanded = false
                            isCreatingCategory = true
                        }
                    } label: {
                        TaskCategoryChoiceRow(
                            category: TaskCategory.custom(id: "new-category", title: "Nova categoria", tone: .mint),
                            isSelected: false,
                            overrideSymbolName: "plus.circle.fill"
                        )
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isCreatingCategory {
                Divider()

                HStack(spacing: 10) {
                    TextField("Nome da nova categoria", text: $newCategoryTitle)
                        .textFieldStyle(.plain)
                        .font(.body.weight(.semibold))

                    Button {
                        createCategory()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(NinaTheme.mint)
                    }
                    .buttonStyle(.plain)
                    .disabled(newCategoryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(newCategoryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            isCreatingCategory = false
                        }
                        newCategoryTitle = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(NinaTheme.muted)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
        kind = isPlantingSeed ? .task : task.kind
        dueDate = isPlantingSeed
            ? Self.defaultDueDate()
            : (task.dueAt ?? Self.date(fromDueLabel: task.dueLabel))
        category = task.category
        priority = task.priority
        recurrence = task.recurrence
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
        let categoryForSave = persistedCategoryIfNeeded(category)
        Haptics.success()
        switch mode {
        case .add(let sectionID):
            store.addTask(
                title: title,
                subtitle: subtitle,
                owner: owner,
                dueLabel: dueLabel,
                dueAt: dueAt,
                category: categoryForSave,
                priority: priority,
                recurrence: recurrenceForSave,
                kind: kind,
                sectionID: sectionID
            )
        case .edit(let id):
            store.updateTask(
                id: id,
                title: title,
                subtitle: subtitle,
                owner: owner,
                dueLabel: dueLabel,
                dueAt: dueAt,
                category: categoryForSave,
                priority: priority,
                recurrence: recurrenceForSave,
                kind: kind,
                expectedVersion: loadedTaskVersion
            )
        case .plant(let id):
            store.updateTask(
                id: id,
                title: title,
                subtitle: subtitle,
                owner: owner,
                dueLabel: dueLabel,
                dueAt: dueAt,
                category: categoryForSave,
                priority: priority,
                recurrence: recurrenceForSave,
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
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                isCreatingCategory = false
                isCategoryDropdownExpanded = false
            }
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
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isCreatingCategory = false
            isCategoryDropdownExpanded = false
        }
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

private struct TaskEditorMenuRow: View {
    var title: String
    var value: String
    var systemName: String
    var tone: MemberTone

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemName)
                .foregroundStyle(NinaTheme.muted)

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Text(value)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(NinaTheme.ink)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.black))
                    .foregroundStyle(tone.color)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct TaskCategoryChoiceRow: View {
    var category: TaskCategory
    var isSelected: Bool
    var overrideSymbolName: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: overrideSymbolName ?? category.symbolName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(category.tone.color)
                .frame(width: 20)

            Text(category.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NinaTheme.ink)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.black))
                    .foregroundStyle(NinaTheme.mint)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
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

    private var ownerOptions: [String] {
        var options = ["Casa"]
        for member in store.familyGroup.members where member.role != .assistant {
            if !options.contains(member.name) {
                options.append(member.name)
            }
        }

        if !owner.isEmpty, !options.contains(owner) {
            options.append(owner)
        }

        return options
    }

    private var ownerMenu: some View {
        Menu {
            ForEach(ownerOptions, id: \.self) { option in
                Button {
                    owner = option
                } label: {
                    Label(option, systemImage: owner == option ? "checkmark" : "person.fill")
                }
            }
        } label: {
            HStack(spacing: 12) {
                Label("Responsável", systemImage: "person.fill")
                    .foregroundStyle(NinaTheme.muted)

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Text(owner)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(NinaTheme.ink)
                        .lineLimit(1)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.black))
                        .foregroundStyle(NinaTheme.sky)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(
                    title: isEditing ? "Editar compra" : "Novo item",
                    subtitle: "Lista rápida para mercado, farmácia e coisas da casa."
                )

                SoftCard {
                    TextField("Item", text: $title)
                        .font(.headline)
                        .textFieldStyle(.plain)
                        .focused($isTitleFocused)
                        .submitLabel(.next)

                    Divider()

                    TextField("Quantidade", text: $amount)
                        .textFieldStyle(.plain)

                    Divider()

                    ownerMenu
                }

                PrimaryCapsuleButton(title: isEditing ? "Salvar item" : "Adicionar item", systemName: "cart.fill") {
                    save(keepingSheetOpen: false)
                }
                .disabled(trimmedTitle.isEmpty)
                .opacity(trimmedTitle.isEmpty ? 0.5 : 1)

                if !isEditing {
                    Button {
                        save(keepingSheetOpen: true)
                    } label: {
                        Label("Adicionar e continuar", systemImage: "plus.circle.fill")
                            .font(.headline.weight(.black))
                            .foregroundStyle(NinaTheme.mint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(NinaTheme.mint.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedTitle.isEmpty)
                    .opacity(trimmedTitle.isEmpty ? 0.5 : 1)

                    if addedCount > 0 {
                        Text(
                            addedCount == 1
                                ? "1 item adicionado nesta sessão."
                                : "\(addedCount) itens adicionados nesta sessão."
                        )
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NinaTheme.muted)
                    }
                }

                if isEditing {
                    Button(role: .destructive) {
                        Haptics.warning()
                        isShowingDeleteConfirmation = true
                    } label: {
                        Label("Apagar item", systemImage: "trash.fill")
                            .font(.headline.weight(.black))
                            .foregroundStyle(NinaTheme.coral)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(NinaTheme.coral.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
        }
        .alert("Apagar este item?", isPresented: $isShowingDeleteConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Apagar", role: .destructive) {
                deleteItem()
            }
        } message: {
            Text("O item sai da lista de compras da casa.")
        }
        .scrollDismissesKeyboard(.interactively)
        .ninaSheetBackground()
        .navigationTitle(isEditing ? "Editar" : "Adicionar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Fechar") {
                    Haptics.selection()
                    dismiss()
                }
            }
        }
        .onAppear(perform: loadIfNeeded)
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
    }

    private func save(keepingSheetOpen: Bool) {
        guard !trimmedTitle.isEmpty else {
            Haptics.error()
            return
        }

        Haptics.success()
        switch mode {
        case .add:
            store.addShoppingItem(title: title, amount: amount, owner: owner)
        case .edit(let id):
            store.updateShoppingItem(id: id, title: title, amount: amount, owner: owner)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionTitle(
                title: "Convidar família",
                subtitle: "Quem abrir o link envia um pedido para uma pessoa responsável aprovar."
            )

            SoftCard {
                HStack(spacing: 14) {
                    IconBubble(systemName: "link", tone: .mint)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.familyGroup.name)
                            .font(.headline.weight(.black))
                            .foregroundStyle(NinaTheme.ink)

                        Text(inviteURL.absoluteString)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(NinaTheme.muted)
                            .textSelection(.enabled)
                    }
                }

                HStack {
                    Label(store.familyLimitLabel, systemImage: "person.2.fill")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(NinaTheme.muted)

                    Spacer()

                    Text(store.canInviteMorePeople ? "\(store.remainingFamilySlots) vagas" : "limite cheio")
                        .font(.caption.weight(.black))
                        .foregroundStyle(store.canInviteMorePeople ? NinaTheme.mint : NinaTheme.coral)
                }

                if let invite = store.inviteStatus {
                    Divider()

                    HStack {
                        Label(invite.status.title, systemImage: "clock.badge.checkmark.fill")
                            .font(.caption.weight(.black))
                            .foregroundStyle(invite.status.tone.color)

                        Spacer()

                        Text("\(invite.usesRemaining) de \(invite.maxUses) usos disponíveis")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(NinaTheme.muted)
                    }

                    Text("Expira em \(invite.expiresAt.formatted(date: .long, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(NinaTheme.muted)
                }
            }

            if store.canManageFamily, store.canInviteMorePeople, inviteIsActive {
                ShareLink(item: inviteURL) {
                    Label("Compartilhar convite", systemImage: "square.and.arrow.up.fill")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(NinaTheme.sky, in: Capsule())
                }
            } else {
                Label(
                    store.canInviteMorePeople ? "Gere um novo convite para continuar" : "Limite de família atingido",
                    systemImage: "person.crop.circle.badge.exclamationmark"
                )
                    .font(.headline.weight(.black))
                    .foregroundStyle(NinaTheme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(NinaTheme.line.opacity(0.45), in: Capsule())
            }

            Spacer()
        }
        .padding(18)
        .ninaSheetBackground()
        .navigationTitle("Convite")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Fechar") {
                    Haptics.selection()
                    dismiss()
                }
            }
        }
    }
}

struct MemberDetailSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var memberID: UUID

    var body: some View {
        VStack {
            if let member = store.familyGroup.members.first(where: { $0.id == memberID }) {
                MemberDetailContent(member: member)
            } else {
                ContentUnavailableView("Participante não encontrado", systemImage: "person.crop.circle")
            }

            Spacer()
        }
        .padding(18)
        .ninaSheetBackground()
        .navigationTitle("Participante")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Fechar") {
                    Haptics.selection()
                    dismiss()
                }
            }
        }
    }
}

struct SuggestionDetailSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var suggestion: NinaSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionTitle(title: suggestion.title, subtitle: "Sugestão criada pela Nina local.")

            SoftCard {
                HStack(spacing: 12) {
                    IconBubble(systemName: suggestion.symbolName, tone: suggestion.category.tone)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(suggestion.detail)
                            .font(.body.weight(.bold))
                            .foregroundStyle(NinaTheme.ink)

                        Text("\(suggestion.payloadOwner) · \(suggestion.payloadDueLabel)")
                            .font(.subheadline)
                            .foregroundStyle(NinaTheme.muted)
                    }
                }

                Divider()

                Text(suggestion.payloadDetail)
                    .font(.subheadline)
                    .foregroundStyle(NinaTheme.muted)
            }

            PrimaryCapsuleButton(title: suggestion.actionTitle, systemName: "plus.circle.fill") {
                Haptics.success()
                store.applySuggestion(suggestion)
                dismiss()
            }

            Spacer()
        }
        .padding(18)
        .ninaSheetBackground()
        .navigationTitle("Sugestão")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Fechar") {
                    Haptics.selection()
                    dismiss()
                }
            }
        }
    }
}

#Preview("Task sheet") {
    NavigationStack {
        TaskEditorSheet(mode: .add(sectionID: AppStore.houseTasksSectionID))
            .environment(AppStore())
    }
}
