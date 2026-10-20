import XCTest

@MainActor final class DiaryUITests: XCTestCase {
    func testDiaryOlderNewerLatestAndDateFilterRemainReversible() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-navigation-start-today", "--diary-history-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["logMeal"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Diary"].tap()
        let days = app.buttons.matching(identifier: "diaryDay")
        func firstDay(_ date: String) -> XCUIElement {
            days.matching(NSPredicate(format: "value == %@", date + " UTC")).firstMatch
        }
        func observedDays() -> String {
            days.allElementsBoundByIndex.map { "\($0.value ?? "nil"): \($0.label)" }.joined(separator: " | ")
        }
        func assertTop(_ date: String) -> Bool {
            let anchor = firstDay(date)
            for _ in 0..<10 {
                if anchor.exists && anchor.isHittable { break }
                app.swipeDown(velocity: .fast)
            }
            guard anchor.exists && anchor.isHittable else {
                XCTFail("Expected page anchor \(date); observed \(observedDays())")
                return false
            }
            XCTAssertEqual(anchor.value as? String, date + " UTC")
            return true
        }
        func tapPage(_ id: String, first date: String) -> Bool {
            let button = app.buttons[id]
            for _ in 0..<10 { if button.exists && button.isHittable { break }; app.swipeUp(velocity: .fast) }
            guard button.exists && button.isHittable && button.isEnabled else {
                XCTFail("Page action \(id) unavailable; observed \(observedDays())")
                return false
            }
            let previous = days.firstMatch.value as? String
            button.tap()
            let changed = NSPredicate { _, _ in (days.firstMatch.value as? String) != previous }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: nil)], timeout: 10), .completed)
            return assertTop(date)
        }
        XCTAssertTrue(days.firstMatch.waitForExistence(timeout: 10))
        print("HISTORY_INITIAL_ROWS " + observedDays())
        guard assertTop("2026-10-19"),
              tapPage("earlierDiaryDays", first: "2026-09-19"),
              tapPage("earlierDiaryDays", first: "2026-08-20"),
              tapPage("newerDiaryDays", first: "2026-09-19"),
              tapPage("latestDiaryDays", first: "2026-10-19") else { return }
        app.buttons["chooseDiaryDate"].tap(); app.buttons["applyDiaryDate"].tap()
        XCTAssertTrue(app.buttons["showAllDiaryDays"].waitForExistence(timeout: 5))
        let filtered = NSPredicate { _, _ in days.count == 1 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: filtered, object: nil)], timeout: 10), .completed)
        XCTAssertEqual(days.count, 1)
        days.firstMatch.tap()
        XCTAssertTrue(app.buttons["logMealForDay"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["showAllDiaryDays"].waitForExistence(timeout: 5))
        XCTAssertEqual(days.count, 1)
        app.buttons["showAllDiaryDays"].tap()
        let unfiltered = NSPredicate { _, _ in days.count > 1 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: unfiltered, object: nil)], timeout: 10), .completed)
        _ = assertTop("2026-10-19")
    }
    func testFirstRunCreatesNamedDiaryWithoutInventingRecords() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--onboarding-ui-test", "--proof-english"]
        app.launch()
        let name = app.textFields["newDiaryName"]
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["createDiary"].isEnabled)
        XCTAssertTrue(app.buttons["Restore from diary archive"].exists)
        name.tap(); name.typeText("Synthetic diary")
        app.buttons["createDiary"].tap()
        // Pip's onboarding follows: answer, skip ChatGPT, and save the formula estimate.
        let next = app.buttons["onboardingNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()
        for (field, value) in [("Height in cm", "170"), ("Weight in kg", "80"), ("Birth year", "1990"), ("Target weight in kg", "72")] {
            if field == "Target weight in kg" { next.tap() } // sex: keep "Prefer not to say"
            let input = app.textFields.matching(NSPredicate(format: "label == %@ OR placeholderValue == %@", field, field.components(separatedBy: " in ")[0])).firstMatch
            XCTAssertTrue(input.waitForExistence(timeout: 5), field)
            input.tap(); input.typeText(value)
            next.tap()
        }
        next.tap() // pace
        next.tap() // diet
        app.buttons["onboardingSkipConnect"].tap()
        XCTAssertTrue(app.staticTexts["Estimate from a standard formula"].waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.buttons["logMeal"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
        XCTAssertEqual(app.buttons.matching(identifier: "mealRow").count, 0)
        app.buttons["profileSettings"].tap()
        XCTAssertTrue(app.buttons["localProfiles"].label.contains("Synthetic diary"))
    }
    func testPrecisionGlassReferenceScreensInBothAppearances() {
        for mode in ["light", "dark"] {
            let app = launch(["--proof-" + mode])
            app.buttons["logMeal"].tap()
            let note = app.textFields["mealText"]
            XCTAssertTrue(note.waitForExistence(timeout: 5))
            note.tap(); note.typeText("Synthetic lunch")
            if app.buttons["doneMealText"].exists { app.buttons["doneMealText"].tap() }
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "Precision Glass Capture " + mode; capture.lifetime = .keepAlways; add(capture)
            app.buttons["sendMeal"].tap()
            XCTAssertTrue(app.buttons["mealRow"].firstMatch.waitForExistence(timeout: 10))
            for tab in ["Today", "Diary", "Progress", "Coach"] {
                app.tabBars.buttons[tab].tap()
                XCTAssertTrue(app.buttons["profileSettings"].waitForExistence(timeout: 5))
                if tab == "Coach" {
                    let heading = app.staticTexts["What would you like to record?"]
                    XCTAssertTrue(heading.waitForExistence(timeout: 5))
                    XCTAssertGreaterThanOrEqual(heading.frame.minX, app.frame.minX + 16)
                    XCTAssertGreaterThanOrEqual(app.staticTexts["coachDate"].frame.minY, app.navigationBars["Coach"].frame.maxY)
                }
                let screen = XCTAttachment(screenshot: app.screenshot())
                screen.name = "Precision Glass " + tab + " " + mode; screen.lifetime = .keepAlways; add(screen)
            }
            app.buttons["profileSettings"].tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
            let settings = XCTAttachment(screenshot: app.screenshot())
            settings.name = "Precision Glass Settings " + mode; settings.lifetime = .keepAlways; add(settings)
            app.terminate()
        }
    }

    func testPrecisionGlassNavigationAndSettingsReturn() {
        let app = launch()
        let expected = ["Today", "Diary", "Progress", "Coach"]
        XCTAssertEqual(app.tabBars.buttons.allElementsBoundByIndex.map(\.label), expected)
        for tab in expected {
            app.tabBars.buttons[tab].tap()
            let profile = app.buttons["profileSettings"]
            XCTAssertTrue(profile.waitForExistence(timeout: 5))
            profile.tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
            app.buttons["doneSettings"].tap()
            XCTAssertTrue(app.tabBars.buttons[tab].isSelected)
        }
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--proof-english"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["logMeal"].waitForExistence(timeout: 15))
        return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let lists = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
        guard let list = lists.reversed().first(where: { list in
            list.isHittable || (list.buttons.allElementsBoundByIndex + list.textFields.allElementsBoundByIndex + list.staticTexts.allElementsBoundByIndex).contains(where: { $0.isHittable })
        }) else { XCTFail("The destination must contain a foreground native list"); return }
        for _ in 0..<10 where !readyToUse(element, in: app) {
            if element.exists, !element.frame.isEmpty,
               element.frame.midY < app.navigationBars.firstMatch.frame.maxY {
                list.swipeDown()
            } else {
                list.swipeUp()
            }
        }
        for _ in 0..<10 where !readyToUse(element, in: app) { list.swipeDown() }
        XCTAssertTrue(readyToUse(element, in: app), "The target must be reachable; morning weight must clear fixed controls")
    }
    private func readyToUse(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, element.isHittable else { return false }
        guard element.identifier == "logWeight" else { return true }
        let top = app.navigationBars.firstMatch.frame.maxY
        var bottom = app.frame.maxY
        let tabs = app.tabBars.firstMatch
        if tabs.exists { bottom = min(bottom, tabs.frame.minY) }
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists { bottom = min(bottom, keyboard.frame.minY) }
        let capture = app.buttons["logMeal"]
        if capture.exists, capture.isHittable { bottom = min(bottom, capture.frame.minY - 12) }
        let frame = element.frame
        guard bottom > top else { return false }
        guard frame.height <= bottom - top else { return true }
        return frame.minY >= top + 4 && frame.maxY <= bottom - 4
    }
    private func replace(_ field: XCUIElement, with value: String) {
        field.tap()
        // A centered tap can place the caret before a short, trailing-aligned value.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        if let text = field.value as? String, !text.isEmpty { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count)) }
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value, "The edited amount must match the requested value before saving")
    }

    func testCapturePhotoReviewCorrectionEditingAndHistory() {
        let app = launch(["--proof-hebrew", "-AppleLanguages", "(he)", "-AppleLocale", "he_IL"])
        app.buttons["logMeal"].tap()
        let field = app.textFields["mealText"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertLessThan(app.navigationBars.buttons["Cancel"].frame.midX, app.buttons["sendMeal"].frame.midX)
        field.tap(); field.typeText("Synthetic lunch")
        if app.buttons["doneMealText"].exists { app.buttons["doneMealText"].tap() }
        app.buttons["syntheticPhoto"].tap()
        let review = app.switches["reviewFirst"]
        let toggle = review.switches.firstMatch
        reveal(toggle, in: app); toggle.tap()
        guard review.value as? String == "1" else {
            let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Review switch input failure"; attachment.lifetime = .keepAlways; add(attachment)
            print("REVIEW_SWITCH_INPUT_STATE\n" + review.debugDescription)
            XCTFail("Review switch must be on before sending"); return
        }
        app.buttons["sendMeal"].tap()
        let row = app.buttons["mealRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); reveal(row, in: app); row.tap()
        XCTAssertFalse(app.tabBars.buttons["Today"].isHittable, "Focused meal details must hide the tab bar")
        let accept = app.buttons["acceptReview"]
        reveal(accept, in: app); XCTAssertTrue(accept.waitForExistence(timeout: 10)); accept.tap()
        let half = app.buttons["halfPortion"]
        reveal(half, in: app); XCTAssertTrue(half.isEnabled); half.tap()
        let edit = app.buttons["editItem"].firstMatch
        reveal(edit, in: app); edit.tap()
        let quantity = app.textFields["itemQuantity"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        XCTAssertLessThan(app.navigationBars.buttons["Cancel"].frame.midX, app.buttons["saveItem"].frame.midX)
        let itemScreen = XCTAttachment(screenshot: app.screenshot()); itemScreen.name = "English item editor"; itemScreen.lifetime = .keepAlways; add(itemScreen)
        replace(quantity, with: "2")
        app.buttons["saveItem"].tap()
        let energy = app.staticTexts["190"]
        XCTAssertTrue(energy.waitForExistence(timeout: 10)); reveal(energy, in: app)
        app.navigationBars.buttons.firstMatch.tap()
        let weight = app.buttons["logWeight"]
        reveal(weight, in: app); weight.tap()
        let input = app.textFields["weightInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertLessThan(app.navigationBars.buttons["Cancel"].frame.midX, app.buttons["saveWeight"].frame.midX)
        let weightScreen = XCTAttachment(screenshot: app.screenshot()); weightScreen.name = "English weight sheet"; weightScreen.lifetime = .keepAlways; add(weightScreen)
        input.tap(); input.typeText("70")
        app.buttons["saveWeight"].tap()
        app.tabBars.buttons["Diary"].tap()
        XCTAssertTrue(app.navigationBars["Diary"].waitForExistence(timeout: 5))
        let day = app.buttons["diaryDay"].firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5)); day.tap()
        XCTAssertFalse(app.tabBars.buttons["Diary"].isHittable)
        let savedWeight = app.staticTexts["Morning weight, 70 kg"]
        reveal(savedWeight, in: app); XCTAssertTrue(savedWeight.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Synthetic diary history"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testCancelDoesNotCreateMealAndProfilesRemainSeparate() {
        let app = launch()
        app.buttons["logMeal"].tap()
        let text = app.textFields["mealText"]; XCTAssertTrue(text.waitForExistence(timeout: 5)); text.tap(); text.typeText("Unsaved synthetic input")
        app.navigationBars.buttons["Cancel"].tap()
        let keepEditing = app.buttons["Keep editing"]
        XCTAssertTrue(keepEditing.waitForExistence(timeout: 5)); keepEditing.tap()
        XCTAssertEqual(text.value as? String, "Unsaved synthetic input", "Keeping the editor must preserve the draft")
        app.navigationBars.buttons["Cancel"].tap()
        let discard = app.buttons["Discard changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5)); discard.tap()
        XCTAssertTrue(app.buttons["logMeal"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["mealRow"].firstMatch.exists)
        let settings = app.buttons["profileSettings"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: settings)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed else { XCTFail("Profile and settings must be reachable after composer dismissal"); return }
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["localProfiles"].tap()
        XCTAssertTrue(app.navigationBars["Local profiles"].waitForExistence(timeout: 5))
        let create = app.buttons["Create local profile"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        let name = app.alerts.textFields.firstMatch; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.typeText("Synthetic second profile")
        app.alerts.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic second profile"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["doneSettings"].tap()
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["logMeal"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["mealRow"].firstMatch.exists)
    }

    func testUnsavedSettingsRequireExplicitDiscard() {
        let app = launch()
        app.buttons["profileSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["Diary preferences"].tap()
        XCTAssertTrue(app.navigationBars["Diary preferences"].waitForExistence(timeout: 5))

        let dietaryPreferences = app.textFields["dietaryPreferences"]
        XCTAssertTrue(dietaryPreferences.waitForExistence(timeout: 5))
        dietaryPreferences.tap()
        dietaryPreferences.typeText("Synthetic dietary preference")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        app.buttons["doneSettings"].tap()
        let keepEditing = app.buttons["Keep editing"]
        XCTAssertTrue(keepEditing.waitForExistence(timeout: 5))
        keepEditing.tap()
        app.buttons["Diary preferences"].tap()
        let retainedDraft = app.textFields["dietaryPreferences"]
        XCTAssertTrue(retainedDraft.waitForExistence(timeout: 5))
        XCTAssertEqual(retainedDraft.value as? String, "Synthetic dietary preference")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["doneSettings"].tap()
        let discard = app.buttons["Discard changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        XCTAssertTrue(app.buttons["logMeal"].waitForExistence(timeout: 5))

        app.buttons["profileSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["Diary preferences"].tap()
        let discardedDraft = app.textFields["dietaryPreferences"]
        XCTAssertTrue(discardedDraft.waitForExistence(timeout: 5))
        XCTAssertNotEqual(discardedDraft.value as? String, "Synthetic dietary preference")
    }

    private func capturePhotoOnlyReview(in app: XCUIApplication) -> XCUIElement {
        app.buttons["logMeal"].tap()
        XCTAssertTrue(app.buttons["syntheticPhoto"].waitForExistence(timeout: 5))
        app.buttons["syntheticPhoto"].tap()
        let review = app.switches["reviewFirst"]
        let toggle = review.switches.firstMatch; reveal(toggle, in: app); toggle.tap()
        XCTAssertEqual(review.value as? String, "1")
        app.buttons["sendMeal"].tap()
        let row = app.buttons["mealRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        return row
    }

    func testPhotoOnlyReviewHasReadableMealTitle() {
        let app = launch()
        let row = capturePhotoOnlyReview(in: app)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Photo-only review meal title"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertTrue(row.label.contains("Meal"), "Photo-only pending/review meals need a readable fallback title; actual label: " + row.label)
    }

    func testMealPhotoViewerClosingAndCancelledDeletionPreserveRecord() {
        let app = launch()
        let row = capturePhotoOnlyReview(in: app)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Awaiting review"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        let originalLabel = row.label
        reveal(row, in: app); row.tap()
        let photo = app.buttons["viewMealPhoto"].firstMatch
        reveal(photo, in: app); photo.tap()
        XCTAssertTrue(app.navigationBars["Meal photo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Photo timing: Unspecified"].exists)
        app.buttons["zoomInPhoto"].tap()
        XCTAssertEqual(app.staticTexts["photoZoomLevel"].label, "200%")
        app.scrollViews["mealPhotoZoom"].doubleTap()
        XCTAssertEqual(app.staticTexts["photoZoomLevel"].label, "100%")
        app.buttons["deleteViewedPhoto"].tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        XCTAssertTrue(app.buttons["closeMealPhoto"].isHittable)
        app.buttons["closeMealPhoto"].tap()
        XCTAssertTrue(app.navigationBars["Meal"].waitForExistence(timeout: 5))
        XCTAssertTrue(photo.exists, "Closing or cancelling deletion must preserve the attachment")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["mealRow"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "mealRow").count, 1)
        XCTAssertEqual(app.buttons["mealRow"].firstMatch.label, originalLabel, "Viewing a photo must not change its meal")
    }

    func testLogMealFromSelectedHistoricalDayKeepsTodaySeparate() {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--proof-english"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 15))
        let input = app.textFields["coachInput"]
        input.tap(); input.typeText("Yesterday I had dessert"); app.buttons["coachSend"].tap()
        let receipt = app.buttons["coachMealLink"].firstMatch
        XCTAssertTrue(receipt.waitForExistence(timeout: 15))
        app.tabBars.buttons["Diary"].tap()
        let day = app.buttons["diaryDay"].firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5)); day.tap()
        let selectedDate = app.navigationBars.firstMatch.identifier
        let log = app.buttons["logMealForDay"]
        XCTAssertTrue(log.waitForExistence(timeout: 5)); reveal(log, in: app); log.tap()
        let note = app.textFields["mealText"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[selectedDate].exists, "The composer must show its selected destination")
        note.tap(); note.typeText("Synthetic selected-day meal")
        if app.buttons["doneMealText"].exists { app.buttons["doneMealText"].tap() }
        let review = app.switches["reviewFirst"].switches.firstMatch
        reveal(review, in: app); review.tap()
        app.buttons["sendMeal"].tap()
        XCTAssertTrue(app.navigationBars[selectedDate].waitForExistence(timeout: 10))
        let meal = app.buttons["savedDayMealReceipt"]
        reveal(meal, in: app); meal.tap()
        XCTAssertTrue(app.staticTexts["Time unspecified"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[selectedDate].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["Today"].tap()
        XCTAssertFalse(app.buttons["mealRow"].firstMatch.exists, "Historical capture must not move records into Today")
    }

    func testEnglishDarkLargeTextRendering() {
        let app = launch(["--proof-hebrew", "--proof-dark", "--proof-largest-text", "-AppleLanguages", "(he)", "-AppleLocale", "he_IL"])
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Apple sample mode"].exists)
        XCTAssertTrue(app.buttons["logMeal"].isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "English dark largest accessibility5 Today"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testLegacyHebrewLaunchUsesEnglishLeftToRight() {
        let app = launch(["--proof-hebrew", "-AppleLanguages", "(he)", "-AppleLocale", "he_IL"])
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "English legacy Hebrew launch"; attachment.lifetime = .keepAlways; add(attachment)
        guard app.navigationBars["Today"].waitForExistence(timeout: 5) else { XCTFail("Legacy Hebrew settings must still open English Today"); return }
        XCTAssertTrue(app.staticTexts["Apple sample mode"].exists)
        let today = app.tabBars.buttons["Today"], diary = app.tabBars.buttons["Diary"], progress = app.tabBars.buttons["Progress"], coach = app.tabBars.buttons["Coach"]
        XCTAssertLessThan(today.frame.midX, diary.frame.midX)
        XCTAssertLessThan(diary.frame.midX, progress.frame.midX)
        XCTAssertLessThan(progress.frame.midX, coach.frame.midX)
        app.buttons["profileSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.segmentedControls.count, 0)
        XCTAssertTrue(app.staticTexts["My diary"].exists)
        app.buttons["Diary preferences"].tap()
        XCTAssertTrue(app.navigationBars["Diary preferences"].waitForExistence(timeout: 5))
        let language = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ OR (label == %@ AND value == %@)", "App language, English", "App language", "English"
        )).firstMatch
        reveal(language, in: app)
        XCTAssertTrue(language.isHittable)
        XCTAssertTrue(language.label == "App language, English" || (language.label == "App language" && language.value as? String == "English"))
        XCTAssertEqual(app.segmentedControls.count, 0, "The unsupported language selector must remain hidden")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ChatGPT connection")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["ChatGPT connection"].waitForExistence(timeout: 5))
        let diagnostic = app.buttons["ChatGPT connection diagnostic"]
        reveal(diagnostic, in: app); diagnostic.tap()
        XCTAssertTrue(app.staticTexts["Connection test"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.segmentedControls.count, 0)
        XCTAssertGreaterThan(app.buttons["Done"].frame.midX, app.frame.midX)
        XCTAssertLessThan(app.staticTexts["Connection test"].frame.minX, app.frame.midX)
        let diagnosticScreen = XCTAttachment(screenshot: app.screenshot()); diagnosticScreen.name = "English connection diagnostic"; diagnosticScreen.lifetime = .keepAlways; add(diagnosticScreen)
    }
}
