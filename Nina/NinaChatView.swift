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
    @State private var composerDraft = ""

    // An example never names a person or a pet: this house may not have them.
    private static let captureExamples = [
        "Acabou o café",
        "Autorização da escola até sexta",
        "Um dia, pintar a sala"
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

            if showsIntro {
                intro
            } else {
                thread
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChatInputBar(
                draft: $composerDraft,
                examples: showsIntro ? Self.captureExamples : []
            )
        }
    }

    // The intro stands in for a thread with nothing to decide yet: a greeting may hide
    // behind it, a proposal never does.
    private var showsIntro: Bool {
        store.messages.allSatisfy { message in
            message.sender == .nina
                && message.proposals.isEmpty
                && message.suggestion == nil
                && !message.hasWithheldProposals
        }
    }

    private var intro: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    Text("Jogue uma lembrança aqui.")
                        .ninaText(.zero)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Eu proponho. Você confirma.")
                        .ninaText(.label, NinaTheme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(store.messages) { message in
                        MessageBubble(
                            message: message,
                            showsDisclaimer: message.id == disclaimerMessageID
                        )
                        .id(message.id)
                    }

                    if store.isNinaResponding {
                        NinaTypingBubble()
                            .id("nina-typing")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            // The newest turn is the one being read, and a pending proposal
            // card sits under it. Opening at the top of the thread hides both.
            .task(id: store.messages.last?.id) {
                await Task.yield()
                guard let lastID = store.messages.last?.id else { return }
                if didLoadInitialMessages {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                } else {
                    didLoadInitialMessages = true
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    // "Can read it wrong" is said once per screen, under the newest reply still waiting on a person.
    private var disclaimerMessageID: ChatMessage.ID? {
        store.messages.last { message in
            message.sender == .nina && message.proposals.contains { $0.state == .pending }
        }?.id
    }

    private var consentContent: some View {
        GeometryReader { proxy in
            ScrollView {
                AIMemoryConsentCard()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: max(proxy.size.height - 104, 0),
                        alignment: .leading
                    )
                    .padding(.bottom, 104)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var adultOnlyContent: some View {
        VStack {
            Spacer(minLength: 0)

            ZeroState(
                headline: "A conversa é dos adultos da casa.",
                body_: "Tarefas e compras continuam com você.",
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
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir ajustes")
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var openTasks: [TaskItem] {
        store.tasks.filter { $0.kind == .task && !$0.isDone }
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
                consentLine("Dá para desligar quando quiser, em Ajustes · Privacidade e dados. Aí eu paro de ler na hora.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ninaCard(fill: NinaTheme.grout, stroke: .clear)

            NinaButton(
                title: "Aceitar e conversar com a Nina",
                fillsWidth: true,
                isEnabled: !store.isSyncingHome
            ) {
                Haptics.lightImpact()
                Task {
                    if await store.grantAIMemoryConsent() {
                        Haptics.success()
                    }
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
                .ninaText(.meta, NinaTheme.muted)
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
    @Binding var draft: String
    var examples: [String]
    @State private var isKeyboardVisible = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var pendingAttachments: [PendingChatAttachment] = []
    @State private var isShowingDocumentPicker = false
    @State private var isShowingDocumentReadingNotice = false
    @State private var isLoadingAttachments = false
    @State private var attachmentError: String?

    var body: some View {
        VStack(spacing: 0) {
            if !examples.isEmpty {
                examplesRow
                    .padding(.bottom, 10)
            }

            Rectangle()
                .fill(NinaTheme.line)
                .frame(height: 1)

            if let notice {
                noticeStrip(notice)
            }

            VStack(alignment: .leading, spacing: 10) {
                if !pendingAttachments.isEmpty {
                    AttachmentDraftStrip(
                        attachments: pendingAttachments,
                        onRemove: removeAttachment
                    )
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
                    TextField("Escreva pra Nina", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .ninaText(.body, NinaTheme.ink)
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
                        .transaction { transaction in
                            transaction.animation = nil
                        }

                    Button(action: sendDraft) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(canSend ? NinaTheme.onCobalt : NinaTheme.muted)
                            .frame(width: 46, height: 46)
                            .background(canSend ? NinaTheme.cobalt : NinaTheme.grout, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.4)
                    .accessibilityLabel("Enviar mensagem")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)

            attachmentPrivacyNote
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
            attachmentError = "Foto e documento são do Premium."
        }
    }

    // An example is a draft to edit, not a message to send: the chip fills the
    // composer and the person decides.
    private var examplesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(examples, id: \.self) { example in
                    Button {
                        Haptics.lightImpact()
                        draft = example
                    } label: {
                        NinaChip(text: example)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .chipRowTrailingFade()
        .disabled(store.isNinaResponding)
        .opacity(store.isNinaResponding ? 0.4 : 1)
    }

    private struct ComposerNotice {
        var systemName: String
        var text: String
        var opensPremium = false
    }

    // An honesty state is never replaced by silence: whatever the thread cannot show about
    // where a reply came from, or which ceiling stopped it, sits on the composer.
    private var notice: ComposerNotice? {
        if let connectionNotice = store.ninaConnectionNotice {
            return ComposerNotice(systemName: "wifi.exclamationmark", text: connectionNotice)
        }
        if let premiumCeiling {
            return ComposerNotice(systemName: "lock", text: premiumCeiling, opensPremium: true)
        }
        if store.isUsingLocalNina {
            return ComposerNotice(systemName: "iphone", text: "Modo local. Nada sai deste aparelho.")
        }
        return nil
    }

    // A server denial arrives as an ordinary Nina line, so the ceiling it names is recovered here:
    // a refusal this household can lift must carry the route, never end the conversation.
    private var premiumCeiling: String? {
        guard !store.householdPremium.isActive,
              let latest = store.messages.last,
              latest.sender == .nina else {
            return nil
        }
        if latest.text == NinaEngineError.attachmentsRequirePremium.userMessage {
            return "Ler foto e documento é do Premium."
        }
        if latest.text == NinaEngineError.rateLimited.userMessage {
            return "No Premium, 30 mensagens por hora."
        }
        return nil
    }

    private func noticeStrip(_ notice: ComposerNotice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: notice.systemName)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(NinaTheme.muted)
                .accessibilityHidden(true)

            Text(notice.text)
                .ninaText(.meta, NinaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if notice.opensPremium {
                Button {
                    Haptics.lightImpact()
                    router.presentedSheet = .premium
                } label: {
                    Text("Ver o Premium")
                        .ninaText(.meta, NinaTheme.ink, weight: .semibold)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(NinaTheme.grout)
    }

    // Off means absent, not locked: a premium upsell for a feature this build
    // does not ship would sell a capability no purchase can unlock.
    private var shipsDocumentReading: Bool {
        NinaAttachmentGate.current.isEnabled
    }

    @ViewBuilder
    private var attachmentControls: some View {
        if shipsDocumentReading {
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
                detail: "Foto e documento são do Premium."
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
    private var attachmentPrivacyNote: some View {
        if !pendingAttachments.isEmpty {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(NinaTheme.line)
                    .frame(height: 1)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(NinaTheme.muted)

                    Text("A foto não fica guardada em servidor nenhum.")
                        .ninaText(.meta, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .accessibilityElement(children: .combine)
        }
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

                    let imageData = try await Task.detached(priority: .userInitiated) {
                        try Self.normalizedImageData(sourceData)
                    }.value
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

    // Decoding, resizing and re-encoding an 1800px photo is tens of milliseconds
    // of CPU. On the main actor that is a visible stall while the composer is open.
    private static func normalizedImageData(_ data: Data) throws -> (full: Data, thumbnail: Data?) {
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
                    .frame(width: 44, height: 44)
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

            Text("Lendo")
                .ninaText(.caption, NinaTheme.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    NinaTheme.grout,
                    in: RoundedRectangle(cornerRadius: NinaTheme.Radius.card, style: .continuous)
                )

            Spacer(minLength: 40)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("A Nina está lendo")
    }
}

private struct MessageBubble: View {
    var message: ChatMessage
    var showsDisclaimer: Bool

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
                    WithheldProposalsLine()
                }

                if let suggestion = message.suggestion {
                    SuggestionMiniCard(suggestion: suggestion)
                }

                if showsDisclaimer {
                    Text("A Nina pode ler errado. Nada entra sem você confirmar.")
                        .ninaText(.meta, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isNina ? "Nina" : "Você"): \(message.text)")
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
                    .frame(width: 44, height: 44)
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
    @State private var resolveFailure: String?

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
            face

            actions
        }
        .clipShape(RoundedRectangle(cornerRadius: NinaTheme.Radius.card, style: .continuous))
        .ninaCard()
        .disabled(isResolving)
        .opacity(isResolving ? 0.4 : 1)
        .alert("Compartilhar com a casa?", isPresented: $isConfirmingShare) {
            Button("Compartilhar") {
                resolve(decision: .accept, memoryVisibility: .shared)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(shareWarning)
        }
    }

    private var pendingTag: some View {
        HStack(spacing: 6) {
            Image(systemName: proposal.kind == .memory ? "lock" : "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NinaTheme.faint)
                .accessibilityHidden(true)

            Eyebrow(text: proposal.kind == .memory ? "Ainda não guardada" : "Ainda não existe")
        }
    }

    private var face: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                if proposal.state == .pending {
                    pendingTag
                }

                objectRow
            }

            if let secondaryLine {
                Text(secondaryLine)
                    .ninaText(.caption, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            extractedReadings

            if isEditing && proposal.state == .pending {
                VStack(spacing: 12) {
                    proposalField("Título", text: $draftTitle)
                    proposalField("Detalhes", text: $draftDetail)
                    if proposal.kind != .memory {
                        ownerPicker
                        if !isSeed {
                            proposalField("Quando", text: $draftDueLabel, hint: dueCorrectionHint)
                        }
                    }
                    if proposal.kind == .shopping {
                        proposalField("Quantidade", text: $draftAmount)
                    }
                }
            }

            metaLine
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NinaTheme.ground)
    }

    private var objectRow: some View {
        HStack(alignment: .top, spacing: 10) {
            if proposal.kind != .memory {
                CategoryGlyph(
                    systemName: confirmationPayload.category.symbolName,
                    size: 18,
                    tint: NinaTheme.ink
                )
                .accessibilityLabel(confirmationPayload.category.title)
            }

            objectTitle
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var objectTitle: some View {
        if proposal.kind == .memory {
            Text(confirmationPayload.title).ninaText(.section)
        } else {
            Text(confirmationPayload.title)
                .ninaText(.body, NinaTheme.ink, weight: .semibold)
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

    // One line under the title, and what the house will carry outranks why Nina proposed it.
    private var secondaryLine: String? {
        if !confirmationPayload.detail.isEmpty {
            return confirmationPayload.detail
        }
        return proposal.payload.rationale.isEmpty ? nil : proposal.payload.rationale
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

                if confirmationPayload.category.id == TaskCategory.bills.id {
                    Text("Para pagar, abra o boleto no banco.")
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

    private struct MetaPair: Hashable {
        var systemName: String
        var value: String
        var label: String
        var isMuted = false
    }

    // Only an attachment is named as the basis; how sure Nina is never joins it, because a score
    // on a household suggestion reads as a verdict on the house instead of a portrait of it.
    private var metaPairs: [MetaPair] {
        var pairs: [MetaPair] = []
        if proposal.kind != .memory {
            pairs.append(
                MetaPair(
                    systemName: isSeed ? "leaf" : "calendar",
                    value: scheduleValue,
                    label: isSeed ? TaskKind.seed.title : "Quando",
                    isMuted: isSeed
                )
            )
            pairs.append(MetaPair(systemName: "person", value: ownerValue, label: "Dono"))
            if proposal.kind == .shopping, !confirmationPayload.amount.isEmpty {
                pairs.append(
                    MetaPair(systemName: "number", value: confirmationPayload.amount, label: "Quantidade")
                )
            }
        }
        if proposal.payload.source == .attachment {
            pairs.append(
                MetaPair(
                    systemName: "paperclip",
                    value: NinaProposalSource.attachment.title,
                    label: "Origem"
                )
            )
        }
        return pairs
    }

    // The date and the owner are decided on the card face: a value kept behind Corrigir would let
    // a person confirm a date they never saw.
    @ViewBuilder
    private var metaLine: some View {
        if !metaPairs.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    ForEach(metaPairs, id: \.self) { metaPairView($0) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(metaPairs, id: \.self) { metaPairView($0) }
                }
            }
        }
    }

    private func metaPairView(_ pair: MetaPair) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: pair.systemName)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(NinaTheme.muted)

            Text(pair.value)
                .ninaText(.label, pair.isMuted ? NinaTheme.muted : NinaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pair.label): \(pair.value)")
    }

    // The line shows the date Nina actually scheduled, not the words she used for it: a label
    // that parsed to nothing is confirmed without a reminder, and the person sees that first.
    private var scheduleValue: String {
        if isSeed {
            return "Plante depois"
        }
        if let date = confirmationPayload.scheduledDate {
            return AppStore.taskDueLabel(for: date)
        }
        let label = confirmationPayload.dueLabel
        guard !label.isEmpty, label.caseInsensitiveCompare("Sem data") != .orderedSame else {
            return "Sem data"
        }
        return "\(label) · sem lembrete"
    }

    private var dueCorrectionHint: String {
        let typed = draftDueLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty {
            return "Vai ficar sem data."
        }
        if let date = confirmationPayload.scheduledDate {
            return "Vai ficar: \(AppStore.taskDueLabel(for: date))."
        }
        return "Não entendi a data. Tente \"amanhã\" ou \"18:00\"."
    }

    private var ownerValue: String {
        HouseholdWorkload.isSharedOwner(confirmationPayload.owner)
            ? "Sem dono"
            : confirmationPayload.owner
    }

    private var ownerOptions: [TaskOwnerChoice] {
        TaskOwnerChoice.options(
            members: store.familyGroup.members,
            selectedName: draftOwner,
            selectedMemberID: nil
        )
    }

    private func isSelectedOwner(_ option: TaskOwnerChoice) -> Bool {
        HouseholdWorkload.isSameOwner(option.name, draftOwner)
    }

    private var selectedOwnerLabel: String {
        if HouseholdWorkload.isSharedOwner(draftOwner) { return "Sem dono" }
        return ownerOptions.first(where: isSelectedOwner)?.label ?? draftOwner
    }

    // The owner is picked from the house, never typed: a misspelt name would create work for
    // someone who does not live here.
    private var ownerPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Dono")
                .ninaText(.caption, NinaTheme.muted)

            Menu {
                ForEach(ownerOptions) { option in
                    Button {
                        Haptics.selection()
                        draftOwner = option.name
                    } label: {
                        Label(
                            HouseholdWorkload.isSharedOwner(option.name) ? "Sem dono" : option.label,
                            systemImage: isSelectedOwner(option) ? "checkmark" : "person"
                        )
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedOwnerLabel)
                        .ninaText(.label, NinaTheme.ink)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NinaTheme.muted)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(
                    NinaTheme.grout,
                    in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dono: \(selectedOwnerLabel)")
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let resolveFailure, proposal.state == .pending {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NinaTheme.ink)
                    Text(resolveFailure)
                        .ninaText(.caption, NinaTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }

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

    private var primaryTitle: String {
        switch proposal.kind {
        case .seed: "Criar semente"
        case .shopping: "Adicionar à lista"
        default: "Criar tarefa"
        }
    }

    private var standardActions: some View {
        VStack(spacing: 8) {
            NinaButton(title: primaryTitle, fillsWidth: true) {
                resolve(decision: .accept)
            }

            HStack(spacing: 8) {
                NinaButton(
                    title: isEditing ? "Pronto" : "Corrigir",
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

    // Sharing is the one move nobody can take back, so it names who gains the reading and asks
    // again; keeping it for yourself stays the single tap.
    private var memoryActions: some View {
        VStack(spacing: 8) {
            NinaButton(title: "Guardar para mim", systemName: "lock", fillsWidth: true) {
                resolve(decision: .accept, memoryVisibility: .privateMemory)
            }

            NinaButton(title: "Compartilhar com a casa", kind: .outline, fillsWidth: true) {
                Haptics.warning()
                isConfirmingShare = true
            }

            HStack(spacing: 8) {
                NinaButton(title: isEditing ? "Pronto" : "Corrigir", kind: .quiet, fillsWidth: true) {
                    Haptics.selection()
                    isEditing.toggle()
                }

                NinaButton(title: "Não", kind: .quiet, fillsWidth: true) {
                    resolve(decision: .reject)
                }
            }
            .padding(.top, 4)
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

    private func proposalField(
        _ title: String,
        text: Binding<String>,
        hint: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .ninaText(.caption, NinaTheme.muted)

            TextField(title, text: text)
                .ninaText(.label, NinaTheme.ink)
                .tint(NinaTheme.cobalt)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(
                    NinaTheme.grout,
                    in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous)
                )
                .accessibilityLabel(title)

            if let hint {
                Text(hint)
                    .ninaText(.meta, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func resolve(
        decision: NinaProposalDecision,
        memoryVisibility: NinaMemoryVisibility? = nil
    ) {
        isResolving = true
        resolveFailure = nil
        let payload = confirmationPayload

        Task {
            let resolved = await store.resolveProposal(
                proposal,
                decision: decision,
                editedPayload: decision == .accept ? payload : nil,
                memoryVisibility: memoryVisibility
            )
            isResolving = false
            if !resolved {
                resolveFailure = decision == .accept
                    ? "Não deu para confirmar agora. Nada entrou na casa. Tente de novo."
                    : "Não deu para responder agora. Tente de novo."
            }
        }
    }
}

// A withheld turn keeps its own line in the thread: the discard is stated on the turn it hid.
private struct WithheldProposalsLine: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "hourglass")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(NinaTheme.muted)
                .accessibilityHidden(true)

            Text("Confirmação ainda fechada nesta versão. Nada entrou na casa.")
                .ninaText(.meta, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SuggestionMiniCard: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router
    var suggestion: NinaSuggestion

    @State private var isRefused = false

    var body: some View {
        if isRefused {
            EmptyView()
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                NinaCheckbox(isOn: false, size: 22)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.title)
                        .ninaText(.body, NinaTheme.ink, weight: .semibold)

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

            // Three exits, never two: disagreement is a first-class button, and a
            // card you can only accept or inspect is a card you cannot refuse.
            HStack(spacing: 10) {
                NinaButton(title: "Ver detalhes", kind: .outline, fillsWidth: true) {
                    Haptics.lightImpact()
                    router.presentedSheet = .suggestion(suggestion)
                }

                NinaButton(title: "Não", kind: .outline, fillsWidth: true) {
                    Haptics.selection()
                    isRefused = true
                }
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
}
