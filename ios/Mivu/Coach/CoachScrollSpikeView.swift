#if DEBUG
import SwiftUI
import UIKit

/// Temporary native feasibility surface. This route never constructs the diary/store.
struct CoachScrollSpikeView: View {
    @State private var probe = CoachScrollProbe()
    var body: some View {
        VStack(spacing: 0) {
            Text("Synthetic conversation scrolling").frame(height: 44)
            HStack(spacing: 12) {
                command("Earlier", "spikeArmPrepend") { probe.arm(.earlier) }
                command("Later", "spikeArmLater") { probe.arm(.later) }
                command("Release", "spikeRelease") { probe.release() }
                Text("Metrics").accessibilityIdentifier("spikeMetrics").accessibilityValue(probe.metrics)
            }.font(.caption).frame(height: 44)
            HStack(spacing: 12) {
                command("Start", "spikeEdge") { probe.goToEdge(.earlier) }
                command("End", "spikeEnd") { probe.goToEdge(.later) }
                command("Middle", "spikeMiddle") { probe.revealMiddle() }
                command("Seek", "spikeSeek") { probe.seekMiddle() }
                command("Overlap", "spikeOverlap") { probe.overlap() }
                command("Photo", "spikePhoto") { probe.revealPhoto() }
            }.font(.caption).frame(height: 44)
            HStack(spacing: 12) {
                command("Reply", "spikeReply") { probe.backgroundReply() }
                command("Text", "spikeType") { probe.reflow() }
                command("Image", "spikeImage") { probe.completeImage() }
                command("Auto focus", "spikeAutoFocus") { probe.armFocusTrial() }
            }.font(.caption).frame(height: 44)
            CoachSpikeTable(probe: probe)
            if probe.timeline.hasNewReply { Text("New reply available").accessibilityIdentifier("spikeLatestIndicator").frame(height: 44) }
            else { Color.clear.frame(height: 44) }
        }
        .task { await probe.timeline.loadLatest(); probe.didLoad() }
        .onAppear { probe.start() }
        .onDisappear { probe.stop() }
        .onChange(of: probe.timeline.revision) { _, _ in probe.didApply() }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.elementFocusedNotification)) { event in
            probe.observeFocusNotification(event)
        }
    }
    private func command(_ label: String, _ id: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action).frame(minHeight: 44).accessibilityIdentifier(id)
    }
}

