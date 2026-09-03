import XCTest

/// Renders the three permission surfaces that had never been seen on a device.
@MainActor
final class LocationOutcomeShots: XCTestCase {

    private func launch(outcome: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ALSkipLaunchMoment"] = "1"
        app.launchEnvironment["ALUsesStubLocation"] = "1"
        app.launchEnvironment["ALStubLocationOutcome"] = outcome
        app.launch()
        XCTAssertTrue(app.staticTexts["Vaquero Flats"].waitForExistence(timeout: 30))
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/al-\(name).png"))
        print("WROTE /tmp/al-\(name).png")
    }

    /// A renter who denied on a previous launch. The prompt is spent, so the
    /// locate control must go straight to recovery, never the explainer.
    func test_predeniedGoesStraightToRecovery() {
        let app = launch(outcome: "predenied")
        app.buttons["Use my location"].tap()
        XCTAssertTrue(
            app.staticTexts["Location is off for Apartment List"].waitForExistence(timeout: 10),
            "a spent prompt must route to recovery, not to the explainer"
        )
        XCTAssertFalse(
            app.staticTexts["See what is near you"].exists,
            "the explainer would be a lie: the system prompt can no longer fire"
        )
        shot(app, "recovery")
    }

    /// Denying at the system prompt must NOT immediately push recovery; the
    /// next deliberate tap does.
    func test_denialIsNotImmediatelyNagged() {
        let app = launch(outcome: "denied")
        app.buttons["Use my location"].tap()
        XCTAssertTrue(app.staticTexts["See what is near you"].waitForExistence(timeout: 10))
        app.buttons["Continue"].tap()

        XCTAssertFalse(
            app.staticTexts["Location is off for Apartment List"].waitForExistence(timeout: 3),
            "two sheets back to back reads as nagging"
        )
        app.buttons["Use my location"].tap()
        XCTAssertTrue(
            app.staticTexts["Location is off for Apartment List"].waitForExistence(timeout: 10),
            "the next deliberate tap should open recovery"
        )
    }

    /// Precision withheld: the UI must say so rather than imply exactness.
    func test_reducedPrecisionSaysSo() {
        let app = launch(outcome: "reduced")
        app.buttons["Use my location"].tap()
        XCTAssertTrue(app.staticTexts["See what is near you"].waitForExistence(timeout: 10))
        app.buttons["Continue"].tap()
        XCTAssertTrue(
            app.staticTexts["Approximate location"].waitForExistence(timeout: 10),
            "precision was withheld and nothing says so"
        )
        shot(app, "reduced")
    }
}
