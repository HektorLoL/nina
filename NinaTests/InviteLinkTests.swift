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
