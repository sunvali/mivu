import SwiftUI
import UIKit

struct CoachTimelineRow: Equatable, Identifiable {
    enum Identity: Hashable { case exchange(UUID), segment(UUID) }
    let id: Identity
    var exchange: CoachExchangeSummary?
    var date: String?
    var targets: [CoachReceiptTarget] = []
    var activity: CoachActivity?
    var fixtureBanner = false
    var isHighlighted = false
}

/// One renderer: SwiftUI content in native self-sizing cells. It owns geometry only.
struct CoachTimelineView: UIViewRepresentable {
    let timeline: CoachTimelineViewModel
    let rows: [CoachTimelineRow]
    var diagnostics: CoachTimelineDiagnostics? = nil
    var jumpToLatest: (@MainActor () -> Void)? = nil
    typealias ViewportRefresh = @MainActor () -> Void
    typealias AccessibilityPageRequest = @MainActor (CoachPageDirection) -> Bool
    var onViewportRefreshReady: (@MainActor (@escaping ViewportRefresh) -> Void)? = nil
    var onAccessibilityPageRequestReady: (@MainActor (@escaping AccessibilityPageRequest) -> Void)? = nil
    var onReply: (@MainActor (CoachExchangeSummary) -> Void)? = nil
    let content: (CoachTimelineRow) -> AnyView
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> CoachTimelineTable {
        let table = CoachTimelineTable(frame: .zero, style: .plain)
        table.backgroundColor = .clear; table.separatorStyle = .none
        table.rowHeight = UITableView.automaticDimension; table.estimatedRowHeight = 200
        table.contentInsetAdjustmentBehavior = .never; table.keyboardDismissMode = .interactive
        table.accessibilityIdentifier = "coachViewport"
        table.register(CoachTimelineCell.self, forCellReuseIdentifier: "exchange")
        table.dataSource = context.coordinator; table.delegate = context.coordinator
        let replyPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.replyPan(_:)))
        replyPan.delegate = context.coordinator; table.addGestureRecognizer(replyPan)
        table.onViewport = { [weak coordinator = context.coordinator] in coordinator?.reportViewport() }
        context.coordinator.table = table
        context.coordinator.baselineCompletion()
        Task { @MainActor [weak table, weak coordinator = context.coordinator] in
            onViewportRefreshReady? { [weak table] in table?.refreshViewportNow() }
            onAccessibilityPageRequestReady? { [weak coordinator] direction in
                coordinator?.requestAccessibilityPage(direction) ?? false
            }
        }
        return table
    }
    func updateUIView(_ table: CoachTimelineTable, context: Context) {
        context.coordinator.owner = self
        context.coordinator.observeCompletion()
        let renderRevision = timeline.revision, renderIdentity = timeline.window.identity
        let isNewRender = !table.hasApplied(timeline)
        // UIKit callbacks may run before this accepted model revision reaches the table.
        table.appliedRevision = nil
        defer {
            table.appliedTimelineID = ObjectIdentifier(timeline)
            table.appliedIdentity = renderIdentity; table.appliedRevision = renderRevision
            table.appliedRenderCount += 1
            table.scheduleViewportReport()
        }
        #if DEBUG
        table.diagnostics = diagnostics; diagnostics?.attach(table, timeline: timeline)
        #endif
        let typeChanged = table.typeSize != nil && table.typeSize != typeSize
        let appearanceChanged = table.typeSize != typeSize || table.colorScheme != colorScheme
        context.coordinator.updateJumpButton(in: table, appearanceChanged: appearanceChanged)
        context.coordinator.updatePagingAccessibility(in: table)
        // A model revision carries a new command. Same-revision measurements are feedback,
        // not another scroll command to replay while the reader moves.
        if isNewRender {
            switch timeline.restoration {
            case .preserve(let anchor): table.readingAnchor = anchor; table.followsLatest = false
            case .latest: table.readingAnchor = nil; table.followsLatest = true
            case .none:
                if case .latest = timeline.window.viewport { table.followsLatest = true; table.readingAnchor = nil }
            }
        }
        if typeChanged, let anchor = table.readingAnchor {
            // Intentional font reflow keeps the same semantic exchange, not an obsolete pixel offset.
            table.readingAnchor = CoachViewportAnchor(rowID: anchor.focusedExchangeID ?? anchor.rowID, offset: 0,
                focusedExchangeID: anchor.focusedExchangeID)
        }
        guard table.rows != rows || appearanceChanged else {
            // Accepted navigation can change only restoration, even on an identical page.
            table.setNeedsLayout(); table.layoutIfNeeded(); table.restorePosition()
            return
        }
        let old = table.rows
        table.typeSize = typeSize; table.colorScheme = colorScheme
        table.isApplyingRows = true; table.rows = rows
        UIView.performWithoutAnimation {
            let oldIDs = Set(old.map(\.id)), newIDs = Set(rows.map(\.id))
            let removed = old.indices.filter { !newIDs.contains(old[$0].id) }.map { IndexPath(row: $0, section: 0) }
            let inserted = rows.indices.filter { !oldIDs.contains(rows[$0].id) }.map { IndexPath(row: $0, section: 0) }
            if old.isEmpty { table.reloadData() }
            else {
                table.beginUpdates()
                table.deleteRows(at: removed, with: .none); table.insertRows(at: inserted, with: .none)
                table.endUpdates()
                // Existing rows can change while adjacent rows are inserted/deleted.
                // Reconfigure their actual cell instead of replacing its identity.
                let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
                for cell in table.visibleCells.compactMap({ $0 as? CoachTimelineCell }) {
                    guard let id = cell.rowID, let row = rows.first(where: { $0.id == id }),
                          appearanceChanged || oldByID[id] != row else { continue }
                    context.coordinator.configure(cell, row: row)
                }
                table.beginUpdates(); table.endUpdates()
            }
            table.setNeedsLayout(); table.layoutIfNeeded()
            table.isApplyingRows = false
            table.restorePosition()
        }
    }

    @MainActor final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate {
        var owner: CoachTimelineView
        weak var table: CoachTimelineTable?
        private var completionBaselineSet = false
        private var lastCompletion: UUID?
        private var previousDragOffset: CGFloat?
        private var dragDirection: CoachPageDirection?
        func baselineCompletion() { lastCompletion = owner.timeline.completedPageRequestID; completionBaselineSet = true }
        func observeCompletion() {
            let completed = owner.timeline.completedPageRequestID
            defer { lastCompletion = completed; completionBaselineSet = true }
            guard completionBaselineSet, let completed, completed != lastCompletion else { return }
            UIAccessibility.post(notification: .announcement, argument: "Conversation page loaded")
        }
        init(_ owner: CoachTimelineView) { self.owner = owner }
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { (tableView as! CoachTimelineTable).rows.count }
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let table = tableView as! CoachTimelineTable; self.table = table
            let cell = table.dequeueReusableCell(withIdentifier: "exchange", for: indexPath) as! CoachTimelineCell
            configure(cell, row: table.rows[indexPath.row]); return cell
        }
        // Swipe right to reply, as in Messages: the row follows the finger, an arrow fades in,
        // a light tap marks the threshold, and the row springs back.
        private var swipingCell: CoachTimelineCell?
        private var swipeArmed = false
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer, owner.onReply != nil, let table else { return false }
            let velocity = pan.velocity(in: table)
            return velocity.x > 0 && velocity.x > abs(velocity.y) * 2 && replyTurn(at: pan.location(in: table)) != nil
        }
        private func replyTurn(at point: CGPoint) -> (CoachTimelineCell, CoachExchangeSummary)? {
            guard let table, let path = table.indexPathForRow(at: point), table.rows.indices.contains(path.row),
                  let turn = table.rows[path.row].exchange, let cell = table.cellForRow(at: path) as? CoachTimelineCell else { return nil }
            return (cell, turn)
        }
        @objc func replyPan(_ pan: UIPanGestureRecognizer) {
            guard let table else { return }
            let threshold: CGFloat = 64
            switch pan.state {
            case .began:
                swipingCell = replyTurn(at: pan.location(in: table))?.0; swipeArmed = false
                swipingCell?.replyIconY = swipingCell.map { pan.location(in: $0).y }
            case .changed:
                let x = max(0, pan.translation(in: table).x)
                let offset = min(x, threshold) + max(0, x - threshold) * 0.15
                swipingCell?.setReplyOffset(offset, progress: min(1, x / threshold))
                if (x >= threshold) != swipeArmed {
                    swipeArmed.toggle()
                    if swipeArmed { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                }
            default:
                let cell = swipingCell
                if pan.state == .ended, swipeArmed, let turn = replyTurn(at: pan.location(in: table))?.1 ?? cell?.rowID.flatMap({ id in
                    table.rows.first { $0.id == id }?.exchange }) { owner.onReply?(turn) }
                swipingCell = nil; swipeArmed = false
                let reset: () -> Void = { cell?.setReplyOffset(0, progress: 0) }
                if UIAccessibility.isReduceMotionEnabled { UIView.animate(withDuration: 0.2, animations: reset) }
                else { UIView.animate(springDuration: 0.4, bounce: 0.25, animations: reset) }
            }
        }
        func updateJumpButton(in table: CoachTimelineTable, appearanceChanged: Bool) {
            guard owner.jumpToLatest != nil else {
                table.jumpButton?.removeFromSuperview(); table.jumpButton = nil; return
            }
            guard table.jumpButton == nil || appearanceChanged else { return }
            var configuration = UIButton.Configuration.glass()
            configuration.image = UIImage(systemName: "arrow.down")
            configuration.cornerStyle = .capsule
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
            configuration.baseForegroundColor = UIColor(Color.diaryAccent)
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
            if let button = table.jumpButton as? UIButton { button.configuration = configuration }
            else {
                let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in self?.owner.jumpToLatest?() })
                button.accessibilityIdentifier = "coachNewMessage"
                button.accessibilityLabel = String(localized: "Jump to latest")
                button.translatesAutoresizingMaskIntoConstraints = false
                table.addSubview(button); table.jumpButton = button
                NSLayoutConstraint.activate([
                    button.centerXAnchor.constraint(equalTo: table.frameLayoutGuide.centerXAnchor),
                    button.bottomAnchor.constraint(equalTo: table.frameLayoutGuide.bottomAnchor, constant: -8),
                    button.leadingAnchor.constraint(greaterThanOrEqualTo: table.frameLayoutGuide.leadingAnchor, constant: 16),
                    button.trailingAnchor.constraint(lessThanOrEqualTo: table.frameLayoutGuide.trailingAnchor, constant: -16),
                    button.widthAnchor.constraint(equalToConstant: 48),
                    button.heightAnchor.constraint(equalToConstant: 48)
                ])
            }
            if let button = table.jumpButton {
                button.overrideUserInterfaceStyle = owner.colorScheme == .dark ? .dark : .light
                table.bringSubviewToFront(button)
            }
        }
        func configure(_ cell: CoachTimelineCell, row: CoachTimelineRow) {
            cell.rowID = row.id; cell.selectionStyle = .none; cell.backgroundColor = .clear
            cell.contentConfiguration = UIHostingConfiguration {
                owner.content(row).dynamicTypeSize(owner.typeSize).environment(\.colorScheme, owner.colorScheme)
            }.margins(.horizontal, 20).margins(.vertical, 8)
        }
        func updatePagingAccessibility(in table: CoachTimelineTable) {
            table.accessibilityCustomActions = [CoachPageDirection.earlier, .later].compactMap { direction in
                let name: String
                switch owner.timeline.window.edgeState(direction) {
                case .available: name = direction == .earlier ? "Load earlier messages" : "Load later messages"
                case .failed: name = direction == .earlier ? "Retry earlier messages" : "Retry later messages"
                case .loading, .exhausted: return nil
                }
                return UIAccessibilityCustomAction(name: name) { [weak self] _ in
                    self?.requestAccessibilityPage(direction) ?? false
                }
            }
        }
        func requestAccessibilityPage(_ direction: CoachPageDirection) -> Bool {
            guard let table, table.hasApplied(owner.timeline), !table.isApplyingRows,
                  let anchor = table.measuredAnchor() else { return false }
            switch owner.timeline.window.edgeState(direction) {
            case .loading, .exhausted: return false
            case .available, .failed: break
            }
            table.followsLatest = false; table.readingAnchor = anchor
            reportViewport()
            let request = direction == .earlier ? owner.timeline.loadEarlier(anchor: anchor) : owner.timeline.loadLater(anchor: anchor)
            return request != nil
        }
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            guard let table = scrollView as? CoachTimelineTable else { return }
            #if DEBUG
            table.diagnostics?.recordPan("begin", table: table)
            #endif
            table.readingAnchor = nil; table.followsLatest = false
            previousDragOffset = table.contentOffset.y; dragDirection = nil
            reportViewport()
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let table = scrollView as? CoachTimelineTable else { return }
            if table.isTracking || table.isDragging || table.isDecelerating {
                #if DEBUG
                table.diagnostics?.recordPan("scroll", table: table)
                #endif
                if let previousDragOffset, abs(table.contentOffset.y - previousDragOffset) > 0.25 {
                    dragDirection = table.contentOffset.y < previousDragOffset ? .earlier : .later
                }
                previousDragOffset = table.contentOffset.y
                reportViewport()
                if let dragDirection { requestPageNearEdge(dragDirection) }
            } else { table.restorePosition(); table.scheduleViewportReport() }
        }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            #if DEBUG
            if let table { table.diagnostics?.recordPan("endDrag", table: table) }
            #endif
            if !decelerate { finishedScroll() }
        }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            #if DEBUG
            if let table { table.diagnostics?.recordPan("endDeceleration", table: table) }
            #endif
            finishedScroll()
        }
        private func finishedScroll() {
            defer { previousDragOffset = nil; dragDirection = nil }
            guard let table, table.hasApplied(owner.timeline) else { return }
            table.followsLatest = owner.timeline.window.pages.last?.hasLater == false && table.contentSize.height - table.contentOffset.y - table.bounds.height <= 80
            reportViewport()
            table.readingAnchor = table.followsLatest ? nil : table.measuredAnchor()
            // At capacity, the same reservation can succeed only after interaction pins settle.
            if let dragDirection { requestPageNearEdge(dragDirection) }
        }
        @discardableResult func requestPageNearEdge(_ direction: CoachPageDirection) -> Task<Void, Never>? {
            guard let table, table.hasApplied(owner.timeline), !table.isApplyingRows,
                  owner.timeline.window.edgeState(direction) == .available,
                  let edge = direction == .earlier ? table.rows.first : table.rows.last,
                  let cell = table.visibleCells.compactMap({ $0 as? CoachTimelineCell }).first(where: { $0.rowID == edge.id }),
                  let anchor = table.measuredAnchor() else { return nil }
            let frame = cell.convert(cell.bounds, to: table).offsetBy(dx: -table.bounds.minX, dy: -table.bounds.minY)
            let near = direction == .earlier ? abs(frame.minY) <= 200 : abs(frame.maxY - table.bounds.height) <= 200
            guard near else { return nil }
            // Reservation/deduplication, failure retry and eviction remain the window's responsibility.
            return direction == .earlier ? owner.timeline.loadEarlier(anchor: anchor) : owner.timeline.loadLater(anchor: anchor)
        }
        func reportViewport() {
            guard let table, table.hasApplied(owner.timeline), !table.isApplyingRows, let anchor = table.measuredAnchor() else { return }
            let interacting = table.isDragging || table.isDecelerating || table.isTracking
            let mode: CoachViewportMode = table.followsLatest ? .latest : .history(anchor)
            let visibleIDs = Set(table.measuredFrames().keys), current = owner.timeline.window
            // Equal geometry must not feed another observation/layout/report cycle.
            guard current.viewport != mode || current.viewportAnchor != anchor ||
                    current.visibleIDs != visibleIDs || current.isInteracting != interacting else { return }
            table.viewportPublicationCount += 1
            owner.timeline.setViewport(mode, visibleIDs: visibleIDs, isInteracting: interacting, measuredAnchor: anchor)
        }
    }
}

