import XCTest
@testable import Nina

final class BackendConfigurationTests: XCTestCase {
    private let publishableKey = "sb_publishable_1234567890abcdefghijklmnop"

    func testAcceptsSecureRootURLAndModernPublishableKey() throws {
        let configuration = try XCTUnwrap(
            SupabaseConfiguration(
                rawURL: " https://project.supabase.co/ ",
                publishableKey: " \(publishableKey) "
            )
        )

        XCTAssertEqual(configuration.url.absoluteString, "https://project.supabase.co/")
        XCTAssertEqual(configuration.publishableKey, publishableKey)
    }

    func testAllowsLoopbackHTTPOnlyWhenExplicitlyEnabled() throws {
        let local = SupabaseConfiguration(
            rawURL: "http://127.0.0.1:54321",
            publishableKey: publishableKey,
            allowsInsecureLocalhost: true
        )
        let releaseLocal = SupabaseConfiguration(
            rawURL: "http://127.0.0.1:54321",
            publishableKey: publishableKey
        )
        let remoteHTTP = SupabaseConfiguration(
            rawURL: "http://project.supabase.co",
            publishableKey: publishableKey,
            allowsInsecureLocalhost: true
        )

        XCTAssertNotNil(local)
        XCTAssertNil(releaseLocal)
        XCTAssertNil(remoteHTTP)
    }

    func testRejectsURLsWithUnexpectedAuthorityOrRoutingComponents() {
        XCTAssertNil(
            SupabaseConfiguration(
                rawURL: "https://user:password@project.supabase.co",
                publishableKey: publishableKey
            )
        )
        XCTAssertNil(
            SupabaseConfiguration(
                rawURL: "https://project.supabase.co/rest/v1",
                publishableKey: publishableKey
            )
        )
        XCTAssertNil(
            SupabaseConfiguration(
                rawURL: "https://project.supabase.co?key=value",
                publishableKey: publishableKey
            )
        )
        XCTAssertNil(
            SupabaseConfiguration(
                rawURL: "https://project.supabase.co/#fragment",
                publishableKey: publishableKey
            )
        )
    }

    func testAcceptsOnlyAnonLegacyJWTs() throws {
        let anonKey = try legacyJWT(role: "anon")
        let serviceRoleKey = try legacyJWT(role: "service_role")

        XCTAssertNotNil(
            SupabaseConfiguration(
                rawURL: "https://project.supabase.co",
                publishableKey: anonKey
            )
        )
        XCTAssertNil(
            SupabaseConfiguration(
                rawURL: "https://project.supabase.co",
                publishableKey: serviceRoleKey
            )
        )
    }

    func testRejectsSecretAndPlaceholderKeys() {
        XCTAssertNil(
            SupabaseConfiguration(
                rawURL: "https://project.supabase.co",
                publishableKey: "sb_secret_1234567890abcdefghijklmnop"
            )
        )
        XCTAssertNil(
            SupabaseConfiguration(
                rawURL: "https://project.supabase.co",
                publishableKey: "$(NINA_SUPABASE_PUBLISHABLE_KEY)"
            )
        )
    }

    private func legacyJWT(role: String) throws -> String {
        let header = try base64URL(["alg": "HS256", "typ": "JWT"])
        let payload = try base64URL(["role": role])
        return "\(header).\(payload).signature"
    }

    private func base64URL(_ object: [String: String]) throws -> String {
        try JSONSerialization.data(withJSONObject: object)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
