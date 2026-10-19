import Foundation
import CoreGraphics
import ImageIO
import os
import Testing
@testable import Mivu

@Suite struct DiaryPhotoLoaderTests {
    @Test func cacheIncludesOwnerProfileContentAndSize() async throws {
        let scope = photoScope(), photoID = UUID(), parent = UUID()
        let first = reference(scope, owner: .meal(parent), photoID: photoID)
        let second = reference(scope, owner: .meal(UUID()), photoID: photoID)
        let turn = reference(scope, owner: .coachTurn(parent), photoID: photoID)
        let bytes = try [first.id: imageData(red: true), second.id: imageData(red: false), turn.id: imageData(red: false)]
        let reader = PhotoReader(bytes)
        let loader = DiaryPhotoLoader(scope: scope, limiter: PhotoWorkLimiter(), reader: { ref, _ in try await reader.read(ref) })
        let firstParentImage = try pixel(try await loader.thumbnail(for: first, pixelSize: 16).image)
        let secondParentImage = try pixel(try await loader.thumbnail(for: second, pixelSize: 16).image)
        #expect(firstParentImage != secondParentImage)
        #expect(try pixel(try await loader.thumbnail(for: turn, pixelSize: 16).image) == secondParentImage)
        _ = try await loader.thumbnail(for: first, pixelSize: 16)
        #expect(await reader.readCount(first) == 1)
        _ = try await loader.thumbnail(for: first, pixelSize: 8)
        #expect(await reader.readCount(first) == 2)
        var replaced = first; replaced.contentToken = UUID()
        await reader.put(replaced, data: try imageData(red: false))
        #expect(try pixel(try await loader.thumbnail(for: replaced, pixelSize: 16).image) == secondParentImage)
        var wrong = first; wrong.profileID = UUID()
        await #expect(throws: DiaryError.wrongOwner) { try await loader.thumbnail(for: wrong, pixelSize: 16) }
        #expect(await reader.readCount(wrong) == 0)
        let next = photoScope(profileID: wrong.profileID)
        await reader.put(wrong, data: try imageData(red: false))
        await loader.reset(to: next)
        #expect(try pixel(try await loader.thumbnail(for: wrong, pixelSize: 16).image) == secondParentImage)
        #expect(await reader.readCount(wrong) == 1)
    }

    @Test func cancelledOffscreenDecodeDoesNotPublish() async throws {
        let scope = photoScope(), gate = DecodeGate(), limiter = PhotoWorkLimiter()
        let ref = reference(scope), data = try imageData()
        let loader = DiaryPhotoLoader(scope: scope, limiter: limiter, reader: { _, _ in data }, decoder: { data, size in
            await gate.enter()
            return try DiaryPhotoLoader.decode(data, pixelSize: size)
        })
        // Prime before installing a blocking gate, so a missing implementation fails rather than hangs in RED.
        _ = try await loader.thumbnail(for: ref, pixelSize: 8)
        await loader.purgeForMemoryPressure(); await gate.arm()
        let pending = Task { try await loader.thumbnail(for: ref, pixelSize: 16) }
        await gate.waitUntilEntered()
        pending.cancel()
        let during = await loader.statistics()
        #expect(during.reservedCost == 1024)
        #expect(await limiter.statistics().active == 1)
        await gate.release()
        await expectCancelled(pending)
        #expect(await loader.statistics().cachedCount == 0)
        #expect(await loader.statistics().reservedCost == 0)
        #expect(await limiter.statistics().active == 0)
    }

