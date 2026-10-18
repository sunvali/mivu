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
        enter("Synthetic delayed weekly report", app: app); app.buttons["coachSend"].tap()
        XCTAssertTrue(app.buttons["Jump to latest"].waitForExistence(timeout: 10))
        let facts = try waitForReply(app, text: "Synthetic delayed weekly report")
        let completed = try waitHistory(app, complete: true)
        XCTAssertEqual(completed["anchorID"] as? String, anchorID)
        XCTAssertEqual(completed["completedReplyID"] as? String, facts["latestTurnID"] as? String)
        try preserved(completed)
    }
    func testSpikeDynamicTypePreservesSemanticPosition() throws {
        let app = launchHistory()
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
