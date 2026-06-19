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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pendingCode = defaults.string(forKey: Self.pendingCodeKey)
    }

    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard let code = InviteLinkParser.code(from: url) else { return false }
        pendingCode = code
        defaults.set(code, forKey: Self.pendingCodeKey)
        return true
    }

    func clear() {
        pendingCode = nil
        defaults.removeObject(forKey: Self.pendingCodeKey)
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SoftCard(padding: 20) {
                        HStack(spacing: 16) {
                            IconBubble(systemName: "person.2.badge.plus", tone: .mint, size: 58)

                            VStack(alignment: .leading, spacing: 5) {
                                Text("Convite para uma casa")
                                    .font(.title2.weight(.black))
                                    .foregroundStyle(NinaTheme.ink)

                                Text("Confirme antes de entrar e compartilhar a rotina.")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(NinaTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    inviteCard

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(NinaTheme.coral)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    PrimaryCapsuleButton(
                        title: isJoining ? "Entrando..." : "Entrar nesta casa",
                        systemName: "arrow.right.circle.fill"
                    ) {
                        acceptInvite()
                    }
                    .disabled(isLoading || isJoining || preview?.isValid != true)
                    .opacity(isLoading || isJoining || preview?.isValid != true ? 0.5 : 1)

                    Button("Agora não") {
                        inviteLinkStore.clear()
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(NinaTheme.muted)
                    .frame(maxWidth: .infinity)
                }
                .padding(18)
                .padding(.bottom, 28)
            }
            .ninaScreenBackground()
            .navigationTitle("Convite")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: code) {
            await loadPreview()
        }
    }

    @ViewBuilder
    private var inviteCard: some View {
        SoftCard(padding: 18) {
            if isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(NinaTheme.mint)

                    Text("Verificando convite...")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(NinaTheme.muted)
                }
            } else if let preview, preview.isValid {
                SectionTitle(
                    title: preview.familyName ?? "Casa compartilhada",
                    subtitle: "A Nina protege este convite com um código único."
                )

                Label(preview.code, systemImage: "lock.shield.fill")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(NinaTheme.sky)
                    .textSelection(.enabled)
            } else {
                Label("Este convite não existe mais ou foi renovado.", systemImage: "link.badge.xmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(NinaTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
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
                errorMessage = store.syncErrorMessage ?? "Não foi possível entrar nesta casa."
            }
        }
    }
}
