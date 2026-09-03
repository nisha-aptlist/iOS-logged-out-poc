import XCTest

/// Is the map chrome reachable at all while the listings sheet is up?
///
/// SPEC: "`presentationBackgroundInteraction` is what makes it non-modal, so
/// the map stays pannable with the sheet up." If the background is modal
/// instead, the search pill, the five filter pills, the header Sign up, and the
/// locate control are all unreachable, and so is panning.
@MainActor
final class ChromeReachableUITests: XCTestCase {

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

    private func header(_ app: XCUIApplication) -> String {
        app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'rentals in'")
        ).firstMatch.label
    }

    /// Every chrome control must be able to receive a touch.
    func test_chromeControlsAreHittable() {
        let app = launched()
        let names = [
            "Use my location", "Sign up", "Any beds", "Studio", "1 bd", "2+ bd", "Max rent"
        ]
        var dead: [String] = []
        for name in names {
            let control = app.buttons[name]
            guard control.exists else { dead.append("\(name) (MISSING)"); continue }
            print("  \(name): exists=true hittable=\(control.isHittable) frame=\(control.frame)")
            if !control.isHittable { dead.append(name) }
        }
        let search = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Search'")
        ).firstMatch
        if search.exists {
            print("  search pill: '\(search.label)' hittable=\(search.isHittable)")
            if !search.isHittable { dead.append("search pill") }
        }
        XCTAssertTrue(
            dead.isEmpty,
            "chrome controls cannot receive a touch: \(dead.joined(separator: ", "))"
        )
    }

    /// Tapping a bedroom filter must change the result count.
    func test_bedroomFilterActuallyFilters() {
        let app = launched()
        let before = header(app)
        print("header before: \(before)")

        let studio = app.buttons["Studio"]
        XCTAssertTrue(studio.waitForExistence(timeout: 5))
        studio.tap()
        sleep(3)

        let after = header(app)
        print("header after tapping Studio: \(after)")
        XCTAssertNotEqual(
            before, after,
            "tapping the Studio filter changed nothing, so the filter row is unreachable"
        )
    }

    /// SPEC: the map stays pannable with the sheet up.
    func test_mapIsPannableWithTheSheetUp() {
        let app = launched()
        sleep(2)
        let before = app.screenshot().pngRepresentation

        // Drag across the map, well above the sheet.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.30))
            .press(
                forDuration: 0.2,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.30))
            )
        sleep(3)
        let after = app.screenshot().pngRepresentation

        XCTAssertNotEqual(
            before, after,
            "a drag across the map changed nothing: the sheet is modal and the map is frozen"
        )
    }

    /// The header Sign up is one of the four gate entry points.
    func test_headerSignUpOpensTheWall() {
        let app = launched()
        let signUp = app.buttons["Sign up"]
        XCTAssertTrue(signUp.waitForExistence(timeout: 5))
        signUp.tap()
        sleep(2)
        XCTAssertTrue(
            app.staticTexts["See every unit"].waitForExistence(timeout: 5),
            "the header Sign up control did not open the wall"
        )
    }

    /// A cluster bubble must zoom in when tapped.
    func test_clusterTapZoomsIn() {
        let app = launched()
        let cluster = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Double tap to zoom in'")
        ).firstMatch
        XCTAssertTrue(cluster.waitForExistence(timeout: 5), "no cluster bubbles on the map")
        print("cluster: '\(cluster.label)' hittable=\(cluster.isHittable)")

        let before = app.screenshot().pngRepresentation
        cluster.tap()
        sleep(3)
        let after = app.screenshot().pngRepresentation
        XCTAssertNotEqual(before, after, "tapping a cluster did nothing")
    }
}

/// Differential: does the chrome come alive once a card is selected?
///
/// The listings detent set is `[.fraction(0.48)]`, but the background
/// interaction modifier names `.fraction(0.58)`, which is only a member of the
/// *card's* detent set. If the chrome is dead in the list state and live in the
/// card state, that mismatch is the cause.
@MainActor
final class BackgroundInteractionDifferentialTests: XCTestCase {

    func test_chromeIsDeadInListStateAndLiveInCardState() {
        let app = XCUIApplication()
        app.launchEnvironment["ALLoopsLaunchMoment"] = "0"
        app.launchEnvironment["ALAlwaysShowLaunchMoment"] = "0"
        app.launchEnvironment["ALUsesStubLocation"] = "1"
        app.launch()
        _ = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'rentals in San Francisco'")
        ).firstMatch.waitForExistence(timeout: 25)

        let locate = app.buttons["Use my location"]
        XCTAssertTrue(locate.waitForExistence(timeout: 5))
        let inListState = locate.isHittable
        print("LIST state  (detents [0.48])        locate hittable = \(inListState)")

        // Select a building from the list, which switches the detent set to
        // [0.25, 0.58] and so makes 0.58 a real member.
        let rows = app.buttons.matching(
            NSPredicate(format: "label == %@", "Vaquero Flats, Mission, from $2,395")
        ).allElementsBoundByIndex
        let listRow = rows.max { $0.frame.minY < $1.frame.minY }
        XCTAssertNotNil(listRow, "no list row to select")
        listRow?.tap()
        sleep(3)

        let inCardState = locate.isHittable
        print("CARD state  (detents [0.25, 0.58])  locate hittable = \(inCardState)")

        XCTAssertTrue(
            inCardState,
            "chrome is dead in the card state too, so the detent mismatch is not the whole story"
        )
        XCTAssertTrue(
            inListState,
            "CONFIRMED: chrome is unreachable in the list state but reachable in the card state. "
                + "presentationBackgroundInteraction names .fraction(0.58), which is absent from "
                + "the listings detent set [.fraction(0.48)], so that sheet stays modal."
        )
    }
}
