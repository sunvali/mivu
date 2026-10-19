import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import UIKit
import Testing
@testable import Mivu

@Suite @MainActor struct CoachCameraTests {
    @Test func cameraIsFirstDestinationAndLibraryCancelResumesIt() async throws {
        let owner = Task10Fixture.ownership()
        let camera = CoachCameraSession(dependencies: .init(available: { true }, authorization: { .authorized }, capture: { try Task10JPEG.tagged() }))
        try await camera.open(presentationID: UUID(), ownership: owner)
        #expect(await camera.state.destination == .camera)
        #expect(await camera.state.isRunning)
        try await camera.choosePhotos()
        #expect(await camera.state.destination == .library)
        #expect(!(await camera.state.isRunning))
        try await camera.libraryCancelled()
        #expect(await camera.state.destination == .camera)
        #expect(await camera.state.isRunning)
        try await camera.close()
        #expect(await camera.state.phase == .closed)
        #expect(!(await camera.state.isRunning))
    }

    @Test(arguments: ["denied", "restricted", "unavailable"])
    func deniedOrUnavailableCameraRetainsLibraryAndClose(reason: String) async throws {
        let camera = CoachCameraSession(dependencies: .init(available: { reason != "unavailable" }, authorization: {
            reason == "restricted" ? .restricted : .denied
        }, capture: { throw CoachCameraFailure.unavailable }))
        try await camera.open(presentationID: UUID(), ownership: Task10Fixture.ownership())
        #expect(!(await camera.state.isRunning))
        #expect(await camera.state.canChoosePhotos)
        #expect(await camera.state.canClose)
        try await camera.choosePhotos()
        #expect(await camera.state.destination == .library)
        try await camera.libraryCancelled()
        #expect(await camera.state.destination == .camera)
        #expect(!(await camera.state.isRunning))
        try await camera.close()
        #expect(await camera.state.phase == .closed)
    }

    @Test func latePermissionCannotReopenDismissedPresentation() async throws {
        let gate = Task10Gate(), first = Task10Once()
        let camera = CoachCameraSession(dependencies: .init(available: { true }, authorization: {
            if await first.claim() { await gate.hold(0) }
            return .authorized
        }, capture: { try Task10JPEG.tagged() }))
        let oldID = UUID(), newID = UUID(), owner = Task10Fixture.ownership()
        let opening = Task10Fixture.operation(gate: gate) { try await camera.open(presentationID: oldID, ownership: owner) }
        do {
            try await gate.waitForArrivals(1)
            try await camera.close()
            try await camera.open(presentationID: newID, ownership: owner)
            await gate.releaseAll()
            await #expect(throws: CoachCameraFailure.stalePresentation) { try await opening.value }
            #expect(await camera.state.presentationID == newID)
            #expect(await camera.state.isRunning)
            try await camera.close()
        } catch { await gate.releaseAll(); _ = try? await opening.value; throw error }
    }

    @Test func cameraPausesForBackgroundAndRecoversInterruption() async throws {
        let camera = CoachCameraSession(dependencies: .init(available: { true }, authorization: { .authorized }, capture: { try Task10JPEG.tagged() }))
        try await camera.open(presentationID: UUID(), ownership: Task10Fixture.ownership())
        try await camera.setForeground(false)
        #expect(!(await camera.state.isRunning))
        try await camera.choosePhotos()
        try await camera.libraryCancelled()
        #expect(!(await camera.state.isRunning))
        try await camera.setForeground(true)
        #expect(await camera.state.isRunning)
        try await camera.interrupted()
        #expect(await camera.state.phase == .interrupted)
        let interrupted = await camera.state
        #expect(interrupted.canChoosePhotos && interrupted.canClose)
        try await camera.retry()
        #expect(await camera.state.isRunning)
        try await camera.close()
        try await camera.setForeground(true)
        #expect(await camera.state.phase == .closed)
    }

    @Test(arguments: [false, true])
    func cancelledStartupCannotOpenAfterCloseBeforeActorEntry(replaced: Bool) async throws {
        let gate = Task10Gate(), owner = Task10Fixture.ownership(), oldID = UUID(), newID = UUID()
        let camera = CoachCameraSession(dependencies: .init(available: { true }, authorization: { .authorized }, capture: { try Task10JPEG.tagged() }))
        await camera.previewAttached(presentationID: oldID)
        let starting = Task10Fixture.operation(gate: gate) {
            try await camera.setForeground(true)
            await gate.hold(0)
            // Deliberately enter the real actor even though this old startup was cancelled.
            try await camera.open(presentationID: oldID, ownership: owner)
        }
        do {
            try await gate.waitForArrivals(1)
            try await camera.close()
            if replaced { try await camera.open(presentationID: newID, ownership: owner) }
            starting.cancel(); await gate.releaseAll()
            await #expect(throws: CancellationError.self) { try await starting.value }
            let state = await camera.state
            #expect(state.presentationID == (replaced ? newID : nil))
            #expect(state.isRunning == replaced)
            #expect(state.phase == (replaced ? .running : .closed))
            try await camera.close()
        } catch { await gate.releaseAll(); _ = try? await starting.value; throw error }
    }

