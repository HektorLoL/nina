import XCTest
@testable import Nina

final class InviteLinkTests: XCTestCase {
    private let code = "casa-47a9f2d0b3c1e8a4d6f2a9c5e7b1d304"

    func testParsesNinaUniversalLink() throws {
        let url = try XCTUnwrap(URL(string: "https://ninai.app/invite/\(code)"))

        XCTAssertEqual(InviteLinkParser.code(from: url), code)
    }

    func testParsesCustomSchemeLink() throws {
        let url = try XCTUnwrap(URL(string: "nina://invite/\(code)"))

        XCTAssertEqual(InviteLinkParser.code(from: url), code)
    }

    func testNormalizesUppercaseUniversalLinkWithQuery() throws {
        let url = try XCTUnwrap(
            URL(string: "https://www.ninai.app/invite/\(code.uppercased())?source=share")
        )

        XCTAssertEqual(InviteLinkParser.code(from: url), code)
    }

    func testRejectsUntrustedHostsAndRoutes() throws {
        XCTAssertNil(InviteLinkParser.code(from: try XCTUnwrap(URL(string: "https://example.com/invite/\(code)"))))
        XCTAssertNil(InviteLinkParser.code(from: try XCTUnwrap(URL(string: "https://ninai.app/other/\(code)"))))
    }

    func testOnlySomeoneWithoutAHouseIsOfferedToCreateOneInsteadOfJoining() {
        XCTAssertTrue(InviteSetAside.offersHouseCreation(.noHome))
        XCTAssertEqual(InviteSetAside.title(for: .noHome), "Criar uma casa")

        for access: HomeAccessState in [.authorized, .pendingApproval, .accessDecision] {
            XCTAssertFalse(InviteSetAside.offersHouseCreation(access))
            XCTAssertEqual(InviteSetAside.title(for: access), "Agora não")
        }
    }

    func testSomeoneAlreadyInAHouseIsToldHowToLeaveItInsteadOfBeingOfferedToJoin() {
        XCTAssertTrue(InviteHouseExit.blocksRequest(.authorized))
        for access: HomeAccessState in [.noHome, .pendingApproval, .accessDecision, .loading, .unavailable] {
            XCTAssertFalse(InviteHouseExit.blocksRequest(access))
        }

        XCTAssertEqual(
            InviteHouseExit.line(canLeave: true, mustHandOver: false, hasAdultToHold: false, canDelete: false),
            "Você já está numa casa. Para entrar nesta, primeiro saia da sua em Sair da casa."
        )
        XCTAssertEqual(
            InviteHouseExit.line(canLeave: false, mustHandOver: true, hasAdultToHold: true, canDelete: true),
            "Você já está numa casa. Para entrar nesta, primeiro passe a sua para outro adulto ou use Apagar a casa."
        )
        XCTAssertEqual(
            InviteHouseExit.line(canLeave: false, mustHandOver: true, hasAdultToHold: false, canDelete: true),
            "Você já está numa casa. Para entrar nesta, primeiro use Apagar a casa."
        )
        XCTAssertEqual(
            InviteHouseExit.line(canLeave: false, mustHandOver: false, hasAdultToHold: false, canDelete: false),
            "Você já está numa casa. Para entrar nesta, primeiro saia da sua."
        )
        XCTAssertEqual(InviteHouseExit.openSettingsTitle, "Abrir Ajustes")
        for canLeave in [true, false] {
            for mustHandOver in [true, false] {
                for hasAdultToHold in [true, false] {
                    let line = InviteHouseExit.line(
                        canLeave: canLeave,
                        mustHandOver: mustHandOver,
                        hasAdultToHold: hasAdultToHold,
                        canDelete: mustHandOver
                    )
                    XCTAssertFalse(line.contains("!"), line)
                    XCTAssertFalse(line.lowercased().contains("convite inválido"), line)
                }
            }
        }
    }

    func testAMembersOwnHouseLinkIsRecognisedByItsCodeOrByTheNameWhenTheCodeIsMasked() {
        XCTAssertTrue(
            InviteHouseExit.isOwnHouse(code: code, previewName: "Outra", houseInviteCode: code, houseName: "Casa Prado")
        )
        XCTAssertFalse(
            InviteHouseExit.isOwnHouse(
                code: code,
                previewName: "Casa Prado",
                houseInviteCode: "casa-00000000000000000000000000000000",
                houseName: "Casa Prado"
            )
        )
        XCTAssertTrue(
            InviteHouseExit.isOwnHouse(code: code, previewName: "casa prado", houseInviteCode: "", houseName: "Casa Prado")
        )
        XCTAssertFalse(
            InviteHouseExit.isOwnHouse(code: code, previewName: "Lar dos Silva", houseInviteCode: "", houseName: "Casa Prado")
        )
        XCTAssertFalse(InviteHouseExit.isOwnHouse(code: code, previewName: nil, houseInviteCode: "", houseName: "Casa Prado"))
        XCTAssertEqual(InviteHouseExit.ownHouseLine, "Você já está nesta casa.")
    }

