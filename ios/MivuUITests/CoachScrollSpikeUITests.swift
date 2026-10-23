import XCTest

/// Retained feasibility regressions now run the shipping timeline and real isolated database.
@MainActor final class CoachScrollSpikeUITests: CoachHistoryTestSupport {
    func testSpikePrependPreservesStationaryAnchorWithinTwoPoints() throws {
        var app = launchHistory(extra: ["--history-uncompensated"])
        app.buttons["historyMeasureStart"].tap(); _ = try waitHistory(app); try partialRow(app)
        app.buttons["historyMeasureEarlier"].tap()
        let negative = try waitHistory(app, complete: true)
        let negativeDrift = try number(negative, "maxDrift")
        XCTAssertTrue((negative["everLost"] as? Bool == true) || negativeDrift > 2, "The same actual-cell measurement must reject an uncompensated insertion")
        app.terminate(); app = launchHistory()
        app.buttons["historyMeasureStart"].tap(); _ = try waitHistory(app); try partialRow(app)
        app.buttons["historyMeasureEarlier"].tap(); try preserved(waitHistory(app, complete: true))
    }
    func testSpikeBidirectionalEvictionAndBackgroundReplyPreserveReader() throws {
        let app = launchHistory()
        let appBounds = app.windows.firstMatch.frame
        guard !appBounds.isEmpty, appBounds.width > 100, appBounds.height > 100 else {
            XCTFail("The launched native window must provide valid screen bounds: \(appBounds)"); return
        }
        for _ in 0..<6 {
            app.buttons["historyMeasureStart"].tap(); _ = try waitHistory(app); try partialRow(app)
            app.buttons["historyMeasureEarlier"].tap(); try preserved(waitHistory(app, complete: true))
        }
        let earlier = try metrics(app)
        XCTAssertEqual(Set((earlier["requestedPages"] as? [[Int]] ?? []).flatMap { $0 }), Set(1...140))
        XCTAssertEqual((earlier["residentIDs"] as? [String])?.count, 100)
        for _ in 0..<2 {
            app.buttons["historyMeasureEnd"].tap(); _ = try waitHistory(app)
            app.buttons["historyMeasureLater"].tap(); try preserved(waitHistory(app, complete: true))
        }
        let ranges = try XCTUnwrap(try metrics(app)["requestedPages"] as? [[Int]])
        XCTAssertEqual(ranges.filter { $0 == Array(121...140) }.count, 2)
        let anchorID = try XCTUnwrap(try metrics(app)["anchorID"] as? String)
        let message = "Synthetic delayed weekly report"
        enter(message, app: app)
        guard sendAfterKeyboardSettles(app, text: message, appBounds: appBounds) else { return }
        XCTAssertTrue(app.buttons["Jump to latest"].waitForExistence(timeout: 10))
        let facts = try waitForReply(app, text: "Synthetic delayed weekly report")
        let completed = try waitHistory(app, complete: true)
        XCTAssertEqual(completed["anchorID"] as? String, anchorID)
        XCTAssertEqual(completed["completedReplyID"] as? String, facts["latestTurnID"] as? String)
        try preserved(completed)
    }
    private func sendAfterKeyboardSettles(_ app: XCUIApplication, text: String, appBounds: CGRect) -> Bool {
        let input = app.textFields["coachInput"], send = app.buttons["coachSend"], keyboard = app.keyboards.firstMatch
        var previous: [CGRect] = [], stableSamples = 0, samples = 0
        var stage = "not sampled", flags = "", geometry = "", stability = ""
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            samples += 1
            let inputExists = input.exists, sendExists = send.exists, keyboardExists = keyboard.exists
            let value = inputExists ? input.value as? String : nil
            let inputHittable = inputExists && input.isHittable
            let sendEnabled = sendExists && send.isEnabled, sendHittable = sendExists && send.isHittable
            flags = "inputExists=\(inputExists) value=\(String(describing: value)) exactText=\(value == text) inputHittable=\(inputHittable) sendExists=\(sendExists) sendEnabled=\(sendEnabled) sendHittable=\(sendHittable) keyboardExists=\(keyboardExists)"
            guard inputExists, value == text, inputHittable, sendExists, sendEnabled, sendHittable, keyboardExists else {
                stage = "controls"; previous = []; stableSamples = 0; return false
            }
            let frames = [keyboard.frame, input.frame, send.frame]
            let visibleKeyboard = frames[0].intersection(appBounds)
            geometry = "bounds=\(appBounds) keyboard=\(frames[0]) visibleKeyboard=\(visibleKeyboard) input=\(frames[1]) send=\(frames[2])"
            guard frames[0].height > 100, visibleKeyboard.height > 100,
                  frames[1].maxY <= frames[0].minY + 2, frames[2].maxY <= frames[0].minY + 2 else {
                stage = "geometry"; previous = []; stableSamples = 0; return false
            }
            let unchanged = previous.count == frames.count && zip(previous, frames).allSatisfy { before, after in
                abs(before.minX - after.minX) <= 0.5 && abs(before.minY - after.minY) <= 0.5 &&
                abs(before.width - after.width) <= 0.5 && abs(before.height - after.height) <= 0.5
            }
            stability = "previous=\(previous) unchanged=\(unchanged) priorStableSamples=\(stableSamples)"
            stableSamples = unchanged ? stableSamples + 1 : 1
            previous = frames; stage = "stability"
            return stableSamples >= 3
        }, object: nil)
        // Stress-fixture AX samples take several seconds; wait for geometry, never a fixed delay.
        let result = XCTWaiter.wait(for: [ready], timeout: 30)
        let proofText = "stage=\(stage) samples=\(samples) stableSamples=\(stableSamples) \(flags) \(geometry) \(stability)"
        XCTAssertEqual(result, .completed, "Send requires the exact draft and a settled on-screen keyboard/composer: " + proofText)
        guard result == .completed else {
            let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = "Unsettled Send geometry"; proof.lifetime = .keepAlways; add(proof)
            return false
        }
        print("COACH_SEND_READY " + proofText)
        send.tap()
        return true
    }
    func testSpikeDynamicTypePreservesSemanticPosition() throws {
        let app = launchHistory()
        // The fixture's empty latest day shows the morning check-in over the timeline; at large text it covers the row's link.
        let checkIn = app.buttons["morningDismiss"]
        if checkIn.waitForExistence(timeout: 3) { checkIn.tap() }
        selectHistoryTurn(80, app: app)
        _ = try waitHistory(app)
        let semanticID = "00000000-0000-0000-0000-000000000080"
        for _ in 0..<2 {
            app.buttons["historyMeasureType"].tap()
            let value = try waitHistory(app, complete: true)
            let id = try XCTUnwrap(value["anchorID"] as? String)
            XCTAssertEqual(id, semanticID)
            XCTAssertTrue((value["visibleIDs"] as? [String] ?? []).contains(id))
            XCTAssertFalse(app.staticTexts["coachText-" + id].label.isEmpty)
            let exchange = app.descendants(matching: .any)["coachExchange-" + semanticID].firstMatch
            let review = exchange.buttons["coachMealLink"].firstMatch
            reveal(review, app: app); review.tap()
            XCTAssertTrue(app.navigationBars["Meal"].waitForExistence(timeout: 5), "The same semantic row's native action must open its actual record")
            XCTAssertTrue(app.buttons["mealSourceChat"].waitForExistence(timeout: 5))
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.tables["coachViewport"].waitForExistence(timeout: 5))
            _ = try waitHistory(app)
            app.buttons["historyMeasureEarlier"].tap(); try preserved(waitHistory(app, complete: true))
        }
    }
    func testSpikePagingPreservesAccessibilityFocus() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Actual VoiceOver automation requires iOS 27") }
        let app = launchHistory()
        for _ in 0..<4 {
            app.buttons["historyMeasureStart"].tap(); _ = try waitHistory(app); try partialRow(app)
            app.buttons["historyMeasureEarlier"].tap(); try preserved(waitHistory(app, complete: true))
        }
        app.buttons["historyMeasureStart"].tap(); _ = try waitHistory(app); try partialRow(app)
        app.buttons["historyMeasureFocus"].tap()
        let service = XCUIDevice.shared.voiceOverService, wasEnabled = service.isEnabled
        if !wasEnabled { try service.enable() }
        defer { if !wasEnabled { try? service.disable() } }
        for _ in 0..<80 {
            if !(try metrics(app)["baselineFocusedID"] as? String ?? "").isEmpty { break }
            _ = try service.moveForward()
        }
        let result = try waitHistory(app, complete: true)
        XCTAssertFalse((result["baselineFocusedID"] as? String ?? "").isEmpty)
        XCTAssertGreaterThanOrEqual(result["committedFocusQueries"] as? Int ?? 0, 3)
        XCTAssertEqual(result["baselineFocusedID"] as? String, result["focusedID"] as? String)
        XCTAssertFalse(result["focusLost"] as? Bool ?? true)
        XCTAssertTrue(result["focusEvictedLatest"] as? Bool == true)
        XCTAssertTrue(result["focusRefetchedLatest"] as? Bool == true)
        XCTAssertTrue(result["focusReplyCommitted"] as? Bool == true)
        XCTAssertEqual(result["focusStage"] as? Int, 4)
        let pages = try XCTUnwrap(result["requestedPages"] as? [[Int]])
        XCTAssertEqual(pages.filter { $0 == Array(121...140) }.count, 2)
        try preserved(result)
    }
}
