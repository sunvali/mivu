import XCTest

@MainActor final class CoachNavigationUITests: XCTestCase {
    func testColdDiarySourceRouteBeforeCoachMountOpensExactSource() {
        let app = launch(["--coach-navigation-start-today"], initialTab: "Today")
        XCTAssertFalse(app.tables["coachViewport"].exists, "Coach has not mounted before this Diary source route")
        openDay(901, in: app)
        let meal = app.buttons.matching(identifier: "historyMeal").firstMatch
        reveal(meal, in: app); meal.tap()
        let source = app.buttons["mealSourceChat"]
        XCTAssertTrue(source.waitForExistence(timeout: 5)); source.tap()
        assertTarget(1, in: app)
        XCTAssertFalse(app.staticTexts["coachTimelineError"].exists)
        XCTAssertFalse(app.staticTexts["coachText-" + id(140)].exists, "The queued source must not be replaced by the latest window")
        XCTAssertEqual(app.staticTexts["coachDate"].label, "Logging to 2027-01-21")
        let input = app.textFields["coachInput"]
        input.tap(); input.typeText("Keep after the cold route")
        openChatHistory(app)
        let nilDay = segment(1132, in: app)
        reveal(nilDay, in: app); nilDay.tap()
        assertTarget(132, in: app)
        XCTAssertEqual(input.value as? String, "Keep after the cold route")
        XCTAssertEqual(app.staticTexts["coachDate"].label, "Logging to 2027-01-21")
    }

    func testOldestHistorySelectionPreservesDraftAndStaticTarget() {
        let app = launch()
        let input = app.textFields["coachInput"]
        input.tap(); input.typeText("Unsent navigation note")
        openChatHistory(app)
        XCTAssertTrue(app.navigationBars["Chat history"].waitForExistence(timeout: 5))
        let first = segment(1001, in: app)
        for _ in 0..<4 {
            let earlier = app.buttons["coachHistoryEarlier"]
            reveal(earlier, in: app)
            XCTAssertGreaterThanOrEqual(earlier.frame.height, 44)
            earlier.tap()
        }
        reveal(first, in: app); first.tap()
        assertTarget(1, in: app)
        XCTAssertEqual(input.value as? String, "Unsent navigation note")
        XCTAssertEqual(app.staticTexts["coachDate"].label, "Logging to 2027-01-21")
        let target = app.descendants(matching: .any)["coachExchange-" + id(1)].firstMatch
        XCTAssertTrue(target.isHittable)
        XCTAssertEqual(target.value as? String, "Selected source message")
        let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = "Exact oldest source with preserved draft and static target"; proof.lifetime = .keepAlways; add(proof)
    }

    func testLegacyRowAndRepeatedCalendarChoicesKeepExactFirstTurns() {
        let app = launch()
        openChatHistory(app)
        let nilDay = segment(1132, in: app)
        reveal(nilDay, in: app); nilDay.tap()
        assertTarget(132, in: app)
        openChatHistory(app)
        app.buttons["coachHistoryChooseDate"].tap()
        XCTAssertTrue(app.buttons["coachHistoryApplyDate"].waitForExistence(timeout: 5))
        app.buttons["coachHistoryApplyDate"].tap()
        let repeated = segment(1140, in: app)
        XCTAssertTrue(repeated.waitForExistence(timeout: 5))
        reveal(repeated, in: app); repeated.tap()
        assertTarget(140, in: app)
        openChatHistory(app)
        app.buttons["coachHistoryChooseDate"].tap()
        let picker = app.datePickers["coachHistoryDatePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let days = picker.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Thursday, 14 January"))
        let day = days.firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        XCTAssertEqual(days.count, 1)
        XCTAssertTrue(day.isHittable); day.tap()
        app.buttons["coachHistoryApplyDate"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["coachHistoryEmpty"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Chat history"].exists)
    }

    func testDiaryDayAndBackdatedMealUseSameCoachAndHonestNoChat() {
        let app = launch()
        app.textFields["coachInput"].tap(); app.textFields["coachInput"].typeText("Keep across diary links")
        openDay(901, in: app)
        let chat = app.buttons["diaryDayOpenChat"]
        XCTAssertTrue(chat.waitForExistence(timeout: 5)); chat.tap()
        assertTarget(5, in: app)
        XCTAssertEqual(app.textFields["coachInput"].value as? String, "Keep across diary links")
        openDay(901, in: app)
        let meal = app.buttons.matching(identifier: "historyMeal").firstMatch
        reveal(meal, in: app); meal.tap()
        let source = app.buttons["mealSourceChat"]
        XCTAssertTrue(source.waitForExistence(timeout: 5)); source.tap()
        assertTarget(1, in: app)
        // The receipt opens the same detail from Coach; its source returns to the existing model.
        let review = app.buttons["coachMealLink"].firstMatch
        reveal(review, in: app); review.tap()
        XCTAssertTrue(app.buttons["mealSourceChat"].waitForExistence(timeout: 5))
        app.buttons["mealSourceChat"].tap(); assertTarget(1, in: app)
        XCTAssertEqual(app.textFields["coachInput"].value as? String, "Keep across diary links")
        openDay(904, in: app)
        app.buttons["diaryDayOpenChat"].tap()
        let unavailable = app.staticTexts["coachTimelineError"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 5))
        XCTAssertEqual(unavailable.label, "No conversation for this diary day.")
        XCTAssertEqual(app.textFields["coachInput"].value as? String, "Keep across diary links")
    }

