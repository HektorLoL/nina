import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

struct NinaChatView: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router
    @State private var didLoadInitialMessages = false

    private static let captureExamples = [
        "a escola pediu autorização até sexta",
        "acabou o café e o detergente",
        "quem vai buscar o Téo quinta?",
        "um dia quero pintar a sala"
    ]

    var body: some View {
        Group {
            if store.canUseNinaAI {
                if store.requiresAIMemoryConsent && !store.hasAIMemoryConsent {
                    consentContent
                } else {
                    chatContent
                }
            } else {
                adultOnlyContent
            }
        }
        .ninaScreenBackground()
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            header
            houseStrip

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        connectionNotice

                        if store.messages.isEmpty {
                            capturePrompt
                        }

                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(store.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }

                            if store.isNinaResponding {
                                NinaTypingBubble()
                                    .id("nina-typing")
                            }

                            if pendingProposalCount > 0 {
                                waitingLine
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 18)
                }
                .scrollDismissesKeyboard(.interactively)
                .task(id: store.messages.last?.id) {
                    await Task.yield()
                    guard didLoadInitialMessages else {
                        didLoadInitialMessages = true
                        return
                    }
                    guard let lastID = store.messages.last?.id else { return }
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChatInputBar()
        }
    }

    private var consentContent: some View {
        ScrollView {
            AIMemoryConsentCard()
                .padding(.horizontal, 20)
                .padding(.top, 30)
                .padding(.bottom, 104)
        }
    }

    private var adultOnlyContent: some View {
        VStack {
            Spacer(minLength: 0)

            ZeroState(
                headline: "A conversa é dos adultos da casa.",
                body_: "Tarefas, compras e o que a casa combinou continuam aqui para você. Só a conversa com a Nina fica com os adultos.",
                presence: .unavailable
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 104)
    }

    private var header: some View {
        HStack {
            NinaWordmark(size: 24)

            Spacer()

            Button {
                Haptics.lightImpact()
                router.presentedSheet = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(NinaTheme.ink)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir ajustes")
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var houseStrip: some View {
        if mineCount > 0 || overdueCount > 0 {
            HStack(spacing: 8) {
                Text("\(mineCount) na sua mão")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(NinaTheme.ink)

                if overdueCount > 0 {
                    Text("·")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(NinaTheme.line)

                    Text(overdueCount == 1 ? "1 atrasada" : "\(overdueCount) atrasadas")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NinaTheme.terracotta)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                NinaTheme.grout,
                in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
            )
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var connectionNotice: some View {
        if let notice = store.ninaConnectionNotice {
            noticeRow(systemName: "wifi.exclamationmark", text: notice)
        } else if store.isUsingLocalNina {
            noticeRow(systemName: "iphone", text: "Modo local. A conversa fica só neste aparelho.")
        }
    }

    private func noticeRow(systemName: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(NinaTheme.ink)

            Text(text)
                .ninaText(.caption, NinaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            NinaTheme.grout,
            in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
        )
    }

    private var capturePrompt: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Joga uma lembrança aqui.")
                .ninaText(.zero)
                .fixedSize(horizontal: false, vertical: true)

            Text("Do jeito que veio na cabeça. Eu leio, monto uma proposta e espero você confirmar. Nada entra na casa sozinho.")
                .ninaText(.label, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.captureExamples, id: \.self) { example in
                    Button {
                        Haptics.lightImpact()
                        sendPreset(example)
                    } label: {
                        NinaChip(text: example)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
            .allowsHitTesting(!store.isNinaResponding)
            .opacity(store.isNinaResponding ? 0.5 : 1)
        }
        .padding(.top, 10)
    }

    private var waitingLine: some View {
        HStack(spacing: 8) {
            NinaMark(size: 10)
            Text(waitingText)
                .ninaText(.caption, NinaTheme.cobalt, weight: .semibold)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    private var waitingText: String {
        switch pendingProposalCount {
        case 1: "A Nina está esperando você."
        case 2: "A Nina está esperando as duas."
        default: "A Nina está esperando as \(pendingProposalCount)."
        }
    }

    private var pendingProposalCount: Int {
        store.messages.reduce(0) { total, message in
            total + message.proposals.count { $0.state == .pending }
        }
    }

    private var openTasks: [TaskItem] {
        store.tasks.filter { $0.kind == .task && !$0.isDone }
    }

    private var mineCount: Int {
        guard let me = store.currentFamilyMember else { return 0 }
        return openTasks.count { $0.ownerMemberID == me.id }
    }

    private var overdueCount: Int {
        openTasks.count { $0.isOverdue() }
    }

    private func sendPreset(_ text: String) {
        Task {
            await store.sendMessage(text)
        }
    }
}

private struct AIMemoryConsentCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NinaMark(size: 48, presence: .listening)

            Text("Antes de eu ler qualquer coisa.")
                .ninaText(.screen)
                .fixedSize(horizontal: false, vertical: true)

            Text("Para eu entender o que você escreve, o texto sai do seu aparelho e vai para um modelo fora do Brasil. Você decide isso por conta própria, e cada adulto da casa decide a dele separado.")
                .ninaText(.label, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                consentLine("Nada do que você manda fica guardado lá. A sua conversa não treina modelo nenhum.")
                consentLine("A sua conversa é só sua. O outro adulto da casa não lê o que você escreve para mim.")
                consentLine("Dá para desligar quando quiser, em Casa · Privacidade. Aí eu paro de ler na hora.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ninaCard(fill: NinaTheme.grout, stroke: .clear)

            NinaButton(
                title: "Aceitar e conversar com a Nina",
                fillsWidth: true,
                isEnabled: !store.isSyncingHome
            ) {
                Haptics.success()
                Task {
                    await store.grantAIMemoryConsent()
                }
            }

            if let error = store.syncErrorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(NinaTheme.ink)

                    Text(error)
                        .ninaText(.caption, NinaTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    NinaTheme.grout,
                    in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
                )
            }

            Text("Sem aceitar, tudo o mais continua funcionando: tarefas, compras, casa. Só a conversa fica desligada.")
                .ninaText(.meta, NinaTheme.faint)
                .fixedSize(horizontal: false, vertical: true)

            NinaButton(title: "Ler a política de privacidade", kind: .quiet) {
                Haptics.selection()
                openURL(NinaLegalLinks.privacyPolicy)
            }
        }
    }

    private func consentLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NinaTheme.ink)
                .frame(width: 16, height: 18)

            Text(text)
                .ninaText(.caption, NinaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ChatInputBar: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router
    @Environment(TabSwipeLock.self) private var tabSwipeLock
    @State private var draft = ""
    @State private var isKeyboardVisible = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var pendingAttachments: [PendingChatAttachment] = []
    @State private var isShowingDocumentPicker = false
    @State private var isShowingDocumentReadingNotice = false
    @State private var isLoadingAttachments = false
    @State private var attachmentError: String?
    @State private var tabSwipeUnlockTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(NinaTheme.line)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                if !pendingAttachments.isEmpty {
                    AttachmentDraftStrip(
                        attachments: pendingAttachments,
                        onRemove: removeAttachment
                    )
                    .simultaneousGesture(tabSwipeDragLock)
                    .onDisappear(perform: unlockTabSwipeImmediately)
                }

                if let attachmentError {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(NinaTheme.ink)

                        Text(attachmentError)
                            .ninaText(.meta, NinaTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        NinaTheme.grout,
                        in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
                    )
                }

                attachmentControls

                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Escreve pra Nina", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(NinaTheme.ink)
                        .tint(NinaTheme.cobalt)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .frame(minHeight: 46, alignment: .leading)
                        .background(
                            NinaTheme.grout,
                            in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
                        )
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.send)
                        .onSubmit(sendDraft)
                        .disabled(store.isNinaResponding)
                        .opacity(store.isNinaResponding ? 0.55 : 1)
                        .transaction { transaction in
                            transaction.animation = nil
                        }

                    Button(action: sendDraft) {
                        Image(systemName: store.isNinaResponding ? "ellipsis" : "arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(canSend ? NinaTheme.onCobalt : NinaTheme.muted)
                            .frame(width: 46, height: 46)
                            .background(canSend ? NinaTheme.cobalt : NinaTheme.grout, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.6)
                    .accessibilityLabel("Enviar mensagem")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)

            footerNote
        }
        .padding(.bottom, isKeyboardVisible ? 8 : 92)
        .background(NinaTheme.ground)
        .transaction { transaction in
            transaction.animation = nil
        }
        .tracksKeyboardVisibility($isKeyboardVisible)
        .fileImporter(
            isPresented: $isShowingDocumentPicker,
            allowedContentTypes: ChatAttachmentLimits.supportedDocumentTypes,
            allowsMultipleSelection: true,
            onCompletion: loadDocuments
        )
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            loadPhotos(items)
        }
        .onChange(of: canReadDocuments) { _, isAllowed in
            guard !isAllowed, !pendingAttachments.isEmpty else { return }
            pendingAttachments = []
            attachmentError = "A leitura de documentos faz parte do Premium da casa."
        }
    }

    @ViewBuilder
    private var attachmentControls: some View {
        HStack(spacing: 8) {
            if canReadDocuments {
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: max(remainingAttachmentSlots, 1),
                    matching: .images
                ) {
                    NinaChip(text: "Foto", systemName: "photo", isDisabled: !canAttach)
                }
                .buttonStyle(.plain)
                .disabled(!canAttach)
                .accessibilityLabel("Adicionar fotos")

                Button {
                    Haptics.lightImpact()
                    isShowingDocumentPicker = true
                } label: {
                    NinaChip(
                        text: isLoadingAttachments ? "Abrindo" : "Documento",
                        systemName: "paperclip",
                        isDisabled: !canAttach
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canAttach)
                .accessibilityLabel("Adicionar documento")
            } else {
                documentReadingChip
            }

            Spacer(minLength: 0)
        }
    }

    private var documentReadingChip: some View {
        Button {
            Haptics.lightImpact()
            isShowingDocumentReadingNotice = true
        } label: {
            NinaChip(text: "Documentos", systemName: "lock")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Leitura de documentos")
        .accessibilityHint("Explica por que enviar foto e documento faz parte do Premium")
        .popover(isPresented: $isShowingDocumentReadingNotice, arrowEdge: .bottom) {
            PremiumGateCard(
                title: "Ver o Premium",
                detail: "Ler boleto, receita e comunicado por foto faz parte do Premium da casa. Sem ele, o envio de foto e documento fica desligado por aqui."
            ) {
                Haptics.lightImpact()
                isShowingDocumentReadingNotice = false
                router.presentedSheet = .premium
            }
            .padding(14)
            .frame(width: 330)
            .ninaSheetBackground()
            .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder
    private var footerNote: some View {
        if !pendingAttachments.isEmpty {
            footerLine(
                systemName: "lock",
                text: "A foto não fica guardada em nenhum servidor. O que sobra é o que eu leio dela, e uma miniatura no seu aparelho."
            )
        } else if hasPendingProposals {
            footerLine(
                systemName: "info.circle",
                text: "A Nina pode ler errado. Nada entra na casa até você confirmar cada uma."
            )
        }
    }

    private func footerLine(systemName: String, text: String) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(NinaTheme.line)
                .frame(height: 1)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(NinaTheme.faint)

                Text(text)
                    .ninaText(.micro, NinaTheme.faint)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .accessibilityElement(children: .combine)
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canReadDocuments: Bool {
        store.householdPremium.isActive
    }

    private var remainingAttachmentSlots: Int {
        max(ChatAttachmentLimits.maxCount - pendingAttachments.count, 0)
    }

    private var canAttach: Bool {
        !store.isNinaResponding && !isLoadingAttachments && remainingAttachmentSlots > 0
    }

    private var canSend: Bool {
        (!trimmedDraft.isEmpty || !pendingAttachments.isEmpty)
            && store.canSendNinaMessages
            && !store.isNinaResponding
            && !isLoadingAttachments
    }

    private var hasPendingProposals: Bool {
        store.messages.contains { message in
            message.proposals.contains { $0.state == .pending }
        }
    }

    private var tabSwipeDragLock: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard isHorizontalDrag(value.translation) else { return }
                tabSwipeUnlockTask?.cancel()
                tabSwipeUnlockTask = nil
                tabSwipeLock.isLocked = true
            }
            .onEnded { _ in
                scheduleTabSwipeUnlock()
            }
    }

    private func isHorizontalDrag(_ translation: CGSize) -> Bool {
        abs(translation.width) > 8 && abs(translation.width) > abs(translation.height)
    }

    private func scheduleTabSwipeUnlock() {
        tabSwipeUnlockTask?.cancel()
        tabSwipeUnlockTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            tabSwipeLock.isLocked = false
            tabSwipeUnlockTask = nil
        }
    }

    private func unlockTabSwipeImmediately() {
        tabSwipeUnlockTask?.cancel()
        tabSwipeUnlockTask = nil
        tabSwipeLock.isLocked = false
    }

    private func sendDraft() {
        let text = trimmedDraft
        guard canSend else { return }

        Haptics.lightImpact()
        let attachments = pendingAttachments.map(\.input)
        draft = ""
        pendingAttachments = []
        attachmentError = nil

        Task {
            await store.sendMessage(text, attachments: attachments)
        }
    }

    private func removeAttachment(_ attachment: PendingChatAttachment) {
        Haptics.selection()
        pendingAttachments.removeAll { $0.id == attachment.id }
        attachmentError = nil
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        let availableSlots = remainingAttachmentSlots
        guard availableSlots > 0 else {
            selectedPhotoItems = []
            attachmentError = ChatAttachmentLimits.countError
            return
        }

        isLoadingAttachments = true
        attachmentError = nil
        let startingIndex = pendingAttachments.count

        Task {
            var loaded: [PendingChatAttachment] = []
            var loadError: String?

            for (index, item) in items.prefix(availableSlots).enumerated() {
                do {
                    guard let sourceData = try await item.loadTransferable(type: Data.self) else {
                        throw ChatAttachmentLoadError.unreadable
                    }

                    let imageData = try normalizedImageData(sourceData)
                    let metadata = ChatAttachment(
                        kind: .image,
                        filename: "foto-\(startingIndex + index + 1).jpg",
                        mimeType: "image/jpeg",
                        byteCount: imageData.full.count,
                        thumbnailData: imageData.thumbnail
                    )
                    loaded.append(PendingChatAttachment(metadata: metadata, data: imageData.full))
                } catch {
                    loadError = "Não foi possível carregar uma das fotos."
                }
            }

            await MainActor.run {
                appendAttachments(loaded)
                selectedPhotoItems = []
                isLoadingAttachments = false
                if let loadError {
                    attachmentError = loadError
                    Haptics.error()
                }
            }
        }
    }

    private func loadDocuments(_ result: Result<[URL], Error>) {
        switch result {
        case .failure:
            attachmentError = "Não foi possível abrir o seletor de documentos."
            Haptics.error()
        case .success(let urls):
            let availableSlots = remainingAttachmentSlots
            guard availableSlots > 0 else {
                attachmentError = ChatAttachmentLimits.countError
                return
            }

            isLoadingAttachments = true
            attachmentError = nil

            Task {
                var loaded: [PendingChatAttachment] = []
                var loadError: String?

                for url in urls.prefix(availableSlots) {
                    do {
                        loaded.append(try loadDocument(at: url))
                    } catch let error as ChatAttachmentLoadError {
                        loadError = error.message
                    } catch {
                        loadError = "Não foi possível carregar um dos documentos."
                    }
                }

                await MainActor.run {
                    appendAttachments(loaded)
                    isLoadingAttachments = false
                    if let loadError {
                        attachmentError = loadError
                        Haptics.error()
                    }
                }
            }
        }
    }

    private func appendAttachments(_ attachments: [PendingChatAttachment]) {
        for attachment in attachments {
            guard pendingAttachments.count < ChatAttachmentLimits.maxCount else {
                attachmentError = ChatAttachmentLimits.countError
                return
            }

            guard attachment.data.count <= ChatAttachmentLimits.maxItemBytes else {
                attachmentError = ChatAttachmentLimits.itemSizeError
                continue
            }

            let nextTotal = pendingAttachments.reduce(0) { $0 + $1.data.count }
                + attachment.data.count
            guard nextTotal <= ChatAttachmentLimits.maxTotalBytes else {
                attachmentError = ChatAttachmentLimits.totalSizeError
                continue
            }

            pendingAttachments.append(attachment)
            Haptics.success()
        }
    }

    private func normalizedImageData(_ data: Data) throws -> (full: Data, thumbnail: Data?) {
        #if canImport(UIKit)
        guard let sourceImage = UIImage(data: data) else {
            throw ChatAttachmentLoadError.unreadable
        }

        let fullImage = sourceImage.resizedToFit(maxSide: 1_800)
        guard let fullData = fullImage.jpegData(compressionQuality: 0.82) else {
            throw ChatAttachmentLoadError.unreadable
        }

        return (fullData, ChatAttachmentLimits.retainedThumbnailData(for: sourceImage))
        #else
        return (data, nil)
        #endif
    }

    private func loadDocument(at url: URL) throws -> PendingChatAttachment {
        let didAccessResource = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileExtension = url.pathExtension.lowercased()
        guard let mimeType = ChatAttachmentLimits.mimeType(for: fileExtension) else {
            throw ChatAttachmentLoadError.unsupported
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= ChatAttachmentLimits.maxItemBytes else {
            throw ChatAttachmentLoadError.tooLarge
        }

        let metadata = ChatAttachment(
            kind: .document,
            filename: String(url.lastPathComponent.prefix(180)),
            mimeType: mimeType,
            byteCount: data.count
        )
        return PendingChatAttachment(metadata: metadata, data: data)
    }
}

private struct PendingChatAttachment: Identifiable, Hashable {
    var metadata: ChatAttachment
    var data: Data

    var id: ChatAttachment.ID { metadata.id }

    var input: NinaAttachmentInput {
        NinaAttachmentInput(metadata: metadata, data: data)
    }
}

enum ChatAttachmentLimits {
    static let maxCount = 3
    static let maxItemBytes = 5 * 1_024 * 1_024
    static let maxTotalBytes = 8 * 1_024 * 1_024

    // A photographed boleto has to stay readable, and it is also the most sensitive thing this app
    // keeps at rest, so every retained thumbnail is bounded: under the ceiling or not kept at all.
    static let maxThumbnailBytes = 320 * 1_024

    #if canImport(UIKit)
    private static let thumbnailAttempts: [(maxSide: CGFloat, quality: CGFloat)] = [
        (900, 0.7),
        (900, 0.5),
        (640, 0.45)
    ]

    static func retainedThumbnailData(for image: UIImage) -> Data? {
        for attempt in thumbnailAttempts {
            guard let data = image
                .resizedToFit(maxSide: attempt.maxSide)
                .jpegData(compressionQuality: attempt.quality) else {
                continue
            }
            if data.count <= maxThumbnailBytes {
                return data
            }
        }
        return nil
    }
    #endif

    static let countError = "Você pode enviar até 3 anexos por mensagem."
    static let itemSizeError = "Cada anexo pode ter até 5 MB."
    static let totalSizeError = "Os anexos juntos podem ter até 8 MB."

    static let supportedDocumentTypes: [UTType] = {
        let extensions = [
            "pdf", "txt", "md", "json", "html", "xml", "rtf",
            "csv", "tsv", "doc", "docx", "odt", "pages",
            "xls", "xlsx", "ppt", "pptx"
        ]
        return extensions.compactMap { UTType(filenameExtension: $0) }
    }()

    private static let mimeTypes: [String: String] = [
        "pdf": "application/pdf",
        "txt": "text/plain",
        "md": "text/markdown",
        "json": "application/json",
        "html": "text/html",
        "xml": "text/xml",
        "rtf": "application/rtf",
        "csv": "text/csv",
        "tsv": "text/tab-separated-values",
        "doc": "application/msword",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "odt": "application/vnd.oasis.opendocument.text",
        "pages": "application/vnd.apple.pages",
        "xls": "application/vnd.ms-excel",
        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "ppt": "application/vnd.ms-powerpoint",
        "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    ]

    static func mimeType(for fileExtension: String) -> String? {
        mimeTypes[fileExtension]
    }
}

private enum ChatAttachmentLoadError: Error {
    case unreadable
    case unsupported
    case tooLarge

    var message: String {
        switch self {
        case .unreadable:
            "Não foi possível ler esse arquivo."
        case .unsupported:
            "Esse tipo de documento ainda não é compatível."
        case .tooLarge:
            ChatAttachmentLimits.itemSizeError
        }
    }
}

private struct AttachmentDraftStrip: View {
    var attachments: [PendingChatAttachment]
    var onRemove: (PendingChatAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentDraftChip(attachment: attachment) {
                        onRemove(attachment)
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }
}

private struct AttachmentDraftChip: View {
    var attachment: PendingChatAttachment
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            attachmentPreview

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.metadata.filename)
                    .ninaText(.meta, NinaTheme.ink, weight: .semibold)
                    .lineLimit(1)

                Text(attachment.metadata.byteCount.formattedFileSize)
                    .ninaText(.micro, NinaTheme.muted)
            }

            Spacer(minLength: 4)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NinaTheme.muted)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remover \(attachment.metadata.filename)")
        }
        .padding(8)
        .frame(width: 214, alignment: .leading)
        .background(
            NinaTheme.grout,
            in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
        )
    }

    @ViewBuilder
    private var attachmentPreview: some View {
        if attachment.metadata.kind == .image,
           let data = attachment.metadata.thumbnailData,
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            CategoryGlyph(systemName: "doc", size: 16, tint: NinaTheme.muted)
                .frame(width: 40, height: 40)
                .background(
                    NinaTheme.ground,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
    }
}

private struct NinaTypingBubble: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            NinaMark(size: 22, presence: .reading)
                .padding(.top, 4)

            Text("A Nina está lendo")
                .ninaText(.caption, NinaTheme.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    NinaTheme.grout,
                    in: RoundedRectangle(cornerRadius: NinaTheme.Radius.card, style: .continuous)
                )

            Spacer(minLength: 40)
        }
    }
}

