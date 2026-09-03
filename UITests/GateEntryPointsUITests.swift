import XCTest

/// SPEC: the gate "Fires on a tap on the listing card ... Also fires on the
/// list's signup button, on a blurred row, and on the header control."
/// Four entry points, tested one per method so a failure names the one.
@MainActor
final class GateEntryPointsUITests: XCTestCase {

    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ALLoopsLaunchMoment"] = "0"
        app.launchEnvironment["ALAlwaysShowLaunchMoment"] = "0"
        app.launchEnvironment["ALUsesStubLocation"] = "1"
        app.launch()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'rentals in San Francisco'")
            ).firstMatch.waitForExistence(timeout: 25)
        )
        return app
    }

    /// Any of the wall's own copy showing means the wall is up.
    private func wallIsUp(_ app: XCUIApplication) -> Bool {
        app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'See every unit'")
        ).firstMatch.exists
            || app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'Create a free account'")
            ).firstMatch.exists
            || app.buttons["Continue with email"].exists
    }

    private func dump(_ app: XCUIApplication, _ label: String) {
        print("---------- \(label) ----------")
        for button in app.buttons.allElementsBoundByIndex where !button.label.isEmpty {
            print("  BTN | \(button.label) | hittable=\(button.isHittable)")
        }
        for text in app.staticTexts.allElementsBoundByIndex
        where !text.label.isEmpty && !text.label.hasPrefix("from $") {
            print("  TXT | \(text.label)")
        }
        print("---------- end \(label) ----------")
    }

    private func selectFromList(_ label: String, in app: XCUIApplication) {
        let matches = app.buttons.matching(
            NSPredicate(format: "label == %@", label)
        ).allElementsBoundByIndex
        guard let row = matches.max(by: { $0.frame.minY < $1.frame.minY }) else {
            XCTFail("no row labelled '\(label)'")
            return
        }
        row.tap()
        sleep(2)
    }

    // MARK: - 1. The listing card (the primary entry point)

    func test_gateFiresOnACardTap() {
        let app = launched()
        selectFromList("Vaquero Flats, Mission, from $2,395", in: app)

        let card = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Vaquero Flats, Mission.'")
        ).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the card never opened")
        print("card frame=\(card.frame) hittable=\(card.isHittable)")
        XCTAssertTrue(card.isHittable, "the listing card cannot receive a touch")

        card.tap()
        sleep(3)
        dump(app, "after card tap")
        XCTAssertTrue(
            wallIsUp(app),
            "SPEC: the gate fires on a tap on the listing card. It did not."
        )
    }

    // MARK: - 2. The list's signup button

    func test_gateFiresOnTheListSignupButton() {
        let app = launched()
        let gate = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Sign up to see all'")
        ).firstMatch
        XCTAssertTrue(gate.waitForExistence(timeout: 5))
        print("list gate frame=\(gate.frame) hittable=\(gate.isHittable)")
        gate.tap()
        sleep(3)
        dump(app, "after list gate tap")
        XCTAssertTrue(wallIsUp(app), "the list's signup button did not open the wall")
    }

    // MARK: - 3. A blurred row

    func test_gateFiresOnABlurredRow() {
        let app = launched()
        let locked = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Locked building'")
        ).allElementsBoundByIndex
        XCTAssertFalse(locked.isEmpty, "no locked rows on screen")
        guard let row = locked.first(where: { $0.isHittable })
            ?? locked.first else { return }
        print("blurred row frame=\(row.frame) hittable=\(row.isHittable)")
        row.tap()
        sleep(3)
        dump(app, "after blurred row tap")
        XCTAssertTrue(wallIsUp(app), "tapping a blurred row did not open the wall")
    }

    // MARK: - 4. The header control

    func test_gateFiresOnTheHeaderControl() {
        let app = launched()
        // The header is only reachable once a card is up, so select one first.
        selectFromList("Vaquero Flats, Mission, from $2,395", in: app)

        let signUp = app.buttons["Sign up"]
        XCTAssertTrue(signUp.waitForExistence(timeout: 5))
        print("header Sign up frame=\(signUp.frame) hittable=\(signUp.isHittable)")
        XCTAssertTrue(signUp.isHittable, "the header Sign up control cannot receive a touch")
        signUp.tap()
        sleep(3)
        dump(app, "after header Sign up tap")
        XCTAssertTrue(wallIsUp(app), "the header control did not open the wall")
    }
}
