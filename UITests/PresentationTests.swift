import XCTest

/// Does anything actually present?
///
/// This suite exists because of a defect no unit test could have caught and no
/// amount of reading did catch: `RootView` presented the signup wall with its
/// own `.sheet` and the detail with `.fullScreenCover`, both of which resolve
/// to the same presentation host as the always-up listings sheet. That sheet
/// holds the only slot, so **the gate was unreachable in the running app** from
/// every one of its four entry points.
///
/// Thirty-seven unit tests passed throughout. The lesson is that presentation
/// is not testable from a store, so it gets its own suite.
@MainActor
final class PresentationTests: XCTestCase {

    /// Waits for LOADED, not merely rendered.
    ///
    /// This gate was `label CONTAINS 'rentals in'`, which also matched the
    /// loading skeleton ("Finding rentals in San Francisco") and even a cluster
    /// pin's accessibility label ("94 rentals in 3 buildings"). So it returned
    /// while the fetch was still in flight and every test then raced a 220ms
    /// repository latency. Three of four tests failed on their first
    /// interaction because nothing was on screen yet.
    ///
    /// The fix is to wait on something that exists ONLY when loaded. A known
    /// building name is that thing: it comes from the fetched inventory, and no
    /// loading or chrome string can satisfy it.
    private func launchToMap() -> XCUIApplication {
        let app = XCUIApplication()
        // Skip the launch moment entirely. Whichever test ran first on a fresh
        // simulator otherwise paid its full 11-second sequence, which is pure
        // variance in front of every assertion in the suite.
        app.launchEnvironment["ALSkipLaunchMoment"] = "1"
        app.launchEnvironment["ALUsesStubLocation"] = "1"
        app.launch()
        let firstBuilding = app.staticTexts["Vaquero Flats"]
        XCTAssertTrue(
            firstBuilding.waitForExistence(timeout: 30),
            "never reached a LOADED map"
        )
        return app
    }

    func test_wallPresentsFromTheListGateAndTheHeader() {
        let app = launchToMap()

        let gate = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Sign up to see all'")
        ).firstMatch
        XCTAssertTrue(gate.waitForExistence(timeout: 8), "the list gate button is missing")
        XCTAssertTrue(gate.isHittable, "the list gate button is not hittable")
        gate.tap()

        let headline = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'See every rental' OR label CONTAINS 'See every unit at'")
        ).firstMatch
        XCTAssertTrue(headline.waitForExistence(timeout: 10), "the wall did not present from the list gate")
        XCTAssertTrue(app.staticTexts["Rent for every unit"].exists, "the unlock bullets are missing")

        app.buttons["Not now"].tap()

        let pill = app.buttons["Sign up"]
        XCTAssertTrue(pill.waitForExistence(timeout: 8), "the header pill is missing")
        pill.tap()
        XCTAssertTrue(headline.waitForExistence(timeout: 10), "the wall did not present from the header pill")
    }

    func test_locateOpensOurExplainerAndDismissalKeepsThePromptSpendable() {
        let app = launchToMap()

        let locate = app.buttons["Use my location"]
        XCTAssertTrue(locate.waitForExistence(timeout: 8))
        locate.tap()

        let explainer = app.staticTexts["See what is near you"]
        XCTAssertTrue(explainer.waitForExistence(timeout: 10), "the explainer did not present")

        app.buttons["Not now"].tap()
        _ = explainer.waitForExistence(timeout: 2)

        // The observable proof that a dismissal did not spend the one system
        // prompt: the next tap offers the explainer again, not recovery.
        locate.tap()
        XCTAssertTrue(
            explainer.waitForExistence(timeout: 10),
            "the second locate tap did not re-offer the explainer, so the prompt was spent"
        )
    }

    func test_searchSharesTheSlotAndStillPresents() {
        let app = launchToMap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Search a neighborhood'"))
            .firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts["Where you looking?"].waitForExistence(timeout: 2)
                || app.staticTexts["Where are you looking?"].waitForExistence(timeout: 8),
            "the search sheet did not present"
        )
    }

    /// The demo path, end to end. This is the one that must not break in front
    /// of an audience.
    func test_fullFunnelCardToWallToUnlockedDetail() {
        let app = launchToMap()

        app.staticTexts["Vaquero Flats"].tap()
        let range = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '$' AND label CONTAINS ' to '")
        ).firstMatch
        XCTAssertTrue(range.waitForExistence(timeout: 8), "the card did not open with a rent range")

        // The card tap is the gate.
        app.staticTexts["Vaquero Flats"].firstMatch.tap()
        let named = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'See every unit at'")
        ).firstMatch
        XCTAssertTrue(named.waitForExistence(timeout: 10), "the wall did not name the building")

        app.buttons["Continue with email"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        field.typeText("renter@example.com")

        let cont = app.buttons["Continue"]
        // Regression guard: on a fixed-height sheet this button fell off the
        // bottom the moment the email field appeared.
        XCTAssertTrue(cont.isHittable, "the Continue button is not reachable")
        cont.tap()

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'AVAILABLE UNITS'"))
                .firstMatch.waitForExistence(timeout: 15),
            "signup did not land on the building it started from"
        )
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'San Francisco, CA'"))
                .firstMatch.exists,
            "the unlocked address is missing"
        )
    }

    /// Regression: the locate control used to die permanently.
    ///
    /// The precedence guard dropped a `permissions.step` transition that
    /// arrived while the wall was up, rather than deferring it. `step` then
    /// never changed again, so nothing re-drove the modal slot, and
    /// `locateTapped()` re-assigning the same value fires no `.onChange`. The
    /// control was dead for the rest of the session.
    func test_locateStillWorksAfterTheWallHasBeenDismissed() {
        let app = launchToMap()

        // Raise and dismiss the wall first.
        let gate = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Sign up to see all'")
        ).firstMatch
        XCTAssertTrue(gate.waitForExistence(timeout: 10))
        gate.tap()
        XCTAssertTrue(
            app.buttons["Not now"].waitForExistence(timeout: 10),
            "the wall did not present"
        )
        app.buttons["Not now"].tap()

        // Now locate must still work.
        let locate = app.buttons["Use my location"]
        XCTAssertTrue(locate.waitForExistence(timeout: 10))
        locate.tap()
        XCTAssertTrue(
            app.staticTexts["See what is near you"].waitForExistence(timeout: 10),
            "the locate control is dead after the wall was dismissed"
        )
    }
}
