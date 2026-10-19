import XCTest

/// Real app root, composer, worker, production timeline and SQL-backed diary; synthetic inference only.
@MainActor final class CoachCorrectionUITests: XCTestCase {
    private let phrase = "Please edit yesterday’s lunch because I ate one more chicken."
    private enum FixtureFailure: Error { case observationTimedOut }

    func testYesterdayLunchCorrectionUsesGroundedUnloadedMealExactlyOnce() throws {
        let app = try launch("success")
        let before = try facts(app)
        submit(app)
        let after = try completed(app)
        try assertSaved(after, original: before, quantity: 3, applications: 1)
        try assertGrounded(after)
        let receipt = try receipt(after)
        XCTAssertEqual(receipt["targetLocalDate"] as? String, "2027-01-15")
        XCTAssertEqual(after["captureZone"] as? String, "UTC")
        XCTAssertEqual(number(after, "capturedAt"), 1_800_093_600)
        XCTAssertTrue((after["assistantText"] as? String)?.contains("2027-01-15") == true)
        XCTAssertTrue((after["assistantText"] as? String)?.contains("3 piece") == true)
        try showCommittedReceipt(app)
        evidence(app, "Grounded original-date correction", after)
        try openAndVerifyCommittedMeal(app, receipt: receipt, facts: after)
    }