/// One measured candidate; the earlier SwiftUI trial captured layout geometry only.
/// The bridge owns only native layout and offset restoration; paging stays shared.
private struct CoachSpikeTable: UIViewRepresentable {
    let probe: CoachScrollProbe
    func makeUIView(context: Context) -> CoachAnchoredTable {
        let table = CoachAnchoredTable(frame: .zero, style: .plain)
        table.probe = probe; probe.attach(table)
        table.accessibilityIdentifier = "spikeViewport"
        table.separatorStyle = .none; table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 200; table.contentInsetAdjustmentBehavior = .never
        table.dataSource = context.coordinator; table.delegate = context.coordinator
        table.register(CoachSpikeTableCell.self, forCellReuseIdentifier: "exchange")
        return table
    }
    func makeCoordinator() -> Coordinator { Coordinator(probe: probe) }
    func updateUIView(_ table: CoachAnchoredTable, context: Context) {
        table.isScrollEnabled = !probe.stationary
        let rows = probe.timeline.exchanges
        let signature = rows.map { $0.id.uuidString + ($0.assistantText ?? "") }.joined()
            + String(probe.largeText) + String(probe.imageComplete) + String(probe.intrinsicImage)
        guard signature != table.signature else { return }
        let old = table.rows
        let categoryChanged = table.largeText != probe.largeText
        let intrinsicChanged = table.intrinsicImage != probe.intrinsicImage
        table.recordNative("rows-before")
        table.largeText = probe.largeText; table.intrinsicImage = probe.intrinsicImage
        // Row IDs have their new map before UIKit commits its old->new index
        // transition. Restore only after that atomic transition has completed.
        table.isApplyingRows = true
        table.signature = signature; table.rows = rows
        table.recordNative("rows-new-map")
        UIView.performWithoutAnimation {
            if old.isEmpty { table.reloadData() }
            else {
                let oldIDs = Set(old.map(\.id)), newIDs = Set(rows.map(\.id))
                let removed = old.indices.filter { !newIDs.contains(old[$0].id) }.map { IndexPath(row: $0, section: 0) }
                let inserted = rows.indices.filter { !oldIDs.contains(rows[$0].id) }.map { IndexPath(row: $0, section: 0) }
                if !removed.isEmpty || !inserted.isEmpty {
                    table.beginUpdates()
                    table.deleteRows(at: removed, with: .none); table.insertRows(at: inserted, with: .none)
                    table.endUpdates()
                } else {
                    // Preserve native cell identity through a reflow or delayed
                    // image completion; reconfigure the existing hosted content.
                    if categoryChanged {
                        for path in table.indexPathsForVisibleRows ?? [] {
                            if let cell = table.cellForRow(at: path) { context.coordinator.configure(cell, row: rows[path.row]) }
                        }
                    }
                    if intrinsicChanged, let index = rows.firstIndex(where: { $0.id == probe.imageStressID }) {
                        table.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
                    }
                    table.beginUpdates(); table.endUpdates()
                }
            }
            table.setNeedsLayout(); table.layoutIfNeeded()
            table.recordNative("rows-native-layout")
            table.isApplyingRows = false; table.restoreAnchor()
            table.recordNative("rows-committed")
            if let target = table.semanticTarget { table.reveal(target); table.semanticTarget = nil }
        }
    }
    @MainActor final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        let probe: CoachScrollProbe
        init(probe: CoachScrollProbe) { self.probe = probe }
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { (tableView as! CoachAnchoredTable).rows.count }
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let table = tableView as! CoachAnchoredTable
            let cell = table.dequeueReusableCell(withIdentifier: "exchange", for: indexPath)
            let row = table.rows[indexPath.row]
            configure(cell, row: row)
            return cell
        }
        func configure(_ cell: UITableViewCell, row: CoachExchangeSummary) {
            (cell as? CoachSpikeTableCell)?.exchangeID = row.id
            cell.selectionStyle = .none
            cell.contentConfiguration = UIHostingConfiguration {
                CoachSpikeExchange(row: row, probe: probe)
                    .dynamicTypeSize(probe.largeText ? .accessibility2 : .large)
            }.margins(.all, 8)
        }
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { probe.setScrollIdle(false) }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { probe.setScrollIdle(true) } }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { probe.setScrollIdle(true) }
        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { probe.setScrollIdle(true) }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { (scrollView as? CoachAnchoredTable)?.nativeOffsetDidChange() }
    }
}

private struct CoachSpikeExchange: View {
    let row: CoachExchangeSummary
    let probe: CoachScrollProbe
    @AccessibilityFocusState(for: .voiceOver) private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(row.text).accessibilityIdentifier("spikeText-" + row.id.uuidString).accessibilityFocused($focused)
            if let reply = row.assistantText { Text(reply).foregroundStyle(.secondary) }
            if row.sequence.isMultiple(of: 4) {
                Rectangle().fill(probe.imageComplete ? Color.green : Color.gray)
                    .frame(height: probe.intrinsicImage && row.id == probe.imageStressID ? 168 : 88)
                    .overlay(Text("Synthetic thumbnail"))
            }
            Button("Read recorded serving \(row.sequence)") { probe.openedRowID = row.id }
                .frame(minHeight: 44).accessibilityIdentifier("spikeRead-" + row.id.uuidString)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("spikeExchange-" + row.id.uuidString)
            .onChange(of: focused) { _, value in probe.observedFocus(value ? row.id : nil, origin: "AccessibilityFocusState") }
    }
}

private final class CoachSpikeTableCell: UITableViewCell { var exchangeID: UUID? }

