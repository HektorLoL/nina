import Foundation
import Observation
import SwiftUI

enum InviteLinkParser {
    nonisolated static func code(from url: URL) -> String? {
        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased()
        let components = url.pathComponents.filter { $0 != "/" }

        let rawCode: String?
        switch scheme {
        case "https", "http":
            guard host == "ninai.app" || host == "www.ninai.app",
                  components.count == 2,
                  components[0].lowercased() == "invite" else {
                return nil
            }
            rawCode = components[1]
        case "nina":
            if host == "invite", components.count == 1 {
                rawCode = components[0]
            } else if components.count == 2, components[0].lowercased() == "invite" {
                rawCode = components[1]
            } else {
                rawCode = nil
            }
        default:
            rawCode = nil
        }

        guard let rawCode else { return nil }
        return AppStore.normalizedInviteCode(from: rawCode)
    }
}

@MainActor
@Observable
final class InviteLinkStore {
    private static let pendingCodeKey = "nina.invite.pendingCode"

    var pendingCode: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let privateDataStore: any PrivateLocalDataStoring

    init(
        defaults: UserDefaults = .standard,
        privateDataStore: any PrivateLocalDataStoring = ProtectedLocalDataStore.shared
    ) {
        self.defaults = defaults
        self.privateDataStore = privateDataStore
        pendingCode = PrivateLocalDataAccess.loadString(
            forKey: Self.pendingCodeKey,
            ownerScope: PrivateLocalDataScope.pendingInvite,
            store: privateDataStore,
            legacyDefaults: defaults
        )
    }

    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard let code = InviteLinkParser.code(from: url) else { return false }
        pendingCode = code
        PrivateLocalDataAccess.writeStringBestEffort(
            code,
            forKey: Self.pendingCodeKey,
            ownerScope: PrivateLocalDataScope.pendingInvite,
            store: privateDataStore,
            legacyDefaults: defaults
        )
        return true
    }

    func clear() {
        pendingCode = nil
        PrivateLocalDataAccess.removeData(
            forKey: Self.pendingCodeKey,
            ownerScope: PrivateLocalDataScope.pendingInvite,
            store: privateDataStore,
            legacyDefaults: defaults
        )
    }
}

struct InviteAcceptanceView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSessionStore.self) private var authSession
    @Environment(InviteLinkStore.self) private var inviteLinkStore
    @Environment(ProfileStore.self) private var profileStore

    @State private var preview: FamilyInvitePreview?
    @State private var isLoading = true
    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var firstName = ""
    @FocusState private var isNameFocused: Bool

    private var knownName: String? {
        authSession.currentUser.flatMap { profileStore.profiles[$0.id]?.displayName }
    }

    // The approver's card and the member row carry this name, so a placeholder must never reach them.
    private var needsName: Bool {
        ProfileNaming.asksForName(
            user: authSession.currentUser,
            knownName: knownName,
            sharedGivenName: authSession.sharedGivenName
        )
    }

    private var hasChosenName: Bool {
        !needsName || !ProfileNaming.isPlaceholder(firstName)
    }

    private var code: String {
        inviteLinkStore.pendingCode ?? ""
    }

    private var householdName: String {
        preview?.familyName ?? "Uma casa"
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 32)

                    Group {
                        if isLoading {
                            loadingHeader
                        } else if preview?.isValid == true {
                            validHeader
                        } else if preview == nil {
                            // The preview RPC answers {valid:false} for a genuinely dead code,
                            // so a nil can only mean we could not reach it. Saying the link is
                            // dead would be asserting a fact we do not have.
                            unverifiedHeader
                        } else {
                            invalidHeader
                        }
                    }
                    .multilineTextAlignment(.center)

                    Spacer(minLength: 32)

                    actions
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .ninaScreenBackground()
        .task(id: code) {
            await loadPreview()
        }
    }

    private var loadingHeader: some View {
        VStack(spacing: 14) {
            NinaMark(size: 44, presence: .rest)
            Text("Conferindo o link.").ninaText(.label, NinaTheme.muted)
        }
    }

    private var validHeader: some View {
        VStack(spacing: 14) {
            MemberAvatar(initials: householdName.ninaInitials, tone: .mint, size: 56)

            VStack(spacing: 6) {
                Eyebrow(text: "Convite")
                Text(householdName)
                    .ninaText(.display)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Possessing an invite grants nothing: an owner or admin approves the request.
            Text("Ter o link não dá acesso. Alguém da casa aprova.")
                .ninaText(.label, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unverifiedHeader: some View {
        VStack(spacing: 14) {
            Text("Não deu para conferir o link.")
                .ninaText(.display)
                .fixedSize(horizontal: false, vertical: true)

            Text("Ter o link não dá acesso. Alguém da casa aprova.")
                .ninaText(.label, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var invalidHeader: some View {
        VStack(spacing: 14) {
            Text("Este link não vale mais.")
                .ninaText(.display)
                .fixedSize(horizontal: false, vertical: true)

            // The RPC answers the same way for every failure, so the copy names
            // no reason: guessing one would be inventing it.
            Text("Peça um novo para quem te chamou.")
                .ninaText(.label, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .ninaText(.caption, NinaTheme.ink, weight: .semibold)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // request_family_join is the real authority, so an unverified link
            // keeps the button: the server decides, not the preview.
            if preview?.isValid == true || preview == nil {
                if needsName, !isLoading {
                    ChosenNameField(name: $firstName, focus: $isNameFocused, focusValue: true)
                        .submitLabel(.join)
                        .onSubmit(acceptInvite)
                        .padding(.bottom, 2)
                }

                NinaButton(
                    title: isJoining ? "Enviando" : "Pedir para entrar",
                    fillsWidth: true,
                    isEnabled: !isLoading && !isJoining && hasChosenName
                ) {
                    acceptInvite()
                }
            }

            NinaButton(title: "Criar minha casa", kind: .outline, fillsWidth: true) {
                inviteLinkStore.clear()
            }
        }
    }

    private func loadPreview() async {
        guard !code.isEmpty else {
            preview = nil
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        preview = await store.previewHomeInvite(code)
        isLoading = false
    }

    private func acceptInvite() {
        guard preview?.isValid != false, !isJoining, hasChosenName else { return }
        isNameFocused = false
        isJoining = true
        errorMessage = nil

        Task {
            if let user = authSession.currentUser,
               let name = ProfileNaming.nameToSave(
                   user: user,
                   knownName: knownName,
                   sharedGivenName: authSession.sharedGivenName,
                   typed: firstName
               ) {
                let saved = await profileStore.chooseDisplayName(name, for: user)
                guard authSession.currentUser?.id == user.id else {
                    isJoining = false
                    return
                }
                guard saved else {
                    isJoining = false
                    errorMessage = ChosenNameCopy.saveFailed
                    return
                }
                authSession.noteChosenDisplayName(name)
            }

            let joined = await store.joinHome(with: code, member: authSession.currentUser)
            isJoining = false

            if joined {
                Haptics.success()
                inviteLinkStore.clear()
            } else {
                // AppStore already fires the error haptic on every failure path.
                errorMessage = store.syncErrorMessage ?? "Não foi possível pedir entrada agora."
            }
        }
    }
}
