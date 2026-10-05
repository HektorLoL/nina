import SwiftUI

// A person the server does not record as an adult gets only this, where Nina is a program spoken of in the third person.
struct MinorRootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            switch store.homeAccessState {
            case .minorMember:
                memberContent
            case .pendingApproval:
                MinorPendingView()
            case .accessDecision:
                MinorAccessDecisionView()
            default:
                MinorNoHomeView()
            }
        }
        .ninaScreenBackground()
    }

    @ViewBuilder
    private var memberContent: some View {
        if let home = store.minorHome {
            switch home.viewer.state {
            case .active:
                if home.viewer.needsAcknowledgement, home.viewer.acknowledgementKind != nil {
                    MinorWelcomeView(home: home)
                } else {
                    TimelineView(.everyMinute) { context in
                        if store.isMinorOverDailyLimit(now: context.date) {
                            MinorStatusView(
                                headline: "Por hoje é só.",
                                line: home.viewer.supervision.alertsEnabled
                                    ? "Seus avisos continuam chegando."
                                    : "Volte amanhã."
                            )
                        } else {
                            MinorHomeView(home: home)
                        }
                    }
                }
            case .noGuardian:
                MinorStatusView(
                    headline: "Sua conta está pausada.",
                    line: "Falta um responsável na casa."
                )
            case .ageRequired:
                MinorAgeRequiredView()
            case .noHome:
                MinorNoHomeView()
            }
        } else {
            MinorNoHomeView()
        }
    }
}

struct MinorStatusView: View {
    let headline: String
    let line: String

    @State private var isShowingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            MinorHeader(isShowingSettings: $isShowingSettings)
            Spacer(minLength: 24)
            ZeroState(headline: headline, body_: line, presence: .rest)
                .padding(.horizontal, 20)
            Spacer(minLength: 24)
        }
        .minorSettingsSheet(isPresented: $isShowingSettings)
    }
}

private struct MinorHeader: View {
    @Binding var isShowingSettings: Bool