private final class CoachAnchoredTable: UITableView {
    weak var probe: CoachScrollProbe?
    var rows: [CoachExchangeSummary] = []
    var signature = ""
    var largeText = false
    var intrinsicImage = false
    var semanticTarget: UUID?
    var isApplyingRows = false
    private var restoring = false
    private var layingOut = false
    private var recordingNative = false
    private weak var baselineCell: CoachSpikeTableCell?
    var nativeEvents: [[String: Any]] = []
    func retainBaselineIdentity(_ id: UUID) {
        baselineCell = visibleCells.compactMap { $0 as? CoachSpikeTableCell }.first { $0.exchangeID == id }
    }
    override func layoutSubviews() {
        guard !layingOut else { super.layoutSubviews(); return }
        layingOut = true
        recordNative("layout-before", onlyDrift: true)
        super.layoutSubviews()
        layingOut = false
        restoreAnchor()
        recordNative("layout-after", onlyDrift: true)
    }
    func nativeOffsetDidChange() {
        recordNative("offset-callback", onlyDrift: true)
        guard !layingOut else { return }
        restoreAnchor()
    }
    func restoreAnchor() {
        guard !restoring, !isApplyingRows, let anchor = probe?.restorationAnchor else { return }
        restoring = true
        defer { restoring = false }
        for _ in 0..<8 {
            super.layoutSubviews()
            guard let index = rows.firstIndex(where: { $0.id == anchor.rowID }) else { return }
            let observed = rectForRow(at: IndexPath(row: index, section: 0)).minY - contentOffset.y
            let delta = observed - anchor.offset
            guard abs(delta) > 0.25 else { return }
            recordNative("correction-before")
            let target = max(-adjustedContentInset.top, contentOffset.y + delta)
            setContentOffset(CGPoint(x: contentOffset.x, y: target), animated: false)
            probe?.recordCorrection(delta)
            recordNative("correction-after")
        }
    }
    func recordNative(_ event: String, onlyDrift: Bool = false, sampledOffset: Double? = nil) {
        guard !recordingNative, let context = probe?.diagnosticContext else { return }
        recordingNative = true
        defer { recordingNative = false }
        let nativeCount = numberOfSections > 0 ? numberOfRows(inSection: 0) : 0
        let index = rows.firstIndex(where: { $0.id == context.anchor.rowID })
        let rect = index.flatMap { $0 < nativeCount ? rectForRow(at: IndexPath(row: $0, section: 0)) : nil }
        let observed = rect.map { $0.minY - contentOffset.y }
        if onlyDrift, let observed, abs(observed - context.anchor.offset) <= 0.25 { return }
        let cell = visibleCells.compactMap { $0 as? CoachSpikeTableCell }.first { $0.exchangeID == context.anchor.rowID }
        let actualCellRect = cell.map { $0.convert($0.bounds, to: self).offsetBy(dx: -bounds.minX, dy: -bounds.minY) }
        let tablePresentation = layer.presentation()
        let retainedReference = cell ?? baselineCell
        let cellPresentation = retainedReference?.layer.presentation()
        let presentedRect: CGRect? = if let tablePresentation, let cellPresentation {
            cellPresentation.convert(cellPresentation.bounds, to: tablePresentation)
                .offsetBy(dx: -tablePresentation.bounds.minX, dy: -tablePresentation.bounds.minY)
        } else { nil }
        let value: [String: Any] = ["event": event, "time": CACurrentMediaTime(), "phase": context.phase,
            "preservingReader": context.preserving, "measurementActive": context.measuring, "stationaryInput": context.stationary,
            "anchorID": context.anchor.rowID.uuidString, "baseline": context.anchor.offset,
            "offset": observed as Any? ?? NSNull(), "rawRowY": rect?.minY as Any? ?? NSNull(), "rowHeight": rect?.height as Any? ?? NSNull(),
            "contentOffset": contentOffset.y, "contentHeight": contentSize.height,
            "rowCount": rows.count, "nativeRowCount": nativeCount, "anchorIndex": index as Any? ?? NSNull(),
            "applyingRows": isApplyingRows, "restoring": restoring, "layingOut": layingOut,
            "retainedCellID": cell?.exchangeID?.uuidString ?? "",
            "baselineReferenceCurrentID": baselineCell?.exchangeID?.uuidString ?? "",
            "cellViewportY": actualCellRect?.minY as Any? ?? NSNull(),
            "cellHeight": actualCellRect?.height as Any? ?? NSNull(),
            "presentedCellViewportY": presentedRect?.minY as Any? ?? NSNull(),
            "presentedCellHeight": presentedRect?.height as Any? ?? NSNull(),
            "tableBoundsY": bounds.minY,
            "presentedTableBoundsY": tablePresentation?.bounds.minY as Any? ?? NSNull(),
            "sampledOffset": sampledOffset as Any? ?? NSNull()]
        if nativeEvents.count == 192 { nativeEvents.removeFirst() }
        nativeEvents.append(value)
    }
    func measuredFrames() -> [UUID: CGRect] {
        // rectForRow can expose an intermediate estimated row map before layout;
        // native diagnostic traces proved it differed from both the retained
        // cell and its presentation. Only actual stable-ID cells are evidence.
        Dictionary(uniqueKeysWithValues: visibleCells.compactMap { value in
            guard let cell = value as? CoachSpikeTableCell, let id = cell.exchangeID,
                  rows.contains(where: { $0.id == id }) else { return nil }
            let rect = cell.convert(cell.bounds, to: self).offsetBy(dx: -bounds.minX, dy: -bounds.minY)
            return (id, rect)
        })
    }
    func reveal(_ id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        scrollToRow(at: IndexPath(row: index, section: 0), at: .top, animated: false)
        layoutIfNeeded()
    }
    func measuredHeight(_ id: UUID) -> Double? {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return nil }
        return rectForRow(at: IndexPath(row: index, section: 0)).height
    }
    func exchangeContainingFocusedFrame(_ frame: CGRect) -> UUID? {
        guard let window, !frame.isEmpty, !frame.isNull, !frame.isInfinite,
              UIAccessibility.convertToScreenCoordinates(window.bounds, in: window).contains(frame) else { return nil }
        let matches = visibleCells.compactMap { value -> UUID? in
            guard let cell = value as? CoachSpikeTableCell, cell.window === window,
                  let id = cell.exchangeID, rows.contains(where: { $0.id == id }),
                  UIAccessibility.convertToScreenCoordinates(cell.bounds, in: cell).contains(frame) else { return nil }
            return id
        }
        return matches.count == 1 ? matches[0] : nil
    }
}