private struct MessageBubble: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router
    var message: ChatMessage

    private var isNina: Bool {
        message.sender == .nina
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isNina {
                NinaMark(size: 22)
                    .padding(.top, 4)
            } else {
                Spacer(minLength: 44)
            }

            VStack(alignment: isNina ? .leading : .trailing, spacing: 12) {
                bubble
                    .frame(maxWidth: 268, alignment: isNina ? .leading : .trailing)

                ForEach(message.proposals) { proposal in
                    NinaProposalCard(proposal: proposal)
                }

                if message.hasWithheldProposals {
                    WithheldProposalsCard()
                }

                if let premiumCeiling {
                    PremiumGateCard(title: "Ver o Premium", detail: premiumCeiling) {
                        Haptics.lightImpact()
                        router.presentedSheet = .premium
                    }
                }

                if let suggestion = message.suggestion {
                    SuggestionMiniCard(suggestion: suggestion)
                }
            }
            .frame(maxWidth: .infinity, alignment: isNina ? .leading : .trailing)
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !message.attachments.isEmpty {
                MessageAttachmentsView(
                    attachments: message.attachments,
                    isNina: isNina
                )
            }

            if !message.text.isEmpty {
                Text(message.text)
                    .ninaText(.body, isNina ? NinaTheme.ink : NinaTheme.ground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            isNina ? NinaTheme.cobaltWash : NinaTheme.ink,
            in: RoundedRectangle(cornerRadius: NinaTheme.Radius.card, style: .continuous)
        )
    }

    // A server denial arrives as an ordinary Nina line, so the ceiling it names is recovered here:
    // a refusal this household can lift must carry the route, never end the conversation.
    private var premiumCeiling: String? {
        guard isNina, !store.householdPremium.isActive else { return nil }
        if message.text == NinaEngineError.attachmentsRequirePremium.userMessage {
            return "Ler boleto, receita e comunicado por foto faz parte do Premium da casa."
        }
        if message.text == NinaEngineError.rateLimited.userMessage {
            return "No Premium são 30 mensagens por hora, e não 10 por dia."
        }
        return nil
    }
}

