import XCTest

/// Walks to each screen and writes a PNG to /tmp/qa-shots so the appearance and
/// Dynamic Type passes can be reviewed as images.
@MainActor
final class ScreenshotUITests: XCTestCase {

    private func save(_ app: XCUIApplication, _ name: String) {
        let dir = URL(fileURLWithPath: "/tmp/qa-shots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = app.screenshot().pngRepresentation
        try? data.write(to: dir.appendingPathComponent("\(name).png"))
        print("SAVED \(name) (\(data.count) bytes)")
    }

    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ALLoopsLaunchMoment"] = "0"
        app.launchEnvironment["ALAlwaysShowLaunchMoment"] = "0"
        app.launchEnvironment["ALUsesStubLocation"] = "1"
        app.launch()
        _ = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'rentals in San Francisco'")
        ).firstMatch.waitForExistence(timeout: 25)
        return app
    }

    private func selectVaquero(_ app: XCUIApplication) {
        let rows = app.buttons.matching(
            NSPredicate(format: "label == %@", "Vaquero Flats, Mission, from $2,395")
        ).allElementsBoundByIndex
        rows.max(by: { $0.frame.minY < $1.frame.minY })?.tap()
        sleep(2)
    }

    /// Suffix comes from the launch environment so one method covers every
    /// appearance and text-size combination the runner sets up.
    private var suffix: String {
        ProcessInfo.processInfo.environment["QA_SHOT_SUFFIX"] ?? "default"
    }

    func test_captureEveryScreen() {
        let app = launched()
        save(app, "map-\(suffix)")

        selectVaquero(app)
        save(app, "card-peek-\(suffix)")

        // Expand to the taller detent.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
            .press(
                forDuration: 0.2,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
            )
        sleep(2)
        save(app, "card-expanded-\(suffix)")

        // The wall, via the card.
        let card = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Vaquero Flats, Mission.'")
        ).firstMatch
        if card.exists { card.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).tap() }
        sleep(3)
        save(app, "wall-\(suffix)")

        // The wall with the email field revealed: the detent is fixed, so this
        // is where content overflow shows up.
        if app.buttons["Continue with email"].exists {
            app.buttons["Continue with email"].tap()
            sleep(2)
            save(app, "wall-email-\(suffix)")

            let field = app.textFields.firstMatch
            if field.waitForExistence(timeout: 3) {
                field.tap()
                field.typeText("renter@example.com")
                app.buttons["Continue"].tap()
                sleep(7)
                save(app, "after-signup-\(suffix)")
            }
        }
    }

    /// The explainer and recovery sheets.
    func test_captureLocationSheets() {
        let app = launched()
        selectVaquero(app)
        let locate = app.buttons["Use my location"]
        if locate.waitForExistence(timeout: 5), locate.isHittable {
            locate.tap()
            sleep(2)
            save(app, "explainer-\(suffix)")
        }
    }
}
