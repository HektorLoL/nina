import XCTest
@testable import Nina

@MainActor
final class KidsModeTests: XCTestCase {
    func testKidsModeIsOnByDefaultOnlyForAChildUnderTwelve() {
        XCTAssertTrue(KidsMode.isOn(band: .under12, override: ""))
        XCTAssertFalse(KidsMode.isOn(band: .twelveToFifteen, override: ""))
        XCTAssertFalse(KidsMode.isOn(band: .sixteenToSeventeen, override: ""))
        XCTAssertFalse(KidsMode.isOn(band: nil, override: ""))
    }

    func testTheSwitchInAjustesWinsOverTheBandBothWays() {
        XCTAssertTrue(KidsMode.isOn(band: .twelveToFifteen, override: KidsMode.Override.on.rawValue))
        XCTAssertFalse(KidsMode.isOn(band: .under12, override: KidsMode.Override.off.rawValue))
        XCTAssertTrue(KidsMode.isOn(band: .under12, override: "anything else"))
    }

    func testEveryCategoryGetsAFilledColourfulTileAndAnUnknownOneGetsAStar() {
        for category in TaskCategory.allCases {
            let tile = KidsMode.tile(for: category.symbolName)
            XCTAssertTrue(tile.symbolName.hasSuffix(".fill") || tile.symbolName == "fork.knife", category.id)
            XCTAssertNotNil(UIImage(systemName: tile.symbolName), tile.symbolName)
        }
        XCTAssertEqual(KidsMode.tile(for: "tag").symbolName, "star.fill")
        XCTAssertEqual(
            Set(TaskCategory.allCases.map { KidsMode.tile(for: $0.symbolName).symbolName }).count,
            TaskCategory.allCases.count
        )
    }

    func testTheGreetingAndProgressNeverShoutAndNeverSpeakAsNina() {
        XCTAssertEqual(KidsMode.greeting(firstName: "Ana"), "Oi, Ana")
        XCTAssertEqual(KidsMode.greeting(firstName: "  "), "Oi")
        XCTAssertEqual(KidsMode.progressLine(done: 2, total: 5), "2 de 5 feitas")
        XCTAssertEqual(KidsMode.progressLine(done: 1, total: 1), "1 de 1 feita")
        for text in [KidsMode.greeting(firstName: "Ana"), KidsMode.progressLine(done: 0, total: 1)] {
            XCTAssertFalse(text.contains("!"))
            XCTAssertFalse(text.lowercased().contains("eu "))
        }
    }

    func testModoCriancaIsKeptPerAccountSoASiblingOpensInTheirOwnBandsDefault() async throws {
        let suiteName = "KidsModeTests.\(#function).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nina-kids-mode-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        defaults.set(KidsMode.Override.on.rawValue, forKey: KidsMode.legacyOverrideKey)
        let store = AppStore(
            defaults: defaults,
            privateDataStore: ProtectedLocalDataStore(directoryURL: directory),
            remoteHomeBackend: nil,
            ninaEngine: MockNinaEngine()
        )
        let teen = AuthUser(id: UUID().uuidString, displayName: "Bia", email: nil, provider: .apple)
        let sibling = AuthUser(id: UUID().uuidString, displayName: "Leo", email: nil, provider: .apple)

        await store.activateHomeContext(for: teen)
        XCTAssertEqual(store.kidsModeOverride, "")
        XCTAssertNil(defaults.string(forKey: KidsMode.legacyOverrideKey))

        store.setKidsMode(true)
        await store.activateHomeContext(for: sibling)
        XCTAssertEqual(store.kidsModeOverride, "")

        await store.activateHomeContext(for: teen)
        XCTAssertEqual(store.kidsModeOverride, KidsMode.Override.on.rawValue)

        store.clearLocalData(for: teen.id)
        XCTAssertNil(defaults.string(forKey: KidsMode.overrideKey(for: teen.id)))
        XCTAssertEqual(store.kidsModeOverride, "")
    }
}
