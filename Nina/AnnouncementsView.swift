import SwiftUI

enum NinaAnnouncementStage: Hashable {
    case live
    case comingSoon

    var title: String {
        switch self {
        case .live: "Novo"
        case .comingSoon: "Em breve"
        }
    }
}

struct NinaAnnouncement: Identifiable, Hashable {
    var title: String
    var detail: String
    var systemName: String
    var stage: NinaAnnouncementStage

    var id: String { title }
}

// A feature moves from "Em breve" to "Novo" when the build that ships it ships; a new id shows the board once more.
struct NinaAnnouncementBoard: Hashable {
    var id: String
    var items: [NinaAnnouncement]

    func items(in stage: NinaAnnouncementStage) -> [NinaAnnouncement] {
        items.filter { $0.stage == stage }
    }

    static let current = NinaAnnouncementBoard(
        id: "2026-10",
        items: [
            NinaAnnouncement(
                title: "Dia da criança em imagem",
                detail: "Compartilhe a lista de hoje como imagem ou PDF.",
                systemName: "photo.on.rectangle",
                stage: .live
            ),
            NinaAnnouncement(
                title: "Dúvidas e suporte",
                detail: "Respostas rápidas e o email do suporte, em Ajustes.",
                systemName: "questionmark.circle",
                stage: .live
            ),
            NinaAnnouncement(
                title: "Modo criança",
                detail: "Uma tela mais simples e colorida para os pequenos.",
                systemName: "figure.and.child.holdinghands",
                stage: .comingSoon
            ),
            NinaAnnouncement(
                title: "Foto vira tarefa",
                detail: "Boleto, receita ou bilhete da escola, lidos por foto.",
                systemName: "doc.viewfinder",
                stage: .comingSoon
            ),
        ]
    )
}

enum AnnouncementGate {
    enum Decision: Equatable {
        case present
        case markSeen
        case stayQuiet
    }

    static let seenBoardKey = "nina.announcements.seenBoard"

    // Someone who just met the app in the tutorial has nothing that is "new" yet, so the board is filed unseen.
    static func decision(
        seenBoardID: String,
        board: NinaAnnouncementBoard,
        finishedTutorialThisLaunch: Bool
    ) -> Decision {
        guard !board.items.isEmpty, seenBoardID != board.id else { return .stayQuiet }
        return finishedTutorialThisLaunch ? .markSeen : .present
    }
}

struct AnnouncementsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var board: NinaAnnouncementBoard = .current

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(eyebrow: "Novidades") { dismiss() }

            ScrollView {
                AnnouncementsContent(board: board)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            NinaButton(title: "Entendi", fillsWidth: true) {
                Haptics.selection()
                dismiss()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .ninaSheetBackground()
        .presentationDragIndicator(.visible)
    }
}

struct AnnouncementsScreen: View {
    @Environment(\.dismiss) private var dismiss

    var board: NinaAnnouncementBoard = .current

    var body: some View {
        VStack(spacing: 0) {
            BackHeader { dismiss() }

            ScrollView {
                AnnouncementsContent(board: board)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 34)
            }
        }
        .ninaSheetBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct AnnouncementsContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let board: NinaAnnouncementBoard

    @State private var isShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 14) {
                NinaMark(size: 48)
                    .accessibilityHidden(true)
                Text("Novidades da Nina").ninaText(.screen)
                    .accessibilityAddTraits(.isHeader)
            }

            ForEach([NinaAnnouncementStage.live, .comingSoon], id: \.self) { stage in
                let items = board.items(in: stage)
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: stage.title)
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            AnnouncementRow(item: item)
                                .opacity(isShown ? 1 : 0)
                                .offset(y: isShown || reduceMotion ? 0 : 12)
                                .animation(
                                    reduceMotion ? nil : .snappy(duration: 0.45).delay(rowDelay(stage, index)),
                                    value: isShown
                                )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { isShown = true }
    }

    private func rowDelay(_ stage: NinaAnnouncementStage, _ index: Int) -> Double {
        let before = stage == .comingSoon ? board.items(in: .live).count : 0
        return 0.08 * Double(before + index) + 0.1
    }
}

private struct AnnouncementRow: View {
    let item: NinaAnnouncement

    private var isLive: Bool { item.stage == .live }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.systemName)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(isLive ? NinaTheme.cobalt : NinaTheme.ink)
                .frame(width: 48, height: 48)
                .background(
                    isLive ? NinaTheme.cobaltWash : NinaTheme.grout,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .ninaText(.body, NinaTheme.ink, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.detail)
                    .ninaText(.label, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.stage.title)
    }
}

// The board opens by itself once per board id, over the tabs, and never on top of another sheet.
private struct AnnouncementPresenter: ViewModifier {
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(OnboardingStore.self) private var onboardingStore
    @Environment(RouterPath.self) private var router

    @AppStorage(AnnouncementGate.seenBoardKey) private var seenBoardID = ""
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .task {
                try? await Task.sleep(for: .milliseconds(900))
                let finishedTutorial = authSession.currentUser.map {
                    onboardingStore.completedTutorialUserIDs.contains($0.id)
                } ?? false
                switch AnnouncementGate.decision(
                    seenBoardID: seenBoardID,
                    board: .current,
                    finishedTutorialThisLaunch: finishedTutorial
                ) {
                case .present:
                    guard router.presentedSheet == nil else { return }
                    seenBoardID = NinaAnnouncementBoard.current.id
                    isPresented = true
                case .markSeen:
                    seenBoardID = NinaAnnouncementBoard.current.id
                case .stayQuiet:
                    return
                }
            }
            .sheet(isPresented: $isPresented) {
                AnnouncementsSheet()
            }
    }
}

extension View {
    func presentsAnnouncements() -> some View {
        modifier(AnnouncementPresenter())
    }
}
