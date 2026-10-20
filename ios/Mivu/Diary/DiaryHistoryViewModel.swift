import Foundation
import Observation

struct DiaryHistoryScope: Equatable, Sendable {
    var selection: DiarySelectionOwnership
    var localDate: String?
    var changeGeneration: UInt64
}
enum DiaryHistoryPageStart: Equatable, Sendable { case latest, before(DiaryHistoryCursor) }
struct DiaryHistoryLoad: Sendable {
    var page: DiaryHistoryPage
    var coverage: [DayCompleteness: Int]
}
enum DiaryHistoryNavigation { case earlier, newer, latest }

@MainActor @Observable final class DiaryHistoryViewModel {
    private(set) var page: DiaryHistoryPage?
    private(set) var coverage: [DayCompleteness: Int] = [:]
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private let load: @Sendable (DiaryHistoryScope, DiaryHistoryPageStart) async throws -> DiaryHistoryLoad
    private var scope: DiaryHistoryScope?
    private var acceptedScope: DiaryHistoryScope?
    private var starts: [DiaryHistoryPageStart] = [.latest]
    private var pendingReload = false
    private var requestID = UUID()
    private var failedTarget: [DiaryHistoryPageStart]?

    var canLoadEarlier: Bool { ready && page?.hasMore == true && page?.cursor != nil }
    var canLoadNewer: Bool { ready && starts.count > 1 }
    var canLoadLatest: Bool { canLoadNewer }
    private var ready: Bool { !isLoading && scope != nil && acceptedScope == scope }

    init(load: @escaping @Sendable (DiaryHistoryScope, DiaryHistoryPageStart) async throws -> DiaryHistoryLoad) {
        self.load = load
    }
    func setScope(_ newScope: DiaryHistoryScope?) async {
        guard scope != newScope else { return }
        let retainRows = scope?.selection == newScope?.selection && scope?.localDate == newScope?.localDate && newScope != nil
        scope = newScope; requestID = UUID(); failedTarget = nil; errorMessage = nil
        if !retainRows { page = nil; coverage = [:]; acceptedScope = nil; starts = [.latest] }
        pendingReload = newScope != nil
        guard !isLoading, newScope != nil else { return }
        pendingReload = false
        await perform([.latest])
    }
    func navigate(_ direction: DiaryHistoryNavigation) async {
        let target: [DiaryHistoryPageStart]
        switch direction {
        case .earlier:
            guard canLoadEarlier, let cursor = page?.cursor else { return }
            target = starts + [.before(cursor)]
        case .newer:
            guard canLoadNewer else { return }
            target = Array(starts.dropLast())
        case .latest:
            guard canLoadLatest else { return }
            target = [.latest]
        }
        await perform(target)
    }
    func retry() async {
        guard !isLoading, let failedTarget, scope != nil else { return }
        await perform(failedTarget)
    }
    func invalidate() {
        scope = nil; acceptedScope = nil; requestID = UUID(); pendingReload = false
        page = nil; coverage = [:]; starts = [.latest]; failedTarget = nil; errorMessage = nil
    }
    private func perform(_ target: [DiaryHistoryPageStart]) async {
        guard !isLoading, let scope else { return }
        let id = UUID(); requestID = id; isLoading = true; errorMessage = nil
        do {
            let result = try await load(scope, target.last ?? .latest)
            if requestID == id && self.scope == scope {
                page = result.page; coverage = result.coverage; starts = target
                acceptedScope = scope; failedTarget = nil
            }
        } catch {
            if requestID == id && self.scope == scope {
                errorMessage = error.localizedDescription; failedTarget = target
            }
        }
        // Cancellation does not release the slot until the underlying loader actually exits.
        isLoading = false
        if pendingReload, self.scope != nil {
            pendingReload = false
            await perform([.latest])
        }
    }
}