final class CoachTimelineCell: UITableViewCell {
    var rowID: CoachTimelineRow.Identity?
    /// The arrow appears beside the finger, so it sits next to the message being swiped in a tall exchange.
    var replyIconY: CGFloat?
    private lazy var replyIcon: UIImageView = {
        let icon = UIImageView(image: UIImage(systemName: "arrowshape.turn.up.left.fill",
            withConfiguration: UIImage.SymbolConfiguration(textStyle: .subheadline, scale: .medium)))
        icon.tintColor = .secondaryLabel; icon.contentMode = .center; icon.alpha = 0
        icon.backgroundColor = .tertiarySystemFill; icon.layer.cornerRadius = 16; icon.isAccessibilityElement = false
        insertSubview(icon, belowSubview: contentView)
        return icon
    }()
    func setReplyOffset(_ offset: CGFloat, progress: CGFloat) {
        contentView.transform = CGAffineTransform(translationX: offset, y: 0)
        let y = min(max(replyIconY ?? bounds.midY, 24), bounds.height - 24)
        replyIcon.bounds = CGRect(x: 0, y: 0, width: 32, height: 32); replyIcon.center = CGPoint(x: 28, y: y)
        replyIcon.alpha = progress
        let scale = 0.6 + 0.4 * progress
        replyIcon.transform = CGAffineTransform(scaleX: scale, y: scale)
    }
    override func prepareForReuse() { super.prepareForReuse(); setReplyOffset(0, progress: 0) }
}

