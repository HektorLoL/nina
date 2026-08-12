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

                if let message = store.syncErrorMessage {
                    banner(message)
                }

                members

                if isAloneInHouse {
                    dormantPortrait
                    aloneReassurance
                } else {
                    portraitStrip
                }

                if store.canManageFamily, !store.joinRequests.isEmpty {
                    pendingRequests
                }

                // While the house is one person the dormant-portrait card already
                // carries the invite, and a second copy would put two cobalt
                // controls on one screen for the same action.
                if !isAloneInHouse {
                    inviteCard
                }
                memoriesEntry
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 104)
        }
        .ninaScreenBackground()
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.familyGroup.name).ninaText(.screen)
                // The singular branch is load-bearing: the counter used to read
                // "1 pessoas" on the one screen a solo household sees most.
                Text(slotLine).ninaText(.label, NinaTheme.muted)
            }

            Spacer()

            Button {
                Haptics.lightImpact()
                router.presentedSheet = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(NinaTheme.ink)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir ajustes")
            .padding(.top, 4)
        }
    }

    private var slotLine: String {
        let count = store.familyPeopleCount
        let remaining = store.remainingFamilySlots
        let peoplePart = count == 1 ? "1 pessoa" : "\(count) pessoas"
        guard remaining > 0 else { return "\(peoplePart). A casa está cheia." }
        return remaining == 1
            ? "\(peoplePart). Cabe mais 1."
            : "\(peoplePart). Cabem mais \(remaining)."
    }

    private func banner(_ message: String) -> some View {
        // Losing the connection is not lateness, so it never takes terracotta.
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(NinaTheme.ink)
            Text(message).ninaText(.caption, NinaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard(fill: NinaTheme.grout, stroke: .clear)
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
                    subtitle: "IA da casa · não ocupa vaga"
                ) {
                    NinaMark(size: 40)
                } trailing: {
                    EmptyView()
                }
            }
        }
    }

    private func memberSubtitle(_ member: HouseholdMember) -> String {
        var parts: [String] = []
        if member.id == store.currentFamilyMember?.id {
            parts.append("Você")
        } else {
            parts.append(member.role.title)
        }
        if member.role == .child { parts.append("não usa o app") }
        else if member.permissionRole == .admin { parts.append("pode editar") }
        return parts.joined(separator: " · ")
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
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NinaTheme.faint)
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
            Text("O retrato dorme até chegar mais gente.")
                .ninaText(.title)
                .fixedSize(horizontal: false, vertical: true)
            Text("O sinal de sobrecarga é uma comparação. Com um adulto só na casa, não tem o que comparar — e a Nina prefere não desenhar nada a chutar.")
                .ninaText(.label, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if store.canInviteMorePeople {
                NinaButton(title: "Chamar o outro adulto", fillsWidth: true) {
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

    private var aloneReassurance: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(NinaTheme.faint)
            Text("Nada disso trava o resto. A Nina continua montando as tarefas, as compras e as sementes de uma casa de uma pessoa só.")
                .ninaText(.caption, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pendingRequests: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Pedindo para entrar")
            ForEach(store.joinRequests) { request in
                HStack(spacing: 12) {
                    MemberAvatar(initials: request.requesterName.ninaInitials, tone: .sky, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.requesterName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(NinaTheme.ink)
                        Text("Ainda não vê nada da casa").ninaText(.meta, NinaTheme.muted)
                    }
                    Spacer()
                }
                NinaButton(title: "Abrir pedido", kind: .outline, fillsWidth: true) {
                    Haptics.lightImpact()
                    router.presentedSheet = .inviteFamily
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard()
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Chamar alguém")
            // Possessing the link grants nothing: it opens a request an owner or
            // admin approves. Saying so is the whole point of this card.
            Text("O link não dá acesso. Ele pede entrada, e alguém da casa aprova.")
                .ninaText(.label, NinaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if store.canInviteMorePeople {
                NinaButton(title: "Enviar convite", fillsWidth: true) {
                    Haptics.lightImpact()
                    router.presentedSheet = .inviteFamily
                }
            } else {
                Text("A casa chegou no limite de 8 pessoas. A Nina não ocupa vaga.")
                    .ninaText(.caption, NinaTheme.muted)
            }

            if store.canManageFamily {
                NinaButton(title: "Renovar o link", kind: .quiet, isEnabled: !isRotatingInvite) {
                    Haptics.warning()
                    isConfirmingRotation = true
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard()
        .alert("Renovar o link?", isPresented: $isConfirmingRotation) {
            Button("Renovar", role: .destructive) { rotateInvite() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O link antigo para de funcionar na hora. Quem ainda não entrou vai precisar do novo.")
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

    private var memoriesEntry: some View {
        Button {
            Haptics.selection()
            router.navigate(to: .memories)
        } label: {
            NinaRow(
                title: "Memórias",
                subtitle: store.ninaMemories.isEmpty
                    ? "Nada guardado ainda"
                    : "\(store.ninaMemories.count) guardadas"
            ) {
                CategoryGlyph(systemName: "bookmark", size: 19, tint: NinaTheme.ink)
            } trailing: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NinaTheme.faint)
            }
            .padding(.horizontal, 18)
            .ninaCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Memórias").ninaText(.screen)

                    if store.ninaMemories.isEmpty {
                        ZeroState(
                            headline: "Nada guardado ainda.",
                            body_: "Memórias pessoais começam privadas. Compartilhar com a casa é sempre uma escolha explícita."
                        )
                        .padding(.top, 30)
                    } else {
                        ForEach(store.ninaMemories) { memory in
                            memoryCard(memory)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaScreenBackground()
    }

    private func memoryCard(_ memory: NinaMemory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: memory.visibility == .shared ? "person.2" : "lock")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(NinaTheme.faint)
                Text(memory.visibility == .shared ? "A casa vê" : "Só você vê")
                    .ninaText(.eyebrow, NinaTheme.faint, weight: .bold)
            }
            Text(memory.title).ninaText(.section)
            if !memory.body.isEmpty {
                Text(memory.body)
                    .ninaText(.label, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard()
    }
}