    @MainActor
    func testAnInviteHeldWhileThePersonLeavesTheirHouseWaitsAndReturnsOnceTheyHoldNone() throws {
        let suiteName = "InviteLinkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "nina-invite-hold-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let links = InviteLinkStore(
            defaults: defaults,
            privateDataStore: ProtectedLocalDataStore(directoryURL: directory)
        )
        XCTAssertTrue(links.receive(try XCTUnwrap(URL(string: "https://ninai.app/invite/\(code)"))))

        func phase(_ access: HomeAccessState) -> AppEntryPhase {
            AppEntryRouting.phase(
                for: AppEntryInputs(
                    isSignedIn: true,
                    needsAgeCheck: false,
                    homeAccessState: access,
                    viewerIsAdult: true,
                    hasPendingInvite: links.pendingCode != nil,
                    inviteHeldUntilHouseExit: links.isHeldUntilHouseExit,
                    shouldShowTutorial: false
                )
            )
        }

        XCTAssertEqual(phase(.authorized), .invite)

        links.holdUntilHouseExit()

        XCTAssertEqual(phase(.authorized), .app)
        XCTAssertEqual(links.pendingCode, code)
        XCTAssertEqual(phase(.noHome), .invite)

        links.clear()

        XCTAssertFalse(links.isHeldUntilHouseExit)
        XCTAssertEqual(phase(.noHome), .homeSetup)
    }

    @MainActor
    func testACopiedInviteMessageReadsAsItsTokenWhicheverWayItWasPasted() {
        let link = "https://ninai.app/invite/\(code)"
        let message = InviteFamilySheet.message(inviter: "Marta", houseName: "Lar dos Prado")

        for pasted in [
            "\(message) \(link)",
            "\(message)\n\(link)",
            "\(link) \(message)",
            "\(link)\n\n\(message)",
            "  \(link)  ",
            code.uppercased(),
        ] {
            XCTAssertEqual(AppStore.normalizedInviteCode(from: pasted), code, pasted)
        }

        XCTAssertEqual(
            AppStore.normalizedInviteCode(from: "Entra aqui: https://ninai.app/invite/casa-convite-antigo"),
            "casa-convite-antigo"
        )
        XCTAssertNil(AppStore.normalizedInviteCode(from: message))
        XCTAssertEqual(AppStore.normalizedInviteCode(from: "casa-valid-invite"), "casa-valid-invite")
    }

    @MainActor
    func testTheInviteMessageNamesTheHouseWithoutAnArticleAndPromisesOnlyARequest() {
        let message = InviteFamilySheet.message(inviter: "Marta", houseName: "Lar dos Prado")

        XCTAssertTrue(message.hasPrefix("Marta quer dividir a casa com você na Nina: Lar dos Prado."))
        XCTAssertFalse(message.contains("a Lar dos Prado"))
        XCTAssertTrue(message.contains("Tocar no link só pede entrada."))
        XCTAssertTrue(message.contains("Alguém da casa ainda precisa aprovar."))
        XCTAssertFalse(message.contains("—"))
    }

    @MainActor
    func testPendingInvitePersistsUntilCleared() throws {
        let suiteName = "InviteLinkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "nina-invite-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let privateDataStore = ProtectedLocalDataStore(directoryURL: directory)

        let firstStore = InviteLinkStore(
            defaults: defaults,
            privateDataStore: privateDataStore
        )
        XCTAssertTrue(firstStore.receive(try XCTUnwrap(URL(string: "https://ninai.app/invite/\(code)"))))
        XCTAssertNil(defaults.string(forKey: "nina.invite.pendingCode"))

        let restoredStore = InviteLinkStore(
            defaults: defaults,
            privateDataStore: privateDataStore
        )
        XCTAssertEqual(restoredStore.pendingCode, code)

        restoredStore.clear()
        XCTAssertNil(
            InviteLinkStore(
                defaults: defaults,
                privateDataStore: privateDataStore
            ).pendingCode
        )
    }

    @MainActor
    func testLegacyPendingInviteMigratesOutOfDefaults() throws {
        let suiteName = "InviteLinkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "nina-invite-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let privateDataStore = ProtectedLocalDataStore(directoryURL: directory)
        defaults.set(code, forKey: "nina.invite.pendingCode")

        let store = InviteLinkStore(
            defaults: defaults,
            privateDataStore: privateDataStore
        )

        XCTAssertEqual(store.pendingCode, code)
        XCTAssertNil(defaults.string(forKey: "nina.invite.pendingCode"))
        XCTAssertEqual(
            try privateDataStore.data(
                forKey: "nina.invite.pendingCode",
                ownerScope: PrivateLocalDataScope.pendingInvite
            ),
            Data(code.utf8)
        )
    }
}
