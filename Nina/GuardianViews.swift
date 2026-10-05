import SwiftUI

enum GuardianSheetMode: Hashable, Identifiable {
    case approval(FamilyJoinRequest)
    case newProfile(name: String, band: MinorBand?)
    case declare(HouseholdMember)

    var id: String {
        switch self {
        case .approval(let request): "approval-\(request.id.uuidString)"
        case .newProfile(let name, let band): "profile-\(name)-\(band?.rawValue ?? "none")"
        case .declare(let member): "declare-\(member.id.uuidString)"
        }
    }
}

// What the guardian sheet must hold before it may be sent: the declaration, the consent, a relationship and a band.
struct GuardianApprovalForm: Equatable {
    var relationship: GuardianRelationship?
    var band: MinorBand?
    var nicknamesText = ""
    var declaresGuardianship = false
    var consentsToProfile = false
    var healthConsent = false
    var maximumBand: MinorBand?
    var requiresBand = true

    var allowedBands: [MinorBand] {
        maximumBand?.allowedChoices() ?? MinorBand.allCases
    }

    var nicknames: [String] {
        MinorSupervisionDefaults.normalizedNicknames(nicknamesText)
    }

    private var hasValidBand: Bool {
        guard let band else { return !requiresBand }
        return allowedBands.contains(band)
    }

    var canSubmit: Bool {
        declaresGuardianship && consentsToProfile && relationship != nil && hasValidBand
    }

    func approval() -> GuardianApproval? {
        guard canSubmit, let relationship, let band else { return nil }
        return GuardianApproval(
            relationship: relationship,
            band: band,
            healthConsent: healthConsent,
            nicknames: nicknames
        )
    }

    func profileDraft(name: String) -> MinorProfileDraft? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmit, !trimmed.isEmpty, let relationship, let band else { return nil }
        return MinorProfileDraft(
            name: trimmed,
            band: band,
            guardianRelationship: relationship,
            healthConsent: healthConsent,
            nicknames: nicknames,
            relationship: band.householdRole.title
        )
    }

    func declaration(keepsNicknames: Bool) -> GuardianDeclaration? {
        guard canSubmit, let relationship else { return nil }
        return GuardianDeclaration(
            relationship: relationship,
            band: band,
            healthConsent: healthConsent,
            nicknames: keepsNicknames ? nil : nicknames
        )
    }

    static func forApproval(_ request: FamilyJoinRequest) -> GuardianApprovalForm {
        let appleBand = request.requesterAge.appleBand
        return GuardianApprovalForm(band: appleBand, maximumBand: appleBand)
    }
}

