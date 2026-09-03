import XCTest

/// QA suite. `simctl` cannot drive taps, so every flow that needs a gesture
/// lives here: the card at both detents, the wall, the detail screen, and the
/// location sheets. It is also the only place we can assert on what VoiceOver
/// would actually read, which SPEC.md makes a non-negotiable.
/// `@MainActor` because the whole XCUI element API is main-actor isolated and
/// this project builds with strict concurrency complete.
@MainActor
final class BrowseFlowUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Looping launch plus one tap is the fast way in: the non-looping sequence
    /// takes twelve seconds before it hands off on its own.
    private func launchToMap(
        reduceMotion: Bool = false,
        extraEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        // The launch moment plays once per install, so a helper that waits for
        // it hangs on the second run. Skip it and wait on the listings header,
        // which is the real proof the map is up.
        app.launchEnvironment["ALLoopsLaunchMoment"] = "0"
        app.launchEnvironment["ALAlwaysShowLaunchMoment"] = "0"
        app.launchEnvironment["ALUsesStubLocation"] = "1"
        for (key, value) in extraEnvironment { app.launchEnvironment[key] = value }
        if reduceMotion {
            app.launchArguments += ["-UIAccessibilityReduceMotionEnabled", "1"]
        }
        app.launch()

        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS 'rentals in'")
            ).firstMatch.waitForExistence(timeout: 25),
            "the listings sheet header never appeared, so the map never loaded"
        )
        return app
    }

    private func text(containing needle: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", needle)
        ).firstMatch
    }

    /// Taps the LIST row for a building, not the identically-labelled map pin.
    /// Both carry "Name, Hood, from $X"; the row is the one lowest on screen.
    private func selectFromList(_ prefix: String, in app: XCUIApplication) {
        let matches = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", prefix + ",")
        ).allElementsBoundByIndex
        guard let row = matches.max(by: { $0.frame.minY < $1.frame.minY }) else {
            XCTFail("no row for \(prefix)")
            return
        }
        row.tap()
        sleep(2)
    }

    /// The card's own combined label begins "Name, Hood." with a period.
    private func card(_ name: String, _ hood: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "\(name), \(hood).")
        ).firstMatch
    }

    // MARK: - 00 Structure

    /// Not an assertion, a probe. Prints the accessibility tree so the rest of
    /// the suite can target real elements instead of guesses.
    func test_00_dumpAccessibilityTree() {
        let app = launchToMap()
        print("===== MAP TREE BEGIN =====")
        print(app.debugDescription)
        print("===== MAP TREE END =====")

        print("===== BUTTON LABELS =====")
        for button in app.buttons.allElementsBoundByIndex {
            print("BUTTON | \(button.label) | id=\(button.identifier) | hittable=\(button.isHittable)")
        }
        print("===== STATIC TEXTS =====")
        for element in app.staticTexts.allElementsBoundByIndex {
            print("TEXT | \(element.label)")
        }
        print("===== OTHER ELEMENTS (pins live here) =====")
        for element in app.otherElements.allElementsBoundByIndex where !element.label.isEmpty {
            print("OTHER | \(element.label)")
        }
    }

    // MARK: - 01 The blurred rows must not be readable

    /// Superseded by `SheetScopedLeakTests`.
    ///
    /// This version queried the whole app, so it also matched the MAP PIN --
    /// a button labelled "Bartlett Row, Mission, from $2,250" that SPEC line 17
    /// requires to be exposed. It therefore reported a leak the spec mandates,
    /// and masked whether the in-sheet rows were actually fixed. Kept only as a
    /// smoke check that the locked rows announce themselves.
    func test_01_lockedRowsAnnounceAsLocked() {
        let app = launchToMap()
        sleep(2)
        let locked = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Locked. Sign up to see this building.")
        ).count
        print("elements announcing as locked: \(locked)")
        XCTAssertGreaterThan(
            locked, 0,
            "no element announces as locked, so a blurred row has no accessible identity"
        )
    }

    // MARK: - 02 Card at both detents

    func test_02_cardOpensAtPeekAndExpands() {
        let app = launchToMap()

        selectFromList("Vaquero Flats", in: app)

        let card = card("Vaquero Flats", "Mission", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the card never appeared after a row tap")
        print("CARD LABEL (peek): \(card.label)")
        print("===== CARD TREE AT PEEK =====")
        print(app.debugDescription)

        // The peek detent is a compact row: no photo gallery yet.
        let captionAtPeek = app.staticTexts["FACADE"].exists
            || app.staticTexts["LIVING ROOM"].exists
            || app.staticTexts["BAY WINDOW"].exists
        print("gallery caption visible at peek: \(captionAtPeek)")

        // The locked row names what is withheld, before the tap.
        let locked = text(containing: "Locked:", in: app)
        XCTAssertTrue(locked.exists, "SPEC: the card must show a locked row naming what is withheld")
        print("LOCKED ROW LABEL: \(locked.label)")

        // Drag the sheet from its peek detent up to the taller one.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.80))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
        start.press(forDuration: 0.15, thenDragTo: end)
        sleep(1)
        let captionAfterDrag = app.staticTexts["FACADE"].exists
            || app.staticTexts["LIVING ROOM"].exists
            || app.staticTexts["BAY WINDOW"].exists
        print("gallery caption visible after swipe up: \(captionAfterDrag)")
        print("===== TREE AFTER EXPAND =====")
        print(app.debugDescription)
    }

    // MARK: - 03 The wall

    func test_03_wallNamesTheBuildingAndSurfacesAnInvalidEmail() {
        let app = launchToMap()
        selectFromList("Vaquero Flats", in: app)
        let card = card("Vaquero Flats", "Mission", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()

        // SPEC: the ask has a subject.
        let headline = text(containing: "See every unit at", in: app)
        XCTAssertTrue(headline.waitForExistence(timeout: 5), "the wall did not name the building")
        print("WALL HEADLINE: \(headline.label)")

        // The promise must name the five withheld things.
        let promise = text(containing: "Create a free account", in: app)
        XCTAssertTrue(promise.exists)
        print("WALL PROMISE: \(promise.label)")

        app.buttons["Continue with email"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("nope")
        app.buttons["Continue"].tap()

        // This is the assertion that needs a device: the error text is read
        // inside the sheet's content closure, so it only appears if @Observable
        // re-invokes that closure on a SessionStore change.
        let error = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'does not look like an email'")
        ).firstMatch
        XCTAssertTrue(
            error.waitForExistence(timeout: 6),
            "the wall never surfaced the invalid-email error"
        )
        print("WALL ERROR SHOWN: \(error.label)")

        // The wall must still be up after a failure.
        XCTAssertTrue(headline.exists, "SPEC: a failure leaves the wall up")
    }

    func test_04_signupLandsOnTheBuildingItStartedFrom() {
        let app = launchToMap()
        selectFromList("The Duboce", in: app)
        let card = card("The Duboce", "Duboce Triangle", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()

        XCTAssertTrue(text(containing: "See every unit at", in: app).waitForExistence(timeout: 5))
        app.buttons["Continue with email"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("renter@example.com")
        app.buttons["Continue"].tap()

        // SPEC: "After signup from a building, the renter lands on that
        // building, not a dead end."
        // Assert on the reward, not on the badge: the exact street address is
        // a gated field, so its presence proves we are on the detail screen.
        let landedAddress = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'San Francisco, CA'")
        ).firstMatch
        XCTAssertTrue(
            landedAddress.waitForExistence(timeout: 12),
            "signup did not land on the detail screen"
        )
        print("DETAIL ADDRESS: \(landedAddress.label)")

        XCTAssertTrue(
            text(containing: "The Duboce", in: app).exists,
            "landed on a detail screen, but not the building the wall was opened from"
        )

        print("===== DETAIL TREE =====")
        print(app.debugDescription)

        // The reward: rent per unit, move-in dates, the exact address.
        let address = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS 'San Francisco, CA'")
        ).firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 6), "the exact address never loaded")
        print("DETAIL ADDRESS: \(address.label)")

        let availability = app.descendants(matching: .any).containing(
            NSPredicate(format: "label CONTAINS 'Available' OR label CONTAINS 'Call for availability'")
        ).firstMatch
        XCTAssertTrue(availability.exists, "move-in dates never rendered")

        // Back to the map.
        app.buttons["Map"].tap()
        // Returning keeps the building selected, so the sheet shows that
        // building's card rather than the list. Assert on the map surface
        // itself, not on the listings header.
        XCTAssertTrue(
            app.buttons["Use my location"].waitForExistence(timeout: 15),
            "back from detail did not return to the map"
        )
    }

    // MARK: - 05 Location

    func test_05_locateShowsOurExplainerAndDismissingKeepsThePromptSpendable() {
        let app = launchToMap()

        let locate = app.buttons["Use my location"]
        XCTAssertTrue(locate.waitForExistence(timeout: 5))
        locate.tap()

        // SPEC: locate tap -> our explainer -> system prompt.
        let explainer = app.staticTexts["See what is near you"]
        XCTAssertTrue(explainer.waitForExistence(timeout: 5), "the locate tap did not open our explainer")

        app.buttons["Not now"].tap()
        XCTAssertFalse(
            explainer.waitForExistence(timeout: 2),
            "the explainer did not dismiss"
        )

        // SPEC: "Dismissing it must leave authorization .notDetermined." The
        // observable proof is that the next tap offers the explainer again
        // rather than the recovery sheet.
        locate.tap()
        XCTAssertTrue(
            explainer.waitForExistence(timeout: 5),
            "the second locate tap did not re-offer the explainer, so the prompt was spent by a dismissal"
        )

        app.buttons["Continue"].tap()
        // Stub grants when-in-use with full precision.
        XCTAssertFalse(
            app.staticTexts["Approximate location"].waitForExistence(timeout: 3),
            "full precision was granted but the app claims approximate location"
        )
    }

    /// The second locate tap after a grant must re-centre the map, even for a
    /// stationary renter whose coordinate has not changed. This was originally
    /// written expecting to fail, because the camera move was driven by a value
    /// diff on the coordinate; `LocationPermissionStore.recenterRequests` made
    /// the tap itself the event, and this is now a genuine pass.
    func test_06_repeatedLocateTapRecentresTheMap() {
        let app = launchToMap()
        let locate = app.buttons["Use my location"]
        XCTAssertTrue(locate.waitForExistence(timeout: 5))

        locate.tap()
        XCTAssertTrue(app.staticTexts["See what is near you"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()
        sleep(2)

        // Pan away from the granted location.
        app.swipeLeft()
        app.swipeUp()
        sleep(1)
        let afterPan = app.screenshot().pngRepresentation

        locate.tap()
        sleep(3)
        let afterSecondTap = app.screenshot().pngRepresentation

        XCTAssertNotEqual(
            afterPan, afterSecondTap,
            "the second locate tap changed nothing: the camera never returned to the renter"
        )
    }

    // MARK: - 07 Filters

    /// With one matching building nothing is locked, so a gate button that
    /// offers to unlock "all 1" is selling something already on screen.
    func test_07_gateButtonIsNotOfferedWhenNothingIsLocked() {
        let app = launchToMap()

        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Search a neighborhood'")
        ).firstMatch.tap()
        sleep(2)

        let hood = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Bernal Heights'")
        ).firstMatch
        XCTAssertTrue(hood.waitForExistence(timeout: 5), "the neighborhood search never opened")
        hood.tap()

        let header = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'building'")
        ).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        print("HEADER AFTER FILTER: \(header.label)")

        let gate = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Sign up to see all'")
        ).firstMatch
        if gate.exists { print("GATE BUTTON: \(gate.label)") }

        XCTAssertFalse(
            gate.exists,
            "gate button '\(gate.label)' is shown but every matching building is already readable"
        )
    }

    func test_08_emptyResultStateIsReachableAndSaysSo() {
        let app = launchToMap()

        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Search a neighborhood'")
        ).firstMatch.tap()
        sleep(2)
        let hood = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Bernal Heights'")
        ).firstMatch
        XCTAssertTrue(hood.waitForExistence(timeout: 5))
        hood.tap()

        app.buttons["Studio"].tap()

        let empty = app.staticTexts["Nothing matches those filters"]
        XCTAssertTrue(empty.waitForExistence(timeout: 6), "the empty state never rendered")

        // No gate button may float over an empty list.
        let gate = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Sign up to see all'")
        ).firstMatch
        XCTAssertFalse(gate.exists, "gate button '\(gate.label)' is offered over zero results")

        // The copy tells the renter to widen the filters, so there should be a
        // way to do that from here.
        print("===== EMPTY STATE TREE =====")
        print(app.debugDescription)
    }

    // MARK: - 09 The launch moment

    /// SPEC line 10: the shipping launch moment "plays once and advances
    /// itself". SPEC line 59: Reduce Motion collapses it to a static question.
    /// Both must hold at the same time.
    func test_09_nonLoopingLaunchAdvancesUnderReduceMotion() {
        let app = XCUIApplication()
        app.launchEnvironment["ALLoopsLaunchMoment"] = "0"
        app.launchEnvironment["ALUsesStubLocation"] = "1"
        app.launchArguments += ["-UIAccessibilityReduceMotionEnabled", "1"]
        app.launch()

        let mapHeader = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS 'rentals in'")
        ).firstMatch
        XCTAssertTrue(
            mapHeader.waitForExistence(timeout: 30),
            "BLOCKER: with Reduce Motion on, the non-looping launch moment never advances to the map"
        )
    }
}
