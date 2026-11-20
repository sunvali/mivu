import XCTest

@MainActor final class CoachUITests: XCTestCase {
    func testEarlierMessagesRemainReadableWhenNewInputArrives() {
        executionTimeAllowance = 480 // Types and sends 22 messages through the on-screen keyboard.
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        for index in 1...21 {
            enter("History message \(index)", in: app)
            app.buttons["coachSend"].tap()
            XCTAssertTrue(app.staticTexts["History message \(index)"].waitForExistence(timeout: 5))
        }
        app.terminate(); app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["History message 1"].exists, "Reopening should render only the latest twenty turns initially")
        XCTAssertFalse(app.buttons["coachEarlierMessages"].exists)
        let first = app.staticTexts["History message 1"]
        // An unlaid-out row has an empty frame, and asking it for hittability records a failure.
        for _ in 0..<16 where !first.exists || first.frame.isEmpty || !first.isHittable { coachViewport(in: app).swipeDown() }
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.isHittable, "A real upward-history gesture must load and reveal the older page")
        enter("History message 22", in: app); app.buttons["coachSend"].tap()
        let newest = app.staticTexts["History message 22"]
        XCTAssertTrue(first.isHittable, "New input must preserve the history being read")
        let latest = app.buttons["coachNewMessage"]
        let found = latest.waitForExistence(timeout: 5)
        if !found {
            let diagnostic = XCTAttachment(string: app.debugDescription); diagnostic.name = "Paging failure"; diagnostic.lifetime = .keepAlways; add(diagnostic)
        }
        XCTAssertTrue(found); latest.tap()
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: newest)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
    }

    func testPlanNotEligibleExplainsOnceAndInSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--plan-not-eligible-fixture", "--proof-english"]
        app.launch()
        let alert = app.alerts["Your ChatGPT plan can’t be used in Mivu"]
        XCTAssertTrue(alert.waitForExistence(timeout: 15))
        XCTAssertTrue(alert.buttons["Learn more"].exists)
        alert.buttons["Got it"].tap()
        XCTAssertTrue(app.staticTexts["Your ChatGPT plan can’t be used in other apps."].waitForExistence(timeout: 5),
                      "Coach explains the plan instead of offering to connect")
        XCTAssertFalse(app.buttons["connectChatGPT"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 3), "The explanation shows once per account")
        openConnectionSettings(in: app)
        let checkAgain = app.buttons["Check again"]
        revealList(checkAgain, in: app)
        XCTAssertTrue(app.staticTexts["ChatGPT plan unavailable"].exists)
        XCTAssertFalse(app.buttons["Enable ChatGPT plan usage"].exists)
        XCTAssertFalse(app.buttons["connectChatGPT"].exists)
        XCTAssertFalse(app.links["Manage usage"].exists, "There is no plan usage to manage")
    }

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
        let send = app.buttons["coachSend"]
        // The camera cover's dismissal and the restored keyboard settle the composer before Send is hittable.
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: send)], timeout: 5), .completed)
        XCTAssertGreaterThanOrEqual(send.frame.height, 44); send.tap()
        XCTAssertTrue(app.staticTexts["Synthetic coach lunch"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Connect ChatGPT in Settings to continue"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Apple sample mode"].exists)
        openConnectionSettings(in: app)
        let connect = settingsConnectButton(in: app)
        revealList(connect, in: app)
        XCTAssertTrue(connect.exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["doneSettings"].tap()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Today"].tap()
        XCTAssertFalse(app.buttons["mealRow"].firstMatch.exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic coach lunch"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Connect ChatGPT in Settings to continue"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Synthetic offline persisted Coach"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testChatGPTConnectAsksForSharingConsentFromCoachAndSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        let consent = app.alerts["Share with OpenAI?"]
        let coachConnect = app.buttons["connectChatGPT"]
        XCTAssertTrue(coachConnect.waitForExistence(timeout: 5)); coachConnect.tap()
        XCTAssertTrue(consent.waitForExistence(timeout: 5), "Coach must offer the connection in place")
        consent.buttons["Not Now"].tap()
        openConnectionSettings(in: app)
        let settingsConnect = settingsConnectButton(in: app)
        revealList(settingsConnect, in: app)
        XCTAssertTrue(settingsConnect.isEnabled, "The pushed connection page must keep its button usable")
        settingsConnect.tap()
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        consent.buttons["Not Now"].tap()
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
        // Following latest shows the exchange's end; at this size the receipt below the reply fills the screen.
        let reply = ownReply(to: "Two eggs, three bread slices and salad", in: app)
        XCTAssertTrue(reply.waitForExistence(timeout: 15), "The submitted turn must receive its own completed reply")
        nudge(toward: reply, in: app)
        let arrival = XCTAttachment(screenshot: app.screenshot()); arrival.name = "English dark accessibility5 latest reply arrival"; arrival.lifetime = .keepAlways; add(arrival)
        XCTAssertTrue(input.isHittable, "The composer must remain reachable after the latest reply")
        XCTAssertTrue(app.buttons["coachVoice"].isHittable, "A sent draft returns the trailing slot to voice")
        let receipt = app.buttons["coachMealLink"].firstMatch
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        nudge(toward: receipt, in: app)
        XCTAssertLessThan(receipt.frame.maxY, composerTop(in: app) - 8)
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
    func testPartialSuccessShowsSavedCardAndRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        enter("Synthetic partial success", in: app); app.buttons["coachSend"].tap()
        XCTAssertTrue(app.buttons["coachFinishRest"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["coachFinishRest"].isHittable)
        XCTAssertTrue(app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coachReceipt-")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Analysis could not finish. Your input is saved. Check your connection or retry when ready."].exists)
    }
    func testReceiptUndo() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        enter("Two eggs, three bread slices and salad", in: app); app.buttons["coachSend"].tap()
        waitForReply(to: "Two eggs, three bread slices and salad", in: app)
        let undo = app.buttons["coachUndo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 10))
        revealCoachLink(undo, in: app)
        XCTAssertGreaterThanOrEqual(undo.frame.height, 44)
        undo.tap()
        XCTAssertTrue(app.staticTexts["Undone"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["coachUndo"].exists)
    }
    func testCoachDeletedWorkoutShowsUndoAndRestores() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        enter("30 minutes of strength", in: app); app.buttons["coachSend"].tap()
        waitForReply(to: "30 minutes of strength", in: app)
        enter("Synthetic remove workout", in: app); app.buttons["coachSend"].tap()
        waitForReply(to: "Synthetic remove workout", in: app)
        let undo = app.buttons["coachUndo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 10))
        revealCoachLink(undo, in: app)
        undo.tap()
        XCTAssertTrue(app.staticTexts["Undone"].waitForExistence(timeout: 10))
    }
    func testFixtureMealCorrectionHistoricalReviewAndConversationRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        enter("Two eggs, three bread slices and salad", in: app)
        app.buttons["coachPhotos"].tap()
        XCTAssertTrue(app.buttons["syntheticPhoto"].waitForExistence(timeout: 5)); app.buttons["syntheticPhoto"].tap()
        app.buttons["coachSend"].tap()
        XCTAssertTrue(app.staticTexts["coachFixtureBanner"].waitForExistence(timeout: 5))
        waitForReply(to: "Two eggs, three bread slices and salad", in: app)
        openLatestMeal(in: app)
        XCTAssertTrue(app.staticTexts["Egg breakfast"].firstMatch.exists, "A mixed meal shows its Coach title")
        for food in ["Eggs", "Bread", "Salad"] { revealMealDetailItem(app.staticTexts[food].firstMatch, in: app) }
        revealMealDetailItem(app.staticTexts["3 slice"], in: app)
        revealList(app.buttons["viewMealPhoto"].firstMatch, in: app)
        XCTAssertTrue(app.buttons["viewMealPhoto"].firstMatch.isHittable)
        app.navigationBars.buttons.firstMatch.tap()
        enter("half bread", in: app); app.buttons["coachSend"].tap()
        waitForReply(to: "half bread", in: app); openLatestMeal(in: app)
        revealMealDetailItem(app.staticTexts["300"], in: app)
        for quantity in ["1.5 slice", "2 egg", "1 bowl"] {
            revealMealDetailItem(app.staticTexts[quantity], in: app)
        }
        app.navigationBars.buttons.firstMatch.tap()
        enter("Yesterday I had dessert", in: app); app.buttons["coachSend"].tap()
        waitForReply(to: "Yesterday I had dessert", in: app)
        app.tabBars.buttons["Diary"].tap()
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: yesterday)
        XCTAssertTrue(app.selectDiaryDate(date))
        let historicalMeal = app.buttons["historyMeal"].firstMatch
        revealList(historicalMeal, in: app)
        XCTAssertTrue(historicalMeal.label.contains("Time unspecified"))
        historicalMeal.tap()
        revealMealDetailItem(app.staticTexts["Time unspecified"], in: app)
        revealMealDetailItem(app.staticTexts[date], in: app)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Diary"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Coach"].tap(); enter("Fixture review meal", in: app); app.buttons["coachSend"].tap()
        waitForReply(to: "Fixture review meal", in: app)
        let reviewLink = app.buttons.matching(identifier: "coachMealLink").matching(NSPredicate(format: "label CONTAINS %@", "Needs review")).firstMatch
        revealCoachLink(reviewLink, in: app)
        XCTAssertTrue(reviewLink.waitForExistence(timeout: 5)); reviewLink.tap()
        XCTAssertTrue(app.navigationBars["Meal"].waitForExistence(timeout: 5))
        let accept = app.buttons["acceptReview"]
        revealMealDetailItem(accept, in: app)
        XCTAssertTrue(accept.waitForExistence(timeout: 5)); accept.tap()
        revealMealDetailItem(app.staticTexts["Snack"].firstMatch, in: app)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Synthetic fixture saved review record"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate(); app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        let persistedInputs = ["Two eggs, three bread slices and salad", "half bread", "Yesterday I had dessert", "Fixture review meal"]
        var persistedTurnIDs = Set<String>()
        for text in persistedInputs.reversed() {
            let input = app.staticTexts.matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", text, "coachText-")).firstMatch
            revealCoach(input, in: app)
            XCTAssertEqual(input.label, text)
            persistedTurnIDs.insert(input.identifier)
            let reply = ownReply(to: text, in: app)
            revealCoach(reply, in: app)
            XCTAssertFalse(reply.label.isEmpty, "Each of the four actual captured turns must retain its own completed reply")
        }
        XCTAssertEqual(persistedTurnIDs.count, 4)
        let banner = app.staticTexts["coachFixtureBanner"]
        for _ in 0..<12 where !banner.isHittable { coachViewport(in: app).swipeDown() }
        XCTAssertTrue(banner.isHittable)
    }

    func testFixtureGoalsWeightWorkoutBudgetAndRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        app.buttons["profileSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        revealList(app.buttons["editGoals"], in: app); app.buttons["editGoals"].tap()
        let target = app.textFields["goalKcal"]
        XCTAssertTrue(target.waitForExistence(timeout: 5)); target.tap(); target.typeText("2000")
        app.buttons["saveGoals"].tap()
        XCTAssertTrue(app.buttons["doneSettings"].waitForExistence(timeout: 5)); app.buttons["doneSettings"].tap()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 5))
        enter("Two eggs, three bread slices and salad", in: app); app.buttons["coachSend"].tap()
        XCTAssertTrue(app.staticTexts["coachFixtureBanner"].waitForExistence(timeout: 5))
        waitForReply(to: "Two eggs, three bread slices and salad", in: app)
        openLatestMeal(in: app)
        XCTAssertTrue(app.staticTexts["Eggs"].firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()
        enter("I weighed 70 kg this morning", in: app); app.buttons["coachSend"].tap()
        waitForReply(to: "I weighed 70 kg this morning", in: app)
        let chip = app.descendants(matching: .any)["coachWeightChip"].firstMatch
        guard chip.waitForExistence(timeout: 5), chip.label.contains("70 kg") else {
            XCTFail("The morning weigh-in must be saved through the production tool and shown from its receipt")
            return
        }
        enter("I did 30 minutes of strength: Squat, 8 repetitions at 40 kg, estimated burn 200 kcal", in: app)
        app.buttons["coachSend"].tap()
        waitForReply(to: "I did 30 minutes of strength: Squat, 8 repetitions at 40 kg, estimated burn 200 kcal", in: app)
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
        let budget = waitForReply(to: "What is my remaining budget?", in: app)
        // The fixture invents 9999, so the reply must be the app's grounded fact line.
        XCTAssertEqual(budget.label, "Today: 420 of 2,000 kcal, about 1,580 left. Weight average 70 kg.")
        enter("Show my weekly report", in: app); app.buttons["coachSend"].tap()
        let weekly = waitForReply(to: "Show my weekly report", in: app)
        XCTAssertFalse(weekly.label.contains("9999"), weekly.label)
        XCTAssertTrue(weekly.label.hasPrefix("Last 7 days") || weekly.label.hasPrefix("No finished days"), weekly.label)
        app.terminate(); app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        revealCoach(weekly, in: app)
        XCTAssertFalse(weekly.label.contains("9999"))
        for text in ["Two eggs, three bread slices and salad", "I weighed 70 kg this morning", "What is my remaining budget?", "Show my weekly report"].reversed() {
            let input = app.staticTexts[text]
            revealCoach(input, in: app)
            XCTAssertEqual(input.label, text)
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
        // Long enough to overflow the tallest iPhone, so there is history to scroll back into.
        let history = (1...96).map { "Synthetic history line \($0)." }.joined(separator: " ")
        enter(history, in: app); app.buttons["coachSend"].tap()
        let status = app.staticTexts["Connect ChatGPT in Settings to continue"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let latest = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [latest], timeout: 5), .completed)
        XCTAssertLessThan(status.frame.maxY, app.textFields["coachInput"].frame.minY)
        // Read history: scroll until the latest status is off screen, or the timeline keeps following it.
        for _ in 0..<4 where status.isHittable { coachViewport(in: app).swipeDown() }
        XCTAssertFalse(status.isHittable)
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
        waitForReply(to: history, in: app)
        enter("Synthetic delayed weekly report", in: app); app.buttons["coachSend"].tap()
        let activity = app.otherElements["coachActivity"]
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        XCTAssertTrue(activity.isHittable)
        XCTAssertLessThanOrEqual(activity.frame.maxY, app.textFields["coachInput"].frame.minY)
        let banner = app.staticTexts["coachFixtureBanner"]
        for _ in 0..<4 where !banner.isHittable { coachViewport(in: app).swipeDown() }
        XCTAssertTrue(banner.isHittable)
        let before = banner.frame.minY
        let jump = app.buttons["coachNewMessage"]
        XCTAssertTrue(jump.waitForExistence(timeout: 15))
        XCTAssertTrue(banner.isHittable)
        XCTAssertEqual(banner.frame.minY, before, accuracy: 2)
        jump.tap()
        let reply = progressReply(containing: "7 days", in: app)
        let replyArrived = reply.waitForExistence(timeout: 30)
        XCTAssertTrue(replyArrived, "The delayed report must complete both inference rounds after returning to latest")
        guard replyArrived else { return }
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
        coachViewport(in: app).coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).press(forDuration: 9)
        let reply = progressReply(containing: "7 days", in: app)
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
        let reply = progressReply(containing: "7 days", in: app)
        var advertisedUnread = false
        let completedWithoutUnread = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            if app.buttons["coachNewMessage"].exists {
                advertisedUnread = true
                return true
            }
            return reply.exists
        }, object: app)
        let completion = XCTWaiter.wait(for: [completedWithoutUnread], timeout: 30)
        XCTAssertEqual(completion, .completed, "Expected the delayed tool reply while following latest")
        XCTAssertFalse(advertisedUnread, "Latest must not advertise unread content before the delayed reply arrives")
        guard completion == .completed, !advertisedUnread else { return }
        XCTAssertTrue(reply.exists)
        XCTAssertLessThanOrEqual(reply.frame.maxY, app.textFields["coachInput"].frame.minY)
        XCTAssertFalse(app.buttons["coachNewMessage"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        let restoredReplyExists = reply.waitForExistence(timeout: 10)
        let restoredScreen = XCTAttachment(screenshot: app.screenshot())
        restoredScreen.name = "Restored latest Coach reply"; restoredScreen.lifetime = .keepAlways; add(restoredScreen)
        if !restoredReplyExists {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Restored Coach accessibility"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        XCTAssertTrue(restoredReplyExists)
        let restoredLatest = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            reply.frame.maxY <= app.textFields["coachInput"].frame.minY
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [restoredLatest], timeout: 5), .completed, "A reopened chat must restore the latest completed message")
        XCTAssertFalse(app.buttons["coachNewMessage"].exists)
    }

    private func coachViewport(in app: XCUIApplication) -> XCUIElement {
        let table = app.tables["coachViewport"]
        return table.exists ? table : app.scrollViews.firstMatch
    }
    /// Slow drags toward an element: a fling can skip a control inside an exchange several screens tall.
    private func nudge(toward element: XCUIElement, in app: XCUIApplication) {
        let viewport = coachViewport(in: app)
        for _ in 0..<16 {
            if element.isHittable, element.frame.minY >= viewport.frame.minY, element.frame.maxY < composerTop(in: app) - 8 { break }
            let above = element.exists && element.frame.minY < viewport.frame.minY + 8
            let start = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: above ? 200 : -200)),
                withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(element.isHittable)
    }
    private func revealCoachLink(_ link: XCUIElement, in app: XCUIApplication) {
        // Hittable can include a partially clipped link whose center is under the composer.
        for _ in 0..<8 {
            if link.isHittable && link.frame.maxY < composerTop(in: app) - 8 { break }
            coachViewport(in: app).swipeUp()
        }
        XCTAssertTrue(link.isHittable)
        XCTAssertLessThan(link.frame.maxY, composerTop(in: app) - 8)
    }
    /// Pip's strip, with its tappable day chip, sits above the field; a link under it is not reachable.
    private func composerTop(in app: XCUIApplication) -> CGFloat {
        let strip = app.descendants(matching: .any)["coachCompanionStrip"].firstMatch
        return min(strip.exists ? strip.frame.minY : .infinity, app.textFields["coachInput"].frame.minY)
    }
    private func replyElements(in app: XCUIApplication) -> XCUIElementQuery {
        // Find the reply independently of its platform accessibility role.
        app.descendants(matching: .any).matching(identifier: "coachReply")
    }
    private func progressReply(containing text: String, in app: XCUIApplication) -> XCUIElement {
        replyElements(in: app).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
    private func revealCoach(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = coachViewport(in: app)
        for _ in 0..<24 where !element.isHittable {
            let above = !element.exists || element.frame.midY < scroll.frame.midY
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.3 : 0.7))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.7 : 0.3))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        if !element.isHittable {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Coach history reveal failure"; screenshot.lifetime = .keepAlways; add(screenshot)
            let hierarchy = XCTAttachment(string: "Requested element: \(element.description)\n\n\(app.debugDescription)")
            hierarchy.name = "Coach history reveal accessibility"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        XCTAssertTrue(element.isHittable)
    }
    func testPhotoAloneCanBeSentWithoutText() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        app.buttons["coachPhotos"].tap()
        XCTAssertTrue(app.buttons["syntheticPhoto"].waitForExistence(timeout: 5)); app.buttons["syntheticPhoto"].tap()
        let send = app.buttons["coachSend"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "A photo alone is enough to send")
        XCTAssertFalse(app.buttons["coachVoice"].exists)
        XCTAssertTrue(send.isEnabled); send.tap()
        XCTAssertTrue(app.staticTexts["Connect ChatGPT in Settings to continue"].waitForExistence(timeout: 10), "The photo-only turn is saved")
    }

    private func quickPromptsApp(hour: Int = 8, id: String = UUID().uuidString, seed: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", id, "--coach-ui-test", "--coach-inference-fixture", "--proof-english", "--quick-prompts-hour", String(hour)]
        if seed { app.launchArguments.append("--quick-prompts-fixture") }
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        return app
    }
    private func chips(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coachQuickPrompt-"))
    }

    func testQuickPromptFillDoesNotSendAndTrailingSlotSwapsMicForSend() {
        let app = quickPromptsApp()
        XCTAssertTrue(app.buttons["coachVoice"].isHittable, "An empty draft offers voice in the trailing slot")
        XCTAssertFalse(app.buttons["coachSend"].exists)
        let strip = app.descendants(matching: .any)["coachCompanionStrip"].firstMatch
        XCTAssertLessThanOrEqual(strip.frame.maxY, app.textFields["coachInput"].frame.minY, "Pip must not cover the field")
        let fill = app.buttons["coachQuickPrompt-log.slot"]
        XCTAssertTrue(fill.waitForExistence(timeout: 5)); XCTAssertTrue(fill.isHittable); XCTAssertGreaterThanOrEqual(fill.frame.height, 44)
        XCTAssertLessThanOrEqual(chips(in: app).count, 4)
        fill.tap()
        XCTAssertEqual(app.textFields["coachInput"].value as? String, "For breakfast I had ")
        XCTAssertTrue(app.buttons["coachSend"].waitForExistence(timeout: 3), "A draft swaps the mic for Send")
        XCTAssertFalse(app.buttons["coachVoice"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["coachQuickPrompts"].exists, "Chips step aside once the draft has text")
        XCTAssertEqual(app.buttons.matching(identifier: "coachMealLink").count, 0, "A fill chip never sends by itself")
    }

    func testQuickPromptSendSendsTheQuestion() {
        let app = quickPromptsApp()
        let send = app.buttons["coachQuickPrompt-ask.yesterday"]
        XCTAssertTrue(send.waitForExistence(timeout: 5)); send.tap()
        XCTAssertTrue(ownReply(to: "How was yesterday?", in: app).exists)
    }

    func testQuickPromptsHideWhileTypingAndReturnWhenCleared() {
        let app = quickPromptsApp()
        let row = app.descendants(matching: .any)["coachQuickPrompts"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        enter("a", in: app)
        XCTAssertTrue(row.waitForNonExistence(timeout: 3))
        app.textFields["coachInput"].typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertTrue(row.waitForExistence(timeout: 3), "The row rides the keyboard while the box is empty")
    }

    func testQuickPromptsStepAsideForAClarification() {
        let app = quickPromptsApp()
        enter("clarify-options", in: app); app.buttons["coachSend"].tap()
        XCTAssertTrue(app.buttons["coachOptionChip"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["coachQuickPrompts"].exists, "Answer chips own the moment")
    }

    func testHiddenSuggestionStaysHiddenAfterRelaunch() {
        let id = UUID().uuidString
        var app = quickPromptsApp(id: id)
        let weight = app.buttons["coachQuickPrompt-log.weight"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        weight.press(forDuration: 1.2)
        app.buttons["Hide this suggestion"].tap()
        XCTAssertTrue(weight.waitForNonExistence(timeout: 3))
        app.terminate(); app = quickPromptsApp(id: id)
        XCTAssertTrue(app.buttons["coachQuickPrompt-log.slot"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["coachQuickPrompt-log.weight"].exists)
    }

    func testCollapseArrowHidesAndRestoresTheRow() {
        let id = UUID().uuidString
        var app = quickPromptsApp(id: id)
        let collapse = app.buttons["coachQuickPromptsCollapse"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 5)); XCTAssertGreaterThanOrEqual(collapse.frame.height, 44)
        let field = app.descendants(matching: .any)["coachInput"]
        collapse.tap()
        XCTAssertTrue(app.buttons["coachQuickPromptsExpand"].waitForExistence(timeout: 3))
        XCTAssertEqual(chips(in: app).count, 0)
        // The tray shrinks to the field: the arrow moves beside it instead of keeping the row's band.
        XCTAssertEqual(app.buttons["coachQuickPromptsExpand"].frame.midY, field.frame.midY, accuracy: 12)
        app.terminate(); app = quickPromptsApp(id: id)
        let expand = app.buttons["coachQuickPromptsExpand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5), "Collapsed stays collapsed after relaunch")
        expand.tap()
        XCTAssertTrue(app.buttons["coachQuickPrompt-log.slot"].waitForExistence(timeout: 3))
    }

    func testSuggestionsSwitchTurnsTheRowOff() {
        let app = quickPromptsApp()
        XCTAssertTrue(app.descendants(matching: .any)["coachQuickPrompts"].waitForExistence(timeout: 5))
        app.buttons["profileSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let toggle = app.switches["coachSuggestionsToggle"]
        for _ in 0..<6 where !toggle.isHittable { app.swipeUp() }
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["coachQuickPrompts"].exists)
        XCTAssertFalse(app.buttons["coachQuickPromptsExpand"].exists)
    }

    func testRelogChipCopiesYesterdaysLunch() {
        let app = quickPromptsApp(hour: 13, seed: true)
        let relog = app.buttons["coachQuickPrompt-relog"]
        XCTAssertTrue(relog.waitForExistence(timeout: 5))
        XCTAssertTrue(relog.label.contains("Same lunch") && relog.label.contains("420"), relog.label)
        relog.tap()
        XCTAssertEqual(app.textFields["coachInput"].value as? String, "For lunch I had Eggs 2 egg, Bread 3 slice, Salad 1 bowl")
        XCTAssertTrue(app.descendants(matching: .any)["coachReplyBar"].exists, "The re-log quotes its source meal")
        app.buttons["coachSend"].tap()
        XCTAssertTrue(app.staticTexts["Logged it again."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "420")).firstMatch.exists)
        XCTAssertTrue(app.buttons["coachQuickPrompt-fix.portion"].waitForExistence(timeout: 5), "A fresh log offers its follow-ups")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coachQuickPrompt-")).firstMatch.identifier, "coachQuickPrompt-ask.calories")
    }

    private func enter(_ text: String, in app: XCUIApplication) {
        let input = app.textFields["coachInput"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText(text)
    }
    private func ownReply(to text: String, in app: XCUIApplication) -> XCUIElement {
        let input = app.staticTexts.matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", text, "coachText-")).firstMatch
        if !input.waitForExistence(timeout: 2) {
            let jump = app.buttons["coachNewMessage"]
            if jump.waitForExistence(timeout: 3), jump.isHittable { jump.tap() }
        }
        XCTAssertTrue(input.waitForExistence(timeout: 5), "The exact submitted text must identify its captured turn after returning to latest")
        let identifier = input.identifier
        XCTAssertTrue(identifier.hasPrefix("coachText-"))
        let exchange = app.descendants(matching: .any)["coachExchange-" + String(identifier.dropFirst("coachText-".count))].firstMatch
        return exchange.descendants(matching: .any).matching(identifier: "coachReply").firstMatch
    }
    @discardableResult private func waitForReply(to text: String, in app: XCUIApplication) -> XCUIElement {
        let reply = ownReply(to: text, in: app)
        XCTAssertTrue(reply.waitForExistence(timeout: 15), "The submitted turn must receive its own completed reply: \(text)")
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: reply)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed, "The current turn's completed reply must remain visible after arrival")
        return reply
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
    /// Coach's own connect link stays in the hierarchy under Settings, so match the Settings label too.
    private func settingsConnectButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "connectChatGPT").matching(NSPredicate(format: "label == %@", "Continue with ChatGPT")).firstMatch
    }
    private func openConnectionSettings(in app: XCUIApplication) {
        app.buttons["profileSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Coach AI")).firstMatch
        revealList(row, in: app); row.tap()
        XCTAssertTrue(app.navigationBars["Coach AI"].waitForExistence(timeout: 5))
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
        // Progress is a chart-first scroll view rather than a list.
        let scroll = app.scrollViews.firstMatch
        if scroll.exists { return scroll }
        XCTFail("The destination must contain its native list")
        return nil
    }
    private func revealMealDetailItem(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Meal"].exists, "Meal content checks require the actual record destination")
        revealList(element, in: app)
    }
}