struct GuardianApprovalSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let mode: GuardianSheetMode
    var onFinished: () -> Void = {}

    @State private var form: GuardianApprovalForm
    @State private var isSending = false

    init(mode: GuardianSheetMode, onFinished: @escaping () -> Void = {}) {
        self.mode = mode
        self.onFinished = onFinished
        switch mode {
        case .approval(let request):
            _form = State(initialValue: .forApproval(request))
        case .newProfile(_, let band):
            _form = State(initialValue: GuardianApprovalForm(band: band))
        case .declare(let member):
            let isLegacy = member.minorAccess?.hasProfileConsent != true
            _form = State(initialValue: GuardianApprovalForm(requiresBand: isLegacy))
        }
    }

    private var name: String {
        switch mode {
        case .approval(let request): request.requesterName
        case .newProfile(let name, _): name
        case .declare(let member): member.name
        }
    }

    private var isProfile: Bool {
        switch mode {
        case .approval: false
        case .newProfile: true
        case .declare(let member): member.userID == nil
        }
    }

    private var isUnknownRequester: Bool {
        if case .approval(let request) = mode { return request.requesterAge == .unknown }
        return false
    }

    private var showsBandChips: Bool {
        switch mode {
        case .approval, .newProfile: true
        case .declare: form.requiresBand
        }
    }

    private var showsNicknames: Bool {
        if case .declare = mode { return form.requiresBand }
        return true
    }

    private var primaryTitle: String {
        switch mode {
        case .approval: "Aprovar"
        case .newProfile: "Cadastrar"
        case .declare: "Confirmar"
        }
    }

    private var cardLines: [String] {
        let opening = isProfile
            ? ["O perfil de \(name) fica guardado no Brasil.", "\(name) não tem conta própria."]
            : [
                "\(name) vai ver só as próprias tarefas e marcar o que fez.",
                "Não conversa com a Nina, não compra nada e não vê o resto da casa."
            ]
        return opening + [
            "As tarefas de \(name) não vão para a inteligência artificial.",
            "Quando um adulto fala de \(name) com a Nina, o nome vai trocado por um código.",
            "Você controla avisos e tempo de uso, e pode apagar a conta quando quiser."
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(eyebrow: "Responsável") { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Você é responsável por \(name)?")
                        .ninaText(.screen)
                        .fixedSize(horizontal: false, vertical: true)

                    if isUnknownRequester {
                        Text("\(name) não informou a idade. Se for adulto, peça para compartilhar a faixa no app.")
                            .ninaText(.label, NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(cardLines, id: \.self) { line in
                            Text(line)
                                .ninaText(.label, NinaTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ninaCard(fill: NinaTheme.grout, stroke: .clear)

                    chipGroup(eyebrow: "Quem você é") {
                        ForEach(GuardianRelationship.allCases) { relationship in
                            chip(relationship.title, isSet: form.relationship == relationship) {
                                form.relationship = relationship
                            }
                        }
                    }

                    if showsBandChips {
                        chipGroup(eyebrow: "Idade de \(name)") {
                            ForEach(MinorBand.allCases) { band in
                                let isAllowed = form.allowedBands.contains(band)
                                chip(band.chipTitle, isSet: form.band == band, isEnabled: isAllowed) {
                                    form.band = band
                                }
                            }
                        }
                    }

                    if showsNicknames {
                        VStack(alignment: .leading, spacing: 6) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Apelidos")
                                    .ninaText(.meta, NinaTheme.muted)
                                    .accessibilityHidden(true)
                                TextField("Pedrinho, Pê", text: $form.nicknamesText)
                                    .ninaText(.body, NinaTheme.ink)
                                    .tint(NinaTheme.cobalt)
                                    .accessibilityLabel("Apelidos")
                                    .textInputAutocapitalization(.words)
                                    .autocorrectionDisabled()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                NinaTheme.grout,
                                in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
                            )

                            Text("Só para a Nina esconder o nome.")
                                .ninaText(.caption, NinaTheme.muted)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        checkbox(
                            "Declaro que sou mãe, pai ou responsável legal de \(name).",
                            isOn: $form.declaresGuardianship
                        )
                        checkbox(
                            "Autorizo a Nina a guardar o nome, a faixa de idade e as tarefas de \(name), e aceito os Termos e a Política de Privacidade como responsável por \(name).",
                            isOn: $form.consentsToProfile
                        )
                    }

                    checkbox(
                        "Autorizo registrar lembretes de saúde de \(name), como remédio e consulta.",
                        isOn: $form.healthConsent
                    )
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ninaCard(fill: NinaTheme.grout, stroke: .clear)

                    if let error = store.syncErrorMessage {
                        NinaErrorNote(text: error)
                    }

                    VStack(spacing: 6) {
                        NinaButton(
                            title: primaryTitle,
                            fillsWidth: true,
                            isEnabled: form.canSubmit,
                            isPending: isSending
                        ) {
                            submit()
                        }

                        NinaButton(title: "Agora não", kind: .quiet) {
                            Haptics.selection()
                            dismiss()
                        }

                        NinaButton(title: "Ler sobre famílias", kind: .quiet) {
                            Haptics.selection()
                            openURL(NinaLegalLinks.families)
                        }
                    }

                    Text("Se você não é responsável, feche e peça a quem é.")
                        .ninaText(.meta, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { Haptics.lightImpact() }
    }

    private func chipGroup<Content: View>(
        eyebrow: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: eyebrow)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { content() }
                VStack(alignment: .leading, spacing: 8) { content() }
            }
        }
    }

    private func chip(
        _ title: String,
        isSet: Bool,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.lightImpact()
            action()
        } label: {
            NinaChip(text: title, isSet: isSet, isDisabled: !isEnabled)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func checkbox(_ text: String, isOn: Binding<Bool>) -> some View {
        Button {
            Haptics.selection()
            isOn.wrappedValue.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                NinaCheckbox(isOn: isOn.wrappedValue, isSquare: true)
                Text(text)
                    .ninaText(.label, NinaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn.wrappedValue ? "Marcado" : "Desmarcado")
    }

    private func submit() {
        guard form.canSubmit, !isSending else { return }
        isSending = true
        Task {
            let succeeded: Bool
            switch mode {
            case .approval(let request):
                if let approval = form.approval() {
                    succeeded = await store.approveJoinRequest(request, asGuardian: approval)
                } else {
                    succeeded = false
                }
            case .newProfile(let name, _):
                if let draft = form.profileDraft(name: name) {
                    succeeded = await store.addMinorProfile(draft)
                } else {
                    succeeded = false
                }
            case .declare(let member):
                if let declaration = form.declaration(keepsNicknames: !form.requiresBand) {
                    succeeded = await store.declareMinorGuardianship(for: member, declaration: declaration)
                } else {
                    succeeded = false
                }
            }
            isSending = false
            if succeeded {
                Haptics.success()
                onFinished()
                dismiss()
            }
        }
    }
}

// Only a live guardian sees supervision; any other adult sees who answers for the minor and nothing more.
struct MinorSupervisionSection: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router
    @Environment(\.dismiss) private var dismiss

    let member: HouseholdMember

    @State private var guardianSheet: GuardianSheetMode?
    @State private var isShowingHealthConsent = false
    @State private var isConfirmingRemoval = false
    @State private var isConfirmingWithdrawal = false
    @State private var isConfirmingProfileDeletion = false
    @State private var isShowingWardDeletion = false
    @State private var isConfirmingOlderBand: MinorBand?
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var isShowingUsage = false

    private var access: MinorAccess {
        member.minorAccess ?? MinorAccess()
    }

    private var guardianNames: String {
        access.guardianNames.isEmpty ? "Ninguém" : ListFormatter.localizedString(byJoining: access.guardianNames)
    }

    private var isLastGuardian: Bool {
        access.guardianNames.count <= 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !access.hasProfileConsent, !member.isClaimed {
                legacyCard
            }

            if access.isViewerGuardian, let supervision = access.supervision {
                guardianBlock(supervision)
            } else {
                observerBlock
            }
        }
        .sheet(item: $guardianSheet) { mode in
            NavigationStack {
                GuardianApprovalSheet(mode: mode)
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingHealthConsent) {
            NavigationStack {
                MinorHealthConsentSheet(member: member)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingUsage) {
            NavigationStack {
                MinorUsageHistoryView(name: member.name, days: access.supervision?.usageLast7Days ?? [])
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .accountDeletionSheet(isPresented: $isShowingWardDeletion, target: .ward(member))
        .alert("Tirar \(member.name) da casa?", isPresented: $isConfirmingRemoval) {
            Button("Cancelar", role: .cancel) {}
            Button("Tirar", role: .destructive) {
                Task {
                    if await store.removeFamilyMember(member) {
                        Haptics.success()
                        dismiss()
                    }
                }
            }
        } message: {
            Text("As tarefas de \(member.name) ficam na casa.")
        }
        .alert("Retirar sua autorização?", isPresented: $isConfirmingWithdrawal) {
            Button("Cancelar", role: .cancel) {}
            Button("Retirar", role: .destructive) {
                Task {
                    if await store.endMinorGuardianship(for: member) {
                        Haptics.success()
                    }
                }
            }
        } message: {
            Text(isLastGuardian ? "O perfil de \(member.name) é apagado." : "Você deixa de responder por \(member.name).")
        }
        .alert("Apagar o perfil de \(member.name)?", isPresented: $isConfirmingProfileDeletion) {
            Button("Cancelar", role: .cancel) {}
            Button("Apagar", role: .destructive) {
                Task {
                    if await store.removeFamilyMember(member) {
                        Haptics.success()
                        dismiss()
                    }
                }
            }
        } message: {
            Text("As tarefas voltam para a casa. Não dá para desfazer.")
        }
        .alert(
            "Mudar a idade de \(member.name)?",
            isPresented: Binding(
                get: { isConfirmingOlderBand != nil },
                set: { if !$0 { isConfirmingOlderBand = nil } }
            )
        ) {
            Button("Cancelar", role: .cancel) {}
            Button("Confirmar") {
                guard let band = isConfirmingOlderBand else { return }
                Task { _ = await store.changeMinorBand(for: member, to: band) }
            }
        } message: {
            Text("Você confirma de novo a autorização como responsável por \(member.name).")
        }
    }

    private var legacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quem responde por \(member.name)?")
                .ninaText(.section)
                .fixedSize(horizontal: false, vertical: true)
            if let deletionDate = access.pendingDeletionAt {
                Text("Sem isso, o perfil some em \(Self.deletionDateLabel(deletionDate)).")
                    .ninaText(.label, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.canActForMinors {
                NinaButton(title: "Sou responsável", fillsWidth: true) {
                    guardianSheet = .declare(member)
                }
            } else {
                Text("Só um responsável com idade confirmada pela Apple cadastra.")
                    .ninaText(.caption, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard()
    }

    // The date comes from the server's deadline; without one the card promises no timeline.
    private static func deletionDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeZone = MinorUsageClock.timeZone
        formatter.dateFormat = "d 'de' MMMM"
        return formatter.string(from: date)
    }

    private var observerBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: "Supervisão")
            valueRow("Responsáveis", guardianNames)
            if store.canActForMinors, access.hasProfileConsent || member.isClaimed {
                NinaButton(title: "Também sou responsável", kind: .quiet) {
                    Haptics.lightImpact()
                    guardianSheet = .declare(member)
                }
            }
        }
    }

    private func guardianBlock(_ supervision: MinorSupervision) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: "Supervisão")

            valueRow("Responsáveis", guardianNames)
            NinaDivider(inset: 0)
            bandRow(supervision)

            if member.isClaimed {
                NinaDivider(inset: 0)
                Toggle(isOn: Binding(
                    get: { supervision.alertsEnabled },
                    set: { value in
                        Haptics.selection()
                        update(MinorSupervisionUpdate(alertsEnabled: value))
                    }
                )) {
                    Text("Avisos").ninaText(.body, NinaTheme.ink, weight: .medium)
                }
                .tint(NinaTheme.ink)
                .frame(minHeight: 52)

                NinaDivider(inset: 0)
                quietHoursRow(supervision)
                NinaDivider(inset: 0)
                limitRow(supervision)

                if supervision.dailyLimitMinutes == nil {
                    Text("Sem limite, o tempo de \(member.name) fica só no Tempo de Uso do iPhone.")
                        .ninaText(.caption, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 6)
                }

                NinaDivider(inset: 0)
                Button {
                    Haptics.selection()
                    isShowingUsage = true
                } label: {
                    valueRow("Tempo na Nina", "\(supervision.usageTodayMinutes ?? 0) min hoje", showsChevron: true)
                }
                .buttonStyle(.plain)
            }

            NinaDivider(inset: 0)
            Button {
                Haptics.lightImpact()
                isShowingHealthConsent = true
            } label: {
                valueRow("Saúde", access.hasHealthConsent ? "Autorizado" : "Sem autorização", showsChevron: true)
            }
            .buttonStyle(.plain)

            NinaDivider(inset: 0)
            exportRow

            Text("\(member.name) não conversa com a Nina e não compra nada.")
                .ninaText(.caption, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(spacing: 2) {
                if member.isClaimed {
                    NinaButton(title: "Tirar da casa", kind: .quiet) {
                        Haptics.warning()
                        isConfirmingRemoval = true
                    }
                }
                NinaButton(title: "Retirar autorização", kind: .quiet) {
                    Haptics.warning()
                    isConfirmingWithdrawal = true
                }
                if member.isClaimed {
                    NinaButton(title: "Apagar conta", kind: .quiet) {
                        Haptics.warning()
                        isShowingWardDeletion = true
                    }
                } else {
                    NinaButton(title: "Apagar perfil", kind: .quiet) {
                        Haptics.warning()
                        isConfirmingProfileDeletion = true
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        }
    }

    private func bandRow(_ supervision: MinorSupervision) -> some View {
        Menu {
            ForEach(MinorBand.allCases) { band in
                let mayChoose = band <= supervision.band || !member.isClaimed
                Button {
                    Haptics.selection()
                    if band > supervision.band {
                        isConfirmingOlderBand = band
                    } else {
                        Task { _ = await store.changeMinorBand(for: member, to: band) }
                    }
                } label: {
                    Label(band.chipTitle, systemImage: band == supervision.band ? "checkmark" : "person")
                }
                .disabled(!mayChoose || band == supervision.band)
            }
        } label: {
            valueRow("Idade", supervision.band.chipTitle, showsChevron: true)
        }
        .buttonStyle(.plain)
    }

    private func quietHoursRow(_ supervision: MinorSupervision) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            valueRow(
                "Silenciar à noite",
                MinorSupervisionDefaults.quietWindowLabel(start: supervision.quietStart, end: supervision.quietEnd)
            )
            HStack(spacing: 12) {
                DatePicker(
                    "Começa",
                    selection: timeBinding(minutes: supervision.quietStart) { value in
                        update(MinorSupervisionUpdate(quietStart: value))
                    },
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                Text("às").ninaText(.caption, NinaTheme.muted)
                DatePicker(
                    "Termina",
                    selection: timeBinding(minutes: supervision.quietEnd) { value in
                        update(MinorSupervisionUpdate(quietEnd: value))
                    },
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                Spacer(minLength: 0)
            }
            .tint(NinaTheme.ink)
            .padding(.bottom, 6)
        }
    }

    private func limitRow(_ supervision: MinorSupervision) -> some View {
        Menu {
            ForEach(Array(MinorSupervisionDefaults.dailyLimitChoices.enumerated()), id: \.offset) { _, choice in
                Button {
                    Haptics.selection()
                    update(MinorSupervisionUpdate(dailyLimitMinutes: .some(choice)))
                } label: {
                    Label(
                        MinorSupervisionDefaults.limitTitle(choice),
                        systemImage: choice == supervision.dailyLimitMinutes ? "checkmark" : "clock"
                    )
                }
            }
        } label: {
            valueRow(
                "Limite por dia",
                MinorSupervisionDefaults.limitTitle(supervision.dailyLimitMinutes),
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var exportRow: some View {
        if let exportURL {
            ShareLink(item: exportURL) {
                valueRow("Exportar dados", "Compartilhar", showsChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                exportData()
            } label: {
                valueRow("Exportar dados", isExporting ? "Gerando" : "", showsChevron: true)
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
        }
    }

    private func valueRow(_ title: String, _ value: String, showsChevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(title).ninaText(.body, NinaTheme.ink, weight: .medium)
            Spacer(minLength: 8)
            Text(value)
                .ninaText(.meta, NinaTheme.muted)
                .multilineTextAlignment(.trailing)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NinaTheme.faint)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private func timeBinding(minutes: Int, onChange: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    byAdding: .minute,
                    value: minutes,
                    to: Calendar.current.startOfDay(for: .now)
                ) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                onChange((components.hour ?? 0) * 60 + (components.minute ?? 0))
            }
        )
    }

    private func update(_ change: MinorSupervisionUpdate) {
        Task { _ = await store.updateMinorSupervision(for: member, update: change) }
    }

    private func exportData() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let data = try await store.exportMinorData(for: member)
                exportURL = try PrivacyExportFileStore.write(data, filename: store.privacyExportFilename)
                Haptics.success()
            } catch {
                store.reportSyncError("Não foi possível gerar a exportação agora.")
            }
        }
    }
}

// Health reminders for a minor are a separate consent: granting it is a tick, and withdrawing it deletes
// the minor's health reminders, so the withdrawal is confirmed first.
struct MinorHealthConsentSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let member: HouseholdMember

    @State private var authorizes = false
    @State private var isSaving = false
    @State private var isConfirmingWithdrawal = false

    private var isGranted: Bool {
        member.minorAccess?.hasHealthConsent == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(eyebrow: "Saúde") { dismiss() }
                .padding(.horizontal, -20)

            if isGranted {
                Text("Lembretes de saúde de \(member.name) estão autorizados.")
                    .ninaText(.title)
                    .fixedSize(horizontal: false, vertical: true)

                NinaButton(title: "Retirar autorização", kind: .outline, fillsWidth: true, isPending: isSaving) {
                    Haptics.warning()
                    isConfirmingWithdrawal = true
                }
            } else {
                Button {
                    Haptics.selection()
                    authorizes.toggle()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        NinaCheckbox(isOn: authorizes, isSquare: true)
                        Text(consentText)
                            .ninaText(.label, NinaTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(consentText)
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(authorizes ? "Marcado" : "Desmarcado")

                NinaButton(title: "Autorizar", fillsWidth: true, isEnabled: authorizes, isPending: isSaving) {
                    save(granted: true)
                }
            }

            if let error = store.syncErrorMessage {
                NinaErrorNote(text: error)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
        .alert("Retirar a autorização de saúde?", isPresented: $isConfirmingWithdrawal) {
            Button("Cancelar", role: .cancel) {}
            Button("Retirar", role: .destructive) {
                save(granted: false)
            }
        } message: {
            Text("Os lembretes de saúde de \(member.name) são apagados.")
        }
    }

    private var consentText: String {
        "Autorizo registrar lembretes de saúde de \(member.name), como remédio e consulta."
    }

    private func save(granted: Bool) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            let saved = await store.setMinorHealthConsent(for: member, granted: granted)
            isSaving = false
            if saved {
                Haptics.success()
                dismiss()
            }
        }
    }
}

struct MinorUsageHistoryView: View {
    @Environment(\.dismiss) private var dismiss

    let name: String
    let days: [MinorUsageDay]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetHeader(eyebrow: "Tempo na Nina") { dismiss() }
                .padding(.horizontal, -20)

            if days.isEmpty {
                Text("Sem tempo registrado nos últimos 7 dias.")
                    .ninaText(.label, NinaTheme.muted)
            } else {
                ForEach(days) { day in
                    HStack {
                        Text(Self.label(for: day.day)).ninaText(.body)
                        Spacer()
                        Text("\(day.minutes) min").ninaText(.meta, NinaTheme.muted)
                    }
                    .frame(minHeight: 44)
                    NinaDivider(inset: 0)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private static func label(for day: String) -> String {
        guard let date = PostgresDateOnlyCodec.date(from: day, timeZone: MinorUsageClock.timeZone) else { return day }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeZone = MinorUsageClock.timeZone
        formatter.dateFormat = "EEEE, d"
        return formatter.string(from: date).capitalized
    }
}
