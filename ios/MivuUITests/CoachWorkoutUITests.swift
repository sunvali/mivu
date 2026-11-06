import XCTest

/// Pip's workout cards with seeded synthetic routines and workouts (`--coach-workout-fixture`) and the fixture model.
@MainActor final class CoachWorkoutUITests: XCTestCase {
    private static let screens = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("build/workouts/screens/t14")

    func testRoutineCardStartsLiveWorkout() {
        let app = launch()
        send("Synthetic start Push day", in: app)
        let start = app.buttons["coachRoutineStart"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        reveal(start, in: app)
        XCTAssertEqual(start.label, "Start Push day")
        XCTAssertGreaterThanOrEqual(start.frame.height, 44); XCTAssertGreaterThanOrEqual(start.frame.width, 44)
        start.tap()
        XCTAssertTrue(app.buttons["addExercise"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["liveWorkoutNotice"].exists)
    }

    func testStartWhileAnotherRunsOpensItWithNotice() {
        let app = launch(["--coach-workout-running"])
        send("Synthetic start Leg day", in: app)
        let start = app.buttons["coachRoutineStart"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        reveal(start, in: app)
        XCTAssertEqual(start.label, "Start Leg day")
        start.tap()
        let notice = app.descendants(matching: .any)["liveWorkoutNotice"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(notice.label.contains("Push day is already running"), notice.label)
        XCTAssertTrue(app.buttons["addExercise"].exists)
        capture("Already running notice", in: app)
    }

    func testAddedToCardOpensStoredGym() {
        let app = launch(["--coach-workout-running"])
        send("Synthetic another bench set", in: app)
        XCTAssertTrue(app.staticTexts["Added to Push day"].waitForExistence(timeout: 15))
        let link = app.buttons["coachWorkoutLink"].firstMatch
        reveal(link, in: app)
        link.tap()
        XCTAssertTrue(app.buttons["addExercise"].waitForExistence(timeout: 10))
        // The stored copy: the routine's ticked set and Pip's new one.
        XCTAssertEqual(app.buttons.matching(identifier: "tickSet").count, 2, app.debugDescription)
        capture("Gym after Pip added a set", in: app)
    }

    /// Pip's bar in the gym: a message adds the set without leaving the workout, Pip answers above the bar, Undo takes it back.
    func testGymPipBarAddsASetWithUndo() {
        let app = launch(["--coach-workout-running"])
        let banner = app.buttons["workoutBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        banner.tap()
        let ticks = app.buttons.matching(identifier: "tickSet")
        XCTAssertTrue(ticks.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(ticks.count, 1)
        let input = app.textFields["gymPipInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["gymPipCamera"].exists, "no machine camera without ChatGPT's recognizer")
        input.tap(); input.typeText("Synthetic another bench set")
        app.buttons["gymPipSend"].tap()
        let reply = app.staticTexts["gymPipReply"]
        XCTAssertTrue(reply.waitForExistence(timeout: 20))
        XCTAssertTrue(ticks.element(boundBy: 1).waitForExistence(timeout: 5), "Pip's set shows in the open gym")
        XCTAssertTrue(app.buttons["addExercise"].exists, "still in the gym, not sent to Coach")
        app.buttons["gymPipUndo"].tap()
        XCTAssertTrue(ticks.element(boundBy: 1).waitForNonExistence(timeout: 5))
        XCTAssertEqual(ticks.count, 1)
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testWorkoutSettingsLinkOpensWorkouts() {
        let app = launch()
        send("open workout settings", in: app)
        let link = app.buttons.matching(identifier: "coachSettingsLink").matching(NSPredicate(format: "label == %@", "Open workout settings")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 15))
        reveal(link, in: app)
        link.tap()
        XCTAssertTrue(app.navigationBars["Workouts"].waitForExistence(timeout: 10))
        // Import and export sit at the bottom of Workouts.
        let importRow = app.buttons["importWorkoutsRow"].firstMatch
        reveal(importRow, in: app)
        XCTAssertTrue(app.buttons["exportWorkouts"].exists)
        importRow.tap()
        XCTAssertTrue(app.buttons["chooseWorkoutCSV"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Import workouts"].exists)
    }

    // The routine card and the New best pill, light and dark, at the default and the largest accessibility size.
    func testCardsLightDefault() throws { try cards(scheme: "light", largest: false) }
    func testCardsDarkDefault() throws { try cards(scheme: "dark", largest: false) }
    func testCardsLightLargest() throws { try cards(scheme: "light", largest: true) }
    func testCardsDarkLargest() throws { try cards(scheme: "dark", largest: true) }

    private func cards(scheme: String, largest: Bool) throws {
        try FileManager.default.createDirectory(at: Self.screens, withIntermediateDirectories: true)
        let size = largest ? "largest" : "default"
        let app = launch(["--proof-\(scheme)"] + (largest ? ["--proof-largest-text"] : []))
        if largest {
            // At the largest sizes the morning check-in covers the whole chat and its close button sits under the
            // profile button; it only shows while today has no food, so a synthetic breakfast clears it.
            send("Synthetic breakfast", in: app)
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.descendants(matching: .any)["morningCheckIn"].firstMatch)
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 20), .completed)
        }
        send("Synthetic heavy bench", in: app)
        let best = app.descendants(matching: .any)["coachReceiptNewBest"].firstMatch
        XCTAssertTrue(best.waitForExistence(timeout: 15))
        reveal(best, in: app)
        XCTAssertEqual(best.label, "New best")
        try save("new-best-\(scheme)-\(size)", in: app)
        send("Synthetic start Push day", in: app)
        let start = app.buttons["coachRoutineStart"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        reveal(start, in: app)
        XCTAssertEqual(start.label, "Start Push day")
        XCTAssertGreaterThanOrEqual(start.frame.height, 44); XCTAssertGreaterThanOrEqual(start.frame.width, 44)
        try save("routine-card-\(scheme)-\(size)", in: app)
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--coach-workout-fixture", "--proof-english"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        return app
    }

    private func send(_ text: String, in app: XCUIApplication) {
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText(text)
        app.buttons["coachSend"].tap()
    }

    /// Scrolls in small steps until the element sits fully between the navigation bar and the composer.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        func composerTop() -> CGFloat {
            let strip = app.descendants(matching: .any)["coachCompanionStrip"].firstMatch
            return min(strip.exists ? strip.frame.minY : .infinity, app.textFields["coachInput"].frame.minY)
        }
        let top = app.navigationBars["Coach"].frame.maxY
        let table = app.tables["coachViewport"], viewport = table.exists ? table : app.scrollViews.firstMatch
        for _ in 0..<16 {
            if element.isHittable, element.frame.minY >= top, element.frame.maxY < composerTop() - 8 { break }
            let start = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: element.frame.minY < top ? 120 : -120)),
                        withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        if !element.isHittable { capture("Reveal failed", in: app) }
        XCTAssertTrue(element.isHittable, "frame \(element.frame), top \(top), composer \(composerTop())")
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func save(_ name: String, in app: XCUIApplication) throws {
        capture(name, in: app)
        try app.screenshot().pngRepresentation.write(to: Self.screens.appendingPathComponent(name + ".png"))
    }
}