    func testAmbiguousLunchItemAndServingClarifyWithoutBusinessWrite() throws {
        for ambiguity in ["meal", "item", "quantity", "description", "page", "itemsOmitted"] {
            let app = try launch(ambiguity)
            defer { app.terminate() }
            let before = try facts(app)
            submit(app)
            let after = try wait(app, "focused clarification: " + ambiguity) {
                $0["turnState"] as? String == "completed"
            }
            XCTAssertEqual(number(after, "receiptCount"), 0, ambiguity)
            XCTAssertEqual(number(after, "correctionApplications"), 0, ambiguity)
            XCTAssertEqual((after["audit"] as? [[String]])?.count, 0, ambiguity)
            XCTAssertEqual(after["businessUnchanged"] as? Bool, true, ambiguity)
            XCTAssertEqual(number(after, "quantity"), ambiguity == "quantity" ? 200 : 2, ambiguity)
            XCTAssertEqual(after["unit"] as? String, ambiguity == "quantity" ? "g" : "piece", ambiguity)
            assertIdentity(after, original: before)
            let calls = try XCTUnwrap(after["calls"] as? [[String: String]])
            XCTAssertEqual(calls.first?["name"], "get_meals_for_date", ambiguity)
            XCTAssertEqual(calls.last?["name"], "ask_clarification", ambiguity)
            XCTAssertFalse(calls.contains { ["correct_item", "log_food", "append_food"].contains($0["name"] ?? "") }, ambiguity)
            let expectedKind: String, expectedQuestion: String
            switch ambiguity {
            case "item", "itemsOmitted":
                expectedKind = "food"; expectedQuestion = "Which saved food item should I update?"
            case "quantity":
                expectedKind = "portion"; expectedQuestion = "How much was the additional serving? Give its amount and unit."
            default:
                expectedKind = "meal"; expectedQuestion = "Which meal do you mean?"
            }
            let arguments = try XCTUnwrap(calls.last?["arguments"])
            let clarification = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any])
            XCTAssertEqual(clarification["kind"] as? String, expectedKind, ambiguity)
            XCTAssertEqual(after["assistantText"] as? String, expectedQuestion, ambiguity)
            evidence(app, "No-write ambiguity " + ambiguity, after)
        }
    }

    func testDelayedAcceptedCorrectionRetainsCaptureDateAcrossTravelAndDST() throws {
        let app = try launch("delayed")
        let before = try facts(app)
        submit(app)
        let accepted = try barrier(app, "before-processing")
        XCTAssertEqual(number(accepted, "receiptCount"), 0)
        XCTAssertEqual(number(accepted, "quantity"), 2)
        XCTAssertEqual(accepted["captureZone"] as? String, "America/New_York")
        XCTAssertEqual(number(accepted, "capturedAt"), 1_773_030_600)
        app.buttons["correctionTravel"].tap()
        let traveled = try wait(app, "processing timezone changed") { $0["currentProfileZone"] as? String == "Asia/Tokyo" }
        XCTAssertEqual(traveled["turnID"] as? String, accepted["turnID"] as? String)
        XCTAssertGreaterThan(number(traveled, "processAt") - number(traveled, "capturedAt"), 3 * 86_400)
        // Same accepted input naturally resumes in a fresh process, days later in another zone.
        evidence(app, "Accepted DST capture before termination", traveled)
        app.terminate(); app.launch()
        let after = try completed(app)
        try assertSaved(after, original: before, quantity: 3, applications: 1, date: "2026-03-08")
        XCTAssertEqual(after["turnID"] as? String, accepted["turnID"] as? String)
        XCTAssertEqual(number(after, "sequence"), number(accepted, "sequence"))
        XCTAssertEqual(number(after, "capturedAt"), number(accepted, "capturedAt"))
        XCTAssertEqual(after["captureZone"] as? String, "America/New_York")
        XCTAssertEqual(after["currentProfileZone"] as? String, "Asia/Tokyo")
        try assertGrounded(after, date: "2026-03-08")
        evidence(app, "DST original-date result after travel and process recovery", after)
    }

    func testActualManualEditDuringGroundedInferenceRejectsStaleCorrection() throws {
        let app = try launch("stale")
        let before = try facts(app)
        submit(app)
        let held = try barrier(app, "before-correction")
        try assertGrounded(held)
        XCTAssertEqual(number(held, "quantity"), 2)
        XCTAssertEqual(number(held, "receiptCount"), 0)
        try editChickenToFive(app)
        app.buttons["correctionRelease"].tap()
        let after = try wait(app, "stale correction rejected") { $0["turnState"] as? String == "needsRetry" }
        try assertSaved(after, original: before, quantity: 5, applications: 0, receiptExpected: false)
        XCTAssertEqual(number(after, "manualApplications"), 1)
        XCTAssertEqual((after["audit"] as? [[String]])?.count, 1)
        XCTAssertEqual(after["assistantText"] as? String, "")
        XCTAssertTrue(app.staticTexts["coachError"].waitForExistence(timeout: 5))
        evidence(app, "Actual editor wins over stale grounded correction", after)
    }

    func testCrashAfterActualCommitRecoversSameTurnAndReceiptWithoutSecondIncrement() throws {
        let app = try launch("crash")
        let before = try facts(app)
        submit(app)
        let held = try barrier(app, "after-commit")
        try assertSaved(held, original: before, quantity: 3, applications: 1)
        XCTAssertEqual(held["observedCommitOutput"] as? Bool, true)
        XCTAssertEqual(held["turnState"] as? String, "analyzing")
        XCTAssertEqual(held["assistantText"] as? String, "")
        try assertGrounded(held)
        let originalReceipt = try canonical(receipt(held))
        evidence(app, "Durable commit before actual process termination", held)
        app.terminate(); app.launch()
        let replay = try completed(app)
        try assertSaved(replay, original: before, quantity: 3, applications: 1)
        XCTAssertEqual(replay["turnID"] as? String, held["turnID"] as? String)
        XCTAssertEqual(number(replay, "sequence"), number(held, "sequence"))
        XCTAssertEqual(number(replay, "capturedAt"), number(held, "capturedAt"))
        XCTAssertEqual(try canonical(receipt(replay)), originalReceipt)
        app.terminate(); app.launch()
        let reopened = try completed(app)
        try assertSaved(reopened, original: before, quantity: 3, applications: 1)
        XCTAssertEqual(reopened["turnID"] as? String, held["turnID"] as? String)
        XCTAssertEqual(try canonical(receipt(reopened)), originalReceipt)
        evidence(app, "Same-arguments recovery and second reopen", reopened)
    }

    func testLaterActualManualFiveSurvivesRecoveryOfOriginalThreeReceipt() throws {
        let app = try launch("crash-later-edit")
        let before = try facts(app)
        submit(app)
        let held = try barrier(app, "after-commit")
        try assertSaved(held, original: before, quantity: 3, applications: 1)
        XCTAssertEqual(held["observedCommitOutput"] as? Bool, true)
        let originalReceipt = try canonical(receipt(held))
        try editChickenToFive(app)
        let edited = try wait(app, "later current quantity 5") { self.number($0, "quantity") == 5 }
        XCTAssertEqual(edited["turnState"] as? String, "analyzing")
        XCTAssertEqual(try canonical(receipt(edited)), originalReceipt)
        XCTAssertEqual(number(edited, "manualApplications"), 1)
        app.terminate(); app.launch()
        let replay = try completed(app)
        try assertSaved(replay, original: before, quantity: 5, applications: 1)
        XCTAssertEqual(replay["turnID"] as? String, held["turnID"] as? String)
        XCTAssertEqual(try canonical(receipt(replay)), originalReceipt)
        XCTAssertEqual(number(replay, "manualApplications"), 1)
        XCTAssertEqual((replay["audit"] as? [[String]])?.count, 2)
        XCTAssertTrue((replay["assistantText"] as? String)?.contains("3 piece") == true)
        try showCommittedReceipt(app)
        evidence(app, "Original receipt 3 remains distinct from current manual 5", replay)
    }

    private func launch(_ scenario: String) throws -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture",
            "--coach-history-fixture", "--coach-correction-fixture", "--correction-scenario", scenario, "--proof-english"]
        app.launch()
        let initial = try wait(app, "isolated fixture ready") { $0["auditReady"] as? Bool == true && $0["turnID"] as? String == "" }
        XCTAssertEqual(initial["sourceOutsideLatest"] as? Bool, true)
        XCTAssertLessThanOrEqual(number(initial, "loadedCount"), 100)
        XCTAssertGreaterThan(number(initial, "newerExchangeCount"), 100)
        XCTAssertEqual((initial["audit"] as? [[String]])?.count, 0)
        return app
    }
    private func submit(_ app: XCUIApplication) {
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText(phrase)
        app.buttons["coachSend"].tap()
    }
    private func completed(_ app: XCUIApplication) throws -> [String: Any] {
        try wait(app, "accepted correction completed") { $0["turnState"] as? String == "completed" }
    }
    private func barrier(_ app: XCUIApplication, _ name: String) throws -> [String: Any] {
        try wait(app, "observable inference boundary " + name) { $0["phase"] as? String == name }
    }
    private func facts(_ app: XCUIApplication) throws -> [String: Any] {
        let element = app.staticTexts["correctionFacts"]
        let value = try XCTUnwrap(element.value as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any])
    }
    private func wait(_ app: XCUIApplication, _ description: String, _ predicate: @escaping ([String: Any]) -> Bool) throws -> [String: Any] {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = try? self.facts(app), value["error"] == nil, value["expired"] as? Bool != true else { return false }
            return predicate(value)
        }, object: nil)
        guard XCTWaiter.wait(for: [expectation], timeout: 20) == .completed else {
            // Always drain a suspended transport before reporting failure.
            if app.buttons["correctionRelease"].exists { app.buttons["correctionRelease"].tap() }
            let last = (try? facts(app)) ?? [:]; evidence(app, "Failed boundary " + description, last)
            XCTFail("Timed out: \(description); facts=\(last)"); throw FixtureFailure.observationTimedOut
        }
        return try facts(app)
    }
    private func number(_ facts: [String: Any], _ key: String) -> Double { (facts[key] as? NSNumber)?.doubleValue ?? -.infinity }
    private func receipt(_ facts: [String: Any]) throws -> [String: Any] { try XCTUnwrap(facts["receipt"] as? [String: Any]) }
    private func canonical(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: .sortedKeys) }
    private func assertIdentity(_ facts: [String: Any], original: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        for key in ["mealID", "dayID", "itemID", "sourceTurnID"] { XCTAssertEqual(facts[key] as? String, original[key] as? String, key, file: file, line: line) }
        for key in ["mealIDs", "itemIDs"] { XCTAssertEqual(facts[key] as? [String], original[key] as? [String], key, file: file, line: line) }
    }
    private func assertSaved(_ facts: [String: Any], original: [String: Any], quantity: Double, applications: Int,
                             date: String = "2027-01-15", receiptExpected: Bool = true, file: StaticString = #filePath, line: UInt = #line) throws {
        assertIdentity(facts, original: original, file: file, line: line)
        XCTAssertEqual(number(facts, "quantity"), quantity, file: file, line: line)
        XCTAssertEqual(facts["unit"] as? String, "piece", file: file, line: line)
        XCTAssertEqual(facts["targetDate"] as? String, date, file: file, line: line)
        XCTAssertEqual(facts["unrelatedPreserved"] as? Bool, true, file: file, line: line)
        XCTAssertEqual(number(facts, "correctionApplications"), Double(applications), file: file, line: line)
        XCTAssertEqual(number(facts, "receiptCount"), receiptExpected ? 1 : 0, file: file, line: line)
        XCTAssertEqual((facts["audit"] as? [[String]])?.count, applications + ((facts["manualApplications"] as? NSNumber)?.intValue ?? -1), file: file, line: line)
        if receiptExpected {
            let receipt = try receipt(facts)
            XCTAssertEqual(receipt["mealID"] as? String, facts["mealID"] as? String, file: file, line: line)
            XCTAssertEqual(receipt["itemID"] as? String, facts["itemID"] as? String, file: file, line: line)
            XCTAssertEqual(receipt["dayID"] as? String, facts["dayID"] as? String, file: file, line: line)
            XCTAssertEqual(receipt["turnID"] as? String, facts["turnID"] as? String, file: file, line: line)
            XCTAssertEqual(receipt["targetLocalDate"] as? String, date, file: file, line: line)
            let item = try XCTUnwrap((receipt["items"] as? [[String: Any]])?.first)
            XCTAssertEqual(item["itemID"] as? String, facts["itemID"] as? String, file: file, line: line)
            XCTAssertEqual(number(item, "quantity"), 3, file: file, line: line)
            XCTAssertEqual(item["unit"] as? String, "piece", file: file, line: line)
        }
    }
    private func assertGrounded(_ facts: [String: Any], date: String = "2027-01-15") throws {
        XCTAssertFalse((facts["contextMealIDs"] as? [String] ?? []).contains(facts["mealID"] as? String ?? ""))
        XCTAssertTrue((facts["candidateMealIDs"] as? [String] ?? []).contains(facts["mealID"] as? String ?? ""))
        XCTAssertEqual(facts["groundedMealID"] as? String, facts["mealID"] as? String)
        XCTAssertTrue((facts["groundedItemIDs"] as? [String] ?? []).contains(facts["itemID"] as? String ?? ""))
        XCTAssertEqual(number(facts, "groundedQuantity"), 2)
        let calls = try XCTUnwrap(facts["calls"] as? [[String: String]])
        XCTAssertEqual(calls.compactMap { $0["name"] }, ["get_meals_for_date", "get_meal", "correct_item"])
        func arguments(_ index: Int) throws -> [String: Any] {
            let raw = try XCTUnwrap(calls[index]["arguments"])
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        }
        XCTAssertEqual(try arguments(0)["target_local_date"] as? String, date)
        XCTAssertEqual(try arguments(1)["meal_id"] as? String, facts["mealID"] as? String)
        let correction = try arguments(2)
        XCTAssertEqual(correction["meal_id"] as? String, facts["mealID"] as? String)
        XCTAssertEqual(correction["item_id"] as? String, facts["itemID"] as? String)
        XCTAssertEqual(number(correction, "quantity"), 3)
        XCTAssertEqual(number(correction, "expected_revision"), 1)
    }
    private func editChickenToFive(_ app: XCUIApplication) throws {
        app.buttons["correctionLunch"].tap()
        XCTAssertTrue(app.navigationBars["Meal"].waitForExistence(timeout: 5))
        let chicken = app.buttons.matching(identifier: "editItem").matching(NSPredicate(format: "label CONTAINS %@", "Chicken")).firstMatch
        for _ in 0..<8 where !chicken.isHittable { app.swipeUp() }
        XCTAssertTrue(chicken.isHittable); chicken.tap()
        let field = app.textFields["itemQuantity"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
        field.press(forDuration: 1)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        else { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String ?? "").count)) }
        field.typeText("5")
        app.buttons["saveItem"].tap()
        XCTAssertTrue(app.navigationBars["Meal"].waitForExistence(timeout: 5))
        app.navigationBars["Meal"].buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["correctionFacts"].waitForExistence(timeout: 5))
        app.buttons["correctionRefresh"].tap()
        _ = try wait(app, "actual manual edit committed") { self.number($0, "quantity") == 5 && self.number($0, "manualApplications") == 1 }
    }
    private func showCommittedReceipt(_ app: XCUIApplication) throws {
        if app.buttons["coachNewMessage"].exists { app.buttons["coachNewMessage"].tap() }
        let amount = app.staticTexts.matching(identifier: "coachReceiptQuantity").matching(NSPredicate(format: "label CONTAINS %@", "3 piece")).firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["coachReceiptDate"].firstMatch.label.contains("2027-01-15"))
    }
    private func openAndVerifyCommittedMeal(_ app: XCUIApplication, receipt: [String: Any], facts: [String: Any]) throws {
        let key = try XCTUnwrap(receipt["operationKey"] as? String)
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "coachReceipt-" + key)).firstMatch
        let link = card.buttons.matching(identifier: "coachMealLink").firstMatch
        for _ in 0..<6 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable); link.tap()
        XCTAssertTrue(app.navigationBars["Meal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2027-01-15"].waitForExistence(timeout: 5))
        evidence(app, "Committed meal original date", facts)
        for (name, serving) in [("Chicken", "3 piece"), ("Rice", "1 cup"), ("Salad", "1 bowl")] {
            let row = app.buttons.matching(identifier: "editItem").matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
            for _ in 0..<8 where !row.isHittable { app.swipeUp() }
            XCTAssertTrue(row.isHittable, name)
            XCTAssertTrue(row.label.contains(serving), "\(name) must render \(serving); got \(row.label)")
        }
        evidence(app, "Committed meal chicken three with preserved rice and salad", facts)
    }
    private func evidence(_ app: XCUIApplication, _ name: String, _ facts: [String: Any]) {
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = name; capture.lifetime = .keepAlways; add(capture)
        let data = (try? canonical(facts)) ?? Data()
        let audit = XCTAttachment(string: String(decoding: data, as: UTF8.self) + "\n" + app.debugDescription)
        audit.name = name + " stored facts and accessibility"; audit.lifetime = .keepAlways; add(audit)
    }
}