/// Committed-update sampling observes actual cell geometry; fixture commands never supply offsets.
@MainActor @Observable private final class CoachScrollProbe: NSObject {
    let source: CoachScrollSpikeSource
    let timeline: CoachTimelineViewModel
    var frames: [UUID: CGRect] = [:]
    var viewport: CGRect = .zero
    var contentOffset: CGPoint = .zero
    @ObservationIgnored weak var table: CoachAnchoredTable?
    var scrollIdle = true
    var stationary = false
    var largeText = false
    var imageComplete = false
    var intrinsicImage = false
    var imageStressID: UUID?
    private var imageStressBeforeHeight: Double?
    var openedRowID: UUID?
    private var phase = "loading"
    private var link: UIUpdateLink?
    private var stableSince: CFTimeInterval = 0
    private var stableFrames = 0
    private var previous: CGRect?
    private var previousID: UUID?
    private var anchor: CoachViewportAnchor?
    private var readingAnchor: CoachViewportAnchor?
    private var measurementActive = false
    private var before: Double?
    private var after: Double?
    private var maxDrift = 0.0
    private var operationID = UUID()
    private var baselineOffset: CGPoint = .zero
    private var baselineGeneration: UUID?
    private var corrections: [Double] = []
    private var correctionTarget: CGFloat?
    private var currentDirection: CoachPageDirection = .earlier
    private var focusedID: UUID?
    private var focusEvents: [[String: String]] = []
    private var focusDiagnostics: [[String: Any]] = []
    private var focusTrialArmed = false
    private var semanticID: UUID?
    private var operationKind = ""
    private var everLost = false
    private var currentlyMissing = false
    private var lossCount = 0
    private var focusStage = 0
    private var baselineFocusSequence = 0
    private var baselineFocusedID: UUID?
    private var focusTrialActive = false
    private var pendingFocusLoss = false
    private var committedFocusQueries = 0
    private var maxEarlierInFlight = 0
    private var maxLaterInFlight = 0
    private let uncompensated = ProcessInfo.processInfo.arguments.contains("--spike-uncompensated")