    @Test func memoryPressurePurgesAndCostIsBounded() async throws {
        let scope = photoScope(), data = try imageData(width: 1024, height: 1024)
        let reader = PhotoReader([:]), first = reference(scope), second = reference(scope), third = reference(scope), fourth = reference(scope), fifth = reference(scope)
        for ref in [first, second, third, fourth, fifth] { await reader.put(ref, data: data) }
        let loader = DiaryPhotoLoader(scope: scope, limiter: PhotoWorkLimiter(), reader: { ref, _ in try await reader.read(ref) })
        for ref in [first, second, third, fourth] { _ = try await loader.thumbnail(for: ref, pixelSize: 1024) }
        #expect(await loader.statistics().residentCost == 16 * 1024 * 1024)
        _ = try await loader.thumbnail(for: first, pixelSize: 1024)
        _ = try await loader.thumbnail(for: fifth, pixelSize: 1024)
        _ = try await loader.thumbnail(for: first, pixelSize: 1024)
        #expect(await reader.readCount(first) == 1)
        _ = try await loader.thumbnail(for: second, pixelSize: 1024)
        #expect(await reader.readCount(second) == 2)
        let stats = await loader.statistics()
        #expect(stats.residentCost <= 16 * 1024 * 1024)
        #expect(stats.peakAccountedCost <= 16 * 1024 * 1024)
        await loader.purgeForMemoryPressure()
        #expect(await loader.statistics().residentCost == 0)
        for size in [0, -1, 2049, Int.max] {
            await #expect(throws: DiaryPhotoError.invalidSize) { try await loader.thumbnail(for: first, pixelSize: size) }
        }
        #expect(await reader.readCount(first) == 1)
        #expect(await loader.statistics().reservedCost == 0)
    }

    @Test func reservationsWaitAndCancellationRetainsNoncooperativeAccounting() async throws {
        let scope = photoScope(), data = try imageData(), gate = DecodeGate()
        let events = AsyncStream<DiaryPhotoLoader.Statistics>.makeStream()
        defer { events.continuation.finish() }
        let loader = DiaryPhotoLoader(scope: scope, limiter: PhotoWorkLimiter(), reader: { _, _ in data }, decoder: { data, size in
            await gate.enter()
            return try DiaryPhotoLoader.decode(data, pixelSize: size)
        }, observe: { events.continuation.yield($0) })
        _ = try await loader.thumbnail(for: reference(scope), pixelSize: 8)
        await loader.purgeForMemoryPressure(); await gate.arm()
        let first = Task { try await loader.thumbnail(for: reference(scope), pixelSize: 2048) }
        await gate.waitUntilEntered()
        let second = Task { try await loader.thumbnail(for: reference(scope), pixelSize: 16) }
        let waiting = await next(events.stream) { $0.waitingReservations == 1 }
        #expect(waiting.reservedCost == 16 * 1024 * 1024 && waiting.residentCost == 0)
        second.cancel(); await expectCancelled(second)
        first.cancel()
        #expect(await loader.statistics().reservedCost == 16 * 1024 * 1024)
        await gate.release(); await expectCancelled(first)
        let done = await loader.statistics()
        #expect(done.residentCost == 0 && done.reservedCost == 0 && done.waitingReservations == 0)
        #expect(done.peakAccountedCost <= 16 * 1024 * 1024)
    }

    @Test func memoryWarningDiscardsLateDecodeAndSameKeyConcurrentMissesStayBounded() async throws {
        let scope = photoScope(), data = try imageData(), gate = DecodeGate()
        let loader = DiaryPhotoLoader(scope: scope, limiter: PhotoWorkLimiter(), reader: { _, _ in data }, decoder: { data, size in
            await gate.enter()
            return try DiaryPhotoLoader.decode(data, pixelSize: size)
        })
        let ref = reference(scope)
        _ = try await loader.thumbnail(for: ref, pixelSize: 8)
        await loader.purgeForMemoryPressure(); await gate.arm()
        let first = Task { try await loader.thumbnail(for: ref, pixelSize: 16) }
        let second = Task { try await loader.thumbnail(for: ref, pixelSize: 16) }
        await gate.waitUntilEntered(2)
        #expect(await loader.statistics().reservedCost == 2048)
        await loader.purgeForMemoryPressure()
        #expect(await loader.statistics().reservedCost == 2048)
        await gate.release()
        await expectStale(first); await expectStale(second)
        let purged = await loader.statistics()
        #expect(purged.residentCost == 0 && purged.reservedCost == 0)
        await gate.arm()
        let third = Task { try await loader.thumbnail(for: ref, pixelSize: 16) }
        let fourth = Task { try await loader.thumbnail(for: ref, pixelSize: 16) }
        await gate.waitUntilEntered(2)
        #expect(await loader.statistics().reservedCost == 2048)
        await gate.release()
        _ = try await third.value; _ = try await fourth.value
        let stats = await loader.statistics()
        #expect(stats.cachedCount == 1 && stats.residentCost == 512 && stats.reservedCost == 0)
    }

