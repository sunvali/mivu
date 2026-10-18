import Foundation
import CoreGraphics
import ImageIO

struct DiaryPhotoScope: Hashable, Sendable {
    let identity: CoachTimelineIdentity
    let selectionEpoch: UInt64
}

struct DiaryPhotoThumbnail: Sendable {
    let image: CGImage
    let decodedCost: Int

    init(image: CGImage) throws {
        let cost = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard !cost.overflow, cost.partialValue > 0 else { throw DiaryPhotoError.invalidImage }
        self.image = image
        decodedCost = cost.partialValue
    }
}

enum DiaryPhotoError: Error, Equatable {
    case invalidSize, invalidImage, staleRequest
}

actor PhotoWorkLimiter {
    struct Statistics: Equatable, Sendable {
        var active = 0
        var queued = 0
        var peakActive = 0
    }
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    private var state = Statistics()
    private var waiters: [Waiter] = []
    private let observe: (@Sendable (Statistics) -> Void)?

    init(observe: (@Sendable (Statistics) -> Void)? = nil) { self.observe = observe }

    func withPermit<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        let value = try await operation()
        try Task.checkCancellation()
        return value
    }

    func statistics() -> Statistics { state }

    private func acquire() async throws {
        try Task.checkCancellation()
        if state.active < 2 {
            state.active += 1
            publish()
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                waiters.append(Waiter(id: id, continuation: continuation))
                publish()
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        publish()
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func release() {
        state.active -= 1
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            state.active += 1
            next.continuation.resume()
        }
        publish()
    }

    private func publish() {
        state.queued = waiters.count
        state.peakActive = max(state.peakActive, state.active)
        observe?(state)
    }
}