private struct MessageAttachmentsView: View {
    var attachments: [ChatAttachment]
    var isNina: Bool

    @State private var openedAttachment: ChatAttachment?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(attachments) { attachment in
                if attachment.kind == .image,
                   let data = attachment.thumbnailData,
                   let image = UIImage(data: data) {
                    Button {
                        Haptics.lightImpact()
                        openedAttachment = attachment
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: 230, minHeight: 120, maxHeight: 150)
                                .clipShape(RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous))

                            Text(attachment.filename)
                                .ninaText(.micro, isNina ? NinaTheme.muted : NinaTheme.ground.opacity(0.72))
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Abrir \(attachment.filename)")
                    .accessibilityHint("Mostra a foto em tela cheia para você conferir")
                } else {
                    HStack(spacing: 10) {
                        CategoryGlyph(
                            systemName: attachment.kind == .image ? "photo" : "doc",
                            size: 16,
                            tint: isNina ? NinaTheme.muted : NinaTheme.ground
                        )
                        .frame(width: 34, height: 34)
                        .background(
                            isNina ? NinaTheme.ground : NinaTheme.ground.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.filename)
                                .ninaText(.meta, isNina ? NinaTheme.ink : NinaTheme.ground, weight: .semibold)
                                .lineLimit(1)

                            Text(attachment.byteCount.formattedFileSize)
                                .ninaText(.micro, isNina ? NinaTheme.muted : NinaTheme.ground.opacity(0.72))
                        }
                    }
                    .padding(8)
                    .background(
                        isNina ? NinaTheme.ground : NinaTheme.ground.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
                    )
                }
            }
        }
        .fullScreenCover(item: $openedAttachment) { attachment in
            AttachmentImageViewer(attachment: attachment) {
                Haptics.selection()
                openedAttachment = nil
            }
        }
    }
}