    @Test func globalLimiterCoversDecodeImportAndInferenceWork() async throws {
        let events = AsyncStream<PhotoWorkLimiter.Statistics>.makeStream()
        defer { events.continuation.finish() }
        let limiter = PhotoWorkLimiter(observe: { events.continuation.yield($0) })
        #expect(try await limiter.withPermit { 7 } == 7)
        let scope = photoScope(), gate = DecodeGate(), importGate = DecodeGate(), visionGate = DecodeGate(), data = try imageData()
        await gate.arm(); await importGate.arm(); await visionGate.arm()
        let loader = DiaryPhotoLoader(scope: scope, limiter: limiter, reader: { _, _ in data }, decoder: { data, size in
            await gate.enter(); return try DiaryPhotoLoader.decode(data, pixelSize: size)
        })
        let decode = Task { try await loader.thumbnail(for: reference(scope), pixelSize: 16) }
        await gate.waitUntilEntered()
        let imported = Task { try await limiter.withPermit { await importGate.enter(); return 1 } }
        await importGate.waitUntilEntered()
        let vision = Task { try await limiter.withPermit { await visionGate.enter(); return 2 } }
        let queued = await next(events.stream) { $0.active == 2 && $0.queued == 1 }
        #expect(queued.peakActive == 2)
        decode.cancel()
        #expect(await limiter.statistics().active == 2)
        #expect(await visionGate.entered == 0)
        await gate.release(); await expectCancelled(decode)
        await visionGate.waitUntilEntered()
        #expect(await limiter.statistics().active == 2)
        let cancelledQueued = Task { try await limiter.withPermit { 99 } }
        _ = await next(events.stream) { $0.queued == 1 && $0.active == 2 }
        cancelledQueued.cancel(); await expectCancelled(cancelledQueued)
        await importGate.release(); await visionGate.release()
        #expect(try await imported.value == 1)
        #expect(try await vision.value == 2)
        await #expect(throws: DiaryPhotoError.invalidImage) {
            try await limiter.withPermit { throw DiaryPhotoError.invalidImage }
        }
        let final = await limiter.statistics()
        #expect(final.active == 0 && final.queued == 0 && final.peakActive <= 2)
    }

    @Test func progressConsumerResolvesActualOwnerAndSurvivesSiblingDeletion() async throws {
        var source = ChatHistoryFixture.snapshot(exchanges: 1)
        source.meals[0].photos[0].data = try imageData(red: true)
        var sibling = source.meals[0]; sibling.id = UUID(); sibling.photos[0].data = try imageData(red: false)
        source.meals.append(sibling)
        let turnID = source.coachTurns[0].id
        source.coachTurns[0].photos = []; source.coachTurns[0].photoIDs = source.meals[0].photos.map(\.id)
        source.coachTurns[0].receipts.append(CoachReceipt(operationKey: "\(turnID)/weight/2027-01-15", turnID: turnID,
            dayID: source.days[0].id, weightID: source.weights[0].id, committedRevision: 1, resultJSON: "{}"))
        let f = try CaptureFixture(snapshot: source); defer { f.remove() }
        let store = DiaryStore(directory: f.root), head = try await store.selectPagedProfile(f.profileID)
        let scope = photoScope(head: head, epoch: try await store.selectionEpoch(expectedProfileID: f.profileID))
        let loader = storeLoader(scope: scope, store: store)
        let database = try DiaryDatabase(url: f.url)
        let old = try #require(database.coachPage(.latest, expectedProfileID: f.profileID).exchanges.first?.photos.first)
        let siblingRef = try #require(database.meal(id: sibling.id, expectedProfileID: f.profileID).photos.first)
        #expect(old.owner == .meal(source.meals[0].id) && old.photoID == siblingRef.photoID)
        let oldPixel = try pixel(try await loader.thumbnail(for: old, pixelSize: 16).image)
        var replacement = source.meals[0].photos[0]; replacement.data = try imageData(red: false)
        let updated = try database.transaction(expected: head, maximumBytes: ChatHistoryFixture.maximumBytes) {
            try $0.replacePhoto(replacement, mealID: source.meals[0].id)
        }
        await loader.invalidate(updated.changes)
        let current = try #require(database.meal(id: source.meals[0].id, expectedProfileID: f.profileID).photos.first)
        #expect(current.contentToken != old.contentToken)
        #expect(try pixel(try await loader.thumbnail(for: current, pixelSize: 16).image) != oldPixel)
        let removed = try database.deleteMeal(source.meals[0].id, expected: updated.head, maximumBytes: ChatHistoryFixture.maximumBytes)
        await loader.invalidate(removed.changes)
        let surviving = try #require(database.coachPage(.latest, expectedProfileID: f.profileID).exchanges.first?.photos.first)
        #expect(surviving.owner == .coachTurn(turnID) && surviving.contentToken != current.contentToken)
        #expect(try pixel(try await loader.thumbnail(for: surviving, pixelSize: 16).image) == pixel(try await loader.thumbnail(for: siblingRef, pixelSize: 16).image))
        await #expect(throws: DiaryError.notFound) { try await loader.thumbnail(for: old, pixelSize: 16) }
        #expect(try database.meal(id: sibling.id, expectedProfileID: f.profileID).photos == [siblingRef])
        // Explicit removal of the sibling must not leave its cached evidence available.
        let deleted = try database.deletePhoto(mealID: sibling.id, photoID: siblingRef.photoID, expected: removed.head, maximumBytes: ChatHistoryFixture.maximumBytes)
        await loader.invalidate(deleted.changes)
        await #expect(throws: DiaryError.notFound) { try await loader.thumbnail(for: siblingRef, pixelSize: 16) }
    }

    @Test func restoreInvalidatesContentTokensAndLateImages() async throws {
        var source = ChatHistoryFixture.snapshot(exchanges: 0)
        source.meals[0].photos[0].data = try imageData()
        let f = try CaptureFixture(snapshot: source); defer { f.remove() }
        let store = DiaryStore(directory: f.root), head = try await store.selectPagedProfile(f.profileID)
        let firstScope = photoScope(head: head, epoch: try await store.selectionEpoch(expectedProfileID: f.profileID))
        let ref = try #require(try await store.meal(id: source.meals[0].id, expectedProfileID: f.profileID).photos.first)
        let gate = DecodeGate(), publisher = PhotoPublisher(scope: firstScope)
        let loader = storeLoader(scope: firstScope, store: store, decoder: { data, size in
            await gate.enter(); return try DiaryPhotoLoader.decode(data, pixelSize: size)
        })
        _ = try await loader.thumbnail(for: ref, pixelSize: 8)
        await gate.arm()
        let late = Task { try await loader.thumbnail(for: ref, pixelSize: 16) }
        await gate.waitUntilEntered()
        let coordinator = DiaryExportCoordinator(store: store, temporaryDirectory: f.root)
        let ticket = try await coordinator.makeClone(try await store.exportRequest(expectedProfileID: f.profileID))
        let portable = try await coordinator.completeSnapshot(ticket)
        let prepared = try await coordinator.prepareReplacement(portable, replacing: ticket)
        let restored = try await store.installReplacement(prepared)
        let nextScope = photoScope(head: restored, epoch: try await store.selectionEpoch(expectedProfileID: f.profileID))
        let nextRef = try #require(try await store.meal(id: source.meals[0].id, expectedProfileID: f.profileID).photos.first)
        #expect(nextScope.identity != firstScope.identity && nextScope.selectionEpoch != firstScope.selectionEpoch)
        #expect(nextRef.photoID == ref.photoID && nextRef.contentToken != ref.contentToken)
        await loader.reset(to: nextScope); await publisher.reset(nextScope)
        await gate.release()
        await publisher.consume(late, capturedScope: firstScope)
        #expect(await publisher.publications == 0)
        #expect(await loader.statistics().cachedCount == 0)
        #expect(try await loader.thumbnail(for: nextRef, pixelSize: 16).decodedCost > 0)
        try await coordinator.release(ticket)
    }

    @Test func sameProfileReselectionRejectsLateAssignment() async throws {
        let scope = photoScope(), gate = DecodeGate(), data = try imageData(), ref = reference(scope)
        let loader = DiaryPhotoLoader(scope: scope, limiter: PhotoWorkLimiter(), reader: { _, _ in data }, decoder: { data, size in
            await gate.enter(); return try DiaryPhotoLoader.decode(data, pixelSize: size)
        })
        _ = try await loader.thumbnail(for: ref, pixelSize: 8)
        await gate.arm()
        let publisher = PhotoPublisher(scope: scope)
        let late = Task { try await loader.thumbnail(for: ref, pixelSize: 16) }
        await gate.waitUntilEntered()
        await loader.reset(to: photoScope())
        let returned = DiaryPhotoScope(identity: scope.identity, selectionEpoch: scope.selectionEpoch + 2)
        await loader.reset(to: returned); await publisher.reset(returned)
        await gate.release(); await publisher.consume(late, capturedScope: scope)
        #expect(await publisher.publications == 0)
        #expect(await loader.statistics().cachedCount == 0)
        #expect(try await loader.thumbnail(for: ref, pixelSize: 16).decodedCost > 0)
    }

    @Test func resetDuringLimiterReturnRejectsCompletedImage() async throws {
        let scope = photoScope(), data = try imageData(), gate = LimiterReturnGate()
        defer { gate.release() }
        let limiter = PhotoWorkLimiter(observe: { gate.observe($0) })
        let loader = DiaryPhotoLoader(scope: scope, limiter: limiter, reader: { _, _ in data })
        let ref = reference(scope)
        _ = try await loader.thumbnail(for: ref, pixelSize: 8)
        gate.arm()
        let pending = Task { try await loader.thumbnail(for: ref, pixelSize: 16) }
        await gate.waitUntilBlocked()
        // Decode and insertion have finished; only the limiter's final return is held.
        #expect(await loader.statistics().cachedCount == 2)
        let nextScope = DiaryPhotoScope(identity: scope.identity, selectionEpoch: scope.selectionEpoch + 1)
        await loader.reset(to: nextScope)
        gate.release()
        await expectStale(pending)
        #expect(!gate.timedOut && !gate.blockedMainThread)
        #expect(await loader.statistics().cachedCount == 0)
        #expect(await limiter.statistics().active == 0)
    }

    @Test func productionDecoderUsesBoundedPixelsOffMain() async throws {
        let scope = photoScope(), data = try imageData(width: 40, height: 20, orientation: 6)
        let observed = ThreadObservation()
        let loader = DiaryPhotoLoader(scope: scope, limiter: PhotoWorkLimiter(), reader: { _, _ in data }, decoder: { data, size in
            await observed.record(photoWorkIsOnMainThread())
            return try DiaryPhotoLoader.decode(data, pixelSize: size)
        })
        let output = try await loader.thumbnail(for: reference(scope), pixelSize: 16)
        #expect(output.image.width == 8 && output.image.height == 16)
        #expect(output.image.bitsPerComponent == 8 && output.image.bitsPerPixel == 32)
        #expect(output.decodedCost == 512 && output.decodedCost == output.image.bytesPerRow * output.image.height)
        #expect(await observed.mainThread == false)
        #expect(try pixel(output.image, x: 4, y: 2) != pixel(output.image, x: 4, y: 13))
        let landscape = try DiaryPhotoLoader.decode(imageData(width: 40, height: 20), pixelSize: 16)
        #expect(landscape.image.width == 16 && landscape.image.height == 8)
        let high = try imageData(width: 12, height: 8, highBitDepth: true)
        let highSource = try #require(CGImageSourceCreateWithData(high as CFData, nil))
        #expect(try #require(CGImageSourceCreateImageAtIndex(highSource, 0, nil)).bitsPerComponent == 16)
        let normalized = try DiaryPhotoLoader.decode(high, pixelSize: 12)
        #expect(normalized.image.bitsPerComponent == 8 && normalized.image.bitsPerPixel == 32 && normalized.decodedCost == 384)
        for bad in [Data(), Data(data.prefix(12)), Data([0, 1, 2, 3])] {
            let invalid = DiaryPhotoLoader(scope: scope, limiter: PhotoWorkLimiter(), reader: { _, _ in bad })
            await #expect(throws: DiaryPhotoError.invalidImage) { try await invalid.thumbnail(for: reference(scope), pixelSize: 16) }
            let failed = await invalid.statistics()
            #expect(failed.reservedCost == 0 && failed.residentCost == 0)
        }
    }
}