actor DiaryPhotoLoader {
    typealias ContentReader = @Sendable (DiaryPhotoReference, DiaryPhotoScope) async throws -> Data
    typealias Decoder = @Sendable (Data, Int) async throws -> DiaryPhotoThumbnail

    struct Statistics: Equatable, Sendable {
        var residentCost = 0
        var reservedCost = 0
        var peakAccountedCost = 0
        var cachedCount = 0
        var waitingReservations = 0
    }

    private struct Key: Hashable, Sendable {
        let scope: DiaryPhotoScope
        let reference: DiaryPhotoReference.Identity
        let pixelSize: Int
    }
    private struct Entry {
        let thumbnail: DiaryPhotoThumbnail
        var lastUse: UInt64
    }
    private struct ReservationWaiter {
        let id: UUID
        let cost: Int
        let continuation: CheckedContinuation<Void, Error>
    }
    private static let maximumCost = 16 * 1024 * 1024
    private var scope: DiaryPhotoScope
    private let limiter: PhotoWorkLimiter
    private let reader: ContentReader
    private let decoder: Decoder
    private let observe: (@Sendable (Statistics) -> Void)?
    private var state = Statistics()
    private var generation: UInt64 = 0
    private var clock: UInt64 = 0
    private var cache: [Key: Entry] = [:]
    private var reservationWaiters: [ReservationWaiter] = []
    private var decodes: [UUID: Task<DiaryPhotoThumbnail, Error>] = [:]

    init(scope: DiaryPhotoScope, limiter: PhotoWorkLimiter, reader: @escaping ContentReader,
         decoder: @escaping Decoder = { data, size in try DiaryPhotoLoader.decode(data, pixelSize: size) },
         observe: (@Sendable (Statistics) -> Void)? = nil) {
        self.scope = scope
        self.limiter = limiter
        self.reader = reader
        self.decoder = decoder
        self.observe = observe
    }

    func thumbnail(for reference: DiaryPhotoReference, pixelSize: Int) async throws -> DiaryPhotoThumbnail {
        try Task.checkCancellation()
        guard reference.profileID == scope.identity.profileID else { throw DiaryError.wrongOwner }
        let cost = try Self.reservationCost(pixelSize)
        let key = Key(scope: scope, reference: reference.id, pixelSize: pixelSize)
        if var entry = cache[key] {
            clock &+= 1; entry.lastUse = clock; cache[key] = entry
            return entry.thumbnail
        }
        let requestedGeneration = generation
        let thumbnail = try await limiter.withPermit {
            try await self.load(reference, key: key, cost: cost, generation: requestedGeneration)
        }
        try validate(key, generation: requestedGeneration)
        return thumbnail
    }

    func reset(to scope: DiaryPhotoScope) {
        self.scope = scope
        purge()
    }
    func invalidate(_ changes: DiaryChanges) {
        if changes.profileReset || changes.timelineReset || !changes.mealIDs.isEmpty || !changes.turnIDs.isEmpty { purge() }
    }
    func purgeForMemoryPressure() { purge() }
    func statistics() -> Statistics { state }

    private func load(_ reference: DiaryPhotoReference, key: Key, cost: Int,
                      generation requestedGeneration: UInt64) async throws -> DiaryPhotoThumbnail {
        try validate(key, generation: requestedGeneration)
        try await reserve(cost)
        var ownsReservation = true
        defer { if ownsReservation { releaseReservation(cost) } }
        try validate(key, generation: requestedGeneration)
        let data = try await reader(reference, key.scope)
        try validate(key, generation: requestedGeneration)
        guard !data.isEmpty, data.count <= 10_000_000 else { throw DiaryPhotoError.invalidImage }
        let id = UUID(), decoder = self.decoder
        let decode = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let result = try await decoder(data, key.pixelSize)
            try Task.checkCancellation()
            return result
        }
        decodes[id] = decode
        defer { decodes[id] = nil }
        let thumbnail = try await withTaskCancellationHandler {
            try await decode.value
        } onCancel: {
            decode.cancel()
        }
        try validate(key, generation: requestedGeneration)
        guard thumbnail.image.width <= key.pixelSize, thumbnail.image.height <= key.pixelSize,
              thumbnail.image.bitsPerComponent == 8, thumbnail.image.bitsPerPixel == 32,
              thumbnail.decodedCost <= cost else { throw DiaryPhotoError.invalidImage }
        if let previous = cache.removeValue(forKey: key) { state.residentCost -= previous.thumbnail.decodedCost }
        state.reservedCost -= cost
        ownsReservation = false
        clock &+= 1
        cache[key] = Entry(thumbnail: thumbnail, lastUse: clock)
        state.residentCost += thumbnail.decodedCost
        resumeReservations()
        publish()
        return thumbnail
    }

    private func validate(_ key: Key, generation requestedGeneration: UInt64) throws {
        try Task.checkCancellation()
        guard generation == requestedGeneration, scope == key.scope else { throw DiaryPhotoError.staleRequest }
    }

    private func reserve(_ cost: Int) async throws {
        try Task.checkCancellation()
        if makeRoom(for: cost) {
            state.reservedCost += cost
            publish()
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                reservationWaiters.append(ReservationWaiter(id: id, cost: cost, continuation: continuation))
                publish()
            }
        } onCancel: {
            Task { await self.cancelReservation(id) }
        }
    }

    private func cancelReservation(_ id: UUID) {
        guard let index = reservationWaiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = reservationWaiters.remove(at: index)
        resumeReservations()
        publish()
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func releaseReservation(_ cost: Int) {
        state.reservedCost -= cost
        resumeReservations()
        publish()
    }

    private func resumeReservations() {
        while let first = reservationWaiters.first, makeRoom(for: first.cost) {
            reservationWaiters.removeFirst()
            state.reservedCost += first.cost
            first.continuation.resume()
        }
    }

    private func makeRoom(for cost: Int) -> Bool {
        while state.residentCost + state.reservedCost + cost > Self.maximumCost,
              let oldest = cache.min(by: { $0.value.lastUse < $1.value.lastUse }) {
            state.residentCost -= oldest.value.thumbnail.decodedCost
            cache[oldest.key] = nil
        }
        return state.residentCost + state.reservedCost + cost <= Self.maximumCost
    }

    private func purge() {
        generation &+= 1
        cache.removeAll()
        state.residentCost = 0
        // A cancelled ImageIO operation still owns its reservation and permit until it actually exits.
        for decode in decodes.values { decode.cancel() }
        let waiting = reservationWaiters; reservationWaiters = []
        for waiter in waiting { waiter.continuation.resume(throwing: DiaryPhotoError.staleRequest) }
        publish()
    }

    private func publish() {
        state.cachedCount = cache.count
        state.waitingReservations = reservationWaiters.count
        state.peakAccountedCost = max(state.peakAccountedCost, state.residentCost + state.reservedCost)
        observe?(state)
    }

    private nonisolated static func reservationCost(_ size: Int) throws -> Int {
        let square = size.multipliedReportingOverflow(by: size)
        let bytes = square.partialValue.multipliedReportingOverflow(by: 4)
        guard size > 0, !square.overflow, !bytes.overflow, bytes.partialValue <= maximumCost else { throw DiaryPhotoError.invalidSize }
        return bytes.partialValue
    }

    nonisolated static func decode(_ data: Data, pixelSize: Int) throws -> DiaryPhotoThumbnail {
        _ = try reservationCost(pixelSize)
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: pixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCache: false
              ] as CFDictionary), image.width > 0, image.height > 0,
              image.width <= pixelSize, image.height <= pixelSize,
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw DiaryPhotoError.invalidImage }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        guard let normalized = context.makeImage() else { throw DiaryPhotoError.invalidImage }
        return try DiaryPhotoThumbnail(image: normalized)
    }
}
