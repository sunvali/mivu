import XCTest

@MainActor class CoachHistoryTestSupport: XCTestCase {
    func launchHistory(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-ui-test", "--coach-inference-fixture", "--coach-history-fixture", "--proof-english"] + extra
        app.launch(); XCTAssertTrue(app.tables["coachViewport"].waitForExistence(timeout: 15))
        _ = try? waitHistory(app); return app
    }
    func metrics(_ app: XCUIApplication) throws -> [String: Any] {
        let data = try XCTUnwrap((app.staticTexts["historyMetrics"].value as? String)?.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    func waitHistory(_ app: XCUIApplication, complete: Bool = false) throws -> [String: Any] {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = try? self.metrics(app), value["scrollIdle"] as? Bool == true,
                  (value["stableFrames"] as? Int ?? 0) >= 3 else { return false }
            return complete ? value["phase"] as? String == "complete" : ["ready", "complete"].contains(value["phase"] as? String ?? "")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
        return try metrics(app)
    }
    func viewport(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["coachViewport"].firstMatch }
    func partialRow(_ app: XCUIApplication) throws {
        var value = try waitHistory(app)
        for _ in 0..<6 where (value["firstVisibleOffset"] as? Double ?? 0) >= -4 || remainder(value) < 44 {
            let point = viewport(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            point.press(forDuration: 0.05, thenDragTo: point.withOffset(CGVector(dx: 0, dy: -43)))
            value = try waitHistory(app)
        }
        XCTAssertLessThan(try number(value, "firstVisibleOffset"), 0)
        XCTAssertGreaterThanOrEqual(remainder(value), 44)
    }
    private func remainder(_ value: [String: Any]) -> Double { (value["firstVisibleOffset"] as? Double ?? 0) + ((value["visibleRowHeights"] as? [Double])?.first ?? 0) }
    func number(_ value: [String: Any], _ key: String) throws -> Double { try XCTUnwrap((value[key] as? NSNumber)?.doubleValue, key) }
    func preserved(_ value: [String: Any]) throws {
        let beforeAnchorY = try number(value, "before"), afterAnchorY = try number(value, "after")
        XCTAssertLessThanOrEqual(abs(afterAnchorY - beforeAnchorY), 2)
        XCTAssertLessThanOrEqual(try number(value, "maxDrift"), 2)
        XCTAssertFalse(value["everLost"] as? Bool ?? true)
        XCTAssertLessThanOrEqual(try number(value, "residentCount") + number(value, "reservedCapacity"), 100)
        XCTAssertLessThanOrEqual(try number(value, "peakCapacity"), 100)
        let attachment = XCTAttachment(string: String(describing: value)); attachment.name = "Production retained-cell geometry"; attachment.lifetime = .keepAlways; add(attachment)
        print("COACH_PRODUCTION_GEOMETRY " + String(describing: value))
    }
    func enter(_ text: String, app: XCUIApplication) {
        let input = app.textFields["coachInput"]; input.tap(); input.typeText(text)
    }
    func waitForReply(_ app: XCUIApplication, text: String) throws -> [String: Any] {
        let condition = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let facts = try? self.fixtureFacts(app), facts["latestText"] as? String == text,
                  facts["latestState"] as? String == "completed", !(facts["latestReply"] as? String ?? "").isEmpty else { return false }
            return true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 40), .completed)
        return try fixtureFacts(app)
    }
    func fixtureFacts(_ app: XCUIApplication) throws -> [String: Any] {
        let data = try XCTUnwrap((app.staticTexts["historyFixtureFacts"].value as? String)?.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<14 where !element.isHittable {
            let surface = viewport(app), frame = surface.frame
            let down = element.exists && !element.frame.isEmpty && element.frame.minY < frame.minY
            let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let step = min(80, frame.height * 0.25) * (down ? 1.0 : -1.0)
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: step)),
                withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        if !element.isHittable { printRouteDiagnostics(app, target: element) }
        XCTAssertTrue(element.isHittable)
    }
    func printRouteDiagnostics(_ app: XCUIApplication, target: XCUIElement? = nil) {
        let native = app.staticTexts["historyMetrics"].value as? String ?? ""
        print("COACH_ROUTE_DIAGNOSTICS " + native)
        if let target {
            print("COACH_ROUTE_AX identifier=\(target.identifier) frame=\(target.frame) hittable=\(target.isHittable) value=\(String(describing: target.value))")
        }
    }
    func assertIdleViewportStopsPublishing(_ app: XCUIApplication) throws {
        let baseline = try waitHistory(app)
        let samples = try number(baseline, "committedSamples"), publications = try number(baseline, "viewportPublications")
        // Observe real committed native updates; no sleep or requested-offset substitution.
        let observed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = try? self.metrics(app), let count = value["committedSamples"] as? Double else { return false }
            return count >= samples + 12
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [observed], timeout: 5), .completed)
        let settled = try metrics(app)
        XCTAssertEqual(try number(settled, "viewportPublications"), publications,
            "An idle production table must stop publishing identical viewport state")
    }
    func openChatHistory(_ app: XCUIApplication) {
        if !app.buttons["coachHistory"].exists, app.buttons["OverflowBarButtonItem"].exists { app.buttons["OverflowBarButtonItem"].tap() }
        let action = app.buttons["coachHistory"].exists ? app.buttons["coachHistory"] : app.buttons["Chat history"]
        XCTAssertTrue(action.waitForExistence(timeout: 5)); action.tap()
    }
    func selectHistoryTurn(_ number: Int, app: XCUIApplication) {
        openChatHistory(app)
        XCTAssertTrue(app.navigationBars["Chat history"].waitForExistence(timeout: 5))
        let initial = app.buttons["coachHistorySegment-00000000-0000-0000-0000-000000001140"]
        XCTAssertTrue(initial.waitForExistence(timeout: 5))
        guard (1...140).contains(number),
              let list = app.collectionViews.allElementsBoundByIndex.first(where: { $0.isHittable })
                ?? app.tables.allElementsBoundByIndex.first(where: { $0.identifier != "coachViewport" && $0.isHittable }) else {
            XCTFail("The presented history list must be active"); return
        }
        func visibleSegments() -> [Int] {
            list.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coachHistorySegment-"))
                .allElementsBoundByIndex.filter { $0.isHittable }.compactMap { Int($0.identifier.suffix(12)).map { $0 - 1000 } }
        }
        // This fixture has140 distinct segments; the real bounded history query replaces each30-row page.
        // Offscreen AX nonexistence is not evidence that the target is outside the current page.
        for page in 0..<((140 - number) / 30) {
            let earlier = list.buttons["coachHistoryEarlier"]
            for _ in 0..<12 where !earlier.isHittable { list.swipeUp() }
            guard earlier.isHittable else { XCTFail("The next real history page action is unavailable"); return }
            earlier.tap()
            let upper = 140 - (page + 1) * 30, lower = max(1, upper - 29)
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let visible = visibleSegments()
                return !visible.isEmpty && visible.allSatisfy { (lower...upper).contains($0) }
            }, object: nil)
            let result = XCTWaiter.wait(for: [changed], timeout: 5)
            XCTAssertEqual(result, .completed)
            guard result == .completed else { return }
        }
        let id = String(format: "00000000-0000-0000-0000-%012d", 1000 + number)
        let row = list.buttons["coachHistorySegment-" + id]
        for _ in 0..<12 where !row.isHittable {
            let above = row.exists && !row.frame.isEmpty && row.frame.minY < list.frame.minY
            if above || number > (visibleSegments().max() ?? number) { list.swipeDown() }
            else { list.swipeUp() }
        }
        guard row.isHittable else { XCTFail("The exact loaded history segment must be visible"); return }
        row.tap()
        XCTAssertTrue(app.tables["coachViewport"].waitForExistence(timeout: 10))
    }

}

