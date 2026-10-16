import XCTest

@MainActor final class CoachUITests: XCTestCase {
    func testOfflineTextPhotoCapturePersistsAcrossRelaunchAndTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        for tab in ["Today", "Diary", "Progress", "Coach"] { XCTAssertTrue(app.tabBars.buttons[tab].exists) }
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
        app.buttons["profileSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ChatGPT connection")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["ChatGPT connection"].waitForExistence(timeout: 5))
        revealList(app.buttons["Continue with ChatGPT"], in: app)
        XCTAssertTrue(app.buttons["Continue with ChatGPT"].isHittable)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["doneSettings"].tap()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(input.isHittable, "The composer must remain reachable after the latest reply")
        XCTAssertTrue(send.isHittable)
        let receipt = app.buttons["coachMealLink"].firstMatch
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        revealCoachLink(receipt, in: app)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "English dark accessibility5 populated Coach"; screenshot.lifetime = .keepAlways; add(screenshot)
        openLatestMeal(in: app)
        XCTAssertFalse(app.tabBars.buttons["Coach"].isHittable)
        for label in ["Protein", "Carbs", "Fat"] {
            revealMealDetailItem(app.staticTexts[label], in: app)
        }
        let detail = XCTAttachment(screenshot: app.screenshot()); detail.name = "English dark accessibility5 meal nutrition"; detail.lifetime = .keepAlways; add(detail)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5)); XCTAssertTrue(input.isHittable)
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
        for food in ["Eggs", "Bread", "Salad"] { revealMealDetailItem(app.staticTexts[food].firstMatch, in: app) }
        revealMealDetailItem(app.staticTexts["3 slice"], in: app)
        revealList(app.buttons["viewMealPhoto"].firstMatch, in: app)
        XCTAssertTrue(app.buttons["viewMealPhoto"].firstMatch.isHittable)
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
        app.tabBars.buttons["Diary"].tap()
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: yesterday)
        formatter.dateFormat = "EEEE, d MMM"
        let displayedDate = formatter.string(from: yesterday)
        let historical = app.buttons.matching(identifier: "diaryDay").matching(NSPredicate(format: "label CONTAINS %@", displayedDate)).firstMatch
        XCTAssertTrue(historical.waitForExistence(timeout: 5)); historical.tap()
        XCTAssertTrue(app.navigationBars[date].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["Diary"].isHittable)
        let historicalMeal = app.buttons["historyMeal"].firstMatch
        revealList(historicalMeal, in: app)
        XCTAssertTrue(historicalMeal.label.contains("Time unspecified"))
        historicalMeal.tap()
        revealMealDetailItem(app.staticTexts["Time unspecified"], in: app)
        revealMealDetailItem(app.staticTexts[date], in: app)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars[date].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Diary"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Today"].tap(); app.buttons["logMeal"].tap()
        let manual = app.textFields["mealText"]; XCTAssertTrue(manual.waitForExistence(timeout: 5)); manual.tap(); manual.typeText("Fixture review meal")
        if app.buttons["doneMealText"].exists { app.buttons["doneMealText"].tap() }
        let review = app.switches["reviewFirst"].switches.firstMatch
        for _ in 0..<5 where !review.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(review.isHittable); review.tap(); app.buttons["sendMeal"].tap()
        app.tabBars.buttons["Coach"].tap(); waitForReplies(4, in: app)
        let reviewLink = app.buttons.matching(identifier: "coachMealLink").matching(NSPredicate(format: "label CONTAINS %@", "Needs review")).firstMatch
        revealCoachLink(reviewLink, in: app)
        XCTAssertTrue(reviewLink.waitForExistence(timeout: 5)); reviewLink.tap()
        let accept = app.buttons["acceptReview"]; XCTAssertTrue(accept.waitForExistence(timeout: 5)); revealMealDetailItem(accept, in: app); accept.tap()
        revealMealDetailItem(app.staticTexts["Snack"].firstMatch, in: app)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Synthetic fixture saved review record"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["half bread"].waitForExistence(timeout: 15))
        XCTAssertEqual(replyElements(in: app).count, 4)
        let banner = app.staticTexts["coachFixtureBanner"]
        for _ in 0..<12 where !banner.isHittable { app.scrollViews.firstMatch.swipeDown() }
        XCTAssertTrue(banner.isHittable)
    }

    func testFixtureGoalsWeightWorkoutBudgetAndRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["coachFixtureBanner"].exists)
        app.buttons["profileSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        revealList(app.buttons["editGoals"], in: app); app.buttons["editGoals"].tap()
        let target = app.textFields["goalKcal"]
        XCTAssertTrue(target.waitForExistence(timeout: 5)); target.tap(); target.typeText("2000")
        app.buttons["saveGoals"].tap()
        XCTAssertTrue(app.buttons["doneSettings"].waitForExistence(timeout: 5)); app.buttons["doneSettings"].tap()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 5))
        enter("Two eggs, three bread slices and salad", in: app); app.buttons["coachSend"].tap()
        waitForReplies(1, in: app)
        openLatestMeal(in: app)
        XCTAssertTrue(app.staticTexts["Eggs"].firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()
        enter("I weighed 70 kg this morning", in: app); app.buttons["coachSend"].tap()
        waitForReplies(2, in: app)
        guard replyElements(in: app).element(boundBy: 1).label.contains("Recorded weight: 70 kg.") else {
            XCTFail("The morning weigh-in must be saved through the production tool and reported from its receipt")
            return
        }
        enter("I did 30 minutes of strength: Squat, 8 repetitions at 40 kg, estimated burn 200 kcal", in: app)
        app.buttons["coachSend"].tap(); waitForReplies(3, in: app)
        let workout = app.buttons["coachWorkoutLink"]
        revealCoachLink(workout, in: app)
        XCTAssertGreaterThanOrEqual(workout.frame.height, 44); workout.tap()
        XCTAssertTrue(app.navigationBars["Workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Squat"].exists)
        XCTAssertTrue(app.staticTexts["30 minutes"].exists)
        XCTAssertTrue(app.staticTexts["Time unspecified"].exists)
        XCTAssertTrue(app.staticTexts["Set 1: 8 repetitions · 40 kg"].exists)
        let detail = XCTAttachment(screenshot: app.screenshot()); detail.name = "Synthetic Coach receipt opens actual workout"; detail.lifetime = .keepAlways; add(detail)
        app.navigationBars.buttons.firstMatch.tap()
        enter("What is my remaining budget?", in: app); app.buttons["coachSend"].tap()
        let budget = progressReply(containing: "Day coverage:", in: app)
        XCTAssertTrue(budget.waitForExistence(timeout: 15)); XCTAssertTrue(budget.isHittable)
        for fact in ["Recorded food: 420 kcal.", "Remaining from recorded food: 1580 kcal.", "Configured target: 2000 kcal.", "Recorded workouts: 1.", "Estimated exercise burn: 200 kcal.", "Weight average: 70 kg from 1 measured dates."] {
            XCTAssertTrue(budget.label.contains(fact), fact)
        }
        XCTAssertFalse(budget.label.contains("Explicit exercise-adjusted remaining"))
        enter("Show my weekly report", in: app); app.buttons["coachSend"].tap()
        let weekly = progressReply(containing: "Period recorded workouts: 1.", in: app)
        XCTAssertTrue(weekly.waitForExistence(timeout: 15)); XCTAssertTrue(weekly.isHittable)
        XCTAssertTrue(weekly.label.contains("6 missing"))
        app.terminate(); app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        revealCoach(weekly, in: app)
        XCTAssertTrue(weekly.label.contains("Remaining from recorded food: 1580 kcal."))
        XCTAssertTrue(weekly.label.contains("Weight average: 70 kg from 1 measured dates."))
        XCTAssertTrue(weekly.label.contains("Estimated exercise burn: 200 kcal."))
        for text in ["Two eggs, three bread slices and salad", "I weighed 70 kg this morning", "What is my remaining budget?", "Show my weekly report"] {
            revealCoach(app.staticTexts[text], in: app)
        }
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        let workouts = app.buttons["openWorkouts"]
        revealList(workouts, in: app); workouts.tap()
        XCTAssertTrue(app.navigationBars["Workouts"].waitForExistence(timeout: 5))
        let savedWorkout = app.buttons["workoutRow"].firstMatch
        revealList(savedWorkout, in: app); savedWorkout.tap()
        XCTAssertTrue(app.navigationBars["Workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Squat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["30 minutes"].exists)
        let persisted = XCTAttachment(screenshot: app.screenshot()); persisted.name = "Synthetic Coach workout persisted after relaunch"; persisted.lifetime = .keepAlways; add(persisted)
    }

    func testLatestFollowsActionsAndHistoryOffersNewMessage() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        let history = (1...32).map { "Synthetic history line \($0)." }.joined(separator: " ")
        enter(history, in: app); app.buttons["coachSend"].tap()
        let status = app.staticTexts["Waiting for an authorized connection"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let latest = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [latest], timeout: 5), .completed)
        XCTAssertLessThan(status.frame.maxY, app.textFields["coachInput"].frame.minY)
        app.scrollViews.firstMatch.swipeDown()
        let banner = app.staticTexts.matching(NSPredicate(format: "label == %@", history)).firstMatch
        XCTAssertTrue(banner.isHittable)
        enter("Synthetic new message", in: app); app.buttons["coachSend"].tap()
        let jump = app.buttons["coachNewMessage"]
        XCTAssertTrue(jump.waitForExistence(timeout: 5))
        XCTAssertTrue(banner.isHittable, "Sending while reading history must preserve the reading position")
        XCTAssertGreaterThanOrEqual(jump.frame.height, 44)
        jump.tap()
        XCTAssertTrue(app.staticTexts["Synthetic new message"].isHittable)
        XCTAssertFalse(jump.exists)
        let arrival = XCTAttachment(screenshot: app.screenshot())
        arrival.name = "Synthetic latest Coach message after history jump"; arrival.lifetime = .keepAlways; add(arrival)
    }

    func testThinkingFollowsLatestThenReplyPreservesHistoryAndJumpResumesFollowing() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        let history = (1...32).map { "Synthetic earlier line \($0)." }.joined(separator: " ")
        enter(history, in: app); app.buttons["coachSend"].tap()
        waitForReplies(1, in: app)
        enter("Synthetic delayed weekly report", in: app); app.buttons["coachSend"].tap()
        let activity = app.otherElements["coachActivity"]
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        XCTAssertTrue(activity.isHittable)
        XCTAssertLessThanOrEqual(activity.frame.maxY, app.textFields["coachInput"].frame.minY)
        let banner = app.staticTexts["coachFixtureBanner"]
        for _ in 0..<4 where !banner.isHittable { app.scrollViews.firstMatch.swipeDown() }
        XCTAssertTrue(banner.isHittable)
        let before = banner.frame.minY
        let jump = app.buttons["coachNewMessage"]
        XCTAssertTrue(jump.waitForExistence(timeout: 15))
        XCTAssertTrue(banner.isHittable)
        XCTAssertEqual(banner.frame.minY, before, accuracy: 2)
        jump.tap()
        let reply = progressReply(containing: "Period recorded workouts:", in: app)
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        let bottom = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            reply.frame.maxY <= app.textFields["coachInput"].frame.minY
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [bottom], timeout: 5), .completed)
        XCTAssertFalse(jump.exists)
        enter("Open backup settings", in: app); app.buttons["coachSend"].tap()
        let link = app.buttons["coachSettingsLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        XCTAssertTrue(link.isHittable)
        XCTAssertLessThanOrEqual(link.frame.maxY, app.textFields["coachInput"].frame.minY)
        let arrival = XCTAttachment(screenshot: app.screenshot())
        arrival.name = "Synthetic incoming Coach reply preserves history and resumes latest"; arrival.lifetime = .keepAlways; add(arrival)
    }

    func testRestingFingerDuringThinkingDoesNotDisableFollowing() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--proof-largest-text"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        enter("Synthetic delayed weekly report", in: app); app.buttons["coachSend"].tap()
        XCTAssertTrue(app.otherElements["coachActivity"].waitForExistence(timeout: 5))
        // Hold in the scroll view's empty gutter without dragging or selecting text.
        app.scrollViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).press(forDuration: 9)
        let reply = progressReply(containing: "Period recorded workouts:", in: app)
        XCTAssertTrue(reply.waitForExistence(timeout: 10))
        let bottom = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            reply.frame.maxY <= app.textFields["coachInput"].frame.minY
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [bottom], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["coachNewMessage"].exists)
    }

    func testLatestActivityAndReplyNeverAdvertiseAnUnreadMessage() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--proof-largest-text"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        enter("Synthetic delayed weekly report", in: app); app.buttons["coachSend"].tap()
        XCTAssertTrue(app.otherElements["coachActivity"].waitForExistence(timeout: 5))
        let unread = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: app.buttons["coachNewMessage"])
        unread.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unread], timeout: 10), .completed, "Capture, thinking, tools and completed reply at latest must not advertise unread content")
        let reply = progressReply(containing: "Period recorded workouts:", in: app)
        XCTAssertTrue(reply.exists)
        XCTAssertLessThanOrEqual(reply.frame.maxY, app.textFields["coachInput"].frame.minY)
        XCTAssertFalse(app.buttons["coachNewMessage"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        XCTAssertTrue(reply.waitForExistence(timeout: 10))
        let restoredLatest = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            reply.frame.maxY <= app.textFields["coachInput"].frame.minY
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [restoredLatest], timeout: 5), .completed, "A reopened chat must restore the latest completed message")
        XCTAssertFalse(app.buttons["coachNewMessage"].exists)
    }

    private func revealCoachLink(_ link: XCUIElement, in app: XCUIApplication) {
        // Hittable can include a partially clipped link whose center is under the composer.
        for _ in 0..<8 {
            if link.isHittable && link.frame.maxY < app.textFields["coachInput"].frame.minY - 8 { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(link.isHittable)
        XCTAssertLessThan(link.frame.maxY, app.textFields["coachInput"].frame.minY - 8)
    }
    private func replyElements(in app: XCUIApplication) -> XCUIElementQuery {
        // Selectable reply text can restore as Other instead of StaticText.
        app.descendants(matching: .any).matching(identifier: "coachReply")
    }
    private func progressReply(containing text: String, in app: XCUIApplication) -> XCUIElement {
        replyElements(in: app).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
    private func revealCoach(_ element: XCUIElement, in app: XCUIApplication) {
        // Long report replies virtualize earlier conversation rows.
        for _ in 0..<12 where !element.isHittable { app.scrollViews.firstMatch.swipeDown() }
        for _ in 0..<12 where !element.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func enter(_ text: String, in app: XCUIApplication) {
        let input = app.textFields["coachInput"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText(text)
    }
    private func waitForReplies(_ count: Int, in app: XCUIApplication) {
        let replies = replyElements(in: app)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            replies.count >= count
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
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
        revealCoachLink(link, in: app)
        XCTAssertTrue(link.isHittable); link.tap()
        XCTAssertTrue(app.navigationBars["Meal"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["Coach"].isHittable, "Focused record details must hide the tab bar")
    }
    private func revealList(_ element: XCUIElement, in app: XCUIApplication) {
        guard let list = nativeList(in: app) else { return }
        for _ in 0..<10 where !element.isHittable {
            if element.exists, !element.frame.isEmpty,
               element.frame.midY < app.navigationBars.firstMatch.frame.maxY {
                list.swipeDown()
            } else {
                list.swipeUp()
            }
        }
        for _ in 0..<10 where !element.isHittable { list.swipeDown() }
        XCTAssertTrue(element.isHittable)
    }
    private func nativeList(in app: XCUIApplication) -> XCUIElement? {
        let collection = app.collectionViews.firstMatch
        if collection.exists { return collection }
        let table = app.tables.firstMatch
        if table.exists { return table }
        XCTFail("The destination must contain its native list")
        return nil
    }
    private func revealMealDetailItem(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Meal"].exists, "Meal content checks require the actual record destination")
        revealList(element, in: app)
    }
}
