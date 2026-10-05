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
        for text in [KidsMode.greeting(firstName: "Ana"), KidsMode.progressLine(done: 0, total: 1)] {
            XCTAssertFalse(text.contains("!"))
            XCTAssertFalse(text.lowercased().contains("eu "))
        }
    }
}
