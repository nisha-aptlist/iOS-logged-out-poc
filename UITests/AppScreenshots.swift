import XCTest

/// Captures the documented screens from a real run.
///
/// These are the images in `Screenshots/`. They are produced by driving the app,
/// not staged, so a screenshot that no longer matches the app is a failing test
/// rather than a stale file nobody noticed.
@MainActor
final class AppScreenshots: XCTestCase {

    private let out = "/tmp/al-shots"

    override func setUp() {
        try? FileManager.default.createDirectory(
            atPath: out, withIntermediateDirectories: true
        )
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        let data = app.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
        print("SHOT \(name)")
    }

    private func app(_ env: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ALUsesStubLocation"] = "1"
        app.launchEnvironment["ALSkipLaunchMoment"] = "1"
        for (k, v) in env { app.launchEnvironment[k] = v }
        app.launch()
        return app
    }

    private func waitForMap(_ app: XCUIApplication) {
        XCTAssertTrue(
            app.staticTexts["Vaquero Flats"].waitForExistence(timeout: 30),
            "never reached a loaded map"
        )
    }

    /// The launch moment, held open by the looping demo flag.
    func test_01_launch() {
        let app = self.app([
            "ALSkipLaunchMoment": "0",
            "ALAlwaysShowLaunchMoment": "1",
            "ALLoopsLaunchMoment": "1"
        ])
        XCTAssertTrue(app.staticTexts["SAN FRANCISCO"].waitForExistence(timeout: 20))
        save(app, "01-launch")
    }

    /// Map, chrome, and the gated listings sheet.
    func test_02_map() {
        let app = self.app()
        waitForMap(app)
        save(app, "02-map")
    }

    /// The card at its peek detent, then dragged tall.
    func test_03_card() {
        let app = self.app()
        waitForMap(app)

        app.staticTexts["Vaquero Flats"].tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS '$' AND label CONTAINS ' to '")
            ).firstMatch.waitForExistence(timeout: 10),
            "the card did not open"
        )
        save(app, "03-card-peek")

        // Drag the grabber up to the taller detent.
        let grabber = app.otherElements["Sheet height"].firstMatch
        if grabber.waitForExistence(timeout: 5) {
            let from = grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let to = from.withOffset(CGVector(dx: 0, dy: -280))
            from.press(forDuration: 0.1, thenDragTo: to)
            save(app, "04-card-expanded")
        }
    }

    /// The wall, then the unlocked detail it leads to.
    func test_05_wallAndDetail() {
        let app = self.app()
        waitForMap(app)

        app.staticTexts["Vaquero Flats"].tap()
        _ = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '$' AND label CONTAINS ' to '")
        ).firstMatch.waitForExistence(timeout: 10)

        app.staticTexts["Vaquero Flats"].firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'See every unit at'")
            ).firstMatch.waitForExistence(timeout: 10),
            "the wall did not present"
        )
        save(app, "05-signup-wall")

        app.buttons["Continue with email"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        field.typeText("renter@example.com")
        save(app, "06-wall-email")

        app.buttons["Continue"].tap()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'AVAILABLE UNITS'"))
                .firstMatch.waitForExistence(timeout: 15),
            "signup did not land on the building"
        )
        save(app, "07-unlocked-detail")
    }

    /// Our pre-permission explainer, over the map.
    func test_08_locationExplainer() {
        let app = self.app()
        waitForMap(app)
        app.buttons["Use my location"].tap()
        XCTAssertTrue(app.staticTexts["See what is near you"].waitForExistence(timeout: 10))
        save(app, "08-location-explainer")
    }

    /// A renter whose one prompt is already spent.
    func test_09_locationRecovery() {
        let app = self.app(["ALStubLocationOutcome": "predenied"])
        waitForMap(app)
        app.buttons["Use my location"].tap()
        XCTAssertTrue(
            app.staticTexts["Location is off for Apartment List"].waitForExistence(timeout: 10)
        )
        save(app, "09-location-recovery")
    }

    /// Precision withheld: the app says so rather than implying exactness.
    func test_10_reducedPrecision() {
        let app = self.app(["ALStubLocationOutcome": "reduced"])
        waitForMap(app)
        app.buttons["Use my location"].tap()
        _ = app.staticTexts["See what is near you"].waitForExistence(timeout: 10)
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Approximate location"].waitForExistence(timeout: 10))
        save(app, "10-reduced-precision")
    }

    /// A filter with fewer results than the free row count: no gate is offered,
    /// because nothing is withheld.
    func test_11_nothingWithheld() {
        let app = self.app()
        waitForMap(app)
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Search a neighborhood'")
        ).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Where are you looking?"].waitForExistence(timeout: 10))
        let hood = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Bernal Heights'")
        ).firstMatch
        if hood.waitForExistence(timeout: 5) {
            hood.tap()
            _ = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'building'")
            ).firstMatch.waitForExistence(timeout: 10)
            save(app, "11-nothing-withheld")
        }
    }
}