    @Test func cancelledPermissionResponseClosesOnlyItsCurrentPresentation() async throws {
        let gate = Task10Gate(), owner = Task10Fixture.ownership()
        let camera = CoachCameraSession(dependencies: .init(available: { true }, authorization: {
            await gate.hold(0); return .authorized
        }, capture: { try Task10JPEG.tagged() }))
        let opening = Task10Fixture.operation(gate: gate) { try await camera.open(presentationID: UUID(), ownership: owner) }
        do {
            try await gate.waitForArrivals(1)
            opening.cancel(); await gate.releaseAll()
            await #expect(throws: CancellationError.self) { try await opening.value }
            let state = await camera.state
            #expect(state.phase == .closed && state.presentationID == nil && !state.isRunning)
        } catch { await gate.releaseAll(); _ = try? await opening.value; throw error }
    }

    @Test(arguments: [false, true])
    func genericCameraPhotoUsesSharedPreparationOffMainAndHonorsTwoPermits(cancelled: Bool) async throws {
        let statistics = AsyncStream<PhotoWorkLimiter.Statistics>.makeStream()
        let limiter = PhotoWorkLimiter(observe: { statistics.continuation.yield($0) })
        let f = try await Task10Fixture.make(photoWorkLimiter: limiter); defer { f.remove() }
        let preparation = PhotoPreparation(limiter: f.diary.photoWorkLimiter), gate = Task10Gate()
        let image = UIImage(cgImage: try Task10JPEG.image(Task10JPEG.tagged()), scale: 1, orientation: .right)
        let first = Task10Fixture.operation(gate: gate) { try await f.diary.photoWorkLimiter.withPermit { await gate.hold(0) } }
        let second = Task10Fixture.operation(gate: gate) { try await f.diary.photoWorkLimiter.withPermit { await gate.hold(1) } }
        var processing: Task<Data?, Error>?
        do {
            try await gate.waitForArrivals(2)
            processing = Task {
                defer { statistics.continuation.finish() }
                return try await CameraCapture.preparePhoto(image, preparation: preparation, normalize: { try Task10JPEG.normalizeCameraOffMain($0) })
            }
            let current = try #require(processing)
            var queued = false
            for await state in statistics.stream where state.active == 2 && state.queued == 1 { queued = true; break }
            try #require(queued)
            #expect(preparation.isPreparing && !preparation.canCapture)
            if cancelled {
                current.cancel()
                await #expect(throws: CancellationError.self) { _ = try await current.value }
                let held = await f.diary.photoWorkLimiter.statistics()
                #expect(held.active == 2 && held.peakActive == 2)
            }
            await gate.releaseAll(); _ = try await first.value; _ = try await second.value
            if !cancelled {
                let result = try await current.value
                let bytes = try #require(result)
                let output = try Task10JPEG.image(bytes)
                #expect(output.width == 40 && output.height == 80)
                let top = try Task10JPEG.pixel(output, x: 20, y: 10), bottom = try Task10JPEG.pixel(output, x: 20, y: 70)
                #expect(top.red > 200 && top.blue < 40 && bottom.blue > 200 && bottom.red < 40)
                #expect(try Task10JPEG.properties(bytes)[kCGImagePropertyGPSDictionary] == nil)
            }
            let final = await f.diary.photoWorkLimiter.statistics()
            #expect(final.active == 0 && final.peakActive == 2)
            #expect(!preparation.isPreparing && preparation.canCapture)
        } catch {
            processing?.cancel(); await gate.releaseAll()
            _ = try? await processing?.value; _ = try? await first.value; _ = try? await second.value
            throw error
        }
    }