private func photoScope(profileID: UUID = UUID()) -> DiaryPhotoScope {
    DiaryPhotoScope(identity: CoachTimelineIdentity(profileID: profileID, timelineGeneration: UUID()), selectionEpoch: 1)
}
private func photoScope(head: DiaryHead, epoch: UInt64) -> DiaryPhotoScope {
    DiaryPhotoScope(identity: CoachTimelineIdentity(profileID: head.profile.id, timelineGeneration: head.timelineGeneration), selectionEpoch: epoch)
}
private func reference(_ scope: DiaryPhotoScope, owner: DiaryPhotoOwner = .meal(UUID()), photoID: UUID = UUID()) -> DiaryPhotoReference {
    DiaryPhotoReference(profileID: scope.identity.profileID, owner: owner, photoID: photoID,
        createdAt: Date(timeIntervalSince1970: 1_800_000_000), role: .before, contentToken: UUID())
}
private func storeLoader(scope: DiaryPhotoScope, store: DiaryStore,
                         decoder: @escaping DiaryPhotoLoader.Decoder = { data, size in try DiaryPhotoLoader.decode(data, pixelSize: size) }) -> DiaryPhotoLoader {
    DiaryPhotoLoader(scope: scope, limiter: PhotoWorkLimiter(), reader: { reference, captured in
        try await store.validateSelection(epoch: captured.selectionEpoch, expectedProfileID: reference.profileID)
        let head = try await store.diaryHead(expectedProfileID: reference.profileID)
        guard head.timelineGeneration == captured.identity.timelineGeneration else { throw DiaryPhotoError.staleRequest }
        let bytes = try await store.photoContent(reference, expectedProfileID: reference.profileID)
        try await store.validateSelection(epoch: captured.selectionEpoch, expectedProfileID: reference.profileID)
        let after = try await store.diaryHead(expectedProfileID: reference.profileID)
        guard after.timelineGeneration == captured.identity.timelineGeneration else { throw DiaryPhotoError.staleRequest }
        return bytes
    }, decoder: decoder)
}

