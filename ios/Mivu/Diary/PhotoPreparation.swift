import Foundation
import Observation

@MainActor @Observable final class PhotoPreparation {
    private var limiter: PhotoWorkLimiter?
    init(limiter: PhotoWorkLimiter? = nil) { self.limiter = limiter }
    func use(limiter: PhotoWorkLimiter?) { self.limiter = limiter }
    private(set) var isPreparing = false
    private var generation: UUID?
    private var active = true
    var canCapture: Bool { active && !isPreparing }
    func begin() -> UUID {
        let id = UUID()
        guard active else { return id }
        generation = id; isPreparing = true
        return id
    }
    func isCurrent(_ id: UUID) -> Bool { generation == id && isPreparing }
    func load(_ id: UUID, using operation: @escaping @Sendable () async throws -> Data) async throws -> Data? {
        guard isCurrent(id), !Task.isCancelled else { return nil }
        let work: @Sendable () async throws -> Data = {
            let task = Task.detached(priority: .userInitiated) { try Task.checkCancellation(); return try await operation() }
            return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        }
        let data: Data
        if let limiter { data = try await limiter.withPermit(work) } else { data = try await work() }
        return isCurrent(id) && !Task.isCancelled ? data : nil
    }
    func finish(_ id: UUID) { if generation == id { generation = nil; isPreparing = false } }
    func cancel() { active = false; generation = nil; isPreparing = false }
}