    override init() {
        let fixture = CoachScrollSpikeSource(); source = fixture
        timeline = CoachTimelineViewModel { request, generation in await fixture.page(request, generation) }
        super.init()
    }
    private var rows: [CoachExchangeSummary] { timeline.exchanges }
    private var visibleRows: [CoachExchangeSummary] { rows.filter { frames[$0.id]?.intersection(viewport).isEmpty == false } }
    var metrics: String {
        let first = visibleRows.first
        let value: [String: Any] = ["phase": phase, "operationID": operationID.uuidString,
            "operationKind": operationKind, "anchorID": anchor?.rowID.uuidString ?? "",
            "before": before as Any? ?? NSNull(), "after": after as Any? ?? NSNull(), "maxDrift": maxDrift,
            "visibleIDs": visibleRows.map { $0.id.uuidString }, "residentIDs": rows.map { $0.id.uuidString },
            "visibleRowHeights": visibleRows.compactMap { frames[$0.id]?.height },
            "residentCount": timeline.window.residentCount, "reservedCapacity": timeline.window.reservedCapacity,
            "peakCapacity": timeline.peakCapacity, "requestedPages": timeline.requestedRanges,
            "renderer": "UITableView", "viewportHeight": viewport.height, "viewportWidth": viewport.width,
            "measurementChannel": "afterUpdateCompleteRetainedCellViewport",
            "everLost": everLost, "currentlyMissing": currentlyMissing, "lossCount": lossCount,
            "measurementActive": measurementActive, "preservingReader": readingAnchor != nil && !uncompensated,
            "contentOffsetY": contentOffset.y, "baselineContentOffsetY": baselineOffset.y,
            "firstVisibleOffset": first.flatMap { frames[$0.id]?.minY } as Any? ?? NSNull(),
            "firstVisibleID": first?.id.uuidString ?? "", "stableFrames": stableFrames, "scrollIdle": scrollIdle,
            "anchorHeight": anchor.flatMap { frames[$0.rowID]?.height } as Any? ?? NSNull(),
            "imageStressID": imageStressID?.uuidString ?? "", "imageStressBeforeHeight": imageStressBeforeHeight as Any? ?? NSNull(),
            "imageStressAfterHeight": imageStressID.flatMap { table?.measuredHeight($0) } as Any? ?? NSNull(),
            "corrections": corrections, "category": largeText ? "accessibility2" : "large",
            "timelineGeneration": timeline.window.identity?.timelineGeneration.uuidString ?? "",
            "semanticID": semanticID?.uuidString ?? "", "focusedID": focusedID?.uuidString ?? "",
            "focusEvents": focusEvents, "voiceOverRunning": UIAccessibility.isVoiceOverRunning,
            "focusDiagnostics": focusDiagnostics,
            "pendingFocusLoss": pendingFocusLoss, "committedFocusQueries": committedFocusQueries,
            "baselineFocusSequence": baselineFocusSequence, "baselineFocusedID": baselineFocusedID?.uuidString ?? "",
            "maxEarlierInFlight": maxEarlierInFlight, "maxLaterInFlight": maxLaterInFlight,
            "latestReply": rows.first(where: { $0.sequence == 140 })?.assistantText ?? "",
            "nativeEvents": table?.nativeEvents ?? [],
            "openedRowID": openedRowID?.uuidString ?? "", "error": timeline.error ?? ""]
        return String(data: try! JSONSerialization.data(withJSONObject: value, options: .sortedKeys), encoding: .utf8)!
    }
    func didLoad() { phase = "settling" }
    func didApply() {
        let resident = Set(rows.map(\.id)); frames = frames.filter { resident.contains($0.key) }
        if phase == "held" || phase == "arming" { resetStability(); phase = "applied" }
    }
    func start() {
        guard link == nil, let table else { return }
        let update = UIUpdateLink(view: table)
        update.addAction(to: .afterCADisplayLinkDispatch) { [weak self] _, _ in self?.observePreLayout() }
        update.addAction(to: .afterUpdateComplete) { [weak self] _, info in self?.sample(at: info.modelTime) }
        update.requiresContinuousUpdates = true; update.isEnabled = true; link = update
    }
    func attach(_ table: CoachAnchoredTable) { self.table = table; start() }
    func stop() { link?.isEnabled = false; link?.requiresContinuousUpdates = false; link = nil }
    @discardableResult private func capture(_ kind: String, freeze: Bool = true) -> CoachViewportAnchor? {
        guard (phase == "ready" || phase == "complete"), scrollIdle,
              let first = visibleRows.first, let rect = frames[first.id] else { return nil }
        let value = CoachViewportAnchor(rowID: first.id, offset: rect.minY - viewport.minY, focusedExchangeID: focusedID)
        anchor = value; before = value.offset; after = nil; maxDrift = 0; corrections = []; correctionTarget = nil
        readingAnchor = value; measurementActive = freeze && kind != "reflow"
        table?.nativeEvents = []
        table?.retainBaselineIdentity(value.rowID)
        everLost = false; currentlyMissing = false; lossCount = 0
        baselineOffset = contentOffset; baselineGeneration = timeline.window.identity?.timelineGeneration
        operationID = UUID(); stationary = freeze; operationKind = kind
        timeline.setViewport(.history(value)); return value
    }
    func arm(_ direction: CoachPageDirection) {
        guard let anchor = capture(direction == .earlier ? "prepend" : "append") else { return }
        currentDirection = direction; phase = "arming"
        Task {
            await source.arm(direction); phase = "held"
            if direction == .earlier { timeline.loadEarlier(anchor: anchor); timeline.loadEarlier(anchor: anchor) }
            else { timeline.loadLater(anchor: anchor); timeline.loadLater(anchor: anchor) }
        }
    }
    func release() {
        if operationKind == "overlap" {
            guard capture("overlapReleased") != nil else { return }
            phase = "held"
            Task { await source.release(.earlier); await source.release(.later) }
        } else { Task { await source.release(currentDirection) } }
    }
    func recordCorrection(_ delta: Double) { corrections.append(delta) }
    var restorationAnchor: CoachViewportAnchor? {
        uncompensated ? nil : readingAnchor
    }
    var diagnosticContext: (anchor: CoachViewportAnchor, phase: String, preserving: Bool, measuring: Bool, stationary: Bool)? {
        guard measurementActive || readingAnchor != nil, let anchor else { return nil }
        return (anchor, phase, readingAnchor != nil && !uncompensated, measurementActive, stationary)
    }
    func setScrollIdle(_ value: Bool) {
        scrollIdle = value
        if !value, !stationary {
            endReading(); correctionTarget = nil; resetStability(); phase = "settling"
        }
    }
    func goToEdge(_ direction: CoachPageDirection) {
        currentDirection = direction
        guard !stationary, let row = currentDirection == .earlier ? rows.first : rows.last else { return }
        endReading(); phase = "settling"; resetStability(); table?.reveal(row.id)
    }
    func revealMiddle() {
        guard !stationary, !rows.isEmpty else { return }
        endReading(); phase = "settling"; resetStability(); table?.reveal(rows[rows.count / 2].id)
    }
    func revealPhoto() {
        guard !stationary, let row = rows.first(where: { $0.sequence.isMultiple(of: 4) }) else { return }
        endReading(); phase = "settling"; resetStability(); table?.reveal(row.id)
    }
    func seekMiddle() {
        guard !stationary else { return }
        endReading(); phase = "loading"
        Task { await timeline.seek(.turn(CoachScrollSpikeSource.id(80))); phase = "settling"; resetStability() }
    }
    func overlap() {
        guard let anchor = capture("overlap", freeze: false) else { return }
        phase = "held"
        Task {
            await source.arm(.earlier); await source.arm(.later)
            timeline.loadEarlier(anchor: anchor); timeline.loadLater(anchor: anchor)
        }
    }
    func backgroundReply() {
        guard capture("backgroundReply") != nil else { return }
        phase = "applied"; resetStability()
        Task {
            await source.completeReply()
            timeline.apply(DiaryChanges(turnIDs: [CoachScrollSpikeSource.id(140)]))
        }
    }
    func completeImage() {
        guard let photo = visibleRows.first(where: { $0.sequence.isMultiple(of: 4) }) else { return }
        guard capture("thumbnail") != nil else { return }
        imageStressID = photo.id
        imageStressBeforeHeight = imageStressID.flatMap { table?.measuredHeight($0) }
        imageComplete = true; intrinsicImage.toggle(); phase = "applied"; resetStability()
    }
    func reflow() {
        guard let anchor = capture("reflow") else { return }
        readingAnchor = nil; measurementActive = false
        semanticID = anchor.rowID; largeText.toggle(); phase = "reflow"; resetStability()
        table?.semanticTarget = anchor.rowID
    }
    func armFocusTrial() { focusTrialArmed = true }
    func observedFocus(_ id: UUID?, origin: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        if origin == "AccessibilityFocusState" {
            recordFocusDiagnostic("focus-state", observedID: id)
        }
        if id != focusedID {
            focusedID = id
            focusEvents.append(["id": id?.uuidString ?? "", "origin": origin])
        }
    }
    func observeFocusNotification(_ event: Notification) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        recordFocusDiagnostic("notification", notification: event)
        if let element = event.userInfo?[UIAccessibility.focusedElementUserInfoKey] {
            // A positive target is authoritative immediately, including unrelated
            // or unmapped targets. Never substitute the previous/expected row.
            observedFocus(resolveFocusedExchange(element), origin: "UIAccessibilityPositiveTarget")
        } else {
            // UIKit emits separate previously-focused/currently-focused payloads.
            // Keep the raw interval; test actual current focus at every commit.
            pendingFocusLoss = true
        }
    }
    private func resolveFocusedExchange(_ element: Any?) -> UUID? {
        guard let object = element as? NSObject, let table, let window = table.window else { return nil }
        let frame = object.accessibilityFrame
        guard !frame.isEmpty, !frame.isNull, !frame.isInfinite,
              UIAccessibility.convertToScreenCoordinates(window.bounds, in: window).contains(frame) else { return nil }
        var current: Any? = object
        for _ in 0..<8 {
            guard let value = current as? NSObject else { break }
            if let nativeID = (value as? CoachSpikeTableCell)?.exchangeID,
               rows.contains(where: { $0.id == nativeID }) { return nativeID }
            if let identifier = (value as? UIAccessibilityIdentification)?.accessibilityIdentifier,
               let row = rows.first(where: { identifier.contains($0.id.uuidString) }) { return row.id }
            if let value = value as? UIAccessibilityElement { current = value.accessibilityContainer }
            else if let value = value as? UIView { current = value.superview }
            else { current = nil }
        }
        // SwiftUI AccessibilityNode exposes public frame/label but may expose no
        // identifier/container. Exact unique ownership by an actual cell is the
        // fallback; labels, speech, nearest and prior IDs are never consulted.
        return table.exchangeContainingFocusedFrame(frame)
    }
    private func observeCommittedFocus() {
        guard focusTrialActive, UIAccessibility.isVoiceOverRunning else { return }
        let current = UIAccessibility.focusedElement(using: .notificationVoiceOver)
        let id = resolveFocusedExchange(current)
        committedFocusQueries += 1
        if pendingFocusLoss || id != focusedID { recordFocusDiagnostic("committed-query", observedID: id) }
        observedFocus(id, origin: "CommittedVoiceOverQuery")
        pendingFocusLoss = false
    }
    private func recordFocusDiagnostic(_ kind: String, notification: Notification? = nil, observedID: UUID? = nil) {
        let focused = notification?.userInfo?[UIAccessibility.focusedElementUserInfoKey]
        let unfocused = notification?.userInfo?[UIAccessibility.unfocusedElementUserInfoKey]
        let queried = UIAccessibility.focusedElement(using: .notificationVoiceOver)
        let value: [String: Any] = ["kind": kind, "time": CACurrentMediaTime(), "phase": phase,
            "focusStage": focusStage, "revision": timeline.revision, "requestCount": timeline.requestedRanges.count,
            "observedID": observedID?.uuidString ?? "", "priorID": focusedID?.uuidString ?? "",
            "userInfoKeys": notification?.userInfo?.keys.map { String(describing: $0) }.sorted() ?? [],
            "focused": describeFocusElement(focused), "unfocused": describeFocusElement(unfocused),
            "queried": describeFocusElement(queried)]
        if focusDiagnostics.count == 32 { focusDiagnostics.removeFirst() }
        focusDiagnostics.append(value)
    }
    private func describeFocusElement(_ element: Any?) -> [[String: String]] {
        var current = element
        var chain: [[String: String]] = []
        for _ in 0..<8 {
            guard let object = current as? NSObject else { break }
            chain.append(["class": NSStringFromClass(type(of: object)),
                "identifier": (object as? UIAccessibilityIdentification)?.accessibilityIdentifier ?? "",
                "label": String((object.accessibilityLabel ?? "").prefix(240)),
                "frame": NSCoder.string(for: object.accessibilityFrame),
                "isFocused": String(object.accessibilityElementIsFocused()),
                "nativeExchangeID": (object as? CoachSpikeTableCell)?.exchangeID?.uuidString ?? ""])
            if let value = object as? UIAccessibilityElement { current = value.accessibilityContainer }
            else if let value = object as? UIView { current = value.superview }
            else { current = nil }
        }
        return chain
    }
    private func observePreLayout() {
        guard measurementActive, let anchor, let table else { return }
        if table.measuredFrames()[anchor.rowID] == nil { table.recordNative("pre-layout-anchor-missing") }
    }
    private func sample(at timestamp: CFTimeInterval) {
        if let table {
            viewport = CGRect(origin: .zero, size: table.bounds.size)
            contentOffset = table.contentOffset
            let measured = table.measuredFrames()
            if frames != measured { frames = measured }
        }
        observeCommittedFocus()
        maxEarlierInFlight = max(maxEarlierInFlight, timeline.window.reservations[.earlier] == nil ? 0 : 1)
        maxLaterInFlight = max(maxLaterInFlight, timeline.window.reservations[.later] == nil ? 0 : 1)
        guard scrollIdle, viewport.height > 0 else { resetStability(); return }
        let candidate = anchor?.rowID ?? visibleRows.first?.id
        guard let candidate, let rect = frames[candidate] else {
            if measurementActive, anchor != nil {
                everLost = true; currentlyMissing = true; lossCount += 1; after = nil
                table?.recordNative("committed-anchor-missing")
            }
            resetStability(); return
        }
        currentlyMissing = false
        let offset = rect.minY - viewport.minY
        if measurementActive, let before {
            after = offset; maxDrift = max(maxDrift, abs(offset - before))
            if abs(offset - before) > 2 { table?.recordNative("display-sample", sampledOffset: offset) }
        }
        if previousID == candidate, let previous, abs(previous.minY - rect.minY) <= 0.25, abs(previous.height - rect.height) <= 0.25 {
            stableFrames += 1
        } else { stableSince = timestamp; stableFrames = 1 }
        previous = rect; previousID = candidate
        guard stableFrames >= 3, timestamp - stableSince >= 0.1, correctionTarget == nil else { return }
        if phase == "settling" { phase = "ready" }
        if phase == "reflow" {
            phase = "complete"; stationary = false; after = offset
            let reflowAnchor = CoachViewportAnchor(rowID: candidate, offset: offset, focusedExchangeID: focusedID)
            readingAnchor = reflowAnchor; timeline.setViewport(.history(reflowAnchor))
        }
        if phase == "applied", after != nil {
            if focusStage == 1 {
                focusStage = 2; phase = "held"; resetStability()
                Task {
                    await source.arm(.later); await source.completeReply()
                    timeline.loadLater(anchor: anchor); await source.release(.later)
                }
            } else if focusStage == 2 {
                focusStage = 3; phase = "applied"; resetStability()
                timeline.apply(DiaryChanges(turnIDs: [CoachScrollSpikeSource.id(140)])); imageComplete = true
            } else { phase = "complete"; stationary = false }
        }
        if focusTrialArmed, focusedID != nil, phase == "ready" || phase == "complete" {
            focusTrialArmed = false; focusStage = 1
            focusTrialActive = true
            baselineFocusSequence = focusEvents.count; baselineFocusedID = focusedID
            arm(.earlier)
            Task { await source.release(.earlier) }
        }
    }
    private func endReading() {
        readingAnchor = nil; measurementActive = false; anchor = nil
    }
    private func resetStability() { stableFrames = 0; stableSince = 0; previous = nil; previousID = nil }
}
#endif
