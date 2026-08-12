import SwiftUI

// Tapping a person used to open an edit form even for a viewer who cannot edit.
// The form is now behind a check, and everyone else gets a page they can read.
struct MemberDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router
    @Environment(\.dismiss) private var dismiss

    let member: HouseholdMember

    private var canEdit: Bool { store.canEditFamilyMember(member) }

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
                        .frame(width: 40, height: 40, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Voltar")

                Spacer()

                if canEdit {
                    Button {
                        Haptics.lightImpact()
                        router.presentedSheet = .member(member.id)
                    } label: {
                        Text("Editar").ninaText(.label, NinaTheme.cobalt, weight: .semibold)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 14) {
                        MemberAvatar(
                            initials: member.name.ninaInitials,
                            tone: member.tone,
                            size: 64,
                            isAssistant: member.role == .assistant
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(member.name).ninaText(.title)
                            Text(subtitle).ninaText(.caption, NinaTheme.muted)
                        }
                    }

                    if member.role != .assistant {
                        VStack(spacing: 0) {
                            row("Na casa", member.relationship.isEmpty ? "—" : member.relationship)
                            NinaDivider(inset: 0)
                            row("Em aberto", "\(store.openTaskCount(for: member))")
                            if member.role == .pet, !member.petSpecies.isEmpty {
                                NinaDivider(inset: 0)
                                row("Bicho", [member.petSpecies, member.petBreed].filter { !$0.isEmpty }.joined(separator: " · "))
                            }
                        }
                    }

                    if !member.memoryNote.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(text: "O que a Nina lembra")
                            Text(member.memoryNote)
                                .ninaText(.label, NinaTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .ninaCard(fill: NinaTheme.grout, stroke: .clear)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .ninaScreenBackground()
    }

    private var subtitle: String {
        if member.role == .assistant { return "IA da casa · não ocupa vaga" }
        return member.role.title
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .ninaText(.caption, NinaTheme.muted)
                .frame(width: 92, alignment: .leading)
            Text(value).ninaText(.label)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 46)
    }
}
