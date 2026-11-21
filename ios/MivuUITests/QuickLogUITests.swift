import XCTest

@MainActor final class QuickLogUITests: XCTestCase {
    func testLogFoodOpensCameraLogsPhotoOnTodayAndOffersNote() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english", "--quick-log"]
        app.launch()
        // The simulator has no camera, so the synthetic photo stands in for the shutter.
        let photo = app.buttons["quickLogSyntheticPhoto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["quickLogClose"].exists)
        photo.tap()
        let addNote = app.buttons["quickLogAddNote"]
        XCTAssertTrue(addNote.waitForExistence(timeout: 10))
        // The toast hides itself after 5 seconds, so use it before any slower wait.
        XCTAssertGreaterThanOrEqual(addNote.frame.height, 44)
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
        addNote.tap()
        XCTAssertTrue(app.textFields["mealText"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        let discard = app.buttons["Discard changes"]
        if discard.waitForExistence(timeout: 2) { discard.tap() }
        XCTAssertTrue(app.buttons["mealRow"].firstMatch.waitForExistence(timeout: 10))
    }

    func testSnapItOnTodayIsVisibleAtLaunchAndOpensCamera() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english"]
        app.launch()
        let snapIt = app.buttons["snapIt"]
        XCTAssertTrue(snapIt.waitForExistence(timeout: 15))
        XCTAssertTrue(snapIt.isHittable, "Snap It is on screen as soon as Today opens")
        XCTAssertGreaterThanOrEqual(snapIt.frame.height, 44)
        XCTAssertTrue(snapIt.label.contains("Instant photo log"), "The caption separates Snap It from chatting with Pip")
        XCTAssertLessThan(snapIt.frame.maxY, app.buttons["logMeal"].frame.minY, "Snap It leads the capture bar")
        snapIt.tap()
        let photo = app.buttons["quickLogSyntheticPhoto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        photo.tap()
        XCTAssertTrue(app.buttons["quickLogAddNote"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["mealRow"].firstMatch.waitForExistence(timeout: 10))
    }

    func testSnappedMealShowsThinkingOnTodayUntilCoachFinishes() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--coach-ui-test-slow", "--coach-navigation-start-today", "--proof-english"]
        app.launch()
        let snapIt = app.buttons["snapIt"]
        XCTAssertTrue(snapIt.waitForExistence(timeout: 15))
        snapIt.tap()
        let photo = app.buttons["quickLogSyntheticPhoto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        photo.tap()
        let row = app.buttons["mealRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let thinking = NSPredicate(format: "label CONTAINS 'Thinking'")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: thinking, evaluatedWith: row)], timeout: 6), .completed, "Today shows the Coach is working: \(row.label)")
        app.swipeUp() // The capture bar covers the first row until the list scrolls.
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "today-thinking"; shot.lifetime = .keepAlways; add(shot)
        let done = NSPredicate(format: "NOT (label CONTAINS 'Thinking') AND NOT (label CONTAINS 'Waiting')")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: done, evaluatedWith: row)], timeout: 20), .completed, "The row settles when Coach finishes: \(row.label)")
        let after = XCTAttachment(screenshot: app.screenshot()); after.name = "today-done"; after.lifetime = .keepAlways; add(after)
    }

    func testLargestTextStacksPipThenManualLinkUnderSnapIt() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-navigation-start-today",
                               "--proof-english", "--proof-largest-text"]
        app.launch()
        let snapIt = app.buttons["snapIt"], pip = app.buttons["logMeal"], manual = app.buttons["addManually"]
        XCTAssertTrue(snapIt.waitForExistence(timeout: 15))
        XCTAssertTrue(snapIt.isHittable)
        XCTAssertLessThanOrEqual(pip.frame.maxY, manual.frame.minY, "Typing numbers is the quieter choice under Pip")
        XCTAssertLessThan(snapIt.frame.maxY, pip.frame.minY)
        XCTAssertEqual(pip.label, "Chat with Pip")
        XCTAssertEqual(manual.label, "Add manually")
        XCTAssertGreaterThanOrEqual(manual.frame.height, 44)
    }

    func testCameraRequestWaitsForTheDiaryChooser() {
        let id = UUID().uuidString, app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", id, "--proof-english"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 15))
        app.terminate()
        app.launchArguments += ["-diarySignedOut", "YES", "--quick-log"]
        app.launch()
        let diary = app.buttons["My diary"]
        XCTAssertTrue(diary.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["quickLogSyntheticPhoto"].exists)
        diary.tap()
        XCTAssertTrue(app.buttons["quickLogSyntheticPhoto"].waitForExistence(timeout: 10))
    }

    func testOpenCoachRequestLandsOnCoach() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english", "--open-coach"]
        app.launch()
        let coach = app.tabBars.buttons["Coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: 15))
        let selected = NSPredicate(format: "isSelected == true")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: selected, object: coach)], timeout: 10), .completed)
    }

    func testSnapItTipAppearsAfterFirstLogAndOpensShortcutSteps() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english", "--snap-it-tip"]
        app.launch()
        let how = app.buttons["Show me how"], snapIt = app.buttons["snapIt"], toast = app.buttons["quickLogAddNote"]
        XCTAssertTrue(snapIt.waitForExistence(timeout: 15))
        XCTAssertFalse(how.exists, "No tip before the first photo log")
        snapIt.tap()
        let photo = app.buttons["quickLogSyntheticPhoto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        photo.tap()
        XCTAssertTrue(toast.waitForExistence(timeout: 10))
        XCTAssertFalse(how.exists, "The tip waits for the toast, so it never covers Add Note")
        XCTAssertTrue(toast.waitForNonExistence(timeout: 10))
        XCTAssertTrue(how.waitForExistence(timeout: 5), "The tip points at Snap It after the first log")
        XCTAssertTrue(app.staticTexts["Add Snap It to your Lock Screen, Control Center or Action button."].exists)
        how.tap()
        XCTAssertTrue(app.buttons["snapItVideo"].waitForExistence(timeout: 5), "The steps open with a video")
        app.buttons["doneSnapItShortcuts"].tap()
        XCTAssertFalse(how.waitForExistence(timeout: 2), "The tip is gone once its steps were opened")
        XCTAssertTrue(snapIt.isHittable)
    }

    func testSnapItShortcutsFromSettingsShowVideoAndStepsForEachPlace() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english"]
        app.launch()
        XCTAssertTrue(app.buttons["profileSettings"].waitForExistence(timeout: 15))
        app.buttons["profileSettings"].tap()
        let row = app.buttons["snapItShortcuts"]
        // Settings is a lazy list; the Setup rows start below the fold.
        if !row.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let video = app.buttons["snapItVideo"]
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        XCTAssertEqual(video.value as? String, "Playing")
        video.tap()
        XCTAssertEqual(video.value as? String, "Paused", "A tap pauses the video")
        for (place, step) in [("Control Center", "Swipe down from the top-right corner."),
                              ("Action button", "Open Settings and tap Action Button."),
                              ("Lock Screen", "Remove one of the bottom buttons, then tap +.")] {
            app.segmentedControls["snapItPlace"].buttons[place].tap()
            if !app.staticTexts[step].waitForExistence(timeout: 2) { app.swipeUp() }
            XCTAssertTrue(app.staticTexts[step].waitForExistence(timeout: 5), "\(place) steps are listed")
            app.swipeDown()
        }
        app.buttons["doneSnapItShortcuts"].tap()
        XCTAssertTrue(app.buttons["doneSettings"].waitForExistence(timeout: 5))
    }
}
