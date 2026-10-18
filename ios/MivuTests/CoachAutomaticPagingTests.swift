import SwiftUI
import UIKit
import Testing
@testable import Mivu

private actor AutomaticPageSource {
    let total: Int
    let firstEdgeGate: Task10Gate?
    private var failedFirstEdge = false
    private(set) var calls = 0
    init(total: Int, firstEdgeGate: Task10Gate? = nil) { self.total = total; self.firstEdgeGate = firstEdgeGate }
    func page(_ request: CoachPageRequest, _: UUID) async throws -> CoachPage {
        calls += 1
        if case .before = request, let firstEdgeGate, !failedFirstEdge {
            failedFirstEdge = true
            await firstEdgeGate.hold(0)
            throw CoachQueryError.invalidCursor
        }
        let upper: Int
        switch request {
        case .latest: upper = total
        case .aroundTurn(let id): upper = id == CoachTimelineTestData.id(1) ? 20 : total
        case .before(let cursor): upper = Int(cursor.sequence) - 1
        default: throw CoachQueryError.invalidCursor
        }
        return CoachTimelineTestData.page(max(1, upper - 19)...upper, total: total)
    }
}

private struct AutomaticPageHost: View {
    @Bindable var model: CoachTimelineViewModel
    var jumpAction: (@MainActor () -> Void)? = nil
    var textSize: DynamicTypeSize = .large
    var body: some View {
        CoachTimelineView(timeline: model, rows: model.exchanges.map { CoachTimelineRow(id: .exchange($0.id), exchange: $0) }, jumpToLatest: jumpAction) { row in
            AnyView(Text(row.exchange?.text ?? "").frame(height: 70))
        }.dynamicTypeSize(textSize)
    }
}

