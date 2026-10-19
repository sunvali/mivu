import SwiftUI
import UIKit
import Testing
@testable import Mivu

private actor AccessibleCoachPageSource {
    let gate = Task10Gate()
    private(set) var calls = 0
    func page(_ request: CoachPageRequest, _: UUID) async throws -> CoachPage {
        calls += 1
        switch request {
        case .latest: return CoachTimelineTestData.page(21...40, total: 40)
        case .before:
            await gate.hold(0)
            return CoachTimelineTestData.page(1...20, total: 40)
        default: throw CoachQueryError.invalidCursor
        }
    }
}

private struct AccessibleCoachTimeline: View {
    @Bindable var model: CoachTimelineViewModel
    var onAccessibilityPageRequestReady: (@MainActor (@escaping CoachTimelineView.AccessibilityPageRequest) -> Void)? = nil
    var body: some View {
        CoachTimelineView(timeline: model,
            rows: model.exchanges.map { CoachTimelineRow(id: .exchange($0.id), exchange: $0) },
            onAccessibilityPageRequestReady: onAccessibilityPageRequestReady) { row in
                AnyView(Text(row.exchange?.text ?? "").frame(height: 70))
            }
    }
}

@Suite @MainActor struct CoachChatLayoutTests {
    private func waitFor(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition(), "Native timeline did not apply its current model")
    }
    private func table(in view: UIView) -> CoachTimelineTable? {
        if let table = view as? CoachTimelineTable { return table }
        return view.subviews.lazy.compactMap { table(in: $0) }.first
    }

    @Test func nativeAccessibilityPagingBridgePreservesReaderDeduplicatesAndRejectsExhaustedRequests() async throws {
        let source = AccessibleCoachPageSource()
        defer { Task { await source.gate.releaseAll() } }
        let model = CoachTimelineViewModel(source: { try await source.page($0, $1) })
        await model.loadLatest()
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 500)
        var requestPage: CoachTimelineView.AccessibilityPageRequest?
        window.rootViewController = UIHostingController(rootView: AccessibleCoachTimeline(model: model,
            onAccessibilityPageRequestReady: { requestPage = $0 }))
        window.makeKeyAndVisible()
        defer { window.rootViewController = nil; window.isHidden = true }
        try await waitFor { self.table(in: window)?.hasApplied(model) == true && requestPage != nil }
        let table = try #require(table(in: window))
        table.layoutIfNeeded()
        // The focusable toolbar action uses this same weak native paging callback.
        let anchor = try #require(table.measuredAnchor())
        #expect(table.accessibilityCustomActions?.contains { $0.name == "Load earlier messages" } == true)
        #expect(table.accessibilityCustomActions?.contains { $0.name == "Load later messages" } == false)
        let invoke = try #require(requestPage)
        #expect(invoke(.earlier))
        try await source.gate.waitForArrivals(1)
        #expect(!invoke(.earlier))
        #expect(await source.calls == 2)
        #expect(model.window.residentCount + model.window.reservedCapacity == 40)
        await source.gate.release(0)
        try await waitFor { table.hasApplied(model) && table.rows.count == 40 }
        table.layoutIfNeeded()
        let restored = try #require(table.measuredFrames()[anchor.rowID])
        #expect(abs(restored.minY - anchor.offset) <= 2)
        #expect(table.accessibilityCustomActions?.isEmpty != false)
        #expect(!invoke(.earlier))
        #expect(await source.calls == 2)
    }
}
