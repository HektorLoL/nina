import SwiftUI

struct HouseView: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router

    @State private var isConfirmingRotation = false
    @State private var isRotatingInvite = false

    private var people: [HouseholdMember] {
        store.familyGroup.members.filter { $0.role != .assistant }
    }

    private var assistant: HouseholdMember? {
        store.familyGroup.members.first { $0.role == .assistant }
    }

    private var isAloneInHouse: Bool {
        people.count <= 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                members

                if isAloneInHouse {
                    dormantPortrait
                } else {
                    portraitStrip
                }

                if store.canManageFamily, !store.joinRequests.isEmpty {
                    pendingRequests
                }

                // The weekly digest is one of the three ceilings the paywall sells.
                // Without a surface here, the app charges for something it never shows.
                if !store.insights.isEmpty {
                    weeklyDigest
                } else {
                    digestPlaceholder
                }

                memoriesEntry
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 104)
        }
        .ninaScreenBackground()
        .ninaStatusBarMask()
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 10) {
                    Text(store.familyGroup.name).ninaText(.screen)
                    if store.householdPremium.isActive {
                        PremiumBadge()
                    }
                }
                Text("\(store.familyPeopleCount) de \(AppStore.maxFamilyPeople) pessoas")
                    .ninaText(.label, NinaTheme.muted)
            }

            Spacer()

            Button {
                Haptics.lightImpact()
                router.presentedSheet = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(NinaTheme.ink)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir ajustes")
            .padding(.top, 4)
        }
    }

    private var members: some View {
        VStack(spacing: 0) {
            ForEach(people) { member in
                Button {
                    Haptics.selection()
                    router.navigate(to: .member(member.id))
                } label: {
                    NinaRow(
                        title: member.name,
                        subtitle: memberSubtitle(member)
                    ) {
                        MemberAvatar(initials: member.name.ninaInitials, tone: member.tone)
                    } trailing: {
                        if member.permissionRole == .owner {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(NinaTheme.ink)
                                .accessibilityLabel("Responsável pela casa")
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                NinaDivider()
            }

            if let assistant {
                NinaRow(
                    title: assistant.name,
                    subtitle: "Não ocupa vaga."
                ) {
                    NinaMark(size: 40)
                } trailing: {
                    EmptyView()
                }
            }

            // Alone, the dormant portrait carries the invite, so the screen never offers it twice.
            if !isAloneInHouse, store.canInviteMorePeople {
                NinaDivider()

                actionRow("Convidar alguém", systemName: "link") {
                    Haptics.lightImpact()
                    router.presentedSheet = .inviteFamily
                }
            }

            if store.canManageFamily, store.canInviteMorePeople {
                NinaDivider()

                actionRow("Adicionar criança ou pet", systemName: "person.badge.plus") {
                    Haptics.lightImpact()
                    router.presentedSheet = .addMemberProfile
                }
            }

            if store.canManageFamily, !isAloneInHouse {
                NinaDivider()

                renewInviteRow
            }
        }
    }

    private func memberSubtitle(_ member: HouseholdMember) -> String {
        let role = member.permissionRole == .admin ? member.permissionRole.title : member.role.title
        guard member.id == store.currentFamilyMember?.id else { return role }
        return member.permissionRole == .admin ? "Você · \(role)" : "Você"
    }

    private func actionRow(
        _ title: String,
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            NinaRow(title: title) {
                CategoryGlyph(systemName: systemName, size: 18, tint: NinaTheme.ink)
            } trailing: {
                chevron
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(NinaTheme.faint)
    }

    private var renewInviteRow: some View {
        Button {
            Haptics.warning()
            isConfirmingRotation = true
        } label: {
            NinaRow(title: "Renovar o link") {
                CategoryGlyph(systemName: "arrow.clockwise", size: 18, tint: NinaTheme.ink)
            } trailing: {
                EmptyView()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRotatingInvite)
        .opacity(isRotatingInvite ? 0.4 : 1)
        .alert("Renovar o link?", isPresented: $isConfirmingRotation) {
            Button("Renovar", role: .destructive) { rotateInvite() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O link antigo para de funcionar na hora.")
        }
    }

    private func rotateInvite() {
        isRotatingInvite = true
        Task {
            let rotated = await store.rotateFamilyInvite()
            isRotatingInvite = false
            rotated ? Haptics.success() : Haptics.error()
        }
    }

    private var portraitStrip: some View {
        Button {
            Haptics.lightImpact()
            router.navigate(to: .workload)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Sinal de sobrecarga")
                HStack {
                    Text(store.workloadSnapshot.isConclusive
                        ? store.workloadSnapshot.headline
                        : "Ainda sem retrato da casa")
                        .ninaText(.title)
                    Spacer()
                    chevron
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ninaCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var dormantPortrait: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Sinal de sobrecarga")
            Text("Aparece quando o outro adulto entrar.")
                .ninaText(.title)
                .fixedSize(horizontal: false, vertical: true)

            if store.canInviteMorePeople {
                NinaButton(title: "Convidar", fillsWidth: true) {
                    Haptics.lightImpact()
                    router.presentedSheet = .inviteFamily
                }
                .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard()
    }

    private var weeklyDigest: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "Resumo semanal")

            ForEach(store.insights) { insight in
                VStack(alignment: .leading, spacing: 6) {
                    Text(insight.title).ninaText(.section)
                    Text(insight.message)
                        .ninaText(.label, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if !insight.metric.isEmpty {
                        Text(insight.metric).ninaText(.meta, NinaTheme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if insight.id != store.insights.last?.id {
                    NinaDivider(inset: 0)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard()
    }

    // A house that pays for the digest must see where it will appear; a house
    // that does not must see it is Premium, not a card that does nothing.
    @ViewBuilder
    private var digestPlaceholder: some View {
        if store.householdPremium.isActive {
            NinaRow(title: "Resumo semanal", subtitle: "O primeiro chega em até 7 dias.") {
                CategoryGlyph(systemName: "calendar", size: 18, tint: NinaTheme.ink)
            } trailing: {
                EmptyView()
            }
            .padding(.horizontal, 18)
            .ninaCard()
            .accessibilityElement(children: .combine)
        } else {
            Button {
                Haptics.lightImpact()
                router.presentedSheet = .premium
            } label: {
                NinaRow(title: "Resumo semanal") {
                    CategoryGlyph(systemName: "lock", size: 18, tint: NinaTheme.ink)
                } trailing: {
                    HStack(spacing: 10) {
                        premiumTag
                        chevron
                    }
                }
                .padding(.horizontal, 18)
                .ninaCard()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resumo semanal")
            .accessibilityValue("Premium")
        }
    }

    private var premiumTag: some View {
        Text("Premium")
            .ninaText(.eyebrow, NinaTheme.muted, weight: .bold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(NinaTheme.grout, in: Capsule())
    }

    private var pendingRequests: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Pedindo para entrar")
            ForEach(store.joinRequests) { request in
                PendingJoinRequestCard(request: request)
            }
        }
    }

    private var memoriesEntry: some View {
        Button {
            Haptics.selection()
            router.navigate(to: .memories)
        } label: {
            NinaRow(title: "Memórias", subtitle: memoryCount) {
                CategoryGlyph(systemName: "bookmark", size: 19, tint: NinaTheme.ink)
            } trailing: {
                chevron
            }
            .padding(.horizontal, 18)
            .ninaCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var memoryCount: String? {
        let count = store.ninaMemories.count
        guard count > 0 else { return nil }
        return count == 1 ? "1 guardada" : "\(count) guardadas"
    }
}

// Memories start private. Sharing is always a separate, explicit tap — never a
// side effect of accepting one.
struct MemoriesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.selection()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NinaTheme.ink)
                    .frame(width: 40, height: 40, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voltar")
            .padding(.leading, 20)

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Memórias").ninaText(.screen)

                        if store.ninaMemories.isEmpty {
                            Spacer(minLength: 12)
                            ZeroState(
                                headline: "Nada guardado ainda.",
                                body_: "A Nina propõe guardar. Memórias começam privadas."
                            ) {
                                NinaButton(title: "Conversar com a Nina", kind: .outline) {
                                    Haptics.selection()
                                    NotificationCenter.default.post(name: .ninaSelectChatTab, object: nil)
                                }
                            }
                            Spacer(minLength: 12)
                        } else {
                            ForEach(store.ninaMemories) { memory in
                                MemoryCard(memory: memory)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 40)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaScreenBackground()
    }

}

// Memories are the one object the app calls unrecoverable once shared, so the
// screen that lists them must actually offer the delete its own copy promises.
private struct MemoryCard: View {
    @Environment(AppStore.self) private var store

    let memory: NinaMemory

    @State private var isEditing = false
    @State private var draftTitle = ""
    @State private var draftBody = ""
    @State private var isConfirmingDelete = false
    @State private var isConfirmingShare = false
    @State private var isSaving = false

    private var canEdit: Bool { store.canEditMemory(memory) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: memory.visibility == .shared ? "person.2" : "lock")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(NinaTheme.faint)
                Text(memory.visibility == .shared ? "A casa vê" : "Só você vê")
                    .ninaText(.eyebrow, NinaTheme.faint, weight: .bold)
                Spacer()
            }

            if isEditing {
                TextField("Título", text: $draftTitle)
                    .ninaText(.body, NinaTheme.ink, weight: .medium)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(NinaTheme.grout, in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous))

                TextField("Detalhe", text: $draftBody, axis: .vertical)
                    .ninaText(.label, NinaTheme.ink)
                    .lineLimit(2...6)
                    .padding(12)
                    .background(NinaTheme.grout, in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous))

                HStack(spacing: 10) {
                    NinaButton(title: isSaving ? "Salvando" : "Salvar", isEnabled: !isSaving && !draftTitle.trimmingCharacters(in: .whitespaces).isEmpty) {
                        save()
                    }
                    NinaButton(title: "Cancelar", kind: .quiet) {
                        Haptics.selection()
                        isEditing = false
                    }
                }
            } else {
                Text(memory.title).ninaText(.section)
                if !memory.body.isEmpty {
                    Text(memory.body)
                        .ninaText(.label, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if canEdit {
                    HStack(spacing: 8) {
                        Button {
                            Haptics.lightImpact()
                            draftTitle = memory.title
                            draftBody = memory.body
                            isEditing = true
                        } label: {
                            NinaChip(text: "Editar")
                        }
                        .buttonStyle(.plain)

                        if memory.visibility == .privateMemory {
                            Button {
                                Haptics.warning()
                                isConfirmingShare = true
                            } label: {
                                NinaChip(text: "Compartilhar com a casa")
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        Button {
                            Haptics.warning()
                            isConfirmingDelete = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(NinaTheme.muted)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Apagar memória")
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard()
        .alert("Apagar esta memória?", isPresented: $isConfirmingDelete) {
            Button("Apagar", role: .destructive) {
                Task { _ = await store.deleteMemory(memory) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("A Nina esquece na próxima conversa. Não dá para desfazer.")
        }
        .alert("Compartilhar com a casa?", isPresented: $isConfirmingShare) {
            Button("Compartilhar", role: .destructive) { share() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            // Sharing a private memory is the most irreversible act in the product.
            Text(shareWarning)
        }
    }

    private var shareWarning: String {
        let others = store.familyGroup.members.filter {
            $0.role == .adult && $0.id != store.currentFamilyMember?.id
        }
        if others.count == 1, let other = others.first, !other.name.firstWord.isEmpty {
            return "\(other.name.firstWord) vai poder ler. Não dá para desfazer."
        }
        if others.isEmpty {
            return "Quem entrar vai poder ler. Não dá para desfazer."
        }
        return "Os outros adultos vão poder ler. Não dá para desfazer."
    }

    private func save() {
        var edited = memory
        edited.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.body = draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        Task {
            let saved = await store.updateMemory(edited)
            isSaving = false
            if saved {
                Haptics.success()
                isEditing = false
            }
        }
    }

    private func share() {
        var edited = memory
        edited.visibility = .shared
        Task {
            if await store.updateMemory(edited) { Haptics.success() }
        }
    }
}
