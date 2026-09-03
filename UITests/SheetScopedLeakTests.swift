import XCTest

/// Frame-scoped leak check.
///
/// Unscoped queries cannot answer this question. A map pin is a button labelled
/// "Bartlett Row, Mission, from $2,250" and is exposed BY DESIGN (SPEC: exact
/// pins with the floor of the range). So a whole-app query reports a leak the
/// spec requires, and an absent-pin moment reports a pass that is not real.
/// Only elements inside the listings sheet count.
@MainActor
final class SheetScopedLeakTests: XCTestCase {

    func test_noGatedBuildingIsReadableInsideTheListingsSheet() {
        let app = XCUIApplication()
        app.launchEnvironment["ALLoopsLaunchMoment"] = "0"
        app.launchEnvironment["ALAlwaysShowLaunchMoment"] = "0"
        app.launchEnvironment["ALUsesStubLocation"] = "1"
        app.launch()

        let header = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'rentals in'")
        ).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 25), "never reached the map")
        sleep(3)

        // Guard against the false-pass case: if no pins are on screen we are
        // not actually testing the discrimination we think we are.
        let pinCount = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'from $'")
        ).count
        print("pins on screen: \(pinCount)")
        XCTAssertGreaterThan(pinCount, 0, "no pins rendered, so a pass here would be meaningless")

        // The sheet begins at the header. Anything at or below it is in-sheet.
        let sheetTop = header.frame.minY
        print("sheet top y = \(sheetTop)")

        let gated = [
            "Bartlett Row", "The Corbett", "Lyon & Green", "1188 Mission",
            "Cypress & 19th", "The Alameda", "Fell Street Flats"
        ]

        var inSheetLeaks: [String] = []
        var pinOnlyExposures: [String] = []

        for name in gated {
            let all = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", name)
            ).allElementsBoundByIndex

            let inSheet = all.filter { $0.frame.minY >= sheetTop && $0.frame.height > 0 }
            let aboveSheet = all.filter { $0.frame.minY < sheetTop }

            print("  \(name): total=\(all.count) inSheet=\(inSheet.count) aboveSheet=\(aboveSheet.count)")
            for e in inSheet { print("      IN-SHEET  y=\(Int(e.frame.minY)) '\(e.label)'") }

            if !inSheet.isEmpty { inSheetLeaks.append(name) }
            if !aboveSheet.isEmpty { pinOnlyExposures.append(name) }
        }

        print("gated names exposed ONLY above the sheet (map pins, by design): \(pinOnlyExposures.count)")

        XCTAssertTrue(
            inSheetLeaks.isEmpty,
            "LEAK inside the listings sheet: \(inSheetLeaks.joined(separator: ", "))"
        )
        XCTAssertEqual(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", "Locked. Sign up to see this building.")
            ).count > 0, true,
            "no element announces as locked"
        )
    }
}
