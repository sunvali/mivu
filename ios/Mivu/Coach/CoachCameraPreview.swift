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
        private let focusMark = CALayer()
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        override init(frame: CGRect) {
            super.init(frame: frame)
            focusMark.borderColor = UIColor.systemYellow.cgColor; focusMark.borderWidth = 1.5; focusMark.opacity = 0
            layer.addSublayer(focusMark)
            addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinched)))
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        }
        required init?(coder: NSCoder) { nil }
        // Each step is sent as a ratio, so steps that reach the camera out of order still land on the same zoom.
        @objc private func pinched(_ pinch: UIPinchGestureRecognizer) {
            guard pinch.state == .changed else { return }
            let scale = pinch.scale, camera = camera; pinch.scale = 1
            Task { await camera?.zoom(by: scale) }
        }
        @objc private func tapped(_ tap: UITapGestureRecognizer) {
            guard let preview = layer as? AVCaptureVideoPreviewLayer else { return }
            let point = tap.location(in: self), camera = camera
            let target = preview.captureDevicePointConverted(fromLayerPoint: point)
            Task { await camera?.focus(at: target) }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            focusMark.frame = CGRect(x: point.x - 36, y: point.y - 36, width: 72, height: 72)
            CATransaction.commit()
            let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 1; fade.toValue = 0; fade.duration = 1.2
            focusMark.add(fade, forKey: "fade")
        }
        func setSession(_ session: AVCaptureSession?) {
            guard let preview = layer as? AVCaptureVideoPreviewLayer else { return }
            preview.videoGravity = .resizeAspectFill; preview.session = session
            if let connection = preview.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        }
    }
}
