import SwiftUI

// A portrait the snapshot refused to conclude is never drawn. Both the copy and
// the chart gate on isConclusive — saying the division cannot be drawn without
// guessing and then drawing the guess is the defect this screen exists to avoid.
struct WorkloadView: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var showsMethod = false

    private var snapshot: HouseholdWorkloadSnapshot { store.workloadSnapshot }

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
                    Eyebrow(text: "Sinal de sobrecarga")

                    Text(headline)
                        .ninaText(.display)
                        .fixedSize(horizontal: false, vertical: true)

                    if !snapshot.message.isEmpty {
                        Text(snapshot.message)
                            .ninaText(.label, snapshot.isConclusive ? NinaTheme.ink : NinaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if snapshot.isConclusive {
                        bands
                        provenance
                        if snapshot.sharedCount > 0 {
                            NinaButton(title: "Ver sem dono", kind: .outline, fillsWidth: true) {
                                Haptics.lightImpact()
                                dismiss()
                                NotificationCenter.default.post(name: .ninaShowUnowned, object: nil)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaScreenBackground()
    }

    private var headline: String {
        guard snapshot.isConclusive else { return snapshot.headline }
        return snapshot.isBalanced
            ? "A casa está dividida parecida."
            : "A casa está pesando mais de um lado."
    }

    private var bands: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                ForEach(Array([WorkloadBand.light, .similar, .heavier].enumerated()), id: \.offset) { _, band in
                    Text(band.title.uppercased())
                        .ninaText(.eyebrow, NinaTheme.faint, weight: .bold)
                        .frame(maxWidth: .infinity, alignment: band == .light ? .leading : (band == .heavier ? .trailing : .center))
                }
            }

            // Household order, never sorted by load: row order is an encoding, and
            // sorting descending is the ranking the caption disclaims.
            ForEach(snapshot.entries) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        if entry.isShared {
                            CategoryGlyph(systemName: "house", size: 17, tint: NinaTheme.muted)
                                .frame(width: 26)
                        } else {
                            MemberAvatar(initials: entry.name.ninaInitials, tone: entry.tone, size: 26)
                                .frame(width: 26)
                        }
                        Text(entry.isShared ? "Sem dono" : entry.name)
                            .ninaText(.body, entry.isShared ? NinaTheme.muted : NinaTheme.ink, weight: .medium)
                    }

                    HStack(spacing: 6) {
                        ForEach(Array([WorkloadBand.light, .similar, .heavier].enumerated()), id: \.offset) { _, band in
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(segmentFill(entry: entry, band: band))
                                .frame(height: 30)
                        }
                    }
                }
                // The finding is drawn as a position under a labelled axis, which
                // a screen reader cannot see. It has to be said as well.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    entry.isShared
                        ? "Sem dono: \(entry.band.title)"
                        : "\(entry.name): \(entry.band.title)"
                )
            }
        }
    }

    // Unassigned work is a different weight, never a different hue: it is not a
    // person and must not read as one.
    private func segmentFill(entry: HouseholdWorkloadEntry, band: WorkloadBand) -> Color {
        guard entry.band == band else { return NinaTheme.grout }
        return entry.isShared ? NinaTheme.line : NinaTheme.cobalt
    }

    private var provenance: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text("Só o que está aberto e tem dono. Para conversar, não para cobrar.")
                    .ninaText(.meta, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Haptics.selection()
                    showsMethod.toggle()
                } label: {
                    Image(systemName: showsMethod ? "info.circle.fill" : "info.circle")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(NinaTheme.muted)
                        .frame(width: 44, height: 44, alignment: .topTrailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Como o retrato é feito")
                .accessibilityValue(showsMethod ? "Aberto" : "Fechado")
            }

            if showsMethod {
                Text("Sementes não entram. Não é histórico, é hoje.")
                    .ninaText(.meta, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension Notification.Name {
    static let ninaShowUnowned = Notification.Name("nina.showUnowned")
}