/// Real asymmetric RGBA PNGs, including a 16-bit source and EXIF orientation.
private func imageData(width: Int = 16, height: Int = 8, red: Bool = true, orientation: Int = 1, highBitDepth: Bool = false) throws -> Data {
    let image: CGImage
    if highBitDepth {
        let bytes = Data((0..<(width * height)).flatMap { _ in [UInt8(128), UInt8(0)] })
        let provider = try #require(CGDataProvider(data: bytes as CFData))
        image = try #require(CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 16,
            bytesPerRow: width * 2, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: .byteOrder16Big,
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    } else {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: red ? 1 : 0, green: 0, blue: red ? 0 : 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
        context.fill(CGRect(x: CGFloat(width / 2), y: 0, width: CGFloat(width - width / 2), height: CGFloat(height)))
        image = try #require(context.makeImage())
    }
    let data = NSMutableData()
    let type = orientation == 1 ? "public.png" : "public.jpeg"
    let destination = try #require(CGImageDestinationCreateWithData(data, type as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    let result = data as Data
    let source = try #require(CGImageSourceCreateWithData(result as CFData, nil))
    #expect(CGImageSourceCreateImageAtIndex(source, 0, nil) != nil)
    return result
}
private func pixel(_ image: CGImage, x: Int = 1, y: Int = 1) throws -> [UInt8] {
    let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
    let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    let offset = y * image.width * 4 + x * 4
    return (0..<4).map { bytes[offset + $0] }
}
private actor PhotoReader {
    var values: [DiaryPhotoReference.Identity: Data]
    var counts: [DiaryPhotoReference.Identity: Int] = [:]
    init(_ values: [DiaryPhotoReference.Identity: Data]) { self.values = values }
    func put(_ ref: DiaryPhotoReference, data: Data) { values[ref.id] = data }
    func read(_ ref: DiaryPhotoReference) throws -> Data {
        counts[ref.id, default: 0] += 1
        guard let data = values[ref.id] else { throw DiaryError.notFound }
        return data
    }
    func readCount(_ ref: DiaryPhotoReference) -> Int { counts[ref.id, default: 0] }
}
private actor DecodeGate {
    private var armed = false
    private(set) var entered = 0
    private var releases: [CheckedContinuation<Void, Never>] = []
    private var entries: [(Int, CheckedContinuation<Void, Never>)] = []
    func arm() { armed = true; entered = 0 }
    func enter() async {
        guard armed else { return }
        entered += 1
        let ready = entries.filter { $0.0 <= entered }; entries.removeAll { $0.0 <= entered }
        ready.forEach { $0.1.resume() }
        await withCheckedContinuation { releases.append($0) }
    }
    func waitUntilEntered(_ count: Int = 1) async {
        if entered >= count { return }
        await withCheckedContinuation { entries.append((count, $0)) }
    }
    func release() {
        armed = false
        let pending = releases; releases = []
        pending.forEach { $0.resume() }
    }
}
private func next<Value: Sendable>(_ stream: AsyncStream<Value>, matching: (Value) -> Bool) async -> Value {
    for await value in stream where matching(value) { return value }
    fatalError("Diagnostic stream ended before expected event")
}
private func expectCancelled<Value: Sendable>(_ task: Task<Value, Error>) async {
    do { _ = try await task.value; Issue.record("Cancelled work published a result") }
    catch { #expect(error is CancellationError) }
}
private func expectStale<Value: Sendable>(_ task: Task<Value, Error>) async {
    do { _ = try await task.value; Issue.record("Obsolete work published a result") }
    catch { #expect(error as? DiaryPhotoError == .staleRequest || error is CancellationError) }
}
private actor PhotoPublisher {
    var scope: DiaryPhotoScope
    private(set) var publications = 0
    init(scope: DiaryPhotoScope) { self.scope = scope }
    func reset(_ scope: DiaryPhotoScope) { self.scope = scope }
    func consume(_ task: Task<DiaryPhotoThumbnail, Error>, capturedScope: DiaryPhotoScope) async {
        if let _ = try? await task.value, capturedScope == scope, !Task.isCancelled { publications += 1 }
    }
}
private actor ThreadObservation {
    var mainThread: Bool?
    func record(_ value: Bool) { mainThread = value }
}
private func photoWorkIsOnMainThread() -> Bool { Thread.isMainThread }

/// A bounded synchronous test barrier at the existing diagnostic callback, never a production wait.
private final class LimiterReturnGate: Sendable {
    private struct State {
        var armed = false
        var timedOut = false
        var blockedMainThread = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let semaphore = DispatchSemaphore(value: 0)
    private let entered = AsyncStream<Void>.makeStream()
    var timedOut: Bool { state.withLock { $0.timedOut } }
    var blockedMainThread: Bool { state.withLock { $0.blockedMainThread } }
    func arm() { state.withLock { $0.armed = true } }
    func observe(_ statistics: PhotoWorkLimiter.Statistics) {
        guard statistics.active == 0, state.withLock({ value in
            guard value.armed else { return false }
            value.armed = false
            value.blockedMainThread = photoWorkIsOnMainThread()
            return true
        }) else { return }
        entered.continuation.yield(())
        guard !blockedMainThread else { return }
        if semaphore.wait(timeout: .now() + 10) == .timedOut { state.withLock { $0.timedOut = true } }
    }
    func waitUntilBlocked() async { for await _ in entered.stream { return } }
    func release() { semaphore.signal() }
    deinit { entered.continuation.finish() }
}
