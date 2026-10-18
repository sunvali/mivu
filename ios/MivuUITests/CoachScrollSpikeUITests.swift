import XCTest

@MainActor final class CoachScrollSpikeUITests: XCTestCase {
    func testSpikePrependPreservesStationaryAnchorWithinTwoPoints() throws {
        // A real uncompensated native insertion calibrates the same measurement.
        var app = launch(extra: ["--spike-uncompensated"])
        try partialRow(app)
        let negative = try page(app, direction: "spikeArmPrepend")
        if negative["everLost"] as? Bool == true {
            XCTAssertGreaterThan(try number(negative, "lossCount"), 0)
            if negative["currentlyMissing"] as? Bool == true {
                XCTAssertNil(negative["after"] as? Double, "Lost actual anchor cannot provide a fabricated numeric offset")
            }
        } else {
            XCTAssertGreaterThan(try number(negative, "maxDrift"), 2, "Negative control must detect a real displacement or actual anchor loss")
        }
        evidence(negative, name: "Uncompensated negative control")
        app.terminate()
        app = launch()
        try partialRow(app)
        var observedHeights: Set<Double> = []
        for index in 0..<3 {
            let measured = try page(app, direction: "spikeArmPrepend")
            observedHeights.formUnion(measured["visibleRowHeights"] as? [Double] ?? [])
            try preserved(measured, name: "Variable-height prepend \(index)")
            XCTAssertLessThan(try number(measured, "before"), 0, "The actual first visible exchange is partially clipped")
            if index < 2 { app.buttons["spikeEdge"].tap(); _ = try waitMetrics(app, phase: "ready"); try partialRow(app) }
        }
        XCTAssertGreaterThan(observedHeights.count, 2, "The actual hosted rows must demonstrate variable measured heights")
        app.buttons["spikePhoto"].tap(); _ = try waitMetrics(app, phase: "ready")
        try partialRow(app)
        app.buttons["spikeImage"].tap()
        let image = try waitMetrics(app, phase: "complete")
        try preserved(image, name: "Delayed thumbnail and intrinsic-height stress")
        XCTAssertGreaterThan(try number(image, "imageStressBeforeHeight"), 88, "Photo must be instantiated with its real hosted content height")
        XCTAssertGreaterThan(try number(image, "imageStressAfterHeight") - number(image, "imageStressBeforeHeight"), 70, "Native photo exchange height must actually change")
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Actual variable-height native conversation"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testSpikeBidirectionalEvictionAndBackgroundReplyPreserveReader() throws {
        let app = launch()
        for _ in 0..<6 {
            app.buttons["spikeEdge"].tap(); _ = try waitMetrics(app, phase: "ready")
            try partialRow(app)
            try preserved(try page(app, direction: "spikeArmPrepend"), name: "Seven-page earlier traversal")
        }
        var metrics = try readMetrics(app)
        let ranges = try XCTUnwrap(metrics["requestedPages"] as? [[Int]])
        XCTAssertEqual(Set(ranges.flatMap { $0 }), Set(1...140), "Every synthetic exchange was loaded without gaps")
        XCTAssertEqual((metrics["residentIDs"] as? [String])?.count, 100)
        XCTAssertFalse((metrics["residentIDs"] as? [String] ?? []).contains(id(140)), "Distant latest page was evicted")
        app.buttons["spikeReply"].tap()
        try preserved(try waitMetrics(app, phase: "complete"), name: "Off-viewport asynchronous reply")
        XCTAssertTrue(app.staticTexts["spikeLatestIndicator"].exists)
        for _ in 0..<2 {
            app.buttons["spikeEnd"].tap(); _ = try waitMetrics(app, phase: "ready")
            try preserved(try page(app, direction: "spikeArmLater"), name: "Reverse-direction refetch")
        }
        metrics = try readMetrics(app)
        let refetched = try XCTUnwrap(metrics["requestedPages"] as? [[Int]])
        XCTAssertEqual(refetched.filter { $0 == Array(121...140) }.count, 2, "Evicted latest page must be fetched again")
        let resident = try XCTUnwrap(metrics["residentIDs"] as? [String])
        XCTAssertEqual(resident.count, Set(resident).count, "Resident IDs remain unique")
        XCTAssertTrue(app.staticTexts["Off-viewport asynchronous reply completed."].exists)

        // Both edge responses remain held while a real user gesture changes the
        // intended position. Release only after recapturing the new idle anchor.
        app.buttons["spikeSeek"].tap(); _ = try waitMetrics(app, phase: "ready")
        app.buttons["spikeOverlap"].tap(); _ = try waitMetrics(app, phase: "held")
        let viewport = viewport(app)
        let point = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        point.press(forDuration: 0.05, thenDragTo: point.withOffset(CGVector(dx: 0, dy: -73)))
        _ = try waitMetrics(app, phase: "ready")
        app.buttons["spikeRelease"].tap()
        let overlap = try waitMetrics(app, phase: "complete")
        try preserved(overlap, name: "Overlapped directions after intentional drag")
        XCTAssertEqual(overlap["maxEarlierInFlight"] as? Int, 1)
        XCTAssertEqual(overlap["maxLaterInFlight"] as? Int, 1)
        XCTAssertEqual((overlap["requestedPages"] as? [[Int]])?.suffix(2).count, 2)
    }

