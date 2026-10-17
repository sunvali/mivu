import XCTest

@MainActor final class CompanionUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--proof-english"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        return app
    }

    private func enter(_ text: String, in app: XCUIApplication) {
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText(text)
    }

    private func settings(in app: XCUIApplication) {
        app.buttons["profileSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let list = app.collectionViews.firstMatch
        for _ in 0..<8 where !element.isHittable { list.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    func testLottieReferenceCompositionsAndHorizontalComposerInBothAppearances() {
        for appearance in ["--proof-light", "--proof-dark"] {
            let app = launch([appearance])
            let input = app.textFields["coachInput"]
            let camera = app.buttons["coachPhotos"]
            let send = app.buttons["coachSend"]
            XCTAssertEqual(input.frame.midY, camera.frame.midY, accuracy: 12, "Normal composer must follow the reference's single horizontal row")
            XCTAssertEqual(input.frame.midY, send.frame.midY, accuracy: 12)
            XCTAssertGreaterThanOrEqual(camera.frame.height, 44)
            XCTAssertGreaterThanOrEqual(send.frame.height, 44)
            enter("Two eggs, three bread slices and salad", in: app)
            XCTAssertTrue(send.isHittable); send.tap()
            let link = app.buttons["coachMealLink"].firstMatch
            XCTAssertTrue(link.waitForExistence(timeout: 15))
            let coach = XCTAttachment(screenshot: app.screenshot())
            coach.name = "Pip Lottie Coach " + appearance; coach.lifetime = .keepAlways; add(coach)
            app.tabBars.buttons["Today"].tap()
            let row = app.buttons["mealRow"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            let today = XCTAttachment(screenshot: app.screenshot())
            today.name = "Pip Lottie Today " + appearance; today.lifetime = .keepAlways; add(today)
            XCTAssertTrue(app.buttons["logMeal"].isHittable)
            let list = app.collectionViews.firstMatch
            for _ in 0..<6 where row.frame.maxY >= app.buttons["logMeal"].frame.minY - 12 { list.swipeUp() }
            XCTAssertTrue(row.isHittable)
            XCTAssertLessThan(row.frame.maxY, app.buttons["logMeal"].frame.minY - 8)
            row.tap()
            XCTAssertTrue(app.navigationBars["Meal"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testLivingIdleAndQuietTypingKeepCaptureResponsive() async throws {
        for appearance in ["--proof-light", "--proof-dark"] {
            let app = launch([appearance])
            app.tabBars.buttons["Today"].tap()
            // Observation windows include a complete authored loop for the native motion recording.
            try await Task.sleep(for: .seconds(8.5))
            XCTAssertTrue(app.buttons["logMeal"].isHittable)
            app.tabBars.buttons["Coach"].tap()
            enter("Two eggs, three bread slices and salad", in: app)
            try await Task.sleep(for: .seconds(8.5))
            XCTAssertEqual(app.textFields["coachInput"].value as? String, "Two eggs, three bread slices and salad")
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            XCTAssertTrue(app.buttons["coachSend"].isHittable)
            app.buttons["coachSend"].tap()
            XCTAssertTrue(app.buttons["coachMealLink"].firstMatch.waitForExistence(timeout: 15))
            try await Task.sleep(for: .seconds(2.5))
            let coach = XCTAttachment(screenshot: app.screenshot())
            coach.name = "Living Pip Coach " + appearance; coach.lifetime = .keepAlways; add(coach)
            app.tabBars.buttons["Today"].tap()
            let today = XCTAttachment(screenshot: app.screenshot())
            today.name = "Living Pip Today " + appearance; today.lifetime = .keepAlways; add(today)
            app.terminate()
        }
    }

    func testFallbackKeepsCaptureAndReviewUsable() {
        let app = launch(["--companion-load-failure"])
        app.tabBars.buttons["Today"].tap(); app.buttons["logMeal"].tap()
        let input = app.textFields["mealText"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Fixture review meal")
        if app.buttons["doneMealText"].exists { app.buttons["doneMealText"].tap() }
        let review = app.switches["reviewFirst"].switches.firstMatch
        reveal(review, in: app); review.tap(); app.buttons["sendMeal"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Coach"].tap()
        let link = app.buttons.matching(identifier: "coachMealLink").matching(NSPredicate(format: "label CONTAINS %@", "Needs review")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 15)); link.tap()
        let accept = app.buttons["acceptReview"]
        XCTAssertTrue(accept.waitForExistence(timeout: 5)); reveal(accept, in: app); accept.tap()
        XCTAssertFalse(accept.exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.textFields["coachInput"].waitForExistence(timeout: 5))
    }

    func testSettingsReturnKeepsCoachSendReachable() {
        let app = launch(); settings(in: app)
        app.buttons["editGoals"].tap()
        let target = app.textFields["goalKcal"]
        XCTAssertTrue(target.waitForExistence(timeout: 5)); target.tap(); target.typeText("2000")
        app.buttons["saveGoals"].tap()
        XCTAssertTrue(app.buttons["doneSettings"].waitForExistence(timeout: 5)); app.buttons["doneSettings"].tap()
        enter("Two eggs, three bread slices and salad", in: app)
        let send = app.buttons["coachSend"]
        let reachable = send.isHittable
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Coach keyboard after goal Settings return"; screen.lifetime = .keepAlways; add(screen)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Coach Settings return accessibility"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        XCTAssertTrue(reachable, "Returning from goal Settings must keep the focused composer action reachable")
        XCTAssertGreaterThanOrEqual(send.frame.height, 44)
        send.tap()
        XCTAssertTrue(app.buttons["coachMealLink"].firstMatch.waitForExistence(timeout: 15))
    }

    func testTypingDuringSavedReactionKeepsComposerFocused() {
        let app = launch()
        enter("Two eggs, three bread slices and salad", in: app); app.buttons["coachSend"].tap()
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Next meal draft")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertEqual(input.value as? String, "Next meal draft")
        input.typeText(" stays here")
        XCTAssertEqual(input.value as? String, "Next meal draft stays here")
        XCTAssertTrue(app.buttons["coachSend"].isHittable)
    }

    func testLargestTextGoalKeyboardDoneKeepsCoachSendReachable() {
        let app = launch(["--proof-largest-text", "--proof-dark"]); settings(in: app)
        app.buttons["editGoals"].tap()
        let target = app.textFields["goalKcal"]
        XCTAssertTrue(target.waitForExistence(timeout: 5)); reveal(target, in: app); target.tap(); target.typeText("2000")
        let done = app.buttons["progressKeyboardDone"]
        XCTAssertTrue(done.isHittable); XCTAssertGreaterThanOrEqual(done.frame.height, 44)
        let numeric = XCTAttachment(screenshot: app.screenshot())
        numeric.name = "Goals largest text keyboard dismissal"; numeric.lifetime = .keepAlways; add(numeric)
        done.tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        app.buttons["saveGoals"].tap()
        XCTAssertTrue(app.buttons["doneSettings"].waitForExistence(timeout: 5)); app.buttons["doneSettings"].tap()
        enter("Draft", in: app)
        XCTAssertTrue(app.buttons["coachSend"].isHittable)
        app.buttons["coachSend"].tap()
        XCTAssertTrue(app.staticTexts["Draft"].waitForExistence(timeout: 5))
    }

    func testRapidTabsAndDetailReturnDoNotReplaySavedFeedback() {
        let app = launch()
        enter("Two eggs, three bread slices and salad", in: app); app.buttons["coachSend"].tap()
        let link = app.buttons["coachMealLink"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 15))
        for transition in 0..<50 {
            app.tabBars.buttons[transition.isMultiple(of: 2) ? "Today" : "Coach"].tap()
        }
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
        XCTAssertTrue(app.navigationBars["Meal"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.textFields["coachInput"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "coachMealLink").count, 1)
        XCTAssertFalse(app.buttons["coachNewMessage"].exists)
        // Reducer/runtime suites assert reaction identities; decorative poses have no spoken debug labels.
    }

    func testLargestTextLightAndDarkKeepPrimaryActionsReachable() {
        for appearance in ["--proof-light", "--proof-dark"] {
            let app = launch(["--proof-largest-text", appearance])
            enter("Draft", in: app)
            XCTAssertTrue(app.buttons["coachSend"].isHittable)
            XCTAssertGreaterThanOrEqual(app.buttons["coachSend"].frame.height, 44)
            let coachCapture = XCTAttachment(screenshot: app.screenshot())
            coachCapture.name = "Coach largest text \(appearance)"; coachCapture.lifetime = .keepAlways; add(coachCapture)
            app.buttons["coachSend"].tap()
            app.tabBars.buttons["Today"].tap()
            XCTAssertTrue(app.buttons["logMeal"].isHittable)
            XCTAssertGreaterThanOrEqual(app.buttons["logMeal"].frame.height, 44)
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "Today largest text \(appearance)"; capture.lifetime = .keepAlways; add(capture)
            app.terminate()
        }
    }

    func testSettingsShowsPipPreviewWithoutOneItemPicker() {
        let app = launch(); settings(in: app)
        let name = app.staticTexts["companionName"]
        reveal(name, in: app)
        XCTAssertEqual(name.label, "Pip")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "companionChoice-")).count, 0)
        XCTAssertFalse(app.pickers["Companion"].exists)
    }

    func testUnknownStoredCharacterFallsBackToPipAndCaptureWorks() {
        let app = launch(["--companion-unknown-selection"]); settings(in: app)
        let name = app.staticTexts["companionName"]; reveal(name, in: app); XCTAssertEqual(name.label, "Pip")
        app.buttons["doneSettings"].tap()
        enter("Two eggs, three bread slices and salad", in: app); app.buttons["coachSend"].tap()
        XCTAssertTrue(app.buttons["coachMealLink"].firstMatch.waitForExistence(timeout: 15))
    }

    func testBundledChooserSwitchKeepsDraftAndStopsPreviousCharacter() {
        let app = launch(["--companion-two-fixtures"])
        enter("Draft stays with this diary", in: app); settings(in: app)
        let choice = app.buttons["companionChoice-pip-test-alias"]
        reveal(choice, in: app); XCTAssertGreaterThanOrEqual(choice.frame.height, 44); choice.tap()
        XCTAssertTrue(choice.label.contains("Selected companion"))
        app.buttons["doneSettings"].tap()
        XCTAssertEqual(app.textFields["coachInput"].value as? String, "Draft stays with this diary")
        settings(in: app); reveal(choice, in: app); XCTAssertTrue(choice.label.contains("Selected companion"))
        app.buttons["doneSettings"].tap()
        XCTAssertTrue(app.buttons["coachSend"].isHittable)
    }
}
