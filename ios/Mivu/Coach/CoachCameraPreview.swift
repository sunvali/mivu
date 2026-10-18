import SwiftUI
@preconcurrency import AVFoundation

@MainActor protocol CoachPreviewTarget: AnyObject {
    func setSession(_ session: AVCaptureSession?)
}
protocol CoachPreviewSource: Sendable {
    @MainActor func connect(to target: any CoachPreviewTarget)
}

// AVCam's narrow legacy interop capability; only this adapter attaches the private session.
final class CoachDefaultPreviewSource: CoachPreviewSource {
    private let session: AVCaptureSession
    init(session: AVCaptureSession) { self.session = session }
    @MainActor func connect(to target: any CoachPreviewTarget) { target.setSession(session) }
}

struct CoachCameraPreview: UIViewRepresentable {
    let camera: CoachCameraSession
    let presentationID: UUID
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.camera = camera; view.presentationID = presentationID
        camera.previewSource.connect(to: view)
        Task { await camera.previewAttached(presentationID: presentationID) }
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) { }
    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) {
        uiView.isHidden = true
        let camera = uiView.camera, id = uiView.presentationID
        Task { try? await camera?.close(presentationID: id); uiView.setSession(nil) }
    }
    final class PreviewView: UIView, CoachPreviewTarget {
        var camera: CoachCameraSession?
        var presentationID: UUID?
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        func setSession(_ session: AVCaptureSession?) {
            guard let preview = layer as? AVCaptureVideoPreviewLayer else { return }
            preview.videoGravity = .resizeAspectFill; preview.session = session
            if let connection = preview.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        }
    }
}
