import SwiftUI
import UIKit

/// Optional native measurements used only by the isolated production UI fixture.
@MainActor @Observable final class CoachTimelineDiagnostics {
    var largeText = false
    @ObservationIgnored private var panBeginCount = 0
    @ObservationIgnored private var panEndCount = 0
    @ObservationIgnored private var panScrollCount = 0
    @ObservationIgnored private var panEvents: [[String: String]] = []
    func recordPan(_ event: String, table: CoachTimelineTable) {
        if event == "begin" { panBeginCount += 1 }
        if event == "endDrag" { panEndCount += 1 }
        if event == "scroll" { panScrollCount += 1; return }
        if panEvents.count == 16 { panEvents.removeFirst() }
        panEvents.append(["event": event, "offset": String(describing: table.contentOffset),
            "translation": String(describing: table.panGestureRecognizer.translation(in: table)),
            "location": String(describing: table.panGestureRecognizer.location(in: table)),
            "state": String(describing: table.panGestureRecognizer.state), "tracking": String(table.isTracking),
            "dragging": String(table.isDragging), "decelerating": String(table.isDecelerating)])
    }
    private(set) var revision = 0
    private var committedSamples = 0
    private weak var table: CoachTimelineTable?
    private weak var timeline: CoachTimelineViewModel?
    private var link: UIUpdateLink?
    private var anchor: CoachViewportAnchor?
    private var before: Double?
    private var after: Double?
    private var maximumDrift = 0.0
    private var lost = false
    private var phase = "loading"
    private var kind = ""
    private var stableFrames = 0
    private var stableSince: CFTimeInterval = 0
    private var previousFrame: CGRect?
    private var focused: UUID?
    private var baselineFocus: UUID?
    private var focusQueries = 0
    private var focusLost = false
    private var focusArmed = false
    private var pendingRawFocus = false
    private var rawFocusEvents: [[String: String]] = []
    private var frames: [UUID: CGRect] = [:]
    private var photoTarget: UUID?
    private var photoPublished = false
    private var replyTarget: UUID?
    private var completedReply: UUID?
    private var focusStage = 0
    private var focusLatestID: UUID?
    private var focusEvictedLatest = false
    private var focusRefetchedLatest = false
    private var focusReplyText: String?
    @ObservationIgnored var navigationSnapshot: (@MainActor () -> [String: Any])?
    @ObservationIgnored var focusReplyAction: (@MainActor () async -> String?)?
    var uncompensated: Bool { ProcessInfo.processInfo.arguments.contains("--history-uncompensated") }

