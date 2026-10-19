import XCTest

/// Public XCTest currently proves real VoiceOver reachability, not named custom-action invocation.
@MainActor final class CoachAccessiblePagingUITests: CoachHistoryTestSupport {
    func testVoiceOverReachesHistoryPagingControlAndPreservesFocusedReaderAndDraft() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("VoiceOver traversal requires iOS 27") }
        let app = launchHistory()
        let draft = "Synthetic unsent accessible paging draft"
        enter(draft, app: app)
        let history = app.buttons["coachHistory"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        XCTAssertEqual(history.label, "Chat history")
        let service = XCUIDevice.shared.voiceOverService
        let wasEnabled = service.isEnabled
        if !wasEnabled { try service.enable() }
        defer {
            if !wasEnabled {
                do { try service.disable() }
                catch { XCTFail("Could not restore disabled VoiceOver state: \(error)") }
            }
        }
        var utterances: [String] = []
        func isHistory(_ speech: String) -> Bool {
            speech.contains(history.label) && speech.lowercased().contains("button")
        }
        let initial: XCUIVoiceOverService.Output? = try? service.currentSpeech()
        var reached = isHistory(initial?.utterance ?? "")
        for _ in 0..<80 where !reached {
            let output: XCUIVoiceOverService.Output? = try service.moveBackward()
            let speech = output?.utterance ?? ""
            utterances.append(speech)
            reached = isHistory(speech)
        }
        let traversal = XCTAttachment(string: utterances.joined(separator: "\n"))
        traversal.name = "Actual VoiceOver traversal to Chat history"; traversal.lifetime = .keepAlways; add(traversal)
        XCTAssertTrue(reached, "VoiceOver must reach the existing actual Chat history button without tapping it")
        guard reached else { return }
        let before = try waitHistory(app)
        let nativeBefore = try XCTUnwrap(before["nativeTable"] as? [String: Any])
        let visibleBefore = try XCTUnwrap(before["visibleIDs"] as? [String])
        XCTAssertFalse(visibleBefore.isEmpty)
        let focused: XCUIVoiceOverService.Output? = try service.currentSpeech()
        XCTAssertTrue(isHistory(focused?.utterance ?? ""), "The actual toolbar control must remain VoiceOver focused")
        let after = try waitHistory(app)
        let nativeAfter = try XCTUnwrap(after["nativeTable"] as? [String: Any])
        XCTAssertEqual(after["requestedPages"] as? [[Int]], before["requestedPages"] as? [[Int]],
            "Merely focusing the action host must not execute an edge action")
        XCTAssertEqual((after["visibleIDs"] as? [String])?.first, visibleBefore.first)
        XCTAssertEqual(try number(nativeAfter, "contentOffsetY"), try number(nativeBefore, "contentOffsetY"), accuracy: 2)
        XCTAssertEqual(nativeAfter["followsLatest"] as? Bool, nativeBefore["followsLatest"] as? Bool)
        XCTAssertLessThanOrEqual(try number(after, "residentCount") + number(after, "reservedCapacity"), 100)
        XCTAssertLessThanOrEqual(try number(after, "peakCapacity"), 100)
        XCTAssertEqual(app.textFields["coachInput"].value as? String, draft)
        XCTAssertFalse(app.navigationBars["Chat history"].exists, "Focus traversal must preserve the toolbar button's unactivated normal action")
    }
}