// The photographed document never leaves the device to be read: the viewer opens the thumbnail
// this phone already holds, and nothing here reaches the network.
private struct AttachmentImageViewer: View {
    var attachment: ChatAttachment
    var onClose: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var settledPan: CGSize = .zero

    private static let maximumZoom: CGFloat = 4

    var body: some View {
        ZStack {
            NinaTheme.ink.ignoresSafeArea()

            if let data = attachment.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoom)
                    .offset(pan)
                    .gesture(inspectionGesture)
                    .onTapGesture(count: 2, perform: resetInspection)
                    .accessibilityLabel(attachment.filename)
            } else {
                Text("Não consigo abrir essa foto agora.")
                    .ninaText(.label, NinaTheme.ground)
            }
        }
        .overlay(alignment: .top) { viewerBar }
        .statusBarHidden()
    }

    private var viewerBar: some View {
        HStack(spacing: 12) {
            Text(attachment.filename)
                .ninaText(.caption, NinaTheme.ground, weight: .semibold)
                .lineLimit(1)

            Spacer(minLength: 12)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NinaTheme.ground)
                    .frame(width: 38, height: 38)
                    .background(NinaTheme.ground.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fechar a foto")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var inspectionGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(max(settledZoom * value.magnification, 1), Self.maximumZoom)
            }
            .onEnded { _ in
                settledZoom = zoom
                if zoom == 1 {
                    pan = .zero
                    settledPan = .zero
                }
            }
            .simultaneously(
                with: DragGesture()
                    .onChanged { value in
                        guard zoom > 1 else { return }
                        pan = CGSize(
                            width: settledPan.width + value.translation.width,
                            height: settledPan.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        settledPan = pan
                    }
            )
    }

    private func resetInspection() {
        Haptics.selection()
        zoom = 1
        settledZoom = 1
        pan = .zero
        settledPan = .zero
    }
}

