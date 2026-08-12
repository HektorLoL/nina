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

    @State private var preview: FamilyInvitePreview?
    @State private var isLoading = true
    @State private var isJoining = false
    @State private var errorMessage: String?

    private var code: String {
        inviteLinkStore.pendingCode ?? ""
    }

    private var householdName: String {
        preview?.familyName ?? "uma casa"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                loadingHeader
            } else if preview?.isValid == true {
                validHeader
            } else {
                invalidHeader
            }

            Spacer(minLength: 24)

            if let errorMessage {
                Text(errorMessage)
                    .ninaText(.caption, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
            }

            actions
        }
        .padding(.horizontal, 20)
        .padding(.top, 40)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ninaScreenBackground()
        .task(id: code) {
            await loadPreview()
        }
    }

    private var loadingHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            NinaMark(size: 44, presence: .reading)
            Text("Vendo de quem é este link.").ninaText(.label, NinaTheme.muted)
        }
    }

    private var validHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                MemberAvatar(initials: householdName.ninaInitials, tone: .mint, size: 44)
                Text("Alguém quer dividir a \(householdName) com você.")
                    .ninaText(.caption, NinaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Você abriu o link.\nAinda não entrou.")
                .ninaText(.display)
                .fixedSize(horizontal: false, vertical: true)

            // Possessing an invite grants nothing: the link opens a request, and
            // an owner or admin approves it. Saying so here is the whole screen.
            Text("Ter o link não dá acesso a nada. Ele pede entrada, e alguém da casa precisa aprovar — até lá você não vê nenhuma tarefa, nenhuma conta, nenhuma criança desta casa.")
                .ninaText(.label, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var invalidHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Este link não vale mais.")
                .ninaText(.display)
                .fixedSize(horizontal: false, vertical: true)

            // The RPC answers the same way for every failure, so the copy names
            // no reason: guessing one would be inventing it.
            Text("Ele pode ter expirado, já ter sido usado o bastante, ou ter sido renovado. Peça um novo para quem te chamou.")
                .ninaText(.label, NinaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if preview?.isValid == true {
                NinaButton(
                    title: isJoining ? "Enviando..." : "Pedir para entrar",
                    fillsWidth: true,
                    isEnabled: !isLoading && !isJoining
                ) {
                    acceptInvite()
                }
            }

            NinaButton(title: "Montar a minha própria casa", kind: .outline, fillsWidth: true) {
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
        guard preview?.isValid == true, !isJoining else { return }
        isJoining = true
        errorMessage = nil

        Task {
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