    var body: some View {
        HStack {
            NinaWordmark(size: 20)
            Spacer()
            Button {
                Haptics.lightImpact()
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(NinaTheme.ink)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir ajustes")
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }
}

struct MinorWelcomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL

    let home: MinorHome

    @State private var isShowingSettings = false

    private var guardian: String {
        home.viewer.guardianName ?? "Seu responsável"
    }

    private var isJointAcceptance: Bool {
        home.viewer.acknowledgementKind == .aceitar
    }

    var body: some View {
        VStack(spacing: 0) {
            MinorHeader(isShowingSettings: $isShowingSettings)
            welcome
        }
        .minorSettingsSheet(isPresented: $isShowingSettings)
    }

    private var welcome: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Spacer(minLength: 24)

                    NinaMark(size: 48)

                    Text("Oi, \(home.ownerName).")
                        .ninaText(.screen)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 12) {
                        line("Aqui aparecem as tarefas que combinaram com você.")
                        line("Terminou uma? Marque como feita.")
                        line("A Nina é um programa de computador, não uma pessoa.")
                        line("\(guardian) acompanha sua conta: vê suas tarefas, avisos e tempo de uso.")
                        line("Nunca passe seu acesso para ninguém. Se algo te incomodar, fale com um adulto de confiança.")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ninaCard(fill: NinaTheme.grout, stroke: .clear)

                    if let error = store.syncErrorMessage {
                        NinaErrorNote(text: error)
                    }

                    NinaButton(
                        title: isJointAcceptance ? "Aceitar" : "Entendi",
                        fillsWidth: true,
                        isPending: store.isSyncingHome
                    ) {
                        Haptics.lightImpact()
                        Task { _ = await store.acknowledgeMinorTerms() }
                    }
                    .padding(.top, 4)

                    if isJointAcceptance {
                        Text("Você aceita os Termos junto com \(guardian).")
                            .ninaText(.meta, NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        NinaButton(title: "Ler os Termos", kind: .quiet) {
                            Haptics.selection()
                            openURL(NinaLegalLinks.termsOfUse)
                        }
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .ninaText(.label, NinaTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// Only the minor's own tasks, as title, hour and glyph, marked done with the child's-list semantics.
struct MinorHomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let home: MinorHome

    @AppStorage(KidsMode.overrideKey) private var kidsModeOverride = ""

    @State private var session: ChildDaySession?
    @State private var isShowingSettings = false
    @State private var upcomingMarks: [TaskItem.ID: ChildDayMark] = [:]
    @State private var upcomingChangedAt: [TaskItem.ID: Date] = [:]

    private var isKidsMode: Bool {
        KidsMode.isOn(band: store.viewerAge.band, override: kidsModeOverride)
    }

    private var owner: HouseholdMember {
        home.ownerMember
    }

    private var items: [TaskItem] {
        store.minorTaskItems
    }

    var body: some View {
        let now = Date.now
        let todayRows = session?.rows(child: owner, tasks: items, members: [owner], now: now) ?? []
        let todayIDs = Set(todayRows.map(\.id))
        let upcoming = upcomingTasks(excluding: todayIDs, now: now)

        VStack(spacing: 0) {
            MinorHeader(isShowingSettings: $isShowingSettings)

            ScrollView {
                if isKidsMode {
                    KidsHomeContent(
                        firstName: home.viewer.firstName,
                        syncError: store.syncErrorMessage,
                        todayRows: todayRows,
                        upcoming: upcoming.map { task in
                            KidsUpcomingItem(
                                id: task.id,
                                title: ChildDay.title(of: task),
                                time: task.displayDate(relativeTo: now).map { AppStore.taskDueLabel(for: $0, relativeTo: now) },
                                symbolName: task.category.symbolName,
                                isDone: task.isDone,
                                canToggle: task.recurrence == .none
                                    && (!task.isDone || upcomingMarks[task.id] != nil)
                            )
                        },
                        onTapToday: tap,
                        onTapUpcoming: tapUpcoming
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                } else {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Suas tarefas").ninaText(.screen)
                            if !home.viewer.guardianNames.isEmpty {
                                Text("Responsável: \(home.viewer.guardianList)")
                                    .ninaText(.label, NinaTheme.muted)
                            }
                            if let error = store.syncErrorMessage {
                                NinaErrorNote(text: error)
                                    .padding(.top, 4)
                            }
                        }

                        if todayRows.isEmpty && upcoming.isEmpty {
                            ZeroState(
                                headline: "Nada para hoje.",
                                body_: "Quando combinarem uma tarefa, ela aparece aqui."
                            )
                            .padding(.top, 24)
                        } else {
                            section("Hoje") {
                                if todayRows.isEmpty {
                                    Text("Nada para hoje.")
                                        .ninaText(.label, NinaTheme.muted)
                                        .frame(minHeight: 44, alignment: .leading)
                                } else {
                                    ForEach(todayRows) { row in
                                        MinorTaskRow(
                                            title: row.title,
                                            time: row.time,
                                            symbolName: row.symbolName,
                                            isDone: row.isDone
                                        ) {
                                            tap(row.id)
                                        }
                                        NinaDivider(inset: 52)
                                    }
                                }
                            }

                            if !upcoming.isEmpty {
                                section("Próximos dias") {
                                    ForEach(upcoming) { task in
                                        MinorTaskRow(
                                            title: ChildDay.title(of: task),
                                            time: task.displayDate(relativeTo: now).map { AppStore.taskDueLabel(for: $0, relativeTo: now) },
                                            symbolName: task.category.symbolName,
                                            isDone: task.isDone,
                                            canToggle: task.recurrence == .none
                                                && (!task.isDone || upcomingMarks[task.id] != nil)
                                        ) {
                                            tapUpcoming(task.id)
                                        }
                                        NinaDivider(inset: 52)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .refreshable {
                await store.refreshMinorHome()
            }
        }
        .minorSettingsSheet(isPresented: $isShowingSettings)
        .onAppear { absorb() }
        .onChange(of: store.minorTaskItems) { _, _ in absorb() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.refreshMinorHome() }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: title)
            VStack(spacing: 0) { content() }
        }
    }

    // A row marked from Próximos dias stays in place, shown done, so a mistaken tap can be undone.
    private func upcomingTasks(excluding todayIDs: Set<TaskItem.ID>, now: Date) -> [TaskItem] {
        items
            .filter { $0.kind == .task && !todayIDs.contains($0.id) }
            .filter { !$0.isDone || upcomingMarks[$0.id] != nil }
            .filter { !$0.belongsOnAgenda(for: now) }
            .sorted { ($0.displayDate(relativeTo: now) ?? .distantFuture) < ($1.displayDate(relativeTo: now) ?? .distantFuture) }
    }

    private func absorb() {
        let now = Date.now
        if var current = session {
            current.absorb(child: owner, tasks: items, members: [owner], now: now)
            session = current
        } else {
            session = ChildDaySession(child: owner, tasks: items, members: [owner], now: now)
        }
    }

    private func tap(_ id: TaskItem.ID) {
        guard let session else { return }
        let now = Date.now
        switch session.tap(on: id, tasks: items, now: now) {
        case .ignore:
            return
        case .markDone(let taskID):
            Task {
                guard let mark = await store.markMinorTaskDone(taskID, now: now) else { return }
                self.session?.record(mark)
                Haptics.success()
            }
        case .reopen(let mark):
            Task {
                guard await store.reopenMinorTask(mark) else { return }
                self.session?.release(mark.written.id, at: .now)
                Haptics.selection()
            }
        }
    }

    private func tapUpcoming(_ id: TaskItem.ID) {
        let now = Date.now
        if let changedAt = upcomingChangedAt[id], now.timeIntervalSince(changedAt) < 1 { return }
        upcomingChangedAt[id] = now
        if let mark = upcomingMarks[id] {
            Task {
                guard await store.reopenMinorTask(mark) else { return }
                upcomingMarks[id] = nil
                upcomingChangedAt[id] = .now
                Haptics.selection()
            }
            return
        }
        Task {
            guard let mark = await store.markMinorTaskDone(id) else { return }
            upcomingMarks[id] = mark
            upcomingChangedAt[id] = .now
            Haptics.success()
        }
    }
}

private struct MinorTaskRow: View {
    let title: String
    let time: String?
    let symbolName: String
    let isDone: Bool
    var canToggle = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                NinaCheckbox(isOn: isDone)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .ninaText(.body, isDone ? NinaTheme.muted : NinaTheme.ink, weight: .medium)
                        .strikethrough(isDone, color: NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let time {
                        Text(time).ninaText(.caption, NinaTheme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                CategoryGlyph(systemName: symbolName, size: 17, tint: NinaTheme.muted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canToggle)
        .opacity(canToggle ? 1 : 0.4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isDone ? "Feita" : "Por fazer")
    }
}

private struct MinorNoHomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(ProfileStore.self) private var profileStore
    @Environment(InviteLinkStore.self) private var inviteLinkStore
    @Environment(AgeCheckCoordinator.self) private var ageCheck

    @State private var inviteText = ""
    @State private var firstName = ""
    @State private var isSending = false
    @State private var isShowingSettings = false
    @State private var nameError: String?

    private var isUnknownAge: Bool {
        store.viewerAge.status == .unknown
    }

    // Apple gives no name to a minor or an unknown age, so a name that came from the sign-in is a placeholder.
    private var needsName: Bool {
        guard let user = authSession.currentUser else { return false }
        if store.viewerAge.needsName { return true }
        let name = profileStore.profile(for: user).displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name == "Você"
    }

    private var inviteCode: String? {
        AppStore.normalizedInviteCode(from: inviteText.isEmpty ? (inviteLinkStore.pendingCode ?? "") : inviteText)
    }

    var body: some View {
        VStack(spacing: 0) {
            MinorHeader(isShowingSettings: $isShowingSettings)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(isUnknownAge ? "Falta sua faixa de idade." : "Peça o convite da sua casa.")
                        .ninaText(.screen)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(isUnknownAge
                        ? "Sem ela, só um responsável aprova sua entrada."
                        : "Quem cuida de você aprova sua entrada.")
                        .ninaText(.label, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if needsName {
                        field(label: "Seu primeiro nome") {
                            TextField("Como a casa chama você", text: $firstName)
                                .textInputAutocapitalization(.words)
                        }
                    }

                    field(label: "Link ou código") {
                        TextField(inviteLinkStore.pendingCode ?? "casa-47a9f2d0b3c1e8a4d6f2", text: $inviteText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    if let error = nameError ?? store.syncErrorMessage {
                        Text(error)
                            .ninaText(.caption, NinaTheme.ink, weight: .medium)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    NinaButton(
                        title: "Pedir para entrar",
                        fillsWidth: true,
                        isEnabled: inviteCode != nil && (!needsName || !firstName.trimmingCharacters(in: .whitespaces).isEmpty),
                        isPending: isSending
                    ) {
                        requestJoin()
                    }

                    if isUnknownAge {
                        NinaButton(
                            title: "Compartilhar faixa",
                            kind: .outline,
                            fillsWidth: true,
                            isPending: ageCheck.isRequestingInline
                        ) {
                            Haptics.lightImpact()
                            shareAge()
                        }

                        if let outcome = ageCheck.inlineOutcome {
                            AgeOutcomeNote(outcome: outcome)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .minorSettingsSheet(isPresented: $isShowingSettings)
    }

    private func field<Field: View>(label: String, @ViewBuilder content: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).ninaText(.meta, NinaTheme.muted)
            content()
                .ninaText(.body, NinaTheme.ink)
                .tint(NinaTheme.cobalt)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NinaTheme.grout, in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous))
    }

    // The typed name reaches the server before the request, because the request is named from the server's profile.
    private func requestJoin() {
        guard let inviteCode, !isSending, let user = authSession.currentUser else { return }
        isSending = true
        nameError = nil
        let typedName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let pushesName = needsName
        Task {
            defer { isSending = false }
            if pushesName {
                var profile = profileStore.profile(for: user)
                profile.displayName = typedName
                profileStore.saveProfile(profile, user: user)
                guard await profileStore.pushProfileToServer(
                    profile,
                    photoData: nil,
                    removesPhoto: false,
                    user: user
                ) else {
                    nameError = "Não deu para salvar seu nome. Tente de novo."
                    Haptics.error()
                    return
                }
            }
            if await store.joinHome(with: inviteCode, member: user) {
                Haptics.success()
                inviteLinkStore.clear()
            }
        }
    }

    private func shareAge() {
        guard let user = authSession.currentUser else { return }
        Task {
            guard let status = await ageCheck.requestInline(for: user) else { return }
            await store.applyRecordedAge(status, for: user)
        }
    }
}

private struct MinorAgeRequiredView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(AgeCheckCoordinator.self) private var ageCheck

    @State private var isShowingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            MinorHeader(isShowingSettings: $isShowingSettings)
            Spacer(minLength: 24)
            ZeroState(
                headline: "Falta sua faixa de idade.",
                body_: "Sem ela, só um responsável aprova sua entrada.",
                presence: .rest
            ) {
                VStack(spacing: 10) {
                    NinaButton(title: "Compartilhar faixa", isPending: ageCheck.isRequestingInline) {
                        Haptics.lightImpact()
                        guard let user = authSession.currentUser else { return }
                        Task {
                            guard let status = await ageCheck.requestInline(for: user) else { return }
                            await store.applyRecordedAge(status, for: user)
                        }
                    }

                    if let outcome = ageCheck.inlineOutcome {
                        AgeOutcomeNote(outcome: outcome, alignment: .center)
                    }
                }
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 24)
        }
        .minorSettingsSheet(isPresented: $isShowingSettings)
    }
}

private struct MinorPendingView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession

    @State private var isShowingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            MinorHeader(isShowingSettings: $isShowingSettings)
            Spacer(minLength: 24)
            ZeroState(
                headline: "Pedido enviado.",
                body_: "Um responsável seu na casa precisa aprovar.",
                presence: .waiting
            ) {
                VStack(spacing: 10) {
                    NinaButton(title: "Atualizar", systemName: "arrow.clockwise", isEnabled: !store.isSyncingHome) {
                        Task { await store.activateHomeContext(for: authSession.currentUser) }
                    }
                    NinaButton(title: "Cancelar pedido", kind: .quiet, isEnabled: !store.isSyncingHome) {
                        Task {
                            if await store.cancelPendingJoinRequest() { Haptics.selection() }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 24)
        }
        .minorSettingsSheet(isPresented: $isShowingSettings)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await store.activateHomeContext(for: authSession.currentUser)
            }
        }
    }
}

private struct MinorAccessDecisionView: View {
    @Environment(AppStore.self) private var store

    @State private var isShowingSettings = false
    @State private var isShowingDeletion = false

    private var wasRemoved: Bool {
        store.familyAccessDecision?.outcome == .removed
    }

    var body: some View {
        VStack(spacing: 0) {
            MinorHeader(isShowingSettings: $isShowingSettings)
            Spacer(minLength: 24)
            ZeroState(
                headline: wasRemoved ? "Você saiu da casa." : "Seu pedido não foi aprovado",
                body_: wasRemoved ? "Sua conta é apagada em 30 dias." : "Peça o convite de novo para quem cuida de você.",
                presence: .unavailable
            ) {
                VStack(spacing: 10) {
                    if wasRemoved {
                        NinaButton(title: "Apagar agora", kind: .outline) {
                            Haptics.warning()
                            isShowingDeletion = true
                        }
                    }
                    NinaButton(title: "Entendi", kind: wasRemoved ? .quiet : .primary, isEnabled: !store.isSyncingHome) {
                        Task {
                            if await store.acknowledgeFamilyAccessDecision() { Haptics.selection() }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 24)
        }
        .minorSettingsSheet(isPresented: $isShowingSettings)
        .accountDeletionSheet(isPresented: $isShowingDeletion)
    }
}

extension View {
    func minorSettingsSheet(isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) {
            NavigationStack {
                MinorSettingsView()
            }
            .presentationDragIndicator(.visible)
        }
    }
}

struct MinorSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(OnboardingStore.self) private var onboardingStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage(KidsMode.overrideKey) private var kidsModeOverride = ""

    @State private var isConfirmingSignOut = false

    private var home: MinorHome? {
        store.minorHome
    }

    private var kidsModeBinding: Binding<Bool> {
        Binding(
            get: { KidsMode.isOn(band: store.viewerAge.band, override: kidsModeOverride) },
            set: { isOn in
                Haptics.selection()
                kidsModeOverride = (isOn ? KidsMode.Override.on : .off).rawValue
            }
        )
    }

    private var guardian: String? {
        home?.viewer.guardianName ?? store.viewerAge.firstGuardianName
    }

    private var usageValue: String {
        let used = store.minorUsageMinutes()
        guard let limit = home?.viewer.supervision.dailyLimitMinutes else { return "\(used) min" }
        return "\(used) de \(limit) min"
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(eyebrow: "Ajustes") { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(spacing: 0) {
                        if let guardian {
                            valueRow("Responsável", guardian, systemName: "person")
                            NinaDivider()
                        }
                        if home != nil {
                            NinaRow(title: "Modo criança") {
                                CategoryGlyph(systemName: "star", size: 18, tint: NinaTheme.ink)
                            } trailing: {
                                Toggle("Modo criança", isOn: kidsModeBinding)
                                    .labelsHidden()
                                    .tint(NinaTheme.Kids.leaf)
                            }
                            NinaDivider()
                            valueRow("Tempo hoje", usageValue, systemName: "clock")
                            NinaDivider()
                            valueRow(
                                "Avisos",
                                home?.viewer.supervision.alertsEnabled == false ? "Desligados" : "Ligados",
                                systemName: "bell"
                            )
                            NinaDivider()
                        }
                        link("O que a Nina guarda", systemName: "lock") { MinorKeepsView() }
                        NinaDivider()
                        link("Precisa conversar?", systemName: "heart") { MinorNeedToTalkView() }
                        NinaDivider()
                        link("Minha idade está errada", systemName: "questionmark.circle") { MinorAgeContestView() }
                        NinaDivider()
                        link("Denunciar um problema", systemName: "exclamationmark.bubble") { ReportProblemView() }
                        NinaDivider()
                        external("Termos de uso", systemName: "text.book.closed", url: NinaLegalLinks.termsOfUse)
                        NinaDivider()
                        external("Política de privacidade", systemName: "doc.text", url: NinaLegalLinks.privacyPolicy)
                        NinaDivider()
                        RatingSettingsRow()
                    }

                    VStack(spacing: 4) {
                        NinaButton(title: "Sair", kind: .quiet) {
                            Haptics.warning()
                            isConfirmingSignOut = true
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
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
            }
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
        .alert("Sair deste iPhone?", isPresented: $isConfirmingSignOut) {
            Button("Cancelar", role: .cancel) {}
            Button("Sair", role: .destructive) {
                Task {
                    guard await authSession.signOut() else { return }
                    onboardingStore.cancelReplay()
                    dismiss()
                }
            }
        } message: {
            Text("Para entrar de novo, use sua conta Apple.")
        }
    }

    private func valueRow(_ title: String, _ value: String, systemName: String) -> some View {
        NinaRow(title: title) {
            CategoryGlyph(systemName: systemName, size: 18, tint: NinaTheme.ink)
        } trailing: {
            Text(value)
                .ninaText(.meta, NinaTheme.muted)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private func link<Destination: View>(
        _ title: String,
        systemName: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            NinaRow(title: title) {
                CategoryGlyph(systemName: systemName, size: 18, tint: NinaTheme.ink)
            } trailing: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NinaTheme.faint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func external(_ title: String, systemName: String, url: URL) -> some View {
        Button {
            Haptics.selection()
            openURL(url)
        } label: {
            NinaRow(title: title) {
                CategoryGlyph(systemName: systemName, size: 18, tint: NinaTheme.ink)
            } trailing: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NinaTheme.faint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MinorTextPage: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let lines: [String]
    var linkTitle: String?
    var linkURL: URL?

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    Haptics.selection()
                    dismiss()
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

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(title).ninaText(.screen)
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .ninaText(.label, NinaTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let linkTitle, let linkURL {
                        NinaButton(title: linkTitle, kind: .quiet) {
                            Haptics.selection()
                            openURL(linkURL)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct MinorKeepsView: View {
    @Environment(AppStore.self) private var store

    private var guardian: String {
        store.minorHome?.viewer.guardianName ?? store.viewerAge.firstGuardianName ?? "seu responsável"
    }

    var body: some View {
        MinorTextPage(
            title: "O que a Nina guarda",
            lines: [
                "A Nina guarda seu nome e as tarefas que combinaram com você.",
                "Quem vê: os adultos da sua casa na Nina.",
                "Isso fica guardado em computadores no Brasil.",
                "A Nina é um programa de computador. Ela não conversa com você.",
                "Quando um adulto fala de você com a Nina, seu nome vai trocado por um código.",
                "Quer apagar tudo? Fale com \(guardian) ou toque em Apagar conta."
            ],
            linkTitle: "Mais para os responsáveis",
            linkURL: NinaLegalLinks.families
        )
    }
}

private struct MinorNeedToTalkView: View {
    var body: some View {
        MinorTextPage(
            title: "Precisa conversar?",
            lines: [
                "Se algo te preocupa, fale com um adulto de confiança.",
                "CVV: ligue 188. É de graça, a qualquer hora."
            ]
        )
    }
}

private struct MinorAgeContestView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(AgeCheckCoordinator.self) private var ageCheck
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var guardian: String {
        store.minorHome?.viewer.guardianName ?? store.viewerAge.firstGuardianName ?? "seu responsável"
    }

    private var setByGuardian: Bool {
        store.viewerAge.bandSource == .guardian
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    Haptics.selection()
                    dismiss()
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

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Minha idade está errada").ninaText(.screen)

                    if setByGuardian {
                        Text("\(guardian) informou sua faixa ao aprovar sua entrada. Fale com \(guardian).")
                            .ninaText(.label, NinaTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("A Nina usa a faixa que a Apple informa. Se ela mudou, compartilhe de novo.")
                            .ninaText(.label, NinaTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        NinaButton(
                            title: "Compartilhar de novo",
                            fillsWidth: true,
                            isPending: ageCheck.isRequestingInline
                        ) {
                            Haptics.lightImpact()
                            guard let user = authSession.currentUser else { return }
                            Task {
                                guard let status = await ageCheck.requestInline(for: user) else { return }
                                await store.applyRecordedAge(status, for: user)
                            }
                        }

                        if let outcome = ageCheck.inlineOutcome {
                            AgeOutcomeNote(outcome: outcome)
                        }
                    }

                    Text("Ou escreva para \(NinaLegalLinks.privacyEmail).")
                        .ninaText(.label, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    NinaButton(title: NinaLegalLinks.privacyEmail, kind: .quiet) {
                        Haptics.selection()
                        openURL(NinaLegalLinks.privacyMail)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}