private struct NinaProposalCard: View {
    @Environment(AppStore.self) private var store
    var proposal: NinaProposal

    @State private var draftTitle: String
    @State private var draftDetail: String
    @State private var draftOwner: String
    @State private var draftDueLabel: String
    @State private var draftAmount: String
    @State private var isEditing = false
    @State private var isResolving = false
    @State private var isConfirmingShare = false

    init(proposal: NinaProposal) {
        self.proposal = proposal
        _draftTitle = State(initialValue: proposal.payload.title)
        _draftDetail = State(initialValue: proposal.payload.detail)
        _draftOwner = State(initialValue: proposal.payload.owner)
        _draftDueLabel = State(initialValue: proposal.payload.dueLabel)
        _draftAmount = State(initialValue: proposal.payload.amount)
    }

    var body: some View {
        VStack(spacing: 0) {
            if proposal.state == .pending {
                banner
            }

            face

            actions
        }
        .clipShape(RoundedRectangle(cornerRadius: NinaTheme.Radius.card, style: .continuous))
        .ninaCard()
        .disabled(isResolving)
        .opacity(isResolving ? 0.55 : 1)
        .alert("Compartilhar com a casa?", isPresented: $isConfirmingShare) {
            Button("Compartilhar") {
                resolve(decision: .accept, memoryVisibility: .shared)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(shareWarning)
        }
    }

    private var banner: some View {
        HStack(spacing: 8) {
            Image(systemName: proposal.kind == .memory ? "lock" : "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NinaTheme.faint)

            Eyebrow(text: proposal.kind == .memory ? "Memória · ainda não guardada" : "Isto ainda não existe")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NinaTheme.grout)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NinaTheme.line).frame(height: 1)
        }
    }