    func attach(_ table: CoachTimelineTable, timeline: CoachTimelineViewModel) {
        guard self.table !== table || link == nil else { return }
        stop(); self.table = table; self.timeline = timeline
        let link = UIUpdateLink(view: table)
        link.addAction(to: .afterUpdateComplete) { [weak self, weak table] _, _ in
            guard let self, let table else { return }; sample(table: table)
        }
        link.requiresContinuousUpdates = true; link.isEnabled = true; self.link = link
    }
    func stop() { link?.isEnabled = false; link?.requiresContinuousUpdates = false; link = nil }
    func begin(_ operation: String) {
        guard let table, let anchor = table.measuredAnchor() else { return }
        self.anchor = anchor; before = anchor.offset; after = nil; maximumDrift = 0; lost = false
        photoTarget = nil; photoPublished = false; replyTarget = nil; completedReply = nil
        kind = operation; phase = "measuring"; stableFrames = 0; stableSince = CACurrentMediaTime(); previousFrame = nil
        table.readingAnchor = anchor; table.followsLatest = false
        timeline?.setViewport(.history(anchor), visibleIDs: Set(table.measuredFrames().keys), measuredAnchor: anchor)
        revision += 1
    }
    func beginPhoto() {
        guard let timeline, let table,
              let row = timeline.exchanges.first(where: { table.measuredFrames()[$0.id] != nil && !$0.photos.isEmpty }),
              let photo = row.photos.first else { return }
        begin("thumbnail"); photoTarget = photo.photoID
    }
    func thumbnailDidPublish(_ id: UUID) {
        guard photoTarget == id else { return }
        photoPublished = true; resetStability()
    }
    func expectReply(_ id: UUID, alreadyCompleted: Bool) {
        guard anchor != nil else { return }
        kind = "historySend"; replyTarget = id; completedReply = alreadyCompleted ? id : nil
        phase = "measuring"; resetStability()
    }
    func replyDidComplete(_ id: UUID) {
        guard replyTarget == id else { return }
        completedReply = id; resetStability()
    }
    private func resetStability() { stableFrames = 0; stableSince = CACurrentMediaTime(); previousFrame = nil }
    func observeFocusNotification(_ event: Notification) {
        guard UIAccessibility.isVoiceOverRunning, let table else { return }
        let positive = event.userInfo?[UIAccessibility.focusedElementUserInfoKey]
        let id = positive.flatMap { table.exchange(containing: $0) }
        if positive == nil { pendingRawFocus = true }
        else if baselineFocus != nil, id != baselineFocus { focusLost = true }
        if rawFocusEvents.count == 32 { rawFocusEvents.removeFirst() }
        rawFocusEvents.append(["time": String(CACurrentMediaTime()), "positiveID": id?.uuidString ?? "",
            "keys": event.userInfo?.keys.map { String(describing: $0) }.sorted().joined(separator: ",") ?? ""])
    }
    func sample(table: CoachTimelineTable) {
        committedSamples += 1
        frames = table.measuredFrames()
        let focus = table.focusedExchange()
        if focusArmed, let focus, let timeline {
            focusArmed = false; begin("focus"); baselineFocus = focus; focusLost = false; focusQueries = 0
            focusStage = 1; focusLatestID = timeline.exchanges.last?.id
            focusEvictedLatest = false; focusRefetchedLatest = false; focusReplyText = nil
            timeline.loadEarlier(anchor: table.measuredAnchor())
        }
        if baselineFocus != nil {
            focusQueries += 1; focused = focus; pendingRawFocus = false
            if focus != baselineFocus { focusLost = true }
        }
        let candidate = anchor?.rowID ?? table.measuredAnchor()?.rowID
        let frame = candidate.flatMap { frames[$0] }
        if anchor != nil {
            if let frame, let before { after = frame.minY; maximumDrift = max(maximumDrift, abs(frame.minY - before)) }
            else { lost = true; after = nil }
        }
        let time = CACurrentMediaTime()
        if frame == previousFrame { stableFrames += 1 }
        else { stableFrames = 1; stableSince = time }
        previousFrame = frame
        if stableFrames >= 3, time - stableSince >= 0.1, !table.isDragging, !table.isDecelerating,
           timeline?.window.reservations.isEmpty == true {
            let photoReady = photoTarget == nil || photoPublished
            let replyReady = replyTarget == nil || completedReply == replyTarget
            guard photoReady, replyReady else { revision += 1; return }
            if focusStage == 1, let timeline {
                focusEvictedLatest = !timeline.exchanges.contains { $0.id == focusLatestID }
                focusStage = 2; resetStability()
                timeline.loadLater(anchor: anchor)
            } else if focusStage == 2, let timeline {
                focusRefetchedLatest = timeline.exchanges.contains { $0.id == focusLatestID }
                focusStage = 3; resetStability()
                Task { @MainActor in focusReplyText = await focusReplyAction?(); resetStability() }
            } else if focusStage == 3 {
                guard let focusReplyText, timeline?.exchanges.first(where: { $0.id == focusLatestID })?.assistantText == focusReplyText else { revision += 1; return }
                focusStage = 4; phase = "complete"
            } else { phase = anchor == nil ? "ready" : "complete" }
        }
        revision += 1
    }
    func earlier() { begin("prepend"); timeline?.loadEarlier(anchor: anchor) }
    func later() { begin("append"); timeline?.loadLater(anchor: anchor) }
    func armFocus() { focusArmed = true }
    func reflow() { begin("reflow"); largeText.toggle() }
    func reveal(_ last: Bool) {
        guard let table, let row = last ? timeline?.exchanges.last : timeline?.exchanges.first,
              let index = table.rows.firstIndex(where: { $0.id == .exchange(row.id) }) else { return }
        anchor = nil; before = nil; after = nil; phase = "settling"; stableFrames = 0
        table.readingAnchor = nil; table.followsLatest = false
        table.scrollToRow(at: IndexPath(row: index, section: 0), at: last ? .bottom : .top, animated: false)
        table.layoutIfNeeded(); table.refreshViewportNow()
        table.readingAnchor = table.measuredAnchor()
    }
    func revealPhoto() {
        guard let row = timeline?.exchanges.first(where: { $0.sequence.isMultiple(of: 12) && !$0.photos.isEmpty }) else { return }
        revealRow(row.id, at: .top)
    }
    private func revealRow(_ id: UUID, at position: UITableView.ScrollPosition) {
        guard let table, let index = table.rows.firstIndex(where: { $0.id == .exchange(id) }) else { return }
        anchor = nil; before = nil; after = nil; phase = "settling"; resetStability()
        table.readingAnchor = nil; table.followsLatest = false
        table.scrollToRow(at: IndexPath(row: index, section: 0), at: position, animated: false)
        table.layoutIfNeeded(); table.refreshViewportNow()
        table.readingAnchor = table.measuredAnchor()
    }
    @ObservationIgnored private var jumpSnapshotRevision: Int?
    @ObservationIgnored private var jumpSnapshot: [String: Any] = [:]
    private func accessibilityDescription(_ element: Any?) -> [String: String] {
        guard let value = element as? NSObject else { return ["class": String(describing: element)] }
        return ["class": String(describing: type(of: value)),
            "identifier": (value as? UIAccessibilityIdentification)?.accessibilityIdentifier ?? "",
            "label": value.accessibilityLabel ?? "", "frame": String(describing: value.accessibilityFrame),
            "isElement": String(value.isAccessibilityElement)]
    }
    private func jumpAccessibilitySnapshot(_ table: CoachTimelineTable) -> [String: Any] {
        let count = table.accessibilityElementCount()
        var indexes: [Int] = []
        if count > 0, count < 1_000 {
            indexes = Array(Set(Array(0..<min(count, 8)) + Array(max(0, count - 2)..<count))).sorted()
        }
        var result: [String: Any] = ["tableAXCount": count,
            "tableAXSample": indexes.map { index in
                ["index": String(index)].merging(accessibilityDescription(table.accessibilityElement(at: index))) { _, rhs in rhs }
            }]
        guard let jump = table.jumpButton else { result["hostPresent"] = false; return result }
        result["hostPresent"] = true
        result["host"] = accessibilityDescription(jump)
        result["hostBounds"] = String(describing: jump.bounds)
        result["hostFrame"] = String(describing: jump.frame)
        result["hostScreenFrame"] = String(describing: UIAccessibility.convertToScreenCoordinates(jump.bounds, in: jump))
        result["hostHidden"] = jump.isHidden; result["hostAlpha"] = jump.alpha
        result["hostWindow"] = jump.window != nil; result["hostDescendantOfTable"] = jump.isDescendant(of: table)
        result["hostSuperview"] = jump.superview.map { String(describing: type(of: $0)) } ?? "none"
        result["tableAXHostIndex"] = table.index(ofAccessibilityElement: jump)
        let hostCount = jump.accessibilityElementCount()
        result["hostAXCount"] = hostCount
        result["hostAXSample"] = hostCount > 0 && hostCount < 100
            ? (0..<min(hostCount, 4)).map { accessibilityDescription(jump.accessibilityElement(at: $0)) } : []
        if let window = jump.window {
            let point = jump.convert(CGPoint(x: jump.bounds.midX, y: jump.bounds.midY), to: window)
            var hit = window.hitTest(point, with: nil), path: [String] = []
            for _ in 0..<12 {
                guard let view = hit else { break }
                path.append(String(describing: type(of: view)) + ":" + (view.accessibilityIdentifier ?? ""))
                hit = view.superview
            }
            result["centerHitPath"] = path
        }
        return result
    }
    var metrics: String {
        let visible = timeline?.exchanges.filter { frames[$0.id] != nil } ?? []
        var value: [String: Any] = ["phase": phase, "operationKind": kind, "committedSamples": committedSamples,
            "viewportPublications": table?.viewportPublicationCount ?? 0,
            "photoTargetID": photoTarget?.uuidString ?? "", "photoPublished": photoPublished,
            "replyTargetID": replyTarget?.uuidString ?? "", "completedReplyID": completedReply?.uuidString ?? "",
            "focusStage": focusStage, "focusEvictedLatest": focusEvictedLatest, "focusRefetchedLatest": focusRefetchedLatest,
            "focusReplyCommitted": focusStage == 4, "rowOffsets": Dictionary(uniqueKeysWithValues: frames.map { ($0.key.uuidString, $0.value.minY) }),
            "viewportHeight": table.map { $0.bounds.height - $0.contentInset.bottom } ?? 0, "lastRowBottom": table?.measuredLastRowBottom() as Any? ?? NSNull(),
            "anchorID": anchor?.rowID.uuidString ?? "", "before": before as Any? ?? NSNull(),
            "after": after as Any? ?? NSNull(), "maxDrift": maximumDrift, "everLost": lost,
            "visibleIDs": visible.map { $0.id.uuidString }, "visibleRowHeights": visible.compactMap { frames[$0.id]?.height },
            "firstVisibleOffset": visible.first.flatMap { frames[$0.id]?.minY } as Any? ?? NSNull(),
            "residentIDs": timeline?.exchanges.map { $0.id.uuidString } ?? [],
            "residentCount": timeline?.window.residentCount ?? 0, "reservedCapacity": timeline?.window.reservedCapacity ?? 0,
            "peakCapacity": timeline?.peakCapacity ?? 0, "requestedPages": timeline?.requestedRanges ?? [],
            "stableFrames": stableFrames, "scrollIdle": table.map { !$0.isDragging && !$0.isDecelerating } ?? false,
            "renderer": "UITableView", "measurementChannel": "afterUpdateCompleteActualVisibleCell",
            "focusedID": focused?.uuidString ?? "", "baselineFocusedID": baselineFocus?.uuidString ?? "",
            "committedFocusQueries": focusQueries, "focusLost": focusLost, "rawFocusEvents": rawFocusEvents, "pendingFocusLoss": pendingRawFocus,
            "category": largeText ? "accessibility2" : "large", "error": timeline?.error ?? ""]
        if let table, let timeline, table.hasApplied(timeline), stableFrames >= 3,
           CACurrentMediaTime() - stableSince >= 0.1, jumpSnapshotRevision != timeline.revision {
            // Read public AX enumeration once per settled native/model revision, not each frame.
            jumpSnapshot = jumpAccessibilitySnapshot(table); jumpSnapshotRevision = timeline.revision
        }
        value["jumpAccessibility"] = jumpSnapshot
        value["pan"] = ["begins": panBeginCount, "ends": panEndCount, "scrollCallbacks": panScrollCount, "events": panEvents]
        value["navigation"] = navigationSnapshot?() ?? [:]
        value["timelineRestoration"] = timeline.map { String(describing: $0.restoration) } ?? ""
        value["timelineViewport"] = timeline.map { String(describing: $0.window.viewport) } ?? ""
        if let table {
            value["nativeTable"] = ["appliedRenderCount": table.appliedRenderCount, "appliedRevision": table.appliedRevision as Any? ?? NSNull(),
                "modelRevision": timeline?.revision as Any? ?? NSNull(),
                "hasAppliedModel": timeline.map { table.hasApplied($0) } ?? false, "screenFrame": String(describing: UIAccessibility.convertToScreenCoordinates(table.bounds, in: table)),
                "bounds": String(describing: table.bounds), "contentOffset": String(describing: table.contentOffset), "contentOffsetY": table.contentOffset.y,
                "contentSize": String(describing: table.contentSize), "insets": String(describing: table.adjustedContentInset),
                "readingAnchor": table.readingAnchor.map { String(describing: $0) } ?? "", "followsLatest": table.followsLatest,
                "dragging": table.isDragging, "tracking": table.isTracking, "decelerating": table.isDecelerating,
                "attached": table.window != nil, "applyingRows": table.isApplyingRows,
                "scrollEnabled": table.isScrollEnabled, "panEnabled": table.panGestureRecognizer.isEnabled,
                "panState": String(describing: table.panGestureRecognizer.state),
                "highlightedRows": table.rows.compactMap { row -> String? in
                    guard row.isHighlighted, case .exchange(let id) = row.id else { return nil }; return id.uuidString
                },
                "visibleCells": table.visibleCells.compactMap { cell -> [String: String]? in
                    guard let cell = cell as? CoachTimelineCell, let id = cell.rowID else { return nil }
                    return ["id": String(describing: id), "screenFrame": String(describing: UIAccessibility.convertToScreenCoordinates(cell.bounds, in: cell)),
                            "contentFrame": String(describing: cell.contentView.frame), "hidden": String(cell.isHidden)]
                }]
        }
        return String(decoding: try! JSONSerialization.data(withJSONObject: value, options: .sortedKeys), as: UTF8.self)
    }
}

#if DEBUG
actor CoachHistoryPhotoGate {
    static let shared = CoachHistoryPhotoGate()
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if !open { await withCheckedContinuation { waiters.append($0) } }
    }
    func release() {
        open = true; let waiting = waiters; waiters = []; for waiter in waiting { waiter.resume() }
    }
}
#endif
