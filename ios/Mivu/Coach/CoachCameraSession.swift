import Foundation
import Dispatch
@preconcurrency import AVFoundation

enum CoachCameraFailure: Error, Equatable, Sendable {
    case unavailable, stalePresentation, captureFailed, busy
}

actor CoachCameraSession {
    enum Authorization: Equatable, Sendable { case authorized, denied, restricted }
    enum Destination: Equatable, Sendable { case camera, library }
    enum Phase: Equatable, Sendable { case closed, running, paused, interrupted, unavailable, denied, failed }
    struct State: Equatable, Sendable {
        var presentationID: UUID?
        var destination: Destination?
        var phase: Phase = .closed
        var isRunning = false
        var canChoosePhotos = false
        var canClose = false
        var isCapturing = false
        var hasFlash = false
    }
    struct Dependencies: Sendable {
        let available: @Sendable () -> Bool
        let authorization: @Sendable () async -> Authorization
        let capture: @Sendable () async throws -> Data
    }
    private let dependencies: Dependencies?
    private nonisolated let queue = DispatchSerialQueue(label: "Mivu.CoachCamera")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }
    private let session: AVCaptureSession
    private let output = AVCapturePhotoOutput()
    nonisolated let previewSource: any CoachPreviewSource
    private var configured = false
    private var foreground = true
    private var authorized = false
    private var interruptionActive = false
    private var generation: UInt64 = 0
    private var attachedPresentationID: UUID?
    private var observers: [NSObjectProtocol] = []
    private var subscribers: [UUID: AsyncStream<State>.Continuation] = [:]
    private struct CaptureRequest {
        let delegate: PhotoDelegate
        let generation: UInt64
        var continuation: CheckedContinuation<Data, Error>?
        var data: Data?
        var failed = false
        var finished = false
    }
    private var requests: [UUID: CaptureRequest] = [:]
    private(set) var state = State()

    init(dependencies: Dependencies? = nil) {
        self.dependencies = dependencies
        let session = AVCaptureSession(); self.session = session
        previewSource = CoachDefaultPreviewSource(session: session)
    }
    func updates() -> AsyncStream<State> {
        let id = UUID(), stream = AsyncStream<State>.makeStream()
        subscribers[id] = stream.continuation; stream.continuation.yield(state)
        stream.continuation.onTermination = { [weak self] _ in Task { await self?.unsubscribe(id) } }
        return stream.stream
    }
    private func unsubscribe(_ id: UUID) { subscribers[id] = nil }
    private func publish() { for subscriber in subscribers.values { subscriber.yield(state) } }

    func previewAttached(presentationID: UUID) {
        attachedPresentationID = presentationID
        if state.presentationID == presentationID, authorized { try? resumeIfVisible() }
    }
    func open(presentationID: UUID, ownership: DiarySelectionOwnership) async throws {
        try Task.checkCancellation()
        let previewAlreadyAttached = attachedPresentationID == presentationID
        try close()
        if previewAlreadyAttached { attachedPresentationID = presentationID }
        interruptionActive = false
        generation &+= 1; let expected = generation
        state = State(presentationID: presentationID, destination: .camera, phase: .paused,
                      canChoosePhotos: true, canClose: true, isCapturing: !requests.isEmpty)
        publish()
        let available = dependencies?.available() ?? (AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil)
        guard available else { state.phase = .unavailable; publish(); return }
        let permission: Authorization
        if let dependencies { permission = await dependencies.authorization() }
        else {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: permission = .authorized
            case .notDetermined: permission = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
            case .restricted: permission = .restricted
            default: permission = .denied
            }
        }
        if Task.isCancelled {
            if generation == expected, state.presentationID == presentationID { try close(presentationID: presentationID) }
            throw CancellationError()
        }
        guard generation == expected, state.presentationID == presentationID else { throw CoachCameraFailure.stalePresentation }
        authorized = permission == .authorized
        guard authorized else { state.phase = .denied; publish(); return }
        do { try resumeIfVisible() }
        catch { state.phase = .failed; publish(); throw error }
    }
    private func configure() throws {
        guard !configured, dependencies == nil else { return }
        session.beginConfiguration(); defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw CoachCameraFailure.unavailable }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(output) else { throw CoachCameraFailure.unavailable }
        session.addInput(input); session.addOutput(output)
        state.hasFlash = device.hasFlash
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        configured = true
        observeSession()
    }
    private func observeSession() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
                Task { try? await self?.interrupted() }
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
                Task { try? await self?.retry() }
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] _ in
                Task { await self?.runtimeFailure() }
            }
        ]
    }
    private func resumeIfVisible() throws {
        try Task.checkCancellation()
        guard state.presentationID != nil, authorized, foreground, !interruptionActive, state.destination == .camera else { publish(); return }
        guard dependencies != nil || attachedPresentationID == state.presentationID else { state.phase = .paused; publish(); return }
        try configure()
        try Task.checkCancellation()
        if dependencies == nil, !session.isRunning { session.startRunning() }
        if Task.isCancelled { pause(); throw CancellationError() }
        state.isRunning = dependencies != nil || session.isRunning
        state.phase = state.isRunning ? .running : .failed
        publish()
    }
    private func pause() {
        if dependencies == nil, session.isRunning { session.stopRunning() }
        state.isRunning = false
        if state.phase == .running { state.phase = .paused }
        for id in Array(requests.keys) { cancelCapture(id) }
    }
    func choosePhotos() async throws { guard state.presentationID != nil else { return }; state.destination = .library; pause(); publish() }
    func libraryCancelled() async throws { guard state.presentationID != nil else { return }; state.destination = .camera; try resumeIfVisible() }
    func setForeground(_ foreground: Bool) async throws {
        self.foreground = foreground
        if foreground, state.presentationID != nil, dependencies == nil {
            authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            if !authorized { pause(); state.phase = .denied; publish(); return }
        }
        if foreground { try resumeIfVisible() } else { pause(); publish() }
    }
    func interrupted() async throws {
        guard state.presentationID != nil else { return }
        interruptionActive = true; pause(); state.phase = .interrupted; publish()
    }
    private func runtimeFailure() { guard state.presentationID != nil else { return }; pause(); state.phase = .failed; publish() }
    func retry() async throws {
        guard state.presentationID != nil else { return }
        if dependencies == nil {
            guard !session.isInterrupted else { return }
            authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            if !authorized { state.phase = .denied; publish(); return }
        }
        interruptionActive = false
        try resumeIfVisible()
    }
    func close(presentationID: UUID? = nil) throws {
        if let presentationID, state.presentationID != presentationID { return }
        generation &+= 1; pause(); authorized = false; attachedPresentationID = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }; observers = []
        if configured {
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            for output in session.outputs { session.removeOutput(output) }
            session.commitConfiguration(); configured = false
        }
        state = State(); publish()
    }
    nonisolated static func photoSettings(flash: AVCaptureDevice.FlashMode, supported: [AVCaptureDevice.FlashMode]) -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.flashMode = supported.contains(flash) ? flash : .off
        settings.photoQualityPrioritization = .balanced
        return settings
    }
    func capture(flash: AVCaptureDevice.FlashMode = .off) async throws -> Data {
        guard state.isRunning, foreground, state.destination == .camera else { throw CoachCameraFailure.unavailable }
        guard requests.isEmpty, !state.isCapturing else { throw CoachCameraFailure.busy }
        let expected = generation, presentation = state.presentationID
        state.isCapturing = true; publish()
        defer { state.isCapturing = !requests.isEmpty; publish() }
        if let dependencies {
            let data = try await dependencies.capture()
            try Task.checkCancellation()
            guard generation == expected, state.presentationID == presentation, state.isRunning else { throw CoachCameraFailure.stalePresentation }
            return data
        }
        let id = UUID()
        let bytes: Data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let delegate = PhotoDelegate(owner: self, id: id)
                requests[id] = CaptureRequest(delegate: delegate, generation: expected, continuation: continuation)
                output.capturePhoto(with: Self.photoSettings(flash: flash, supported: output.supportedFlashModes), delegate: delegate)
            }
        } onCancel: { Task { await self.cancelCapture(id) } }
        try Task.checkCancellation()
        guard generation == expected, state.presentationID == presentation, state.isRunning else { throw CoachCameraFailure.stalePresentation }
        return bytes
    }
    private func cancelCapture(_ id: UUID) {
        guard var request = requests[id] else { return }
        request.continuation?.resume(throwing: CoachCameraFailure.stalePresentation); request.continuation = nil; requests[id] = request
    }
    private func processed(_ id: UUID, data: Data?) {
        guard var request = requests[id] else { return }
        request.data = data; request.failed = data == nil; requests[id] = request; finishIfReady(id)
    }
    private func finished(_ id: UUID, failed: Bool) {
        guard var request = requests[id] else { return }
        request.finished = true; request.failed = request.failed || failed; requests[id] = request; finishIfReady(id)
    }
    private func finishIfReady(_ id: UUID) {
        guard let request = requests[id], request.finished, request.data != nil || request.failed else { return }
        requests[id] = nil; state.isCapturing = !requests.isEmpty; publish()
        guard let continuation = request.continuation else { return }
        if request.generation != generation { continuation.resume(throwing: CoachCameraFailure.stalePresentation) }
        else if let data = request.data, !request.failed { continuation.resume(returning: data) }
        else { continuation.resume(throwing: CoachCameraFailure.captureFailed) }
    }
    private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
        let owner: CoachCameraSession
        let id: UUID
        init(owner: CoachCameraSession, id: UUID) { self.owner = owner; self.id = id }
        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            let data = error == nil ? photo.fileDataRepresentation() : nil
            let owner = owner, id = id
            Task { await owner.processed(id, data: data) }
        }
        func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
            let failed = error != nil
            let owner = owner, id = id
            Task { await owner.finished(id, failed: failed) }
        }
    }
}