@MainActor final class CoachHistoryUITests: CoachHistoryTestSupport {
    func testPrependAndThumbnailArrivalPreserveMeasuredOffset() throws {
        let app = launchHistory(extra: ["--history-hold-photos"])
        app.buttons["historyMeasureStart"].tap(); _ = try waitHistory(app); try partialRow(app)
        app.buttons["historyMeasureEarlier"].tap(); try preserved(waitHistory(app, complete: true))
        app.buttons["historyMeasurePhotoRow"].tap(); _ = try waitHistory(app); try partialRow(app)
        app.buttons["historyMeasurePhoto"].tap()
        let started = try metrics(app), photoID = try XCTUnwrap(started["photoTargetID"] as? String)
        XCTAssertFalse(photoID.isEmpty)
        let loaded = app.descendants(matching: .any)["coachPhoto-" + photoID].firstMatch
        let published = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Photo loaded"), object: loaded)
        XCTAssertEqual(XCTWaiter.wait(for: [published], timeout: 10), .completed)
        let completed = try waitHistory(app, complete: true)
        XCTAssertEqual(completed["photoTargetID"] as? String, photoID)
        XCTAssertTrue(completed["photoPublished"] as? Bool == true)
        try preserved(completed)
    }
    func testHistorySendKeepsViewportAndUsesCurrentDay() throws {
        let app = launchHistory()
        app.buttons["historyMeasureStart"].tap(); _ = try waitHistory(app); try partialRow(app)
        app.buttons["historyMeasureEarlier"].tap(); _ = try waitHistory(app, complete: true)
        let baseline = try metrics(app), anchorID = try XCTUnwrap(baseline["anchorID"] as? String)
        enter("Synthetic delayed weekly report", app: app); app.buttons["coachSend"].tap()
        XCTAssertTrue(app.buttons["Jump to latest"].waitForExistence(timeout: 10))
        let facts = try waitForReply(app, text: "Synthetic delayed weekly report")
        let acceptedID = try XCTUnwrap(facts["latestTurnID"] as? String)
        XCTAssertEqual(facts["trackingDayID"] as? String, "00000000-0000-0000-0000-000000000904")
        XCTAssertEqual(facts["capturedAt"] as? Double, ISO8601DateFormatter().date(from: "2027-01-16T10:00:00Z")!.timeIntervalSince1970)
        let completed = try waitHistory(app, complete: true)
        XCTAssertEqual(completed["anchorID"] as? String, anchorID)
        XCTAssertEqual(completed["replyTargetID"] as? String, acceptedID)
        XCTAssertEqual(completed["completedReplyID"] as? String, acceptedID)
        XCTAssertTrue(app.buttons["Jump to latest"].exists)
        try preserved(completed)
    }
    func testRealScrollAutomaticallyPagesAndStopsAtExhaustion() throws {
        let app = launchHistory(extra: ["--history-short-paging"])
        let initial = try metrics(app)
        XCTAssertEqual((initial["requestedPages"] as? [[Int]])?.count, 1)
        XCTAssertFalse(app.buttons["coachEarlierMessages"].exists)
        XCTAssertFalse(app.buttons["coachLaterMessages"].exists)
        for _ in 0..<12 {
            if Set((try metrics(app)["requestedPages"] as? [[Int]] ?? []).flatMap { $0 }) == Set(1...43) { break }
            viewport(app).swipeDown()
            _ = try waitHistory(app)
        }
        let exhausted = try metrics(app)
        let pages = try XCTUnwrap(exhausted["requestedPages"] as? [[Int]])
        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(Set(pages.flatMap { $0 }), Set(1...43))
        XCTAssertEqual(Set(pages.map { $0.map(String.init).joined(separator: ",") }).count, pages.count)
        XCTAssertFalse(app.buttons["coachEarlierMessages"].exists)
        XCTAssertLessThanOrEqual(try number(exhausted, "residentCount") + number(exhausted, "reservedCapacity"), 100)
        viewport(app).swipeDown(); viewport(app).swipeDown()
        _ = try waitHistory(app)
        XCTAssertEqual(try metrics(app)["requestedPages"] as? [[Int]], pages)
        let newest = app.staticTexts["coachText-00000000-0000-0000-0000-000000000043"]
        for _ in 0..<16 where !newest.isHittable {
            viewport(app).swipeUp()
            _ = try waitHistory(app)
        }
        XCTAssertTrue(newest.isHittable, "A real reverse gesture must return through the loaded conversation")
        XCTAssertEqual(try metrics(app)["requestedPages"] as? [[Int]], pages)
        XCTAssertFalse(app.buttons["coachLaterMessages"].exists)
    }
    func testEqualResidentPageJumpAndSeekApplyRestoration() throws {
        let previousFailurePolicy = continueAfterFailure
        continueAfterFailure = false
        defer { continueAfterFailure = previousFailurePolicy }
        let app = launchHistory()
        try assertIdleViewportStopsPublishing(app)
        app.buttons["historyMeasureStart"].tap(); _ = try waitHistory(app); try partialRow(app)
        app.buttons["Jump to latest"].tap()
        let latest = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = try? self.metrics(app), let bottom = value["lastRowBottom"] as? Double,
                  let height = value["viewportHeight"] as? Double else { return false }
            return abs(bottom - height) <= 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [latest], timeout: 10), .completed)
        try assertIdleViewportStopsPublishing(app)
        let residentIDs = try XCTUnwrap(try metrics(app)["residentIDs"] as? [String])
        for _ in 0..<2 {
            // This exact seek returns the same 121...140 page, with measured trailing content.
            selectHistoryTurn(130, app: app)
            let targeted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let value = try? self.metrics(app), let offsets = value["rowOffsets"] as? [String: Double],
                      let offset = offsets["00000000-0000-0000-0000-000000000130"] else { return false }
                return abs(offset) <= 2
            }, object: nil)
            let targetResult = XCTWaiter.wait(for: [targeted], timeout: 10)
            printRouteDiagnostics(app, target: app.descendants(matching: .any)["coachExchange-00000000-0000-0000-0000-000000000130"].firstMatch)
            XCTAssertEqual(targetResult, .completed)
            XCTAssertEqual(try metrics(app)["residentIDs"] as? [String], residentIDs)
            let selected = app.descendants(matching: .any)["coachExchange-00000000-0000-0000-0000-000000000130"].firstMatch
            XCTAssertTrue(selected.isHittable)
            XCTAssertEqual(selected.value as? String, "Selected source message")
            try assertIdleViewportStopsPublishing(app)
            let point = viewport(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            point.press(forDuration: 0.05, thenDragTo: point.withOffset(CGVector(dx: 0, dy: -43)))
            _ = try waitHistory(app)
        }
    }
    func testReceiptShowsCommittedDateAndUnknownEstimates() throws {
        let previousFailurePolicy = continueAfterFailure
        continueAfterFailure = false
        defer { continueAfterFailure = previousFailurePolicy }
        let app = launchHistory()
        app.tabBars.buttons["Diary"].tap()
        XCTAssertTrue(app.selectDiaryDate("2027-01-15"))
        let meal = app.buttons.matching(identifier: "historyMeal").firstMatch
        for _ in 0..<8 where !meal.isHittable { app.swipeUp() }
        XCTAssertTrue(meal.isHittable); meal.tap()
        XCTAssertTrue(app.buttons["mealSourceChat"].waitForExistence(timeout: 5))
        app.buttons["mealSourceChat"].tap()
        let date = app.staticTexts["coachReceiptDate"]
        XCTAssertTrue(date.waitForExistence(timeout: 10)); XCTAssertTrue(date.label.contains("2027-01-15"))
        let details = app.descendants(matching: .any)["coachReceiptDetails"].firstMatch
        reveal(details, app: app); details.tap()
        let unknown = app.staticTexts["coachReceiptUnknown"].firstMatch
        reveal(unknown, app: app)
        let unknownNutritionWasRenderedAsZero = unknown.label == "0"
        XCTAssertFalse(unknownNutritionWasRenderedAsZero)
        XCTAssertTrue(unknown.label.contains("unknown"))
        XCTAssertTrue(app.staticTexts["Estimated nutrition"].exists)
        let receipt = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@",
            "coachReceipt-00000000-0000-0000-0000-000000000001/food/2027-01-15")).firstMatch
        let review = receipt.buttons["coachMealLink"]
        let jump = app.buttons["coachNewMessage"]
        printRouteDiagnostics(app)
        print("COACH_JUMP_AX exists=\(jump.exists)")
        print("COACH_JUMP_AX_CANDIDATES " + app.descendants(matching: .any).matching(NSPredicate(format:
            "identifier == %@ OR identifier == %@ OR label == %@", "coachNewMessage", "coachJumpHost", "Jump to latest")).debugDescription)
        XCTAssertTrue(jump.isHittable)
        XCTAssertGreaterThanOrEqual(jump.frame.height, 44)
        XCTAssertEqual(jump.frame.width, jump.frame.height, accuracy: 1)
        XCTAssertLessThanOrEqual(jump.frame.width, 49)
        XCTAssertEqual(jump.label, "Jump to latest")
        let beforePan = try metrics(app), beforeNative = try XCTUnwrap(beforePan["nativeTable"] as? [String: Any])
        let beforeCounts = try XCTUnwrap(beforePan["pan"] as? [String: Any])
        let beforeOffset = try number(beforeNative, "contentOffsetY"), beforeBegins = try number(beforeCounts, "begins")
        // Start on the actual floating button. The table must own this ordinary native pan.
        let start = jump.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -80)),
            withVelocity: .slow, thenHoldForDuration: 0.2)
        let afterPan = try waitHistory(app), afterNative = try XCTUnwrap(afterPan["nativeTable"] as? [String: Any])
        let afterCounts = try XCTUnwrap(afterPan["pan"] as? [String: Any])
        XCTAssertGreaterThan(try number(afterCounts, "begins"), beforeBegins)
        XCTAssertGreaterThan(try number(afterNative, "contentOffsetY"), beforeOffset + 0.5)
        XCTAssertEqual(afterPan["residentIDs"] as? [String], beforePan["residentIDs"] as? [String])
        XCTAssertEqual(afterPan["requestedPages"] as? [[Int]], beforePan["requestedPages"] as? [[Int]])
        XCTAssertEqual(afterNative["followsLatest"] as? Bool, false)
        reveal(review, app: app); review.tap()
        XCTAssertTrue(app.navigationBars["Meal"].waitForExistence(timeout: 5))
        app.navigationBars["Meal"].buttons.firstMatch.tap()
        XCTAssertTrue(jump.waitForExistence(timeout: 5)); XCTAssertTrue(jump.isHittable); jump.tap()
        let latest = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = try? self.metrics(app), let native = value["nativeTable"] as? [String: Any],
                  native["followsLatest"] as? Bool == true, let bottom = value["lastRowBottom"] as? Double,
                  let height = value["viewportHeight"] as? Double else { return false }
            return abs(bottom - height) <= 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [latest], timeout: 10), .completed)
        XCTAssertTrue(app.staticTexts["coachText-00000000-0000-0000-0000-000000000140"].exists)
    }
    func testCameraDraftDoesNotAutoSubmit() throws {
        let app = launchHistory()
        enter("Synthetic camera draft", app: app)
        app.buttons["coachPhotos"].tap()
        XCTAssertTrue(app.buttons["coachCameraLibrary"].waitForExistence(timeout: 5))
        app.buttons["syntheticPhoto"].tap()
        XCTAssertTrue(app.buttons["coachSend"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["coachInput"].value as? String, "Synthetic camera draft")
        XCTAssertFalse(app.staticTexts["Synthetic camera draft"].exists)
        XCTAssertTrue(app.buttons["Remove photo 1"].exists)
    }
    func testYesterdayLunchCorrectionShowsCommittedTotalAndTargetDate() throws {
        let app = launchHistory()
        let before = try fixtureFacts(app)
        let sourceTurnIDBeforeCorrection = try XCTUnwrap(before["sourceTurnID"] as? String)
        let mealIDsBeforeCorrection = try XCTUnwrap(before["mealIDs"] as? [String])
        enter("Please edit yesterday’s lunch because I ate one more chicken.", app: app)
        app.buttons["coachSend"].tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (try? self.fixtureFacts(app)["receiptQuantity"] as? Double) == 3
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 20), .completed)
        let after = try fixtureFacts(app)
        let sourceTurnIDAfterCorrection = try XCTUnwrap(after["sourceTurnID"] as? String)
        let mealIDsAfterCorrection = try XCTUnwrap(after["mealIDs"] as? [String])
        XCTAssertEqual(sourceTurnIDAfterCorrection, sourceTurnIDBeforeCorrection)
        XCTAssertEqual(mealIDsAfterCorrection, mealIDsBeforeCorrection)
        XCTAssertEqual(after["chickenQuantity"] as? Double, 3)
        XCTAssertEqual(after["receiptDate"] as? String, "2027-01-15")
        if app.buttons["Jump to latest"].exists { app.buttons["Jump to latest"].tap() }
        let quantity = app.staticTexts.matching(identifier: "coachReceiptQuantity").matching(NSPredicate(format: "label CONTAINS %@", "3 piece")).firstMatch
        XCTAssertTrue(quantity.waitForExistence(timeout: 10))
        let committedReceiptShowsThreePiecesAndCapturedYesterday = quantity.exists && app.staticTexts["coachReceiptDate"].label.contains("2027-01-15")
        XCTAssertTrue(committedReceiptShowsThreePiecesAndCapturedYesterday)
        let details = app.descendants(matching: .any)["coachReceiptDetails"].firstMatch
        reveal(details, app: app); details.tap()
        let unknown = app.staticTexts["coachReceiptUnknown"].firstMatch
        reveal(unknown, app: app)
        let unknownNutritionWasRenderedAsZero = unknown.label == "0"
        XCTAssertFalse(unknownNutritionWasRenderedAsZero)
        XCTAssertTrue(unknown.label.contains("unknown"))
        let review = app.buttons["coachMealLink"].firstMatch
        reveal(review, app: app); review.tap()
        XCTAssertTrue(app.navigationBars["Meal"].waitForExistence(timeout: 5))
    }

}
