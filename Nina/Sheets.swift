import StoreKit
import SwiftUI
import UIKit

enum TaskEditorMode: Hashable {
    case add(sectionID: String)
    case edit(UUID)
    case plant(UUID)
}

struct SheetHeader: View {
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
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
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
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
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
                .ninaText(.body, NinaTheme.ink)
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
                .ninaText(.body, NinaTheme.ground, weight: .semibold)
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

private struct SettingsSection<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Eyebrow(text: title)
            }
            VStack(spacing: 0) {
                content
            }
            if let footer {
                Text(footer)
                    .ninaText(.meta, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct NounList: View {
    var eyebrow: String
    var items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: eyebrow)
            ForEach(items, id: \.self) { item in
                Text(item)
                    .ninaText(.label, NinaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsValueText: View {
    var value: String

    var body: some View {
        Text(value)
            .ninaText(.meta, NinaTheme.muted)
            .multilineTextAlignment(.trailing)
    }
}

private struct SettingsLinkRow: View {
    enum Destination {
        case push
        case external
        case action
    }

    var title: String
    var subtitle: String? = nil
    var systemName: String
    var value: String? = nil
    var destination: Destination = .push

    // A chevron promises a pushed screen; rows that leave the app or open a
    // dialog must not wear it.
    var body: some View {
        NinaRow(title: title, subtitle: subtitle) {
            CategoryGlyph(systemName: systemName, size: 18, tint: NinaTheme.ink)
        } trailing: {
            HStack(spacing: 8) {
                if let value {
                    SettingsValueText(value: value)
                }
                switch destination {
                case .push:
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NinaTheme.faint)
                case .external:
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NinaTheme.faint)
                case .action:
                    EmptyView()
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
        .accessibilityValue(value ?? "")
    }
}

private struct SettingsValueRow: View {
    var title: String
    var value: String
    var systemName: String

    var body: some View {
        NinaRow(title: title) {
            CategoryGlyph(systemName: systemName, size: 18, tint: NinaTheme.ink)
        } trailing: {
            SettingsValueText(value: value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

private struct SettingsToggleRow: View {
    var title: String
    var systemName: String
    @Binding var isOn: Bool

    var body: some View {
        NinaRow(title: title) {
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

    @State private var isRenamingHouse = false
    @State private var houseNameDraft = ""

    @AppStorage(LocalHomeNotificationScheduler.notificationsEnabledKey)
    private var notificationsEnabled = true

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
                    accountSection
                    ninaSection
                    houseSection
                    helpSection
                    #if DEBUG
                    developerSection
                    #endif
                    exits
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 34)
            }
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var premiumRow: some View {
        Button {
            Haptics.lightImpact()
            router.presentedSheet = .premium
        } label: {
            SettingsLinkRow(
                title: "Nina Premium",
                systemName: "star",
                value: store.householdPremium.isActive ? "Ativo" : monthlyPriceLabel
            )
        }
        .buttonStyle(.plain)
    }

    private var monthlyPriceLabel: String? {
        premiumStore.products
            .first { $0.subscription?.subscriptionPeriod.unit == .month }
            .map { "\($0.displayPrice)/mês" }
    }

    private var accountSection: some View {
        SettingsSection {
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
                        title: user.linkedProviders.contains(.email) ? "Email de acesso" : "Adicionar email",
                        systemName: "envelope"
                    )
                }
                .buttonStyle(.plain)

                NinaDivider()
            }

            premiumRow
        }
    }

    private var ninaSection: some View {
        SettingsSection(title: "Nina") {
            NavigationLink {
                NotificationPreferencesView()
            } label: {
                SettingsLinkRow(
                    title: "Avisos",
                    systemName: "bell",
                    value: notificationStatusValue
                )
            }
            .buttonStyle(.plain)

            NinaDivider()

            weeklyDigestRow

            NinaDivider()

            NavigationLink {
                PrivacyAndDataView()
            } label: {
                SettingsLinkRow(title: "Privacidade e dados", systemName: "lock")
            }
            .buttonStyle(.plain)

            NinaDivider()

            Button {
                Haptics.selection()
                openURL(NinaLegalLinks.privacyPolicy)
            } label: {
                SettingsLinkRow(
                    title: "Política de privacidade",
                    systemName: "doc.text",
                    destination: .external
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var weeklyDigestRow: some View {
        if !store.householdPremium.isActive {
            // A live switch for a digest the server will not send would read as "on".
            Button {
                Haptics.lightImpact()
                router.presentedSheet = .premium
            } label: {
                SettingsLinkRow(
                    title: "Resumo semanal",
                    systemName: "calendar",
                    value: "Premium"
                )
            }
            .buttonStyle(.plain)
        } else if store.canManageFamily {
            SettingsToggleRow(
                title: "Resumo semanal",
                systemName: "calendar",
                isOn: weeklyDigestBinding
            )
        } else {
            SettingsValueRow(
                title: "Resumo semanal",
                value: store.isWeeklyDigestEnabled ? "Ligado" : "Desligado",
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

    private var remainingSlotsLabel: String {
        store.remainingFamilySlots == 1 ? "1 vaga" : "\(store.remainingFamilySlots) vagas"
    }

    private var inviteValue: String {
        guard store.canInviteMorePeople else { return "Casa cheia" }
        guard store.inviteStatus?.isActive ?? true else { return "Link vencido" }
        return remainingSlotsLabel
    }

    private var houseSection: some View {
        SettingsSection(title: "Casa") {
            if store.canManageFamily {
                Button {
                    Haptics.lightImpact()
                    houseNameDraft = store.familyGroup.name
                    isRenamingHouse = true
                } label: {
                    SettingsLinkRow(
                        title: "Nome da casa",
                        systemName: "house",
                        value: store.familyGroup.name
                    )
                }
                .buttonStyle(.plain)
                .alert("Nome da casa", isPresented: $isRenamingHouse) {
                    TextField("Nome da casa", text: $houseNameDraft)
                    Button("Salvar") {
                        Task { await store.updateFamilyGroup(name: houseNameDraft) }
                    }
                    Button("Cancelar", role: .cancel) {}
                } message: {
                    Text("Todo mundo da casa vê o novo nome.")
                }

                NinaDivider()

                Button {
                    Haptics.lightImpact()
                    router.presentedSheet = .inviteFamily
                } label: {
                    SettingsLinkRow(
                        title: "Convidar alguém",
                        systemName: "person.badge.plus",
                        value: inviteValue
                    )
                }
                .buttonStyle(.plain)
                .disabled(!store.canInviteMorePeople)
                .opacity(store.canInviteMorePeople ? 1 : 0.4)
            } else {
                SettingsValueRow(
                    title: "Nome da casa",
                    value: store.familyGroup.name,
                    systemName: "house"
                )

                NinaDivider()

                SettingsValueRow(
                    title: "Seu acesso",
                    value: store.currentPermissionRole.title,
                    systemName: store.currentPermissionRole.symbolName
                )
            }
        }
    }

    private var notificationStatusValue: String? {
        switch store.notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationsEnabled ? "Ligados" : "Desligados"
        case .notDetermined:
            "Desligados"
        case .denied:
            "Bloqueados"
        case .unavailable:
            nil
        }
    }

    private var helpSection: some View {
        SettingsSection(title: "Ajuda") {
            Button {
                Haptics.lightImpact()
                onboardingStore.replayTutorial()
                dismiss()
            } label: {
                SettingsLinkRow(
                    title: "Rever o tutorial",
                    systemName: "play.circle",
                    destination: .action
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
                    systemName: "envelope.open",
                    destination: .external
                )
            }
            .buttonStyle(.plain)

            NinaDivider()

            Button {
                Haptics.selection()
                openURL(NinaLegalLinks.termsOfUse)
            } label: {
                SettingsLinkRow(
                    title: "Termos de uso",
                    systemName: "text.book.closed",
                    destination: .external
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var exits: some View {
        VStack(spacing: 4) {
            if let message = authSession.errorMessage {
                Text(message)
                    .ninaText(.caption, NinaTheme.ink, weight: .medium)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
            }

            NinaButton(title: "Sair da conta", kind: .quiet, isEnabled: !authSession.isSigningIn) {
                Haptics.warning()
                Task {
                    guard await authSession.signOut() else { return }
                    onboardingStore.cancelReplay()
                    dismiss()
                }
            }

            NavigationLink {
                AccountDeletionView()
            } label: {
                Text("Apagar conta")
                    .ninaText(.body, NinaTheme.ink, weight: .semibold)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("Nina \(versionLabel)")
                .ninaText(.meta, NinaTheme.muted)
                .padding(.top, 10)
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

    private var hasLinkedEmail: Bool {
        authSession.currentUser?.linkedProviders.contains(.email) == true
    }

    private var linkedEmail: String? {
        hasLinkedEmail ? authSession.currentUser?.email : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            BackHeader { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(hasLinkedEmail ? "Email de acesso" : "Adicionar email").ninaText(.screen)

                    if let linkedEmail {
                        NinaRow(title: "Email atual", subtitle: linkedEmail) {
                            CategoryGlyph(systemName: "envelope", size: 18, tint: NinaTheme.ink)
                        } trailing: {
                            EmptyView()
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Email atual")
                        .accessibilityValue(linkedEmail)
                    }

                    VStack(alignment: .leading, spacing: 8) {
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
                        .opacity(isWaitingForCode ? 0.4 : 1)

                        if !hasLinkedEmail {
                            Text("Com um email, você entra por código, sem a Apple.")
                                .ninaText(.meta, NinaTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

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
                        Text("Email confirmado.")
                            .ninaText(.caption, NinaTheme.moss, weight: .semibold)
                    }

                    NinaButton(
                        title: isWaitingForCode ? "Confirmar" : "Enviar código",
                        fillsWidth: true,
                        isEnabled: !(authSession.isRequestingCode || authSession.isSigningIn)
                    ) {
                        isWaitingForCode ? verifyChange() : requestChange()
                    }

                    if isWaitingForCode {
                        NinaButton(title: "Trocar email", kind: .quiet) {
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
            // Prefilling the address already in use under "Novo email" invites a no-op change request.
            email = authSession.pendingEmailChange ?? ""
            authSession.errorMessage = nil
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

    private var acceptedLabel: String? {
        guard let acceptedAt = store.aiMemoryConsent?.acceptedAt else { return nil }
        return "Aceito em \(acceptedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private var consentBinding: Binding<Bool> {
        Binding(
            get: { store.hasAIMemoryConsent },
            set: { isOn in
                Haptics.selection()
                if isOn {
                    Task {
                        if await store.grantAIMemoryConsent() { Haptics.success() }
                    }
                } else {
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

                    VStack(alignment: .leading, spacing: 8) {
                        consentCard

                        Text("Desligar aqui vale só para você. A conversa de outro adulto da casa continua, e o resumo semanal continua saindo se outro adulto ainda tiver aceitado.")
                            .ninaText(.meta, NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let error = store.syncErrorMessage {
                        NoteCard(eyebrow: nil, text: error)
                    }

                    dataRows

                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Onde ficam os seus dados")
                        Text("Em São Paulo. Os seus registros ficam em servidores brasileiros. Para a Nina entender o que você escreve e o que está nas fotos, o conteúdo vai para um modelo fora do Brasil e volta, usado só para responder.")
                            .ninaText(.meta, NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                Text("Deixar a Nina ler o que eu escrevo e fotografo")
                    .ninaText(.body, NinaTheme.ink, weight: .medium)
                    .fixedSize(horizontal: false, vertical: true)
                if let acceptedLabel {
                    Text(acceptedLabel).ninaText(.caption, NinaTheme.muted)
                }
            }

            Spacer(minLength: 12)

            Toggle("Deixar a Nina ler o que eu escrevo e fotografo", isOn: consentBinding)
                .labelsHidden()
                .tint(NinaTheme.ink)
                .disabled(store.isSyncingHome)
                .opacity(store.isSyncingHome ? 0.4 : 1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard()
    }

    private var dataRows: some View {
        SettingsSection(footer: "A conversa some sozinha depois de 30 dias.") {
            NavigationLink {
                PrivacyExportView()
            } label: {
                SettingsLinkRow(title: "Baixar meus dados", systemName: "arrow.down.to.line")
            }
            .buttonStyle(.plain)

            NinaDivider()

            // The thread is per-adult, so erasing it is a decision only you can
            // make about your own conversation — separate from deleting the account.
            Button {
                Haptics.warning()
                isConfirmingHistoryDeletion = true
            } label: {
                SettingsLinkRow(
                    title: "Apagar minha conversa",
                    systemName: "bubble.left.and.exclamationmark.bubble.right",
                    destination: .action
                )
            }
            .buttonStyle(.plain)
        }
        .alert("Apagar sua conversa?", isPresented: $isConfirmingHistoryDeletion) {
            Button("Apagar", role: .destructive) {
                Task { _ = await store.deleteNinaChatHistory() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Tarefas e memórias confirmadas ficam. Não dá para desfazer.")
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
        "Seu perfil e sua foto",
        "A casa e quem mora nela",
        "Tarefas, compras e retratos",
        "Sua conversa com a Nina neste aparelho",
        "Seu consentimento de leitura"
    ]

    var body: some View {
        VStack(spacing: 0) {
            BackHeader { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Baixar meus dados").ninaText(.screen)

                    NounList(eyebrow: "O que vai no arquivo", items: contents)

                    if let exportError {
                        NoteCard(eyebrow: nil, text: exportError)
                    }

                    NinaButton(title: "Gerar arquivo", fillsWidth: true) {
                        generateExport()
                    }

                    if let exportURL {
                        ShareLink(item: exportURL) {
                            NinaButtonFace(title: "Compartilhar", kind: .outline, fillsWidth: true)
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

    private static let remainingItems = [
        "Tarefas que você criou, sem dono",
        "Compras",
        "Memórias compartilhadas"
    ]

    private var disappearingItems: [String] {
        [
            "Sua conversa com a Nina",
            "Suas memórias privadas",
            "Seu perfil e sua foto",
            "Seu acesso a \(store.familyGroup.name)"
        ]
    }

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
                    Text("Apagar conta").ninaText(.screen)

                    NounList(eyebrow: "Some para sempre", items: disappearingItems)
                        .padding(16)
                        .ninaCard()

                    NounList(eyebrow: "Fica na casa", items: Self.remainingItems)
                        .padding(16)
                        .ninaCard(fill: NinaTheme.grout, stroke: .clear)

                    if let errorMessage = authSession.errorMessage {
                        NoteCard(eyebrow: nil, text: errorMessage)
                    }

                    SheetField(label: "Escreva \(Self.confirmationWord) para confirmar") {
                        TextField(Self.confirmationWord, text: $confirmation)
                            .focused($isConfirmationFocused)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                    }
                    .padding(.top, 6)

                    InkButton(
                        title: authSession.isDeletingAccount ? "Apagando" : "Apagar conta",
                        isEnabled: isConfirmed && !authSession.isDeletingAccount
                    ) {
                        Haptics.warning()
                        isConfirmationFocused = false
                        isShowingConfirmation = true
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 34)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { authSession.errorMessage = nil }
        .alert("Apagar sua conta?", isPresented: $isShowingConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Apagar", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("Não dá para desfazer.")
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
                    Text("Avisos").ninaText(.screen)

                    if store.notificationAuthorizationStatus == .denied {
                        deniedCard
                    }

                    SettingsSection(footer: "Prioridade alta ou urgente ganha um segundo aviso uma hora depois.") {
                        SettingsToggleRow(
                            title: "Avisos neste aparelho",
                            systemName: "bell",
                            isOn: notificationToggle
                        )
                    }

                    // Quiet hours silence the alert; they never move it, because the
                    // app must not show one time and deliver another.
                    SettingsSection(footer: "No silêncio, o aviso chega na hora, sem som.") {
                        SettingsToggleRow(
                            title: "Silenciar à noite",
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

    private var deniedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("O iPhone bloqueou os avisos.")
                .ninaText(.section)
                .fixedSize(horizontal: false, vertical: true)

            NinaButton(title: "Abrir Ajustes do iPhone", kind: .outline) {
                Haptics.selection()
                guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                openURL(url)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard(fill: NinaTheme.grout, stroke: .clear)
    }

    private var notificationToggle: Binding<Bool> {
        Binding(
            // A switch that reads ON before iOS allows delivery promises alerts that never come.
            get: {
                switch store.notificationAuthorizationStatus {
                case .denied, .notDetermined:
                    false
                case .authorized, .provisional, .ephemeral, .unavailable:
                    notificationsEnabled
                }
            },
            set: { isEnabled in
                notificationsEnabled = isEnabled
                if isEnabled, store.notificationAuthorizationStatus == .notDetermined {
                    Task {
                        if await store.requestNotificationAuthorization() == false {
                            notificationsEnabled = false
                        }
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
        .opacity(quietHoursEnabled ? 1 : 0.4)
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isManagingSubscription = false
    @State private var selectedPeriod: PremiumPeriod = .yearly
    @State private var activeMarkIsShown = false
    @State private var wasCoveredOnAppear: Bool?

    private let plan = PremiumPlan.mock

    // The house is the unit that has premium; the phone's own receipt only bridges the
    // seconds until the server has confirmed it.
    private var isCovered: Bool {
        store.householdPremium.isActive || premiumStore.entitlement.isActive
    }

    // The house is the sharing unit, but the receipt belongs to one adult: the
    // other adult must never be told both "ativo" and "assine".
    private var isCoveredByAnotherAdult: Bool {
        store.householdPremium.isActive && !premiumStore.entitlement.isActive
    }

    private var coverageEndLabel: String? {
        guard let expiresAt = store.householdPremium.expiresAt else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "d 'de' MMMM"
        return formatter.string(from: expiresAt)
    }

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
            SheetHeader(eyebrow: "") {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isCovered {
                        managementHeading
                        subscriptionCard
                    } else {
                        heading
                        periodControl
                        comparison
                        ceilingNote
                    }
                    statusArea
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 24)
            }

            if isCovered {
                manageArea
            } else {
                purchaseArea
            }
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
        .task {
            await premiumStore.configure(for: authSession.currentUser)
        }
        .onChange(of: isCovered, initial: true) { _, covered in
            if wasCoveredOnAppear == nil { wasCoveredOnAppear = covered }
            guard covered else {
                activeMarkIsShown = false
                return
            }
            if reduceMotion {
                activeMarkIsShown = true
            } else {
                withAnimation(.spring(duration: 0.55, bounce: 0.32).delay(0.05)) {
                    activeMarkIsShown = true
                }
            }
        }
    }

    // A house that arrives already covered is managing, not celebrating.
    private var activatedHere: Bool {
        wasCoveredOnAppear == false && isCovered
    }

    // Moss marks what a person confirmed, and a purchase is exactly that.
    private var managementHeading: some View {
        VStack(alignment: .leading, spacing: 6) {
            if activatedHere {
                ZStack {
                    Circle()
                        .fill(NinaTheme.moss)
                        .frame(width: 56, height: 56)
                    Image(systemName: "checkmark")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(NinaTheme.ground)
                }
                .scaleEffect(activeMarkIsShown ? 1 : 0.6)
                .opacity(activeMarkIsShown ? 1 : 0)
                .accessibilityHidden(true)
                .padding(.bottom, 10)
            }

            Text("Premium ativo na casa").ninaText(.display)
            Text(PremiumTeaserCopy.activeSubtitle)
                .ninaText(.label, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var currentProduct: Product? {
        guard let productID = premiumStore.entitlement.productID else { return nil }
        return premiumStore.products.first { $0.id == productID }
    }

    private var currentPlanName: String {
        if let product = currentProduct { return product.displayName }
        guard let productID = premiumStore.entitlement.productID else { return "Nina Premium" }
        if productID.hasSuffix(".yearly") { return "Nina Premium anual" }
        if productID.hasSuffix(".monthly") { return "Nina Premium mensal" }
        return "Nina Premium"
    }

    private var currentPriceLabel: String? {
        guard let product = currentProduct else { return nil }
        guard let period = product.subscription?.subscriptionPeriod else { return product.displayPrice }
        return "\(product.displayPrice) por \(period.localizedTitle)"
    }

    // The title already says the house is covered; a status row appears only when it says something else.
    private var subscriptionCard: some View {
        VStack(spacing: 0) {
            if isCoveredByAnotherAdult {
                detailRow(title: "Plano", value: "Nina Premium")
                NinaDivider(inset: 0)
                detailRow(title: "Quem assina", value: "Outro adulto")
                if let coverageEndLabel {
                    NinaDivider(inset: 0)
                    detailRow(title: "Vale até", value: coverageEndLabel)
                }
                if store.householdPremium.status != .active {
                    NinaDivider(inset: 0)
                    detailRow(title: "Situação", value: store.householdPremium.status.title)
                }
            } else {
                detailRow(title: "Plano", value: currentPlanName)
                if let price = currentPriceLabel {
                    NinaDivider(inset: 0)
                    detailRow(title: "Preço", value: price)
                }
                NinaDivider(inset: 0)
                detailRow(title: "Renovação", value: premiumStore.entitlement.renewalSummary)
                if premiumStore.entitlement.status != .active {
                    NinaDivider(inset: 0)
                    detailRow(title: "Situação", value: premiumStore.entitlement.statusTitle)
                }
            }
        }
        .ninaCard()
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .ninaText(.label, NinaTheme.muted)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .ninaText(.label, NinaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var manageArea: some View {
        if isCoveredByAnotherAdult {
            Text("Só quem assina muda o plano.")
                .ninaText(.caption, NinaTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)
        } else {
            NinaButton(title: "Gerenciar na App Store", fillsWidth: true) {
                Haptics.lightImpact()
                isManagingSubscription = true
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
    }

    private var heading: some View {
        Text(plan.name).ninaText(.display)
    }

    private var periodControl: some View {
        HStack(spacing: 4) {
            periodOption(.monthly, product: monthlyProduct, badge: nil)
            periodOption(.yearly, product: yearlyProduct, badge: yearlySavingsLabel)
        }
        .padding(4)
        .background(
            NinaTheme.grout,
            in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
        )
    }

    private func periodOption(_ period: PremiumPeriod, product: Product?, badge: String?) -> some View {
        let isSelected = selectedPeriod == period
        return Button {
            Haptics.selection()
            selectedPeriod = period
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    Text(period.title)
                        .ninaText(.label, isSelected ? NinaTheme.ink : NinaTheme.muted, weight: isSelected ? .semibold : .medium)

                    if let badge {
                        Text(badge)
                            .ninaText(.micro, NinaTheme.ground, weight: .bold)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(NinaTheme.ink, in: Capsule())
                    }
                }

                if let price = billedPrice(for: product) {
                    Text(price)
                        .ninaText(.meta, isSelected ? NinaTheme.ink : NinaTheme.muted, weight: isSelected ? .semibold : .regular)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                isSelected ? NinaTheme.ground : Color.clear,
                in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field - 4, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NinaTheme.Radius.field - 4, style: .continuous)
                    .strokeBorder(isSelected ? NinaTheme.ink : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // The billed amount is the price each option shows; a monthly equivalent never stands in for it.
    private func billedPrice(for product: Product?) -> String? {
        guard let product, let period = product.subscription?.subscriptionPeriod else { return nil }
        return "\(product.displayPrice)/\(period.localizedTitle)"
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

            if NinaAttachmentGate.current.isEnabled {
                comparisonRow("Fotos de documentos", free: nil, premium: nil)
                NinaDivider(inset: 0)
            }
            comparisonRow("Conversa com a Nina", free: "10/dia", premium: "30/hora")
            NinaDivider(inset: 0)
            comparisonRow("Resumo semanal", free: nil, premium: nil)
        }
        .ninaCard()
    }

    private func comparisonRow(_ title: String, free: String?, premium: String?) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .ninaText(.label, NinaTheme.ink)
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
                    .ninaText(.meta, isPremium ? NinaTheme.ink : NinaTheme.muted, weight: isPremium ? .semibold : .regular)
            } else {
                Image(systemName: isPremium ? "checkmark" : "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isPremium ? NinaTheme.ink : NinaTheme.faint)
            }
        }
        .frame(width: 76)
        .accessibilityLabel(text ?? (isPremium ? "incluído" : "não incluído"))
    }

    private var ceilingNote: some View {
        Text("Teto da casa: 100 conversas por dia.")
            .ninaText(.caption, NinaTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var statusArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isCovered {
                if premiumStore.isLoadingProducts {
                    Text("Carregando os planos.").ninaText(.caption, NinaTheme.muted)
                } else if premiumStore.products.isEmpty {
                    NoteCard(
                        eyebrow: nil,
                        text: premiumStore.productLoadMessage
                            ?? "Os planos não carregaram. Tente mais tarde."
                    )
                }
            }

            // A covered house already reads its confirmation in the title and the moss mark.
            if let statusMessage = premiumStore.statusMessage, !statusMessage.isEmpty,
               !(isCovered && premiumStore.statusIsConfirmation) {
                Text(statusMessage)
                    .ninaText(
                        .caption,
                        premiumStore.statusIsConfirmation ? NinaTheme.moss : NinaTheme.ink,
                        weight: .semibold
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage = premiumStore.errorMessage, !errorMessage.isEmpty {
                NoteCard(eyebrow: nil, text: errorMessage)
            }
        }
    }

    static let renewalTerms = "Renova sozinho. Cancele quando quiser na App Store."

    // App Review 3.1.2: the billed price, its period, auto-renewal and how to cancel sit beside the button.
    private var subscriptionTerms: String {
        guard let product = selectedProduct,
              let period = product.subscription?.subscriptionPeriod else {
            return Self.renewalTerms
        }
        return "\(product.displayPrice) por \(period.localizedTitle). \(Self.renewalTerms)"
    }

    private var purchaseArea: some View {
        VStack(spacing: 10) {
            if let product = selectedProduct {
                NinaButton(
                    title: purchaseButtonTitle,
                    fillsWidth: true,
                    isEnabled: !isCurrentPlan,
                    isPending: isBusy
                ) {
                    Task {
                        Haptics.lightImpact()
                        await premiumStore.purchase(product)
                        await reloadHouseIfCovered()
                    }
                }
            }

            Text(subscriptionTerms)
                .ninaText(.meta, NinaTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    legalLinks(separated: true)
                }
                VStack(spacing: 0) {
                    legalLinks(separated: false)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func legalLinks(separated: Bool) -> some View {
        linkButton(
            premiumStore.isRestoring ? "Restaurando" : "Restaurar",
            accessibilityLabel: "Restaurar compras",
            isEnabled: !premiumStore.isRestoring
        ) {
            Task {
                Haptics.lightImpact()
                await premiumStore.restorePurchases()
                await reloadHouseIfCovered()
            }
        }
        if separated {
            linkSeparator
        }
        linkButton("Termos", accessibilityLabel: "Termos de uso") {
            Haptics.selection()
            openURL(NinaLegalLinks.termsOfUse)
        }
        if separated {
            linkSeparator
        }
        linkButton("Privacidade", accessibilityLabel: "Política de privacidade") {
            Haptics.selection()
            openURL(NinaLegalLinks.privacyPolicy)
        }
    }

    private var linkSeparator: some View {
        Text("·")
            .ninaText(.caption, NinaTheme.muted)
            .accessibilityHidden(true)
    }

    private func linkButton(
        _ title: String,
        accessibilityLabel: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .ninaText(.caption, NinaTheme.muted, weight: .semibold)
                .padding(.horizontal, 4)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(accessibilityLabel)
    }

    private var purchaseButtonTitle: String {
        if premiumStore.isPurchasing { return "Assinando" }
        if premiumStore.isSyncingBackend { return "Registrando na casa" }
        return isCurrentPlan ? "Plano atual" : "Assinar"
    }

    // Casa reads premium from the house, not from this phone: without a reload the
    // purchase looks like nothing happened until the next foreground.
    private func reloadHouseIfCovered() async {
        guard premiumStore.entitlement.isActive else { return }
        await store.refreshHomeFromRemote(for: authSession.currentUser)
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
    var initialKind: TaskKind = .task
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
                    if !isPlantingSeed {
                        kindSegment
                    }

                    if case .edit = mode {
                        NinaButton(title: "Apagar", kind: .quiet) {
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
        .alert(isSeed ? "Apagar esta semente?" : "Apagar esta tarefa?", isPresented: $isShowingDeleteConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Apagar", role: .destructive) {
                deleteTask()
            }
        } message: {
            Text("Some para toda a casa. Não dá para desfazer.")
        }
    }

    private var titleField: some View {
        TextField("O que fazer?", text: $title, axis: .vertical)
            .lineLimit(1...3)
            .ninaText(.compose, NinaTheme.ink, weight: .semibold)
            .tint(NinaTheme.cobalt)
            .textFieldStyle(.plain)
            .focused($isTitleFocused)
            .submitLabel(.done)
    }

    private var subtitleField: some View {
        TextField("Nota", text: $subtitle, axis: .vertical)
            .lineLimit(1...3)
            .ninaText(.body, NinaTheme.muted)
            .tint(NinaTheme.cobalt)
            .textFieldStyle(.plain)
    }

    // Tarefa or Semente is a choice with two visible sides, so the primitive is met where it is
    // decided and not discovered by tapping a chip that flips.
    private var kindSegment: some View {
        HStack(spacing: 4) {
            kindOption(.task)
            kindOption(.seed)
        }
        .padding(4)
        .background(
            NinaTheme.grout,
            in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
        )
        .padding(.top, 4)
    }

    private func kindOption(_ option: TaskKind) -> some View {
        let isSelected = kind == option
        return Button {
            guard !isSelected else { return }
            Haptics.selection()
            kind = option
            if option == .seed {
                closePanel()
            }
        } label: {
            Text(option.title)
                .ninaText(.label, isSelected ? NinaTheme.ink : NinaTheme.muted, weight: isSelected ? .semibold : .medium)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    isSelected ? NinaTheme.ground : Color.clear,
                    in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field - 4, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: NinaTheme.Radius.field - 4, style: .continuous)
                        .strokeBorder(isSelected ? NinaTheme.ink : Color.clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(option.title)
    }

    @ViewBuilder
    private var reminderChip: some View {
        switch store.notificationAuthorizationStatus {
        case .notDetermined:
            Button {
                Haptics.lightImpact()
                Task {
                    _ = await store.requestNotificationAuthorization()
                }
            } label: {
                EditorChip(systemName: "bell.slash", text: "Ativar avisos")
            }
            .buttonStyle(.plain)
        case .denied:
            Button {
                Haptics.selection()
                guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                openURL(url)
            } label: {
                EditorChip(systemName: "bell.slash", text: "Avisos bloqueados")
            }
            .buttonStyle(.plain)
        case .authorized, .provisional, .ephemeral, .unavailable:
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
                EditorChip(
                    systemName: "bell",
                    text: reminderLead == .atTime ? nil : reminderLead.title,
                    isSet: reminderLead != .atTime
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Aviso")
            .accessibilityValue(reminderLead.title)
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
                Spacer(minLength: 8)

                NinaButton(
                    title: primaryActionTitle,
                    systemName: "arrow.up",
                    isEnabled: !trimmedTitle.isEmpty
                ) {
                    save()
                }
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
                dateChip

                if !isSeed {
                    reminderChip
                }

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
                    EditorChip(
                        systemName: "person",
                        text: isOwnerAssigned ? selectedOwnerLabel : "Sem dono",
                        isSet: isOwnerAssigned
                    )
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.lightImpact()
                    togglePanel(.category)
                } label: {
                    EditorChip(systemName: category.symbolName, text: category.title, isSet: true)
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
                        EditorChip(
                            systemName: "repeat",
                            text: recurrence == .none ? nil : recurrence.shortTitle,
                            isSet: recurrence != .none
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Repetição")
                    .accessibilityValue(recurrence == .none ? "Não repete" : recurrence.title)
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
                    EditorChip(
                        systemName: "flag",
                        text: priority == .normal ? nil : priority.title,
                        isSet: priority != .normal
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Prioridade")
                .accessibilityValue(priority.title)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .chipRowTrailingFade()
    }

    // A seed's date slot stays where the control would have been, readable and not a control.
    @ViewBuilder
    private var dateChip: some View {
        if isSeed {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                Text("Sem data")
                    .ninaText(.caption, NinaTheme.muted, weight: .medium)
            }
            .foregroundStyle(NinaTheme.muted)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(NinaTheme.grout, in: Capsule())
            .frame(minHeight: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sem data. Semente não tem data.")
        } else {
            Button {
                Haptics.lightImpact()
                togglePanel(.date)
            } label: {
                EditorChip(systemName: "calendar", text: Self.dateLabel(for: dueDate), isSet: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var datePanel: some View {
        HStack(spacing: 12) {
            DatePicker(
                "Quando",
                selection: $dueDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .tint(NinaTheme.ink)

            Spacer(minLength: 0)
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
                        .ninaText(.label, NinaTheme.ink)
                        .tint(NinaTheme.cobalt)
                        .textFieldStyle(.plain)
                        .submitLabel(.done)

                    Button {
                        createCategory()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(NinaTheme.ink)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(newCategoryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(newCategoryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                    .accessibilityLabel("Criar categoria")

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
                .ninaText(.label, NinaTheme.ink, weight: .medium)

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NinaTheme.ink)
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
            kind = initialKind
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
        // A semente has no date to load; the editor must not offer "now", which
        // is already past by the time the sheet is saved.
        dueDate = isPlantingSeed || task.kind == .seed
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
            return "Plantar"
        }
        return isEditing ? "Salvar" : "Criar"
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

private struct EditorChip: View {
    var systemName: String
    var text: String?
    var isSet: Bool = false

    var body: some View {
        Group {
            if let text {
                NinaChip(text: text, isSet: isSet, systemName: systemName)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NinaTheme.muted)
                    .frame(width: 44, height: 36)
                    .overlay(Capsule().strokeBorder(NinaTheme.control, lineWidth: 1))
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
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
                label: "Sem dono"
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
                        .ninaText(.compose, NinaTheme.ink, weight: .semibold)
                        .tint(NinaTheme.cobalt)
                        .textFieldStyle(.plain)
                        .focused($isTitleFocused)
                        .submitLabel(.done)

                    TextField("Quantidade", text: $amount)
                        .ninaText(.body, NinaTheme.muted)
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
                                    ? "1 item adicionado."
                                    : "\(addedCount) itens adicionados."
                            )
                            .ninaText(.caption, NinaTheme.muted)
                        }
                    }

                    if isEditing {
                        NinaButton(title: "Apagar", kind: .quiet) {
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
            Text("Some para toda a casa. Não dá para desfazer.")
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
                        EditorChip(
                            systemName: "person",
                            text: ownerMemberID == nil
                                ? "Sem dono"
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
                Spacer(minLength: 8)

                NinaButton(
                    title: isEditing ? "Salvar" : "Adicionar",
                    systemName: "arrow.up",
                    isEnabled: !trimmedTitle.isEmpty
                ) {
                    save(keepingSheetOpen: false)
                }
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

    @State private var isRotatingInvite = false
    @State private var renewFailed = false

    private var inviteURL: URL {
        store.inviteURL
    }

    private var inviteIsActive: Bool {
        store.inviteStatus?.isActive ?? true
    }

    private var canShare: Bool {
        store.canManageFamily && store.canInviteMorePeople && inviteIsActive
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
            SheetHeader(eyebrow: "") {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Convidar alguém").ninaText(.screen)
                        Text("Quem abrir o link pede para entrar. Alguém da casa aprova.")
                            .ninaText(.label, NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if canShare {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(inviteURL.absoluteString)
                                .ninaText(.caption, NinaTheme.cobalt, weight: .semibold)
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            if let inviteValidity {
                                Text(inviteValidity)
                                    .ninaText(.meta, NinaTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .ninaCard(fill: NinaTheme.grout, stroke: .clear)

                        ShareLink(item: inviteURL, message: Text(messageText)) {
                            NinaButtonFace(title: "Enviar convite", kind: .primary, fillsWidth: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        unavailableState
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

    private var inviteValidity: String? {
        guard let invite = store.inviteStatus else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "d 'de' MMM"
        let uses = invite.usesRemaining == 1 ? "1 uso restante" : "\(invite.usesRemaining) usos restantes"
        return "Vale até \(formatter.string(from: invite.expiresAt)) · \(uses)"
    }

    @ViewBuilder
    private var unavailableState: some View {
        if !store.canInviteMorePeople {
            unavailableLine("A casa chegou ao limite de \(AppStore.maxFamilyPeople) pessoas.")
        } else if !store.canManageFamily {
            unavailableLine("Só quem administra a casa convida.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                unavailableLine("Este link não vale mais.")

                NinaButton(title: "Renovar o link", kind: .quiet, isPending: isRotatingInvite) {
                    renewInvite()
                }

                if renewFailed, let message = store.syncErrorMessage {
                    Text(message)
                        .ninaText(.caption, NinaTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func unavailableLine(_ text: String) -> some View {
        Text(text)
            .ninaText(.caption, NinaTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .ninaCard(fill: NinaTheme.grout, stroke: .clear)
    }

    private func renewInvite() {
        isRotatingInvite = true
        renewFailed = false
        Task {
            let rotated = await store.rotateFamilyInvite()
            isRotatingInvite = false
            renewFailed = !rotated
            if rotated {
                Haptics.success()
            }
        }
    }
}

struct SuggestionDetailSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var suggestion: NinaSuggestion

    private var ownerLabel: String {
        HouseholdWorkload.isSharedOwner(suggestion.payloadOwner) ? "Sem dono" : suggestion.payloadOwner
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(eyebrow: "Proposta") {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(suggestion.title).ninaText(.screen)

                    Text(suggestion.payloadDetail)
                        .ninaText(.label, NinaTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        CategoryGlyph(systemName: suggestion.symbolName, size: 17, tint: NinaTheme.muted)
                        Text("\(ownerLabel) · \(suggestion.payloadDueLabel)")
                            .ninaText(.caption, NinaTheme.muted)
                    }

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

// Rows live in a ScrollView, not a List, so long-press is the substitute for swipe actions.
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
                    title: task.completionActionTitle,
                    systemName: "checkmark",
                    tint: NinaTheme.ink
                ) {
                    task.isDone ? Haptics.selection() : Haptics.success()
                    store.toggleTask(task)
                    dismiss()
                }

                // A closed task has nothing to push, hand over or plant.
                if task.kind == .task, !task.isDone {
                    NinaDivider(inset: 52)

                    actionRow(title: "Empurrar pra amanhã", systemName: "clock") {
                        Haptics.success()
                        pushToTomorrow()
                        dismiss()
                    }
                }

                if canTakeOver, !task.isDone, let me {
                    NinaDivider(inset: 52)

                    actionRow(title: "Assumir", systemName: "person") {
                        Haptics.success()
                        takeOver(as: me)
                        dismiss()
                    }
                }

                if !task.isDone {
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
                            plantAfterDismissal()
                        }
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
        .presentationDetents([.medium, .large])
    }

    // Two presentations in one tick lose one of them; the editor waits for the
    // sheet to be gone before it is asked for.
    private func plantAfterDismissal() {
        let router = router
        let taskID = task.id
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            router.presentedSheet = .plantSeed(taskID)
        }
    }

    private var taskLine: some View {
        HStack(spacing: 12) {
            NinaCheckbox(isOn: task.isDone, isOverdue: isOverdue)

            Text(task.title)
                .ninaText(.body, NinaTheme.ink, weight: .medium)
                .lineLimit(1)

            Spacer(minLength: 8)

            if task.kind == .task {
                Text(task.effectiveDueLabel())
                    .ninaText(.meta, isOverdue ? NinaTheme.terracotta : NinaTheme.muted, weight: isOverdue ? .semibold : .regular)
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

    // A snooze, not a rewrite of dueAt: rewriting the anchor of a repeating task
    // would move every future occurrence, not only this one.
    private func pushToTomorrow() {
        let base = max(task.dueAt ?? .now, .now)
        let target = Calendar.current.date(byAdding: .day, value: 1, to: base) ?? base
        store.snoozeTask(task.id, until: target)
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
                    Text("Outra pessoa mexeu nesta tarefa.")
                        .ninaText(.zero)
                        .fixedSize(horizontal: false, vertical: true)

                    versionCard(
                        eyebrow: "Sua versão",
                        task: conflict.localTask,
                        isMine: true
                    )

                    versionCard(
                        eyebrow: "Outra versão",
                        task: conflict.remoteTask,
                        isMine: false
                    )

                    VStack(spacing: 8) {
                        NinaButton(title: "Manter a minha", fillsWidth: true) {
                            Haptics.success()
                            store.keepLocalTaskConflict()
                        }

                        NinaButton(title: "Manter a outra", kind: .outline, fillsWidth: true) {
                            Haptics.selection()
                            store.acceptRemoteTaskConflict()
                        }
                    }
                    .padding(.top, 4)
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
                .ninaText(.body, NinaTheme.ink, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(task.kind == .seed ? "Plante depois" : task.effectiveDueLabel()) · \(HouseholdWorkload.isSharedOwner(task.owner) ? "Sem dono" : task.owner)")
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