    private var face: some View {
        VStack(alignment: .leading, spacing: 12) {
            objectRow

            if !confirmationPayload.detail.isEmpty {
                Text(confirmationPayload.detail)
                    .ninaText(.caption, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if proposal.kind == .memory, proposal.state == .pending {
                NinaButton(title: isEditing ? "Fechar" : "Corrigir o texto", kind: .outline) {
                    Haptics.selection()
                    isEditing.toggle()
                }
            }

            proposalBasis

            extractedReadings

            if isEditing && proposal.state == .pending {
                VStack(spacing: 8) {
                    proposalField("Título", text: $draftTitle)
                    proposalField("Detalhes", text: $draftDetail)
                    if proposal.kind != .memory {
                        proposalField("Responsável", text: $draftOwner)
                        if !isSeed {
                            proposalField("Quando", text: $draftDueLabel)
                        }
                    }
                    if proposal.kind == .shopping {
                        proposalField("Quantidade", text: $draftAmount)
                    }
                }
            }

            decisiveRows
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NinaTheme.ground)
    }

    // The card draws the real object — the same checkbox and the same category glyph a task row
    // carries — so what a person confirms is what the house is about to get.
    private var objectRow: some View {
        HStack(alignment: .top, spacing: 12) {
            if isSeed {
                CategoryGlyph(systemName: "leaf", size: 18, tint: NinaTheme.ink)
            } else if proposal.kind != .memory {
                NinaCheckbox(isOn: false, size: 22)
                    .padding(.top, 1)
            }

            objectTitle
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if isSeed {
                Eyebrow(text: TaskKind.seed.title)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(NinaTheme.grout, in: Capsule())
            } else if proposal.kind != .memory {
                HStack(spacing: 6) {
                    CategoryGlyph(
                        systemName: confirmationPayload.category.symbolName,
                        size: 14,
                        tint: NinaTheme.muted
                    )
                    Text(confirmationPayload.category.title)
                        .ninaText(.meta, NinaTheme.muted)
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var objectTitle: some View {
        if proposal.kind == .memory {
            Text(confirmationPayload.title).ninaText(.section)
        } else {
            Text(confirmationPayload.title)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.1)
                .foregroundStyle(NinaTheme.ink)
        }
    }

    private var confirmationPayload: NinaProposalPayload {
        proposal.confirmationPayload(
            title: draftTitle,
            detail: draftDetail,
            owner: draftOwner,
            dueLabel: draftDueLabel,
            amount: draftAmount
        )
    }

    private var isSeed: Bool {
        proposal.kind == .seed
    }

    // The basis says where a proposal came from; how sure Nina is never joins it, because a score
    // on a household suggestion reads as a verdict on the house instead of a portrait of it.
    @ViewBuilder
    private var proposalBasis: some View {
        if proposal.payload.source != nil || !proposal.payload.rationale.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                if let source = proposal.payload.source {
                    HStack(spacing: 6) {
                        Image(systemName: source.symbolName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NinaTheme.muted)
                        Text(source.title)
                            .ninaText(.micro, NinaTheme.muted, weight: .semibold)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(NinaTheme.grout, in: Capsule())
                }

                if !proposal.payload.rationale.isEmpty {
                    Text(proposal.payload.rationale)
                        .ninaText(.meta, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(basisAccessibilityLabel)
        }
    }

    private var basisAccessibilityLabel: String {
        [proposal.payload.source?.title, proposal.payload.rationale]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    // What Nina read is evidence, not a field: it keeps showing the document's own wording so a
    // misread vencimento can be caught against it while the proposal is still correctable.
    @ViewBuilder
    private var extractedReadings: some View {
        if !proposal.payload.extracted.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "eye")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NinaTheme.faint)
                    Eyebrow(text: "O que eu li")
                    Spacer(minLength: 0)
                }

                VStack(spacing: 0) {
                    ForEach(proposal.payload.extracted.indices, id: \.self) { index in
                        if index > 0 {
                            NinaDivider(inset: 0)
                        }
                        extractedReadingRow(proposal.payload.extracted[index])
                    }
                }

                if proposal.state == .pending {
                    Text("Corrija se eu tiver lido errado.")
                        .ninaText(.meta, NinaTheme.muted)
                }

                if confirmationPayload.category.id == TaskCategory.bills.id {
                    Text("Eu não copio a linha digitável. Para pagar, você abre o boleto no banco, porque este cartão não serve para isso.")
                        .ninaText(.meta, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ninaCard(radius: NinaTheme.Radius.field, fill: NinaTheme.grout, stroke: .clear)
        }
    }

    private func extractedReadingRow(_ reading: NinaExtractedReading) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(reading.label)
                .ninaText(.caption, NinaTheme.muted)

            Spacer(minLength: 8)

            Text(reading.value)
                .ninaText(.label, NinaTheme.ink, weight: .semibold)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 38)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(reading.label): \(reading.value)")
    }

    // Quando, Repete and Dono are decided on the card face: a field kept behind the correction
    // toggle would let a person confirm a date they never saw.
    @ViewBuilder
    private var decisiveRows: some View {
        if proposal.kind != .memory {
            VStack(spacing: 0) {
                NinaDivider(inset: 0)

                decisiveRow("Quando") {
                    Text(scheduleValue)
                        .ninaText(.label, isSeed ? NinaTheme.muted : NinaTheme.ink)
                }

                if proposal.kind == .task || proposal.kind == .reminder {
                    NinaDivider(inset: 0)
                    decisiveRow("Repete") {
                        Text("Não repete").ninaText(.label)
                    }
                }

                NinaDivider(inset: 0)

                decisiveRow("Dono") {
                    Text(ownerValue).ninaText(.label)
                }

                if proposal.kind == .shopping, !confirmationPayload.amount.isEmpty {
                    NinaDivider(inset: 0)
                    decisiveRow("Quantidade") {
                        Text(confirmationPayload.amount).ninaText(.label)
                    }
                }
            }
        }
    }

    private func decisiveRow<V: View>(_ label: String, @ViewBuilder value: () -> V) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .ninaText(.caption, NinaTheme.muted)
                .frame(width: 86, alignment: .leading)
            value()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 42)
        .accessibilityElement(children: .combine)
    }

    private var scheduleValue: String {
        if isSeed {
            return "sem data, e tudo bem"
        }
        guard confirmationPayload.dueAt != nil else {
            return "\(confirmationPayload.dueLabel) · sem lembrete"
        }
        return confirmationPayload.dueLabel
    }

    private var ownerValue: String {
        HouseholdWorkload.isSharedOwner(confirmationPayload.owner)
            ? "A casa, por enquanto"
            : confirmationPayload.owner
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if proposal.state == .pending {
                if proposal.kind == .memory {
                    memoryActions
                } else {
                    standardActions
                }
            } else {
                resolvedLine
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NinaTheme.grout)
        .overlay(alignment: .top) {
            Rectangle().fill(NinaTheme.line).frame(height: 1)
        }
    }

    private var standardActions: some View {
        VStack(spacing: 8) {
            NinaButton(title: proposal.actionTitle, fillsWidth: true) {
                resolve(decision: .accept)
            }

            HStack(spacing: 8) {
                NinaButton(
                    title: isEditing ? "Fechar" : correctionTitle,
                    kind: .outline,
                    fillsWidth: true
                ) {
                    Haptics.selection()
                    isEditing.toggle()
                }

                NinaButton(title: "Não", kind: .quiet, fillsWidth: true) {
                    resolve(decision: .reject)
                }
                .frame(height: 50)
            }
        }
    }

    private var correctionTitle: String {
        proposal.payload.extracted.isEmpty ? "Corrigir" : "Corrigir o que li"
    }

    // Sharing is the one move nobody can take back, so it names who gains the reading and asks
    // again; keeping it for yourself stays the single tap.
    private var memoryActions: some View {
        VStack(spacing: 8) {
            NinaButton(title: "Guardar só para mim", systemName: "lock", fillsWidth: true) {
                resolve(decision: .accept, memoryVisibility: .privateMemory)
            }

            NinaButton(title: "Compartilhar com a casa", kind: .outline, fillsWidth: true) {
                Haptics.warning()
                isConfirmingShare = true
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(NinaTheme.faint)

                Text(shareWarning)
                    .ninaText(.meta, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.top, 2)

            NinaButton(title: "Não guardar nada", kind: .quiet, fillsWidth: true) {
                resolve(decision: .reject)
            }
            .padding(.top, 4)
        }
    }

    private var shareWarning: String {
        let others = store.familyGroup.members.filter {
            $0.role == .adult && $0.id != store.currentFamilyMember?.id
        }
        if others.count == 1, let other = others.first, !other.name.firstWord.isEmpty {
            return "Compartilhar não tem volta. \(other.name.firstWord) vai poder ler, e tirar depois não desfaz a leitura."
        }
        if others.isEmpty {
            return "Compartilhar não tem volta. Quem entrar na casa depois vai poder ler."
        }
        return "Compartilhar não tem volta. Os outros adultos da casa vão poder ler, e tirar depois não desfaz a leitura."
    }

    private var resolvedLine: some View {
        HStack(spacing: 8) {
            Image(systemName: proposal.state == .accepted ? "checkmark" : "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(proposal.state == .accepted ? NinaTheme.moss : NinaTheme.muted)

            Text(resolvedText)
                .ninaText(
                    .caption,
                    proposal.state == .accepted ? NinaTheme.moss : NinaTheme.muted,
                    weight: .semibold
                )
        }
        .accessibilityElement(children: .combine)
    }

    private var resolvedText: String {
        guard proposal.state == .accepted else { return "Você disse que não." }
        return proposal.kind == .memory ? "Você guardou." : "Você confirmou."
    }

    private func proposalField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(NinaTheme.ink)
            .tint(NinaTheme.cobalt)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(
                NinaTheme.grout,
                in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
            )
    }

    private func resolve(
        decision: NinaProposalDecision,
        memoryVisibility: NinaMemoryVisibility? = nil
    ) {
        isResolving = true
        let payload = confirmationPayload

        Task {
            _ = await store.resolveProposal(
                proposal,
                decision: decision,
                editedPayload: decision == .accept ? payload : nil,
                memoryVisibility: memoryVisibility
            )
            isResolving = false
        }
    }
}

private struct WithheldProposalsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hourglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NinaTheme.faint)
                Eyebrow(text: "Confirmação ainda fechada")
                Spacer(minLength: 0)
            }