    @Test(arguments: [CoachAttachmentDraft.PhotoSource.camera, .library])
    func normalizedPhotoDropsLocationMetadataAndPreservesOrientation(source: CoachAttachmentDraft.PhotoSource) async throws {
        let original = try Task10JPEG.tagged()
        let originalProperties = try Task10JPEG.properties(original)
        #expect(originalProperties[kCGImagePropertyGPSDictionary] != nil)
        #expect((originalProperties[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment] != nil)
        #expect(originalProperties[kCGImagePropertyOrientation] as? Int == 6)
        let normalized = try await CoachAttachmentDraft.normalize(original, source: source)
        let properties = try Task10JPEG.properties(normalized)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect((properties[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment] == nil)
        #expect((properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFImageDescription] == nil)
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        let image = try Task10JPEG.image(normalized)
        #expect(image.width == 40 && image.height == 80)
        let top = try Task10JPEG.pixel(image, x: 20, y: 10)
        let bottom = try Task10JPEG.pixel(image, x: 20, y: 70)
        #expect(top.red > 200 && top.blue < 40)
        #expect(bottom.blue > 200 && bottom.red < 40)
        #expect(normalized.count <= 5_000_000)
    }

    @Test func lowStorageCaptureFailureRetainsTextAttachmentsAndSubmissionIdentity() async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let photo = MealPhoto(data: try Task10JPEG.tagged())
        let requiredOwner = try #require(f.diary.selection)
        let draft = CoachAttachmentDraft(ownership: requiredOwner, limiter: f.diary.photoWorkLimiter,
            dependencies: Task10Fixture.dependencies(f.diary), text: "Keep this note", attachments: [photo])
        let submissionID = draft.submissionID
        let camera = CoachCameraSession(dependencies: .init(available: { true }, authorization: { .authorized }, capture: {
            throw CocoaError(.fileWriteOutOfSpace)
        }))
        try await camera.open(presentationID: UUID(), ownership: requiredOwner)
        await #expect(throws: CocoaError.self) { _ = try await camera.capture() }
        #expect(draft.text == "Keep this note" && draft.attachments == [photo])
        #expect(draft.submissionID == submissionID && draft.captureReceipt == nil)
        let beforeSend = try await f.diary.store.snapshotForExport()
        #expect(beforeSend.meals.isEmpty && beforeSend.coachTurns.isEmpty)
        try await camera.close()
    }

    @Test func cameraCaptureAddsComposerPreviewWithoutSendingOrCreatingMeals() async throws {
        let f = try await Task10Fixture.make(); defer { f.remove() }
        let owner = try #require(f.diary.selection)
        let draft = CoachAttachmentDraft(ownership: owner, limiter: f.diary.photoWorkLimiter,
            dependencies: Task10Fixture.dependencies(f.diary), text: "Before shutter")
        let id = draft.submissionID, presentation = try draft.beginPresentation()
        let camera = CoachCameraSession(dependencies: .init(available: { true }, authorization: { .authorized }, capture: { try Task10JPEG.tagged() }))
        try await camera.open(presentationID: presentation, ownership: owner)
        try await draft.capture(using: camera, presentationID: presentation)
        #expect(draft.attachments.count == 1 && draft.text == "Before shutter")
        #expect(draft.submissionID == id && draft.captureReceipt == nil)
        let image = try Task10JPEG.image(try #require(draft.attachments.first?.data))
        #expect(image.width == 40 && image.height == 80)
        let facts = try await f.diary.store.snapshotForExport()
        #expect(facts.coachTurns.isEmpty && facts.meals.isEmpty)
        try await draft.endPresentation(presentation); try await camera.close()
    }

    @Test func lateCaptureCannotReturnBytesAfterPresentationReplacement() async throws {
        let gate = Task10Gate(), firstID = UUID(), nextID = UUID()
        let camera = CoachCameraSession(dependencies: .init(available: { true }, authorization: { .authorized }, capture: {
            await gate.hold(0); return try Task10JPEG.tagged()
        }))
        try await camera.open(presentationID: firstID, ownership: Task10Fixture.ownership())
        let capturing = Task10Fixture.operation(gate: gate) { try await camera.capture() }
        do {
            try await gate.waitForArrivals(1)
            try await camera.close()
            try await camera.open(presentationID: nextID, ownership: Task10Fixture.ownership())
            await gate.releaseAll()
            await #expect(throws: CoachCameraFailure.stalePresentation) { _ = try await capturing.value }
            #expect(await camera.state.presentationID == nextID)
            #expect(await camera.state.isRunning)
            try await camera.close()
        } catch { await gate.releaseAll(); _ = try? await capturing.value; throw error }
    }
}

enum Task10JPEG {
    static func normalizeCameraOffMain(_ image: CameraCaptureImage) throws -> Data {
        #expect(!Thread.isMainThread)
        return try PhotoImport.normalize(image)
    }
    static func tagged() throws -> Data {
        let width = 80, height = 40
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let offset = (y * width + x) * 4
            pixels[offset] = x < 40 ? 255 : 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = x < 40 ? 0 : 255
        } }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let result = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 31.778, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 35.235, kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Synthetic location 31.778,35.235"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFImageDescription: "Synthetic location fixture"],
            kCGImageDestinationLossyCompressionQuality: 1.0
        ] as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return result as Data
    }
    static func properties(_ data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }
    static func image(_ data: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }
    static func pixel(_ image: CGImage, x: Int, y: Int) throws -> (red: UInt8, blue: UInt8) {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { raw in
            let context = try #require(CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return (bytes[(y * image.width + x) * 4], bytes[(y * image.width + x) * 4 + 2])
    }
}

