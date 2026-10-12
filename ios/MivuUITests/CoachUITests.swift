import XCTest

@MainActor final class CoachUITests: XCTestCase {
    func testOfflineTextPhotoCapturePersistsAcrossRelaunchAndTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        for tab in ["Coach", "Today", "History", "Settings"] { XCTAssertTrue(app.tabBars.buttons[tab].exists) }
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Synthetic coach lunch")
        app.buttons["coachPhotos"].tap()
        XCTAssertTrue(app.buttons["syntheticPhoto"].waitForExistence(timeout: 5)); app.buttons["syntheticPhoto"].tap()
        app.navigationBars.buttons["Done"].tap()
        let send = app.buttons["coachSend"]
        XCTAssertTrue(send.isHittable); XCTAssertGreaterThanOrEqual(send.frame.height, 44); send.tap()
        XCTAssertTrue(app.staticTexts["Synthetic coach lunch"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Waiting for an authorized connection"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Apple sample mode"].exists)
        app.tabBars.buttons["Settings"].tap()
        revealList(app.buttons["Connect ChatGPT"], in: app)
        XCTAssertTrue(app.buttons["Connect ChatGPT"].isHittable)
        app.tabBars.buttons["Today"].tap()
        XCTAssertFalse(app.buttons["mealRow"].firstMatch.exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic coach lunch"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Waiting for an authorized connection"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Synthetic offline persisted Coach"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testLargestDynamicTypeDarkCoachKeepsCaptureReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--proof-dark", "--proof-largest-text"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.isHittable); input.tap(); input.typeText("Two eggs, three bread slices and salad")
        let send = app.buttons["coachSend"]
        XCTAssertTrue(send.isHittable); XCTAssertGreaterThanOrEqual(send.frame.height, 44); send.tap()
        XCTAssertTrue(app.staticTexts["Two eggs, three bread slices and salad"].waitForExistence(timeout: 10))
        waitForReplies(1, in: app)
        let arrival = XCTAttachment(screenshot: app.screenshot()); arrival.name = "English dark accessibility5 latest reply arrival"; arrival.lifetime = .keepAlways; add(arrival)
        for _ in 0..<5 where !app.staticTexts["Carbs"].isHittable { app.scrollViews.firstMatch.swipeDown() }
        XCTAssertTrue(app.staticTexts["Carbs"].isHittable)
        for label in ["Protein", "Fat"] {
            for _ in 0..<8 where !app.staticTexts[label].isHittable { app.scrollViews.firstMatch.swipeUp() }
            XCTAssertTrue(app.staticTexts[label].isHittable)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "English dark accessibility5 populated Coach"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testFixtureMealCorrectionHistoricalReviewAndConversationRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["coachFixtureBanner"].exists)
        enter("Two eggs, three bread slices and salad", in: app)
        app.buttons["coachPhotos"].tap()
        XCTAssertTrue(app.buttons["syntheticPhoto"].waitForExistence(timeout: 5)); app.buttons["syntheticPhoto"].tap()
        app.navigationBars.buttons["Done"].tap(); app.buttons["coachSend"].tap()
        waitForReplies(1, in: app)
        openLatestMeal(in: app)
        for food in ["Eggs", "Bread", "Salad"] { XCTAssertTrue(app.staticTexts[food].exists) }
        XCTAssertTrue(app.staticTexts["3 slice"].exists)
        revealList(app.images["Meal photo"], in: app)
        XCTAssertTrue(app.images["Meal photo"].isHittable)
        app.navigationBars.buttons.firstMatch.tap()
        enter("half bread", in: app); app.buttons["coachSend"].tap()
        waitForReplies(2, in: app); openLatestMeal(in: app)
        for quantity in ["1.5 slice", "2 egg", "1 bowl"] {
            revealMealDetailItem(app.staticTexts[quantity], in: app)
        }
        revealMealDetailItem(app.staticTexts["300"], in: app)
        app.navigationBars.buttons.firstMatch.tap()
        enter("Yesterday I had dessert", in: app); app.buttons["coachSend"].tap()
        waitForReplies(3, in: app)
        app.tabBars.buttons["History"].tap()
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: yesterday)
        let historical = app.buttons.containing(.staticText, identifier: date).firstMatch
        XCTAssertTrue(historical.waitForExistence(timeout: 5)); historical.tap()
        XCTAssertTrue(app.staticTexts["Time unspecified"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Today"].tap(); app.buttons["logMeal"].tap()
        let manual = app.textFields["mealText"]; XCTAssertTrue(manual.waitForExistence(timeout: 5)); manual.tap(); manual.typeText("Fixture review meal")
        if app.buttons["doneMealText"].exists { app.buttons["doneMealText"].tap() }
        let review = app.switches["reviewFirst"].switches.firstMatch
        for _ in 0..<5 where !review.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(review.isHittable); review.tap(); app.buttons["sendMeal"].tap()
        app.tabBars.buttons["Coach"].tap(); waitForReplies(4, in: app)
        let reviewLink = app.buttons["Review meal estimate"]
        for _ in 0..<5 where !reviewLink.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(reviewLink.waitForExistence(timeout: 5)); reviewLink.tap()
        let accept = app.buttons["acceptReview"]; XCTAssertTrue(accept.waitForExistence(timeout: 5)); accept.tap()
        XCTAssertTrue(app.staticTexts["Snack"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Synthetic fixture saved review record"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["half bread"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts.matching(identifier: "coachReply").count, 4)
        XCTAssertTrue(app.staticTexts["coachFixtureBanner"].exists)
    }

    private func enter(_ text: String, in app: XCUIApplication) {
        let input = app.textFields["coachInput"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText(text)
    }
    private func waitForReplies(_ count: Int, in app: XCUIApplication) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.staticTexts.matching(identifier: "coachReply").count >= count
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
        let replies = app.staticTexts.matching(identifier: "coachReply")
        if replies.count > 0 {
            let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: replies.element(boundBy: replies.count - 1))
            XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed, "Latest completed reply should remain visible after it arrives")
        }
    }
    private func openLatestMeal(in app: XCUIApplication) {
        let links = app.buttons.matching(identifier: "coachMealLink")
        XCTAssertGreaterThan(links.count, 0)
        guard links.count > 0 else { return }
        let link = links.element(boundBy: links.count - 1)
        for _ in 0..<5 where !link.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(link.isHittable); link.tap()
    }
    private func revealList(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 where !element.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func revealMealDetailItem(_ element: XCUIElement, in app: XCUIApplication) {
        guard let list = app.collectionViews.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            XCTFail("Meal detail should have a visible list")
            return
        }
        for _ in 0..<8 where !element.isHittable { list.swipeDown() }
        for _ in 0..<8 where !element.isHittable { list.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
}