    private func launch(_ extra: [String] = [], initialTab: String = "Coach") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-history-fixture", "--coach-inference-fixture", "--proof-english"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars[initialTab].waitForExistence(timeout: 15))
        if initialTab == "Coach" { XCTAssertTrue(app.tables["coachViewport"].waitForExistence(timeout: 10)) }
        return app
    }
    private func id(_ number: Int) -> String { String(format: "00000000-0000-0000-0000-%012d", number) }
    private func segment(_ number: Int, in app: XCUIApplication) -> XCUIElement { app.buttons["coachHistorySegment-" + id(number)] }
    private func assertTarget(_ number: Int, in app: XCUIApplication) {
        let target = app.staticTexts["coachText-" + id(number)]
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: target)
        let targetResult = XCTWaiter.wait(for: [visible], timeout: 5)
        print("COACH_ROUTE_DIAGNOSTICS " + (app.staticTexts["historyMetrics"].value as? String ?? ""))
        print("COACH_ROUTE_AX identifier=\(target.identifier) frame=\(target.frame) hittable=\(target.isHittable)")
        XCTAssertEqual(targetResult, .completed)
        XCTAssertTrue(app.navigationBars["Coach"].exists)
        let selected = app.descendants(matching: .any)["coachExchange-" + id(number)].firstMatch
        XCTAssertTrue(selected.isHittable)
        XCTAssertEqual(selected.value as? String, "Selected source message")
    }
    private func openDay(_ number: Int, in app: XCUIApplication) {
        guard openDiaryRoot(app) else { return }
        let label = number == 904 ? "2027-01-21 UTC" : "2027-01-15 UTC"
        let day = app.buttons.matching(identifier: "diaryDay").matching(NSPredicate(format: "value == %@", label)).firstMatch
        reveal(day, in: app); day.tap()
        XCTAssertTrue(app.buttons["diaryDayOpenChat"].waitForExistence(timeout: 5))
    }
    private func openChatHistory(_ app: XCUIApplication) {
        if !app.buttons["coachHistory"].exists, app.buttons["OverflowBarButtonItem"].exists { app.buttons["OverflowBarButtonItem"].tap() }
        let action = app.buttons["coachHistory"].exists ? app.buttons["coachHistory"] : app.buttons["Chat history"]
        XCTAssertTrue(action.waitForExistence(timeout: 5)); action.tap()
    }
    private func openDiaryRoot(_ app: XCUIApplication) -> Bool {
        let input = app.textFields["coachInput"]
        let draft = input.exists ? input.value as? String : nil
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            let table = app.tables["coachViewport"]
            let appFrame = app.frame, keyboardFrame = keyboard.frame
            let aboveKeyboard = CGRect(x: appFrame.minX, y: appFrame.minY, width: appFrame.width,
                height: max(0, keyboardFrame.minY - appFrame.minY))
            let visible = table.frame.intersection(aboveKeyboard)
            guard table.isHittable, !visible.isNull, visible.height > 24, !keyboardFrame.isEmpty else {
                XCTFail("A visible table and keyboard are required for native interactive dismissal"); return false
            }
            // Cross the keyboard's measured top and bottom, rather than ending inside the short table.
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: visible.midX - appFrame.minX, dy: visible.maxY - 12 - appFrame.minY))
            let finish = origin.withOffset(CGVector(dx: visible.midX - appFrame.minX,
                dy: min(appFrame.maxY, keyboardFrame.maxY) - 4 - appFrame.minY))
            start.press(forDuration: 0.05, thenDragTo: finish)
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: keyboard)
            let result = XCTWaiter.wait(for: [dismissed], timeout: 5)
            XCTAssertEqual(result, .completed)
            XCTAssertEqual(input.value as? String, draft)
            guard result == .completed else { return false }
        }
        let tab = app.tabBars.buttons["Diary"]
        guard tab.isHittable else { XCTFail("Diary tab must be visible after keyboard dismissal"); return false }
        tab.tap()
        for _ in 0..<3 where !app.navigationBars["Diary"].exists {
            guard !app.navigationBars["Coach"].exists else { XCTFail("Diary navigation is not active"); return false }
            let back = app.navigationBars.buttons.firstMatch
            guard back.waitForExistence(timeout: 5), back.isHittable else { XCTFail("Diary back control is unavailable"); return false }
            back.tap()
        }
        let ready = app.navigationBars["Diary"].waitForExistence(timeout: 5)
        XCTAssertTrue(ready)
        if ready { XCTAssertTrue(app.tabBars.buttons["Diary"].isSelected) }
        return ready
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let isCoach = !app.navigationBars["Chat history"].exists && app.tables["coachViewport"].isHittable && app.navigationBars["Coach"].exists
        let list = isCoach ? app.tables["coachViewport"] : app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        for _ in 0..<16 where !element.isHittable {
            let down = element.exists && !element.frame.isEmpty && element.frame.minY < (isCoach ? list.frame.minY : app.navigationBars.firstMatch.frame.maxY)
            if isCoach {
                let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                let step = min(80, list.frame.height * 0.25) * (down ? 1.0 : -1.0)
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: step)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
            } else if down { list.swipeDown() }
            else { list.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
}
