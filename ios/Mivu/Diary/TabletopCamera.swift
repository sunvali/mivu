import AVFoundation
import SwiftUI

/// The iPhone Duo propped half-open on a table: the preview fills the upright half and the
/// shutter sits on the flat half, so a plate can be snapped hands-free. Permission is
/// already granted by `PhotoInput.openCamera()` before this appears.
struct TabletopCameraView: View {
    let preparation: PhotoPreparation
    let onPhoto: (Data) -> Void
    let onFailure: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var camera = TabletopCameraSession()
    @State private var capturing = false

    var body: some View {
        VStack(spacing: 0) {
            CameraPreview(session: camera.session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Camera preview")
            VStack(spacing: 16) {
                Text("Snap when ready.").font(.headline).foregroundStyle(Color.diaryText)
                    .accessibilityIdentifier("tabletopPrompt")
                HStack {
                    Button("Cancel") { dismiss() }.frame(minWidth: 44, minHeight: 44)
                    Spacer()
                    Button { Task { await capture() } } label: {
                        Circle().strokeBorder(Color.diaryAccent, lineWidth: 4).frame(width: 72, height: 72)
                    }
                    .disabled(capturing || preparation.isPreparing)
                    .accessibilityLabel("Take photo")
                    .accessibilityIdentifier("tabletopShutter")
                    Spacer()
                    Color.clear.frame(width: 64, height: 44)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.diaryCanvas)
        }
        .tint(.diaryAccent)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    private func capture() async {
        capturing = true
        defer { capturing = false }
        guard let data = await camera.capture(), let image = UIImage(data: data),
              let bytes = try? await CameraCapture.preparePhoto(image, preparation: preparation) else {
            onFailure(); dismiss(); return
        }
        onPhoto(bytes)
        dismiss()
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: PreviewView, context: Context) {}
}

/// Owns the capture session; session work runs on its own queue, as AVFoundation requires.
private final class TabletopCameraSession: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "tabletop.camera")
    private var pending: CheckedContinuation<Data?, Never>?

    func start() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                if session.inputs.isEmpty, let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                   let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input), session.canAddOutput(output) {
                    session.beginConfiguration()
                    session.sessionPreset = .photo
                    session.addInput(input)
                    session.addOutput(output)
                    session.commitConfiguration()
                }
                if !session.isRunning { session.startRunning() }
                done.resume()
            }
        }
    }

    func stop() { queue.async { [self] in if session.isRunning { session.stopRunning() } } }

    func capture() async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard pending == nil, session.isRunning else { continuation.resume(returning: nil); return }
                pending = continuation
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        queue.async { [self] in pending?.resume(returning: data); pending = nil }
    }
}