    func testSpikeDynamicTypePreservesSemanticPosition() throws {
        let app = launch()
        _ = try page(app, direction: "spikeArmPrepend")
        app.buttons["spikeMiddle"].tap(); _ = try waitMetrics(app, phase: "ready")
        let prior = try readMetrics(app)
        let identity = try XCTUnwrap(prior["timelineGeneration"] as? String)
        for category in ["accessibility2", "large"] {
            app.buttons["spikeType"].tap()
            let reflow = try waitMetrics(app, phase: "complete")
            let semantic = try XCTUnwrap(reflow["semanticID"] as? String)
            XCTAssertEqual(reflow["category"] as? String, category)
            XCTAssertEqual(reflow["timelineGeneration"] as? String, identity)
            XCTAssertTrue((reflow["residentIDs"] as? [String] ?? []).contains(semantic))
            XCTAssertTrue((reflow["visibleIDs"] as? [String] ?? []).contains(semantic), "Semantic exchange remains visible after intentional font reflow")
            let text = app.staticTexts["spikeText-" + semantic]
            XCTAssertTrue(text.exists); XCTAssertFalse(text.label.isEmpty)
            let read = app.buttons["spikeRead-" + semantic]
            if !read.isHittable { viewport(app).swipeUp(velocity: .slow) }
            XCTAssertTrue(read.isHittable); read.tap()
            XCTAssertEqual(try readMetrics(app)["openedRowID"] as? String, semantic)
            evidence(reflow, name: "Semantic reflow \(category)")
            // Pixel equality is asserted only during a fixed-category stationary
            // prepend, never across the intentional category transition itself.
            _ = try waitIdle(app)
            try preserved(try page(app, direction: "spikeArmPrepend"), name: "Fixed-category prepend \(category)")
        }
    }