            Text("Entendi algo para organizar, mas nesta versão a confirmação ainda não abre. Nada entra na casa até ela abrir.")
                .ninaText(.caption, NinaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard(fill: NinaTheme.grout, stroke: .clear)
        .accessibilityElement(children: .combine)
    }
}

private struct SuggestionMiniCard: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router
    var suggestion: NinaSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                NinaCheckbox(isOn: false, size: 22)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.title)
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.1)
                        .foregroundStyle(NinaTheme.ink)

                    Text(suggestion.detail)
                        .ninaText(.caption, NinaTheme.muted)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                CategoryGlyph(
                    systemName: suggestion.category.symbolName,
                    size: 14,
                    tint: NinaTheme.muted
                )
                .padding(.top, 2)
            }

            NinaButton(title: suggestion.actionTitle, fillsWidth: true) {
                Haptics.success()
                store.applySuggestion(suggestion)
            }

            NinaButton(title: "Ver os detalhes", kind: .quiet, fillsWidth: true) {
                Haptics.lightImpact()
                router.presentedSheet = .suggestion(suggestion)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaCard()
    }
}

#if canImport(UIKit)
private extension UIImage {
    func resizedToFit(maxSide: CGFloat) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxSide, longestSide > 0 else { return self }

        let scale = maxSide / longestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
#endif

private extension Int {
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}

#Preview {
    NinaChatView()
        .environment(AppStore())
        .environment(RouterPath())
        .environment(TabSwipeLock())
}