final class CoachTimelineTable: UITableView {
    var rows: [CoachTimelineRow] = []
    var typeSize: DynamicTypeSize?
    var colorScheme: ColorScheme?
    var jumpButton: UIView?
    var readingAnchor: CoachViewportAnchor?
    var followsLatest = true
    var isApplyingRows = false
    var viewportPublicationCount = 0
    var appliedRenderCount = 0
    var appliedRevision: Int?
    var appliedTimelineID: ObjectIdentifier?
    var appliedIdentity: CoachTimelineIdentity?
    func hasApplied(_ timeline: CoachTimelineViewModel) -> Bool {
        appliedTimelineID == ObjectIdentifier(timeline) && appliedIdentity == timeline.window.identity && appliedRevision == timeline.revision
    }
    var onViewport: (() -> Void)?
    private var restoring = false
    private var layingOut = false
    private var reportScheduled = false
    #if DEBUG
    weak var diagnostics: CoachTimelineDiagnostics?
    #endif
    private var accessibleJump: UIView? {
        guard let jumpButton, jumpButton.superview === self, !jumpButton.isHidden, jumpButton.alpha > 0 else { return nil }
        return jumpButton
    }
    override func accessibilityElementCount() -> Int {
        let count = super.accessibilityElementCount()
        guard count >= 0, count != NSNotFound, accessibleJump != nil else { return count }
        return count + 1
    }
    override func accessibilityElement(at index: Int) -> Any? {
        let count = super.accessibilityElementCount()
        if index == count, let button = accessibleJump { return button }
        return super.accessibilityElement(at: index)
    }
    override func index(ofAccessibilityElement element: Any) -> Int {
        if let button = accessibleJump, let view = element as? UIView, view === button {
            return super.accessibilityElementCount()
        }
        return super.index(ofAccessibilityElement: element)
    }
    override func layoutSubviews() {
        guard !layingOut else { super.layoutSubviews(); return }
        layingOut = true; super.layoutSubviews(); layingOut = false
        if let jumpButton { bringSubviewToFront(jumpButton) }
        restorePosition(); scheduleViewportReport()
    }
    func restorePosition() {
        guard !restoring, !layingOut, !isApplyingRows, !isTracking, !isDragging, !isDecelerating else { return }
        restoring = true; defer { restoring = false }
        #if DEBUG
        if diagnostics?.uncompensated == true { return }
        #endif
        if followsLatest {
            let y = max(-adjustedContentInset.top, contentSize.height - bounds.height + adjustedContentInset.bottom)
            if abs(contentOffset.y - y) > 0.25 { setContentOffset(CGPoint(x: contentOffset.x, y: y), animated: false) }
            return
        }
        guard let anchor = readingAnchor else { return }
        for _ in 0..<8 {
            super.layoutSubviews()
            // Actual visible stable-ID cell geometry is the correction source.
            if let frame = measuredFrames()[anchor.rowID] {
                let delta = frame.minY - anchor.offset
                guard abs(delta) > 0.25 else { return }
                setContentOffset(CGPoint(x: contentOffset.x, y: max(-adjustedContentInset.top, contentOffset.y + delta)), animated: false)
            } else if let index = rows.firstIndex(where: { $0.id == .exchange(anchor.rowID) }) {
                // Realize the target first; estimated row rectangles are never measurement evidence.
                scrollToRow(at: IndexPath(row: index, section: 0), at: .top, animated: false)
            } else { return }
        }
    }
    func measuredFrames() -> [UUID: CGRect] {
        Dictionary(uniqueKeysWithValues: visibleCells.compactMap { cell -> (UUID, CGRect)? in
            guard let cell = cell as? CoachTimelineCell, case .exchange(let id) = cell.rowID,
                  rows.contains(where: { $0.id == .exchange(id) }) else { return nil }
            let rect = cell.convert(cell.bounds, to: self).offsetBy(dx: -bounds.minX, dy: -bounds.minY)
            guard rect.intersection(CGRect(origin: .zero, size: bounds.size)).height > 0 else { return nil }
            return (id, rect)
        })
    }
    func measuredLastRowBottom() -> CGFloat? {
        guard let last = rows.last?.id,
              let cell = visibleCells.compactMap({ $0 as? CoachTimelineCell }).first(where: { $0.rowID == last }) else { return nil }
        return cell.convert(cell.bounds, to: self).maxY - bounds.minY
    }
    func measuredAnchor() -> CoachViewportAnchor? {
        let frames = measuredFrames()
        let visible = rows.compactMap { row -> (UUID, CGRect)? in
            guard case .exchange(let id) = row.id, let frame = frames[id] else { return nil }; return (id, frame)
        }
        guard let value = visible.first(where: { min($0.1.maxY, bounds.height) - max($0.1.minY, 0) >= 44 }) ?? visible.first else { return nil }
        return CoachViewportAnchor(rowID: value.0, offset: value.1.minY, focusedExchangeID: focusedExchange())
    }
    func refreshViewportNow() { onViewport?() }
    override func accessibilityElementDidBecomeFocused() { super.accessibilityElementDidBecomeFocused(); onViewport?() }
    func focusedExchange() -> UUID? {
        guard UIAccessibility.isVoiceOverRunning else { return nil }
        return exchange(containing: UIAccessibility.focusedElement(using: .notificationVoiceOver))
    }
    func exchange(containing element: Any?) -> UUID? {
        guard let object = element as? NSObject, let window else { return nil }
        let frame = object.accessibilityFrame
        guard !frame.isEmpty, !frame.isNull, !frame.isInfinite,
              UIAccessibility.convertToScreenCoordinates(window.bounds, in: window).contains(frame) else { return nil }
        var current: NSObject? = object
        for _ in 0..<8 {
            guard let value = current else { break }
            if let view = value as? UIView, let jumpButton,
               view === jumpButton || view.isDescendant(of: jumpButton) { return nil }
            if (value as? UIAccessibilityIdentification)?.accessibilityIdentifier == "coachNewMessage" { return nil }
            if let cell = value as? CoachTimelineCell, case .exchange(let id) = cell.rowID { return id }
            if let identifier = (value as? UIAccessibilityIdentification)?.accessibilityIdentifier,
               let row = rows.first(where: { row in if case .exchange(let id) = row.id { return identifier.contains(id.uuidString) }; return false }),
               case .exchange(let id) = row.id { return id }
            if let value = value as? UIAccessibilityElement { current = value.accessibilityContainer as? NSObject }
            else if let value = value as? UIView { current = value.superview }
            else { current = nil }
        }
        let matches = visibleCells.compactMap { cell -> UUID? in
            guard let cell = cell as? CoachTimelineCell, case .exchange(let id) = cell.rowID,
                  cell.window === window, UIAccessibility.convertToScreenCoordinates(cell.bounds, in: cell).contains(frame) else { return nil }
            return id
        }
        return matches.count == 1 ? matches[0] : nil
    }
    func scheduleViewportReport() {
        guard !reportScheduled else { return }; reportScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }; reportScheduled = false; onViewport?()
        }
    }
}
