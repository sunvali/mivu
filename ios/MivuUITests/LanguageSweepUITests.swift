import XCTest

/// Walks every main screen in one of three modes and attaches a capture of each.
/// Mode and text size come from the runner's environment: `TEST_RUNNER_SWEEP_MODE=english|rtl|double`
/// and `TEST_RUNNER_SWEEP_TEXT=default|largest`. See docs/verification/languages/README.md.
@MainActor final class LanguageSweepUITests: XCTestCase {
    /// Screens whose text is not all in the string catalogs yet. Empty when the app is language-ready.
    static let notYetLocalized: Set<String> = [
        "onboarding", "today", "diary", "mealDetail", "mealComposer", "manualNutrition", "progress",
        "goalEditor", "weightEditor", "settings",
    ]
    /// Text the fixtures or the test typed: data, not interface.
    static let fixtureData: Set<String> = ["Two eggs, three bread slices and salad", "My diary", "Synthetic history food",
                                           "Eggs", "Bread", "Salad", "All set.", "1 bowl", "2 egg", "3 slice"]

    private var mode: String { ProcessInfo.processInfo.environment["SWEEP_MODE"] ?? "english" }
    private var text: String { ProcessInfo.processInfo.environment["SWEEP_TEXT"] ?? "default" }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = true
        executionTimeAllowance = 600
    }

    private func launch(_ fixture: [String], _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString] + fixture + extra
        if mode == "rtl" { app.launchArguments += ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"] }
        if mode == "double" { app.launchArguments += ["-NSDoubleLocalizedStrings", "YES"] }
        if text == "largest" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }

    private func tab(_ name: String, in app: XCUIApplication) -> XCUIElement {
        // Labels are doubled in double mode, and the Duo's sideways bar is not a tab bar.
        let named = NSPredicate(format: "label BEGINSWITH %@", name)
        let inBar = app.tabBars.buttons.matching(named).firstMatch
        return inBar.exists ? inBar : app.buttons.matching(named).firstMatch
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        // Short drags: a full swipe at the largest text size can carry a row past the screen.
        for _ in 0..<24 where !(element.exists && element.isHittable) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        }
    }

    private func close(_ app: XCUIApplication) {
        for id in ["doneSettings", "cancelManualNutrition", "quickLogClose", "coachCameraClose"] where app.buttons[id].exists && app.buttons[id].isHittable {
            app.buttons[id].tap(); return
        }
        let cancel = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Cancel' OR label BEGINSWITH 'Close' OR label BEGINSWITH 'Done'")).firstMatch
        if cancel.exists && cancel.isHittable { cancel.tap(); return }
        let back = app.navigationBars.buttons.firstMatch
        if back.exists && back.isHittable { back.tap() } else { app.swipeDown(velocity: .fast) }
    }

    /// Opens each screen in turn and calls `body` with its name while it is showing.
    func visitAllScreens(_ body: (String, XCUIApplication) -> Void) {
        func show(_ name: String, _ app: XCUIApplication, opened: Bool = true) {
            XCTAssertTrue(opened, "\(name) did not open")
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "\(mode)-\(text)-\(name)"; capture.lifetime = .keepAlways; add(capture)
            body(name, app)
        }

        var app = launch(["--onboarding-ui-test"])
        show("onboarding", app, opened: app.buttons["onboardingNext"].waitForExistence(timeout: 20))
        app.terminate()

        // With Coach, Log meal opens the chat; the composer sheet is the sample-mode path.
        app = launch([])
        XCTAssertTrue(app.buttons["logMeal"].waitForExistence(timeout: 20)); app.buttons["logMeal"].tap()
        show("mealComposer", app, opened: app.buttons["sendMeal"].waitForExistence(timeout: 10))
        let manual = app.buttons["enterNutritionManually"]
        reveal(manual, in: app)
        if manual.exists {
            manual.tap()
            show("manualNutrition", app, opened: app.buttons["cancelManualNutrition"].waitForExistence(timeout: 10))
        } else { XCTFail("manualNutrition did not open") }
        app.terminate()

        app = launch(["--coach-ui-test", "--coach-inference-fixture", "--coach-navigation-start-today", "--diary-history-fixture"])
        show("today", app, opened: app.buttons["logMeal"].waitForExistence(timeout: 20))

        tab("Diary", in: app).tap()
        show("diary", app, opened: app.descendants(matching: .any)["diaryWeekStrip"].waitForExistence(timeout: 10))
        app.buttons["diaryAddMenu"].firstMatch.tap()
        let weight = app.buttons["logWeightForDay"]
        if weight.waitForExistence(timeout: 5) { weight.tap(); show("weightEditor", app, opened: app.buttons["saveWeight"].waitForExistence(timeout: 10)); close(app) }
        else { XCTFail("weightEditor did not open") }
        let meal = app.buttons["historyMeal"].firstMatch
        reveal(meal, in: app)
        if meal.exists { meal.tap(); show("mealDetail", app, opened: app.navigationBars.buttons["BackButton"].waitForExistence(timeout: 10)); close(app) }
        else { XCTFail("mealDetail did not open") }

        tab("Progress", in: app).tap()
        show("progress", app, opened: app.descendants(matching: .any)["progressList"].waitForExistence(timeout: 10))

        tab("Coach", in: app).tap()
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 10)); input.tap()
        input.typeText("Two eggs, three bread slices and salad")
        app.buttons["coachSend"].tap()
        let receipt = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'coachReceipt-'")).firstMatch
        show("coach", app, opened: receipt.waitForExistence(timeout: 30))
        if app.keyboards.firstMatch.exists { receipt.tap() }
        // Narrow bars fold Chat history into the overflow menu.
        let overflow = app.navigationBars.buttons.matching(NSPredicate(format: "identifier == 'OverflowBarButtonItem' OR label BEGINSWITH 'More'")).firstMatch
        if !app.buttons["coachHistory"].exists, overflow.exists { overflow.tap() }
        let history = app.buttons["coachHistory"].exists ? app.buttons["coachHistory"].firstMatch
            : app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Chat history'")).firstMatch
        if history.waitForExistence(timeout: 5) { history.tap() }
        show("coachHistory", app, opened: app.buttons["coachHistoryChooseDate"].waitForExistence(timeout: 10))
        close(app)

        app.buttons["profileSettings"].firstMatch.tap()
        show("settings", app, opened: app.buttons["doneSettings"].waitForExistence(timeout: 10))
        let goals = app.buttons["editGoals"]
        reveal(goals, in: app)
        if goals.exists { goals.tap(); show("goalEditor", app, opened: app.buttons["saveGoals"].waitForExistence(timeout: 10)); close(app) }
        else { XCTFail("goalEditor did not open") }
    }

    func testEveryScreenOpens() {
        var seen: [String] = []
        visitAllScreens { name, _ in seen.append(name) }
        XCTAssertEqual(Set(seen), Self.notYetLocalized.union(seen), "Every screen in the list is visited")
        XCTAssertEqual(seen.count, 12)
    }

    func testPrimaryActionsStayHittable() {
        let actions = ["today": "logMeal", "mealComposer": "sendMeal", "manualNutrition": "saveManualNutrition", "weightEditor": "saveWeight",
                       "diary": "diaryAskPip", "coach": "coachInput", "goalEditor": "saveGoals", "onboarding": "onboardingNext"]
        visitAllScreens { name, app in
            guard let id = actions[name] else { return }
            let action = app.descendants(matching: .any)[id].firstMatch
            reveal(action, in: app)
            XCTAssertTrue(action.exists && action.isHittable, "\(id) must stay reachable on \(name) in \(mode) at \(text) text")
        }
    }

    func testRightToLeftFlagMirrorsTheApp() throws {
        try XCTSkipUnless(mode == "rtl", "Needs TEST_RUNNER_SWEEP_MODE=rtl")
        let app = launch(["--coach-ui-test", "--coach-navigation-start-today"])
        XCTAssertTrue(app.buttons["logMeal"].waitForExistence(timeout: 20))
        XCTAssertGreaterThan(tab("Today", in: app).frame.midX, tab("Coach", in: app).frame.midX, "The first tab sits on the right")
    }

    /// Until a language is complete it is not bundled, so its speakers get the whole app in English.
    func testHebrewPhoneGetsEnglish() throws {
        try XCTSkipUnless(mode == "english", "Runs without the right-to-left or double-length flags")
        let app = launch(["--coach-ui-test", "--coach-navigation-start-today", "--diary-history-fixture"], ["-AppleLanguages", "(he)", "-AppleLocale", "he_IL"])
        XCTAssertTrue(app.buttons["logMeal"].waitForExistence(timeout: 20))
        for name in ["Today", "Diary", "Progress", "Coach"] { XCTAssertTrue(app.tabBars.buttons[name].exists, "\(name) tab is English") }
        XCTAssertLessThan(tab("Today", in: app).frame.midX, tab("Coach", in: app).frame.midX, "English lays out left to right")
        tab("Diary", in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["diaryWeekStrip"].waitForExistence(timeout: 10))
        let months = DateFormatter().then { $0.locale = Locale(identifier: "en_US") }.monthSymbols ?? []
        let texts = app.staticTexts.allElementsBoundByIndex.map { $0.label }
        XCTAssertTrue(texts.contains { text in months.contains { text.contains($0) } }, "The day title uses an English month: \(texts)")
        XCTAssertFalse(texts.contains { $0.unicodeScalars.contains { (0x0590...0x05FF).contains($0.value) } }, "No Hebrew appears: \(texts)")
    }

    func testTextIsLocalized() throws {
        try XCTSkipUnless(mode == "double", "Needs TEST_RUNNER_SWEEP_MODE=double")
        visitAllScreens { name, app in
            guard !Self.notYetLocalized.contains(name) else { return }
            // Lists build rows as they scroll in, so read the whole screen, then put it back.
            func read() -> Set<String> { Set([app.staticTexts, app.buttons, app.navigationBars].flatMap { $0.allElementsBoundByIndex.map { $0.label } }) }
            var labels = read(), swipes = 0
            while swipes < 6 {
                app.swipeUp(); swipes += 1
                let more = read().subtracting(labels)
                if more.isEmpty { break }
                labels.formUnion(more)
            }
            for _ in 0..<swipes { app.swipeDown() }
            let plain = labels.filter { label in
                !Self.fixtureData.contains(label) && !Self.isLocalized(label)
            }
            XCTAssertTrue(plain.isEmpty, "\(name) shows text that is not localized: \(plain.sorted())")
        }
    }

    /// The double-length flag shows every localized string twice, joined by a space; in the first copy each
    /// placeholder is left as a bare "@". A label can also join several strings with commas.
    static func isLocalized(_ label: String) -> Bool {
        if isDoubled(label) { return true }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US")
        let dateWords = Set(formatter.weekdaySymbols + formatter.shortWeekdaySymbols + formatter.monthSymbols + formatter.shortMonthSymbols + ["AM", "PM", "GMT", "UTC"])
        // Typed text can hold commas of its own, so take fixture data out before splitting.
        let label = fixtureData.reduce(label) { $0.replacingOccurrences(of: $1, with: "") }
        return label.components(separatedBy: ", ").allSatisfy { part in
            let part = part.trimmingCharacters(in: .whitespaces)
            if fixtureData.contains(part) || part.hasPrefix("pose:") || !part.contains(where: \.isLetter) || isDoubled(part) { return true }
            return part.split(whereSeparator: \.isWhitespace).allSatisfy { word in
                !word.contains(where: \.isLetter) || dateWords.contains(word.trimmingCharacters(in: .punctuationCharacters))
            }
        }
    }

    static func isDoubled(_ label: String) -> Bool {
        let words = label.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        return (1..<max(words.count, 1)).contains { cut in
            let pattern = NSRegularExpression.escapedPattern(for: words[..<cut].joined(separator: " ")).replacingOccurrences(of: "@", with: ".+?")
            return words[cut...].joined(separator: " ").range(of: "^" + pattern + "$", options: .regularExpression) != nil
        }
    }
}

private extension DateFormatter {
    func then(_ configure: (DateFormatter) -> Void) -> DateFormatter { configure(self); return self }
}