actor Task10Once {
    private var used = false
    func claim() -> Bool { guard !used else { return false }; used = true; return true }
}

// A noncooperative dependency proves publication/permit guards after cancellation.
actor Task10Gate {
    enum Failure: Error { case operationEndedBeforeGate, deadline }
    private let events = AsyncStream<Void>.makeStream()
    private var arrivals = 0
    private var ended = false
    private var timedOut = false
    private var holds: [Int: CheckedContinuation<Void, Never>] = [:]
    private var deadlines: [Int: Task<Void, Never>] = [:]
    func hold(_ key: Int) async {
        arrivals += 1
        events.continuation.yield(())
        await withCheckedContinuation { holds[key] = $0
            deadlines[key] = Task {
                try? await Task.sleep(for: .seconds(10))
                if !Task.isCancelled { expired() }
            }
        }
    }
    func waitForArrivals(_ count: Int) async throws {
        if arrivals >= count { return }
        let deadline = Task { try? await Task.sleep(for: .seconds(10)); if !Task.isCancelled { expired() } }
        defer { deadline.cancel() }
        for await _ in events.stream {
            if timedOut { throw Failure.deadline }
            if arrivals >= count { return }
            if ended { throw Failure.operationEndedBeforeGate }
        }
        throw CancellationError()
    }
    func operationEnded() { ended = true; events.continuation.yield(()) }
    func release(_ key: Int) { deadlines.removeValue(forKey: key)?.cancel(); holds.removeValue(forKey: key)?.resume() }
    func releaseAll() { for key in Array(holds.keys) { release(key) } }
    private func expired() { timedOut = true; Issue.record("Camera/draft fixture gate exceeded ten seconds"); releaseAll(); events.continuation.yield(()) }
}

@MainActor struct Task10Fixture {
    let diary: DiaryViewModel
    let root: URL
    func remove() { diary.enterBackground(); try? FileManager.default.removeItem(at: root) }
    static func ownership() -> DiarySelectionOwnership {
        DiarySelectionOwnership(identity: CoachTimelineIdentity(profileID: UUID(), timelineGeneration: UUID()), selectionEpoch: 1)
    }
    static func make(maximumBytes: Int = 350_000_000,
                     photoWorkLimiter: PhotoWorkLimiter = PhotoWorkLimiter(),
                     actionLoading: (@Sendable (UUID, DiaryStore) async throws -> DiaryReadModel)? = nil) async throws -> Self {
        let root = URL.temporaryDirectory.appending(path: "CoachDraft-" + UUID().uuidString)
        let store = DiaryStore(directory: root, maximumFileBytes: maximumBytes)
        _ = try await store.createProfile(DiaryProfile(name: "Synthetic camera draft", timeZoneID: "UTC"))
        let diary = DiaryViewModel(store: store, actionReadModelLoading: { owner in
            if let actionLoading { return try await actionLoading(owner, store) }
            return try await store.diaryReadModel(expectedProfileID: owner)
        }, photoWorkLimiter: photoWorkLimiter)
        await diary.load(createDefaultProfile: false)
        _ = try #require(diary.selection)
        return Self(diary: diary, root: root)
    }
    static func dependencies(_ diary: DiaryViewModel) -> CoachAttachmentDraft.Dependencies {
        CoachAttachmentDraft.Dependencies(store: diary.store, refresh: { token in try await diary.refresh(profileID: token.identity.profileID) })
    }
    static func operation<Value: Sendable>(gate: Task10Gate, _ operation: @escaping @MainActor () async throws -> Value) -> Task<Value, Error> {
        Task {
            do { let result = try await operation(); await gate.operationEnded(); return result }
            catch { await gate.operationEnded(); throw error }
        }
    }
}