@Suite @MainActor struct CoachAutomaticPagingTests {
    private func waitFor(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition(), "Native paging bridge did not reach its measured layout")
    }
    private func table(in view: UIView) -> CoachTimelineTable? {
        if let value = view as? CoachTimelineTable { return value }
        return view.subviews.lazy.compactMap { table(in: $0) }.first
    }
    private func mount(_ model: CoachTimelineViewModel, jumpAction: (@MainActor () -> Void)? = nil) async throws -> (UIWindow, CoachTimelineTable, CoachTimelineView.Coordinator) {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 500)
        window.rootViewController = UIHostingController(rootView: AutomaticPageHost(model: model, jumpAction: jumpAction)); window.makeKeyAndVisible()
        try await waitFor { self.table(in: window)?.rows.isEmpty == false }
        let table = try #require(table(in: window)), coordinator = try #require(table.delegate as? CoachTimelineView.Coordinator)
        table.layoutIfNeeded()
        return (window, table, coordinator)
    }
    private func revealStart(_ table: CoachTimelineTable, coordinator: CoachTimelineView.Coordinator) {
        table.followsLatest = false; table.readingAnchor = nil
        table.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false)
        table.layoutIfNeeded(); coordinator.reportViewport()
        table.readingAnchor = table.measuredAnchor()
    }
    private func revealExchange(_ number: Int, table: CoachTimelineTable, coordinator: CoachTimelineView.Coordinator) throws {
        let id = CoachTimelineTestData.id(number)
        let index = try #require(table.rows.firstIndex { $0.id == .exchange(id) })
        table.followsLatest = false; table.readingAnchor = nil
        table.scrollToRow(at: IndexPath(row: index, section: 0), at: .top, animated: false)
        table.layoutIfNeeded(); coordinator.reportViewport()
        table.readingAnchor = table.measuredAnchor()
        let frame = try #require(table.measuredFrames()[id])
        #expect(abs(frame.minY) <= 2)
    }
    @Test func floatingJumpBelongsToNativePanOwnerAndCannotPinUnderlyingExchange() async throws {
        let source = AutomaticPageSource(total: 140)
        let model = CoachTimelineViewModel(source: { try await source.page($0, $1) })
        await model.loadLatest()
        let (window, table, coordinator) = try await mount(model, jumpAction: {})
        defer { window.rootViewController = nil; window.isHidden = true }
        try revealExchange(131, table: table, coordinator: coordinator)
        table.layoutIfNeeded()
        let jump = try #require(table.jumpButton as? UIButton)
        #expect(jump.isDescendant(of: table))
        #expect(jump.bounds.height >= 44)
        #expect(jump.bounds.width > jump.bounds.height)
        let label = try #require(jump.titleLabel), text = try #require(label.text), font = try #require(label.font)
        #expect(text == "Jump to latest")
        let naturalTextWidth = (text as NSString).size(withAttributes: [.font: font]).width
        #expect(label.bounds.width + 1 >= naturalTextWidth)
        let frame = jump.convert(jump.bounds, to: window)
        let point = CGPoint(x: frame.midX, y: frame.midY)
        let hit = try #require(window.hitTest(point, with: nil))
        #expect(hit.isDescendant(of: table))
        #expect(hit === jump || hit.isDescendant(of: jump))
        #expect(table.panGestureRecognizer.view === table)
        let focusedControl = UIAccessibilityElement(accessibilityContainer: jump)
        focusedControl.accessibilityFrame = UIAccessibility.convertToScreenCoordinates(jump.bounds, in: jump)
        #expect(table.exchange(containing: focusedControl) == nil)
        table.readingAnchor = nil
        table.setContentOffset(CGPoint(x: 0, y: table.contentOffset.y + 43), animated: false)
        table.layoutIfNeeded()
        #expect(abs(jump.convert(jump.bounds, to: window).minY - frame.minY) <= 2)
        let contentHeight = table.contentSize.height
        coordinator.owner.jumpToLatest = nil
        coordinator.updateJumpButton(in: table, appearanceChanged: false)
        table.layoutIfNeeded()
        #expect(table.contentSize.height == contentHeight)
        let defaultCount = table.accessibilityElementCount()
        // Preserve only the old valid prefix. With zero default rows, index0 is the appended button.
        let originalRow: Any? = defaultCount > 0 ? table.accessibilityElement(at: 0) : nil
        let originalIndex = originalRow.map { table.index(ofAccessibilityElement: $0) }
        coordinator.owner.jumpToLatest = {}
        coordinator.updateJumpButton(in: table, appearanceChanged: false)
        table.layoutIfNeeded()
        let visibleJump = try #require(table.jumpButton)
        #expect(table.accessibilityElementCount() == defaultCount + 1)
        #expect((table.accessibilityElement(at: defaultCount) as? UIView) === visibleJump)
        #expect(table.index(ofAccessibilityElement: visibleJump) == defaultCount)
        if defaultCount > 0 {
            #expect((table.accessibilityElement(at: 0) == nil) == (originalRow == nil))
            if let originalRow, let originalIndex {
                #expect(table.index(ofAccessibilityElement: originalRow) == originalIndex)
            }
        }
        await model.seek(.turn(CoachTimelineTestData.id(1)))
        try await waitFor { table.hasApplied(model) && table.rows.first?.exchange?.id == CoachTimelineTestData.id(1) }
        let replacedJump = try #require(table.jumpButton)
        #expect(replacedJump === visibleJump && replacedJump.superview === table)
        #expect(table.accessibilityElementCount() == defaultCount + 1)
        #expect((table.accessibilityElement(at: defaultCount) as? UIView) === replacedJump)
        #expect(table.index(ofAccessibilityElement: replacedJump) == defaultCount)
        let host = try #require(window.rootViewController as? UIHostingController<AutomaticPageHost>)
        host.rootView = AutomaticPageHost(model: model, jumpAction: {}, textSize: .accessibility5)
        try await waitFor { table.typeSize == .accessibility5 }
        table.layoutIfNeeded()
        let largeButton = try #require(table.jumpButton as? UIButton), largeLabel = try #require(largeButton.titleLabel)
        #expect(largeButton.bounds.width <= table.bounds.width - 32 + 1)
        let fitting = largeLabel.sizeThatFits(CGSize(width: largeLabel.bounds.width, height: .greatestFiniteMagnitude))
        #expect(largeLabel.bounds.height + 1 >= fitting.height)
        #expect(largeButton.bounds.height >= 44)
    }
    @Test func unappliedModelRevisionCannotPublishOldNativeViewport() async throws {
        let source = AutomaticPageSource(total: 140)
        let model = CoachTimelineViewModel(source: { try await source.page($0, $1) })
        await model.loadLatest()
        let (window, table, coordinator) = try await mount(model)
        defer { window.rootViewController = nil; window.isHidden = true }
        try revealExchange(131, table: table, coordinator: coordinator)
        let oldViewport = model.window.viewport, publications = table.viewportPublicationCount
        let requestedAnchor = CoachTimelineTestData.anchor(130)
        // Reservation changes the model synchronously, before SwiftUI can reconcile UIKit.
        let pendingResult = model.loadEarlier(anchor: requestedAnchor)
        let pending = try #require(pendingResult)
        #expect(!table.hasApplied(model))
        coordinator.reportViewport()
        #expect(model.restoration == .preserve(requestedAnchor))
        #expect(model.window.viewport == oldViewport)
        #expect(table.viewportPublicationCount == publications)
        await pending.value
        try await waitFor { table.hasApplied(model) }
    }
    @Test func repeatedSamePageSeekAndReaderFeedbackKeepActualNativePosition() async throws {
        let source = AutomaticPageSource(total: 140)
        let model = CoachTimelineViewModel(source: { try await source.page($0, $1) })
        await model.loadLatest()
        let (window, table, coordinator) = try await mount(model)
        defer { window.rootViewController = nil; window.isHidden = true }
        let resident = model.exchanges.map(\.id), target = CoachTimelineTestData.id(130)
        for _ in 0..<2 {
            try revealExchange(131, table: table, coordinator: coordinator)
            await model.seek(.turn(target))
            try await waitFor {
                table.hasApplied(model) && abs(table.measuredFrames()[target]?.minY ?? .infinity) <= 2
            }
            #expect(model.exchanges.map(\.id) == resident)
            #expect(table.readingAnchor?.rowID == target)
            // Real coordinator interaction boundaries: measurements must not reinstall a prior sample.
            coordinator.scrollViewWillBeginDragging(table)
            for _ in 0..<2 {
                let desired = table.contentOffset.y + 43
                let renderCount = table.appliedRenderCount
                table.setContentOffset(CGPoint(x: 0, y: desired), animated: false)
                coordinator.reportViewport()
                // Observe an actual representable reconciliation, not a guessed scheduling delay.
                try await waitFor { table.appliedRenderCount > renderCount }
                table.layoutIfNeeded()
                #expect(table.readingAnchor == nil)
                #expect(abs(table.contentOffset.y - desired) <= 2)
            }
            coordinator.scrollViewDidEndDragging(table, willDecelerate: false)
            let settled = try #require(table.measuredAnchor())
            table.layoutIfNeeded()
            #expect(table.readingAnchor?.rowID == settled.rowID)
            #expect(abs((table.measuredFrames()[settled.rowID]?.minY ?? .infinity) - settled.offset) <= 2)
            #expect(model.window.viewportAnchor == table.measuredAnchor())
        }
    }
    @Test func measuredAutomaticEdgeDeduplicatesAndRequiresExplicitFailureRetry() async throws {
        let gate = Task10Gate(), source = AutomaticPageSource(total: 40, firstEdgeGate: gate)
        defer { Task { await gate.releaseAll() } }
        let model = CoachTimelineViewModel(source: { try await source.page($0, $1) })
        await model.loadLatest()
        let (window, table, coordinator) = try await mount(model)
        defer { window.rootViewController = nil; window.isHidden = true }
        revealStart(table, coordinator: coordinator)
        let loading = try #require(coordinator.requestPageNearEdge(.earlier))
        try await gate.waitForArrivals(1)
        for _ in 0..<5 { #expect(coordinator.requestPageNearEdge(.earlier) == nil) }
        #expect(await source.calls == 2)
        #expect(model.window.residentCount + model.window.reservedCapacity == 40)
        await gate.release(0); await loading.value
        if case .failed = model.window.edgeState(.earlier) {} else { Issue.record("Expected the actual failed edge") }
        #expect(coordinator.requestPageNearEdge(.earlier) == nil)
        #expect(await source.calls == 2)
        let retryResult = model.loadEarlier(anchor: table.measuredAnchor())
        let retry = try #require(retryResult); await retry.value
        try await waitFor { table.rows.count == 40 }
        revealStart(table, coordinator: coordinator)
        #expect(model.window.edgeState(.earlier) == .exhausted)
        #expect(coordinator.requestPageNearEdge(.earlier) == nil)
        #expect(await source.calls == 3)
    }
    @Test func measuredAutomaticEdgeDefersAtCapacityUntilInteractionEnds() async throws {
        let source = AutomaticPageSource(total: 160)
        let model = CoachTimelineViewModel(source: { try await source.page($0, $1) })
        await model.loadLatest()
        for _ in 0..<4 {
            let first = try #require(model.exchanges.first)
            let anchor = CoachTimelineTestData.anchor(Int(first.sequence))
            let earlierResult = model.loadEarlier(anchor: anchor)
            let earlier = try #require(earlierResult); await earlier.value
        }
        let (window, table, coordinator) = try await mount(model)
        defer { window.rootViewController = nil; window.isHidden = true }
        revealStart(table, coordinator: coordinator)
        let anchor = try #require(table.measuredAnchor()), visible = Set(table.measuredFrames().keys)
        model.setViewport(.history(anchor), visibleIDs: visible, isInteracting: true, measuredAnchor: anchor)
        #expect(coordinator.requestPageNearEdge(.earlier) == nil)
        #expect(model.window.residentCount == 100 && model.window.reservedCapacity == 0)
        #expect(await source.calls == 5)
        model.setViewport(.history(anchor), visibleIDs: visible, isInteracting: false, measuredAnchor: anchor)
        let loading = try #require(coordinator.requestPageNearEdge(.earlier))
        #expect(model.window.residentCount == 80 && model.window.reservedCapacity == 20)
        #expect(model.window.residentCount + model.window.reservedCapacity == 100)
        await loading.value
        #expect(model.window.residentCount == 100 && model.window.reservedCapacity == 0)
        #expect(!model.exchanges.contains { $0.sequence == 160 })
        #expect(model.peakCapacity <= 100)
    }
}
