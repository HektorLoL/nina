import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

struct NinaChatView: View {
    @Environment(AppStore.self) private var store
    @Environment(TabSwipeLock.self) private var tabSwipeLock
    @State private var tabSwipeUnlockTask: Task<Void, Never>?
    @State private var didLoadInitialMessages = false

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
        .navigationTitle("Nina")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var consentContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                AIMemoryConsentCard()
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 104)
        }
    }

    private var chatContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    connectionNotice
                    quickPrompts

                    LazyVStack(spacing: 14) {
                        ForEach(store.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if store.isNinaResponding {
                            NinaTypingBubble()
                                .id("nina-typing")
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChatInputBar()
        }
    }

    private var adultOnlyContent: some View {
        VStack(spacing: 18) {
            Spacer()

            NinaAvatarView(size: 86)

            VStack(spacing: 8) {
                Text("Conversa disponível para adultos")
                    .font(.title3.weight(.black))
                    .foregroundStyle(NinaTheme.ink)

                Text("Tarefas e informações compartilhadas da casa continuam visíveis, mas a conversa privada com a Nina é restrita aos adultos.")
                    .font(.subheadline)
                    .foregroundStyle(NinaTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(28)
    }

    private var header: some View {
        SoftCard(padding: 18) {
            HStack(spacing: 16) {
                NinaAvatarView(size: 78)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Oi, eu sou a Nina")
                        .font(.title2.weight(.black))
                        .foregroundStyle(NinaTheme.ink)

                    Text("Escreva, envie uma foto ou anexe um documento. Eu ajudo a organizar.")
                        .font(.subheadline)
                        .foregroundStyle(NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Label(store.familyGroup.name, systemImage: "house.fill")
                Spacer(minLength: 12)
                Label(
                    store.isUsingLocalNina ? "modo local, sem memória durável" : "conversa privada",
                    systemImage: store.isUsingLocalNina ? "iphone" : "lock.fill"
                )
            }
            .frame(maxWidth: .infinity)
            .font(.caption.weight(.heavy))
            .foregroundStyle(NinaTheme.mint)
        }
    }

    @ViewBuilder
    private var connectionNotice: some View {
        if let notice = store.ninaConnectionNotice {
            Label(notice, systemImage: "wifi.exclamationmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var quickPrompts: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Jogue uma lembrança aqui", subtitle: "A Nina organiza sem você precisar escolher categoria.")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    QuickChip(title: "Veterinário do Thor", systemName: "pawprint.fill", tone: .lavender) {
                        sendPreset("Lembrar de marcar veterinário para o Thor.")
                    }

                    QuickChip(title: "Gás acaba em 10 dias", systemName: "flame.fill", tone: .coral) {
                        sendPreset("O gás acaba daqui uns 10 dias.")
                    }

                    QuickChip(title: "Aniversário da minha mãe", systemName: "gift.fill", tone: .amber) {
                        sendPreset("Minha mãe faz aniversário semana que vem.")
                    }

                    QuickChip(title: "Receita médica", systemName: "pills.fill", tone: .mint) {
                        sendPreset("Tenho uma foto de receita médica para organizar.")
                    }
                }
                .padding(.vertical, 2)
            }
            .simultaneousGesture(quickPromptDragLock)
            .onDisappear(perform: unlockTabSwipeImmediately)
            .allowsHitTesting(!store.isNinaResponding)
            .opacity(store.isNinaResponding ? 0.58 : 1)
        }
    }

    private var quickPromptDragLock: some Gesture {
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

    private func sendPreset(_ text: String) {
        Task {
            await store.sendMessage(text)
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
}

private struct AIMemoryConsentCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        SoftCard(padding: 18) {
            HStack(alignment: .top, spacing: 14) {
                IconBubble(systemName: "lock.shield.fill", tone: .mint, size: 50)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Antes de conversar")
                        .font(.title3.weight(.black))
                        .foregroundStyle(NinaTheme.ink)

                    Text("A Nina usa suas mensagens, anexos e dados confirmados da casa para responder, sugerir tarefas e propor memórias. Nada vira tarefa ou memória sem sua confirmação.")
                        .font(.subheadline)
                        .foregroundStyle(NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ConsentLine(systemName: "person.fill", text: "Memórias pessoais começam privadas.")
                ConsentLine(systemName: "person.2.fill", text: "Compartilhar uma memória com a casa é sempre uma escolha explícita.")
                ConsentLine(systemName: "trash.fill", text: "Você pode apagar seu histórico privado e revogar este consentimento em Ajustes.")
            }

            PrimaryCapsuleButton(title: "Aceitar e conversar", systemName: "checkmark.shield.fill") {
                Haptics.success()
                store.grantAIMemoryConsent()
            }

            Text("Ao aceitar, você permite esse processamento para recursos de IA e memória da Nina. Você pode continuar usando tarefas e casa sem aceitar.")
                .font(.caption.weight(.bold))
                .foregroundStyle(NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ConsentLine: View {
    var systemName: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemName)
                .font(.caption.weight(.black))
                .foregroundStyle(NinaTheme.mint)
                .frame(width: 18, height: 18)

            Text(text)
                .font(.caption.weight(.bold))
                .foregroundStyle(NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ChatInputBar: View {
    @Environment(AppStore.self) private var store
    @State private var draft = ""
    @State private var isKeyboardVisible = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var pendingAttachments: [PendingChatAttachment] = []
    @State private var isShowingDocumentPicker = false
    @State private var isShowingOrganizerHelp = false
    @State private var isLoadingAttachments = false
    @State private var attachmentError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !pendingAttachments.isEmpty {
                AttachmentDraftStrip(
                    attachments: pendingAttachments,
                    onRemove: removeAttachment
                )
            }

            if let attachmentError {
                Label(attachmentError, systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NinaTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
            }

            TextField("Escreva para a Nina", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(.body)
                .foregroundStyle(NinaTheme.ink)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .frame(minHeight: 34, alignment: .topLeading)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.send)
                .onSubmit(sendDraft)
                .disabled(store.isNinaResponding)
                .transaction { transaction in
                    transaction.animation = nil
                }

            HStack(spacing: 10) {
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: max(remainingAttachmentSlots, 1),
                    matching: .images
                ) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(NinaTheme.ink)
                        .frame(width: 36, height: 36)
                        .background(NinaTheme.cream.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(
                    store.isNinaResponding
                        || isLoadingAttachments
                        || remainingAttachmentSlots == 0
                )
                .accessibilityLabel("Adicionar fotos")

                Button {
                    Haptics.selection()
                    isShowingDocumentPicker = true
                } label: {
                    Image(systemName: isLoadingAttachments ? "ellipsis" : "paperclip")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(NinaTheme.ink)
                        .frame(width: 36, height: 36)
                        .background(NinaTheme.cream.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(
                    store.isNinaResponding
                        || isLoadingAttachments
                        || remainingAttachmentSlots == 0
                )
                .accessibilityLabel("Adicionar documento")

                Button {
                    Haptics.selection()
                    isShowingOrganizerHelp = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .black))

                        Text("Nina organiza")
                            .font(.caption.weight(.black))
                    }
                    .foregroundStyle(NinaTheme.mintInk)
                    .padding(.horizontal, 11)
                    .frame(height: 36)
                    .background(NinaTheme.mint.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Como a Nina organiza")
                .accessibilityHint("Explica o que acontece depois de enviar")
                .popover(isPresented: $isShowingOrganizerHelp, arrowEdge: .bottom) {
                    OrganizerHelpCard()
                        .presentationCompactAdaptation(.popover)
                }

                Spacer(minLength: 8)

                Button(action: sendDraft) {
                    Image(systemName: store.isNinaResponding ? "ellipsis" : "arrow.up")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(sendButtonColor, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Enviar mensagem")
            }
        }
        .padding(8)
        .background(NinaTheme.field, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(NinaTheme.cardStroke, lineWidth: 1)
        )
        .cardShadow()
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .padding(.bottom, isKeyboardVisible ? 8 : 92)
        .background {
            NinaTheme.screenGradient
                .opacity(isKeyboardVisible ? 0.98 : 0)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
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
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var remainingAttachmentSlots: Int {
        max(ChatAttachmentLimits.maxCount - pendingAttachments.count, 0)
    }

    private var canSend: Bool {
        (!trimmedDraft.isEmpty || !pendingAttachments.isEmpty)
            && store.canSendNinaMessages
            && !store.isNinaResponding
            && !isLoadingAttachments
    }

    private var sendButtonColor: Color {
        canSend ? NinaTheme.mint : NinaTheme.muted.opacity(0.36)
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

        let thumbnail = sourceImage
            .resizedToFit(maxSide: 320)
            .jpegData(compressionQuality: 0.72)
        return (fullData, thumbnail)
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

private enum ChatAttachmentLimits {
    static let maxCount = 3
    static let maxItemBytes = 5 * 1_024 * 1_024
    static let maxTotalBytes = 8 * 1_024 * 1_024

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
            HStack(spacing: 10) {
                ForEach(attachments) { attachment in
                    AttachmentDraftChip(attachment: attachment) {
                        onRemove(attachment)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

private struct AttachmentDraftChip: View {
    var attachment: PendingChatAttachment
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            attachmentPreview

            VStack(alignment: .leading, spacing: 3) {
                Text(attachment.metadata.filename)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(NinaTheme.ink)
                    .lineLimit(1)

                Text(attachment.metadata.byteCount.formattedFileSize)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(NinaTheme.muted)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(NinaTheme.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remover \(attachment.metadata.filename)")
        }
        .padding(8)
        .frame(width: 214, alignment: .leading)
        .background(NinaTheme.cream.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var attachmentPreview: some View {
        if attachment.metadata.kind == .image,
           let data = attachment.metadata.thumbnailData,
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(NinaTheme.sky)
                .frame(width: 42, height: 42)
                .background(NinaTheme.sky.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private struct OrganizerHelpCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("A Nina organiza ao enviar", systemImage: "sparkles")
                .font(.headline.weight(.black))
                .foregroundStyle(NinaTheme.ink)

            Text("Ela lê sua mensagem e seus anexos, depois sugere uma tarefa, lembrete ou memória. Nada é criado sem sua confirmação, e memórias pessoais começam privadas.")
                .font(.subheadline)
                .foregroundStyle(NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 290, alignment: .leading)
        .background(NinaTheme.sheet)
    }
}

private struct NinaTypingBubble: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            NinaAvatarView(size: 38)

            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)

                Text("Nina está organizando")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NinaTheme.muted)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(
                NinaTheme.card,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
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
        HStack(alignment: .bottom, spacing: 10) {
            if isNina {
                NinaAvatarView(size: 38)
            } else {
                Spacer(minLength: 40)
            }

            VStack(alignment: isNina ? .leading : .trailing, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    if !message.attachments.isEmpty {
                        MessageAttachmentsView(
                            attachments: message.attachments,
                            isNina: isNina
                        )
                    }

                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.body)
                            .foregroundStyle(isNina ? NinaTheme.ink : .white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        isNina ? NinaTheme.card : NinaTheme.sky,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )

                ForEach(message.proposals) { proposal in
                    NinaProposalCard(proposal: proposal)
                }

                if message.proposals.isEmpty, let suggestion = message.suggestion {
                    SuggestionMiniCard(suggestion: suggestion)
                }
            }
            .frame(maxWidth: 300, alignment: isNina ? .leading : .trailing)

            if isNina {
                Spacer(minLength: 40)
            }
        }
    }
}

private struct MessageAttachmentsView: View {
    var attachments: [ChatAttachment]
    var isNina: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(attachments) { attachment in
                if attachment.kind == .image,
                   let data = attachment.thumbnailData,
                   let image = UIImage(data: data) {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 230, minHeight: 120, maxHeight: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Text(attachment.filename)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isNina ? NinaTheme.muted : Color.white.opacity(0.86))
                            .lineLimit(1)
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: attachment.kind == .image ? "photo.fill" : "doc.text.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(isNina ? NinaTheme.sky : .white)
                            .frame(width: 34, height: 34)
                            .background(
                                isNina ? NinaTheme.sky.opacity(0.14) : Color.white.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.filename)
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(isNina ? NinaTheme.ink : .white)
                                .lineLimit(1)

                            Text(attachment.byteCount.formattedFileSize)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(isNina ? NinaTheme.muted : Color.white.opacity(0.78))
                        }
                    }
                    .padding(8)
                    .background(
                        isNina ? NinaTheme.cream.opacity(0.72) : Color.white.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                }
            }
        }
    }
}

private struct NinaProposalCard: View {
    @Environment(AppStore.self) private var store
    var proposal: NinaProposal

    @State private var draftTitle: String
    @State private var draftDetail: String
    @State private var draftOwner: String
    @State private var draftDueLabel: String
    @State private var isEditing = false
    @State private var isResolving = false

    init(proposal: NinaProposal) {
        self.proposal = proposal
        _draftTitle = State(initialValue: proposal.payload.title)
        _draftDetail = State(initialValue: proposal.payload.detail)
        _draftOwner = State(initialValue: proposal.payload.owner)
        _draftDueLabel = State(initialValue: proposal.payload.dueLabel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                IconBubble(
                    systemName: proposal.payload.symbolName,
                    tone: proposal.payload.category.tone,
                    size: 38
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(proposal.title)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(NinaTheme.ink)

                    Text(proposal.detail)
                        .font(.caption)
                        .foregroundStyle(NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if isEditing && proposal.state == .pending {
                VStack(spacing: 8) {
                    proposalField("Título", text: $draftTitle)
                    proposalField("Detalhes", text: $draftDetail)
                    if proposal.kind != .memory {
                        proposalField("Responsável", text: $draftOwner)
                        proposalField("Quando", text: $draftDueLabel)
                    }
                }
            }

            if proposal.state == .pending {
                pendingActions
            } else {
                Label(
                    proposal.state == .accepted ? "Confirmado" : "Ignorado",
                    systemImage: proposal.state == .accepted
                        ? "checkmark.circle.fill"
                        : "xmark.circle.fill"
                )
                .font(.caption.weight(.black))
                .foregroundStyle(
                    proposal.state == .accepted ? NinaTheme.mint : NinaTheme.muted
                )
            }
        }
        .padding(12)
        .background(
            NinaTheme.cream.opacity(0.9),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .disabled(isResolving)
        .opacity(isResolving ? 0.65 : 1)
    }

    @ViewBuilder
    private var pendingActions: some View {
        if proposal.kind == .memory {
            VStack(alignment: .leading, spacing: 8) {
                proposalButton(
                    "Guardar para mim",
                    systemName: "lock.fill",
                    visibility: .privateMemory
                )
                proposalButton(
                    "Compartilhar com a casa",
                    systemName: "house.fill",
                    visibility: .shared
                )
                rejectButton
            }
        } else {
            HStack(spacing: 8) {
                Button {
                    resolve(decision: .accept)
                } label: {
                    Label(proposal.actionTitle, systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(NinaTheme.mint, in: Capsule())
                }
                .buttonStyle(.plain)

                Button(isEditing ? "Fechar" : "Editar") {
                    Haptics.selection()
                    isEditing.toggle()
                }
                .font(.caption.weight(.black))
                .foregroundStyle(NinaTheme.sky)
                .buttonStyle(.plain)

                rejectButton
            }
        }
    }

    private func proposalField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .font(.caption.weight(.semibold))
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .background(
                NinaTheme.card,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
    }

    private func proposalButton(
        _ title: String,
        systemName: String,
        visibility: NinaMemoryVisibility
    ) -> some View {
        Button {
            resolve(decision: .accept, memoryVisibility: visibility)
        } label: {
            Label(title, systemImage: systemName)
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    visibility == .shared ? NinaTheme.sky : NinaTheme.mint,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private var rejectButton: some View {
        Button {
            resolve(decision: .reject)
        } label: {
            Text("Ignorar")
                .font(.caption.weight(.black))
                .foregroundStyle(NinaTheme.muted)
        }
        .buttonStyle(.plain)
    }

    private func resolve(
        decision: NinaProposalDecision,
        memoryVisibility: NinaMemoryVisibility? = nil
    ) {
        isResolving = true
        var payload = proposal.payload
        payload.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        payload.detail = draftDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        payload.owner = draftOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        payload.dueLabel = draftDueLabel.trimmingCharacters(in: .whitespacesAndNewlines)

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

private struct SuggestionMiniCard: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router
    var suggestion: NinaSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IconBubble(systemName: suggestion.symbolName, tone: suggestion.category.tone, size: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.title)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(NinaTheme.ink)

                    Text(suggestion.detail)
                        .font(.caption)
                        .foregroundStyle(NinaTheme.muted)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 8) {
                Button {
                    Haptics.success()
                    store.applySuggestion(suggestion)
                } label: {
                    Label(suggestion.actionTitle, systemImage: "plus.circle.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(NinaTheme.mint, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.lightImpact()
                    router.presentedSheet = .suggestion(suggestion)
                } label: {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(NinaTheme.sky)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Detalhes da sugestão")
            }
        }
        .padding(12)
        .background(NinaTheme.cream.opacity(0.86), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
    NavigationStack {
        NinaChatView()
            .environment(AppStore())
            .environment(RouterPath())
            .environment(TabSwipeLock())
    }
}