    func testSpikePagingPreservesAccessibilityFocus() throws {
        guard #available(iOS 27.0, *) else {
            throw XCTSkip("Actual VoiceOver automation service requires iOS 27; iOS 26 app support is retained. Run this named case on the iOS 27 simulator.")
        }
        let app = launch()
        for _ in 0..<4 {
            app.buttons["spikeEdge"].tap(); _ = try waitMetrics(app, phase: "ready")
            _ = try page(app, direction: "spikeArmPrepend")
        }
        app.buttons["spikeMiddle"].tap(); _ = try waitMetrics(app, phase: "ready")
        // Arm all fixture changes before starting VoiceOver navigation so no test
        // tap after the actual focus baseline can steal accessibility focus.
        app.buttons["spikeAutoFocus"].tap()
        let service = XCUIDevice.shared.voiceOverService
        let wasEnabled = service.isEnabled
        if !wasEnabled { try service.enable() }
        defer { if !wasEnabled { try? service.disable() } }
        XCTAssertTrue(service.isEnabled)
        var baselineSpeech = try service.currentSpeech().utterance
        for _ in 0..<60 {
            let metrics = try readMetrics(app)
            if !(metrics["baselineFocusedID"] as? String ?? "").isEmpty { break }
            baselineSpeech = try service.moveForward().utterance
        }
        let result = try waitMetrics(app, phase: "complete", timeout: 20)
        if let diagnostics = result["focusDiagnostics"], let data = try? JSONSerialization.data(withJSONObject: diagnostics, options: .sortedKeys) {
            print("SCROLL_FOCUS_DIAGNOSTICS " + String(data: data, encoding: .utf8)!)
        }
        XCTAssertTrue(result["voiceOverRunning"] as? Bool == true)
        XCTAssertGreaterThanOrEqual(result["committedFocusQueries"] as? Int ?? 0, 3, "Actual current VoiceOver focus must be queried at committed updates")
        XCTAssertFalse(result["pendingFocusLoss"] as? Bool ?? true, "Raw focus notification gaps must be resolved by an actual committed query")
        let focused = try XCTUnwrap(result["baselineFocusedID"] as? String)
        XCTAssertFalse(focused.isEmpty, "Baseline requires an observed real VoiceOver exchange focus")
        let sequence = try XCTUnwrap(Int(focused.suffix(12)))
        XCTAssertTrue(baselineSpeech.contains("Exchange \(sequence)"), "Navigation speech must identify the framework-confirmed baseline exchange: \(baselineSpeech)")
        XCTAssertEqual(result["focusedID"] as? String, focused)
        let events = try XCTUnwrap(result["focusEvents"] as? [[String: String]])
        let boundary = try XCTUnwrap(result["baselineFocusSequence"] as? Int)
        XCTAssertTrue(events.dropFirst(boundary).allSatisfy { $0["id"] == focused }, "Every positive target and committed current-focus query must retain the same exchange")
        let currentSpeech = try service.currentSpeech().utterance
        XCTAssertTrue((result["residentIDs"] as? [String] ?? []).contains(focused))
        XCTAssertTrue((result["visibleIDs"] as? [String] ?? []).contains(focused))
        XCTAssertGreaterThan((result["requestedPages"] as? [[Int]])?.count ?? 0, 6, "Automatic focused trial prepends, evicts and refetches")
        XCTAssertEqual(result["latestReply"] as? String, "Off-viewport asynchronous reply completed.")
        try preserved(result, name: "Actual VoiceOver retained through paging and reply")
        print("SCROLL_VOICEOVER_BASELINE_SPEECH " + baselineSpeech)
        print("SCROLL_VOICEOVER_POST_OPERATION_SPEECH " + currentSpeech)
    }

    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diary-ui-test", UUID().uuidString, "--coach-scroll-spike"] + extra
        app.launch()
        XCTAssertTrue(viewport(app).waitForExistence(timeout: 10))
        _ = try? waitMetrics(app, phase: "ready")
        return app
    }
    private func viewport(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["spikeViewport"] }
    private func partialRow(_ app: XCUIApplication) throws {
        var metrics = try waitIdle(app)
        // Position a meaningful partial row before the immutable baseline. A
        // subpixel tail is still visible by definition, but is not the intended
        // controlled reading position for this trial. Never ignore later loss.
        for _ in 0..<4 where (metrics["firstVisibleOffset"] as? Double ?? 0) >= -4 || visibleRemainder(metrics) < 44 {
            let point = viewport(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            point.press(forDuration: 0.05, thenDragTo: point.withOffset(CGVector(dx: 0, dy: -43)))
            metrics = try waitIdle(app)
        }
        XCTAssertLessThan(try number(metrics, "firstVisibleOffset"), 0)
        XCTAssertGreaterThanOrEqual(visibleRemainder(metrics), 44, "Establish actual readable partial geometry before capture")
    }
    private func visibleRemainder(_ metrics: [String: Any]) -> Double {
        (metrics["firstVisibleOffset"] as? Double ?? 0) + ((metrics["visibleRowHeights"] as? [Double])?.first ?? 0)
    }
    private func page(_ app: XCUIApplication, direction: String) throws -> [String: Any] {
        app.buttons[direction].tap()
        let baseline = try waitMetrics(app, phase: "held")
        let anchor = try XCTUnwrap(baseline["anchorID"] as? String)
        let before = try number(baseline, "before")
        app.buttons["spikeRelease"].tap()
        let result = try waitMetrics(app, phase: "finished")
        XCTAssertEqual(result["anchorID"] as? String, anchor)
        XCTAssertEqual(try number(result, "before"), before)
        return result
    }
    private func preserved(_ metrics: [String: Any], name: String) throws {
        evidence(metrics, name: name)
        XCTAssertEqual(metrics["phase"] as? String, "complete", "Actual anchor must survive every displayed sample")
        XCTAssertFalse(metrics["everLost"] as? Bool ?? true, "Any committed actual anchor loss fails even if later recovered")
        XCTAssertLessThanOrEqual(abs(try number(metrics, "after") - number(metrics, "before")), 2)
        XCTAssertLessThanOrEqual(try number(metrics, "maxDrift"), 2, "Transient displacement gate")
        XCTAssertLessThanOrEqual(try number(metrics, "residentCount") + number(metrics, "reservedCapacity"), 100)
        XCTAssertLessThanOrEqual(try number(metrics, "peakCapacity"), 100)
        XCTAssertEqual(metrics["error"] as? String, "")
    }
    private func evidence(_ metrics: [String: Any], name: String) {
        let attachment = XCTAttachment(string: String(describing: metrics)); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let keys = ["phase", "measurementChannel", "measurementActive", "preservingReader", "everLost", "currentlyMissing", "lossCount", "operationID", "operationKind", "anchorID", "before", "after", "maxDrift", "residentCount", "reservedCapacity", "peakCapacity", "renderer", "category", "focusedID", "baselineFocusedID", "baselineFocusSequence", "focusEvents", "committedFocusQueries", "pendingFocusLoss", "corrections", "imageStressID", "imageStressBeforeHeight", "imageStressAfterHeight", "visibleRowHeights"]
        let compact = metrics.filter { keys.contains($0.key) }
        let data = try! JSONSerialization.data(withJSONObject: compact, options: .sortedKeys)
        print("SCROLL_EVIDENCE " + String(data: data, encoding: .utf8)!)
        if ((metrics["maxDrift"] as? Double ?? 0) > 2 || metrics["everLost"] as? Bool == true), !(metrics["corrections"] as? [Double] ?? []).isEmpty,
           let events = metrics["nativeEvents"], let diagnostic = try? JSONSerialization.data(withJSONObject: events, options: .sortedKeys) {
            print("SCROLL_NATIVE_DIAGNOSTICS " + String(data: diagnostic, encoding: .utf8)!)
        }
    }
    private func number(_ metrics: [String: Any], _ key: String) throws -> Double { try XCTUnwrap((metrics[key] as? NSNumber)?.doubleValue, "Missing actual metric \(key)") }
    private func id(_ sequence: Int) -> String { String(format: "00000000-0000-0000-0000-%012d", sequence) }
    private func readMetrics(_ app: XCUIApplication) throws -> [String: Any] {
        let data = try XCTUnwrap((app.staticTexts["spikeMetrics"].value as? String)?.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func waitIdle(_ app: XCUIApplication) throws -> [String: Any] {
        try waitMetrics(app, phase: "idle")
    }
    private func waitMetrics(_ app: XCUIApplication, phase: String, timeout: TimeInterval = 10) throws -> [String: Any] {
        let predicate = NSPredicate { _, _ in
            guard let parsed = try? self.readMetrics(app), parsed["scrollIdle"] as? Bool == true else { return false }
            let observed = parsed["phase"] as? String
            if phase == "finished", observed == "applied" || observed == "complete", parsed["currentlyMissing"] as? Bool == true { return true }
            guard (parsed["stableFrames"] as? Int ?? 0) >= 3 else { return false }
            if phase == "finished" { return observed == "complete" }
            return phase == "idle" ? observed == "ready" || observed == "complete" : observed == phase
        }
        let outcome = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout)
        if outcome != .completed {
            let attachment = XCTAttachment(string: app.debugDescription); attachment.name = "Scroll spike failed hierarchy"; attachment.lifetime = .keepAlways; add(attachment)
            let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Scroll spike failed screenshot"; screenshot.lifetime = .keepAlways; add(screenshot)
        }
        XCTAssertEqual(outcome, .completed, "Waiting for \(phase): \((try? readMetrics(app)) ?? [:])")
        return try readMetrics(app)
    }
}
