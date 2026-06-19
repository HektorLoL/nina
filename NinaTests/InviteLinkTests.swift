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

        let firstStore = InviteLinkStore(defaults: defaults)
        XCTAssertTrue(firstStore.receive(try XCTUnwrap(URL(string: "https://ninai.app/invite/\(code)"))))

        let restoredStore = InviteLinkStore(defaults: defaults)
        XCTAssertEqual(restoredStore.pendingCode, code)

        restoredStore.clear()
        XCTAssertNil(InviteLinkStore(defaults: defaults).pendingCode)
    }
}
