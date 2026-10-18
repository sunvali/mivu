import SwiftUI
import PhotosUI
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

struct CameraCapture: UIViewControllerRepresentable {
    let preparation: PhotoPreparation
    let onPhoto: (Data) -> Void
    let onFailure: () -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}
    static func dismantleUIViewController(_ picker: UIImagePickerController, coordinator: Coordinator) { coordinator.cancel() }
    @MainActor static func preparePhoto(_ image: UIImage, preparation: PhotoPreparation,
                                        normalize: @escaping @Sendable (CameraCaptureImage) throws -> Data = { try PhotoImport.normalize($0) }) async throws -> Data? {
        try Task.checkCancellation()
        guard let cgImage = image.cgImage else { throw DiaryError.invalidData }
        let pixels = CameraCaptureImage(image: cgImage, orientation: image.imageOrientation.rawValue)
        let generation = preparation.begin()
        defer { preparation.finish(generation) }
        return try await preparation.load(generation, using: { try normalize(pixels) })
    }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture
        private var active = true
        private var task: Task<Void, Never>?
        init(_ parent: CameraCapture) { self.parent = parent }
        func cancel() { active = false; task?.cancel(); task = nil }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { cancel(); parent.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard active, task == nil else { return }
            guard let image = info[.originalImage] as? UIImage else { parent.onFailure(); parent.dismiss(); return }
            task = Task {
                do {
                    let bytes = try await CameraCapture.preparePhoto(image, preparation: parent.preparation)
                    guard active, !Task.isCancelled else { return }
                    active = false
                    if let bytes { parent.onPhoto(bytes) }
                    parent.dismiss()
                } catch {
                    guard active, !Task.isCancelled else { return }
                    active = false; parent.onFailure(); parent.dismiss()
                }
            }
        }
    }
}

struct CameraCaptureImage: Sendable {
    let image: CGImage
    let orientation: Int
}

enum PhotoImport {
    static func visionCopies(_ originals: [Data]) throws -> [Data] {
        guard originals.count <= 30 else { throw ResponsesClient.Failure.invalidInput }
        if originals.isEmpty { return [] }
        let budget = min(524_288, 4_194_304 / originals.count)
        return try originals.map { data in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw ResponsesClient.Failure.invalidInput }
            for pixels in [1280, 960, 720, 480, 320] {
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixels,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ] as CFDictionary) else { throw ResponsesClient.Failure.invalidInput }
                for quality in [0.7, 0.5, 0.3] {
                    if let copy = UIImage(cgImage: image).jpegData(compressionQuality: quality), copy.count <= budget { return copy }
                }
            }
            throw ResponsesClient.Failure.limitExceeded
        }
    }
    static func jpeg(_ data: Data) -> Data? {
        try? normalize(data)
    }
    static func normalize(_ data: Data) throws -> Data {
        try Task.checkCancellation()
        guard data.count <= 40_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw DiaryError.invalidData }
        try Task.checkCancellation()
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw DiaryError.invalidData }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= 5_000_000 else { throw DiaryError.invalidData }
        try Task.checkCancellation()
        return output as Data
    }
    static func normalize(_ capture: CameraCaptureImage) throws -> Data {
        try Task.checkCancellation()
        let orientation = UIImage.Orientation(rawValue: capture.orientation) ?? .up
        let rotated = [UIImage.Orientation.left, .leftMirrored, .right, .rightMirrored].contains(orientation)
        let size = CGSize(width: CGFloat(rotated ? capture.image.height : capture.image.width), height: CGFloat(rotated ? capture.image.width : capture.image.height))
        let image = UIImage(cgImage: capture.image, scale: 1, orientation: orientation)
        guard let bytes = jpeg(image, size: size) else { throw DiaryError.invalidData }
        try Task.checkCancellation()
        return bytes
    }
    static func jpeg(_ image: UIImage) -> Data? {
        jpeg(image, size: image.size)
    }
    private static func jpeg(_ image: UIImage, size: CGSize) -> Data? {
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return nil }
        let scale = min(1, 1600 / max(size.width, size.height))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: size.width * scale, height: size.height * scale), format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale))) }
        guard let bytes = rendered.jpegData(compressionQuality: 0.72), bytes.count <= 5_000_000 else { return nil }
        return bytes
    }
    static func syntheticApple() -> Data? {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300), format: format).image { context in
            UIColor.systemBackground.setFill(); context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
            ("🍎" as NSString).draw(at: CGPoint(x: 60, y: 45), withAttributes: [.font: UIFont.systemFont(ofSize: 160)])
        }.jpegData(compressionQuality: 0.8)
    }
}

struct PhotoInput: View {
    @Binding var photos: [Data]
    @Environment(\.diaryPhotoLimiter) private var limiter
    let preparation: PhotoPreparation
    @Binding var importFailed: Bool
    @State private var selected: [PhotosPickerItem] = []
    @State private var showCamera = false
    private enum Notice { case cameraDenied, importFailure([Int]) }
    @State private var notice: Notice?
    @State private var importTask: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { cameraButton; libraryButton }
                VStack(alignment: .leading, spacing: 12) { cameraButton; libraryButton }
            }
            Text("\(photos.count) of 8 photos").font(.caption).foregroundStyle(Color.diarySecondary)
            if !UIImagePickerController.isSourceTypeAvailable(.camera) {
                Text(DiaryLaunch.isSampleMode ? "Camera is unavailable here. Choose Photos or use the synthetic sample." : "Camera is unavailable here. Choose Photos instead.").font(.caption).foregroundStyle(Color.diarySecondary)
                if DiaryLaunch.isSampleMode || DiaryLaunch.isCoachUITest { Button(DiaryLaunch.isSampleMode ? "Add synthetic apple photo" : "Add synthetic test photo") { if let data = PhotoImport.syntheticApple() { photos.append(data) } }.frame(minHeight: 44).disabled(photos.count >= 8 || preparation.isPreparing).accessibilityIdentifier("syntheticPhoto") }
            }
            if preparation.isPreparing { ProgressView("Importing photo") }
            if !photos.isEmpty {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
                            VStack(spacing: 4) {
                                if let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill().frame(width: 112, height: 112).clipped().clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Attached meal photo \(index + 1)") }
                                Button("Remove", role: .destructive) { photos.remove(at: index) }.frame(minWidth: 44, minHeight: 44).accessibilityLabel("Remove photo \(index + 1)")
                            }
                        }
                    }
                }
            }
        }
        .onAppear { preparation.use(limiter: limiter) }
        .buttonStyle(.borderless)
        .tint(.diaryAccent)
        .sheet(isPresented: $showCamera) { CameraCapture(preparation: preparation, onPhoto: { if photos.count < 8 { photos.append($0) } }, onFailure: { importFailed = true }).ignoresSafeArea() }
        .alert(noticeTitle, isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } }), presenting: notice) { value in
            switch value {
            case .cameraDenied:
                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                Button("Cancel", role: .cancel) {}
            case .importFailure:
                Button("OK", role: .cancel) {}
            }
        } message: { value in
            switch value {
            case .cameraDenied:
                Text("Allow camera access in Settings, or choose a photo instead.")
            case .importFailure(let positions):
                Text("\(positions.map { "Photo \($0)" }.joined(separator: ", ")) from this selection could not be imported. Your other photos and note are preserved. Choose a smaller image or another photo.")
            }
        }
        .onChange(of: selected) { _, selection in
            guard !selection.isEmpty else { return }
            importTask?.cancel()
            let generation = preparation.begin()
            importTask = Task {
                var failedPositions: [Int] = []
                defer {
                    if preparation.isCurrent(generation) {
                        preparation.finish(generation); selected = []; importTask = nil
                        if !failedPositions.isEmpty { notice = .importFailure(failedPositions) }
                    }
                }
                for (position, item) in selection.enumerated() {
                    do {
                        guard let jpeg = try await preparation.load(generation, using: {
                            guard let data = try await item.loadTransferable(type: Data.self), let jpeg = PhotoImport.jpeg(data) else { throw DiaryError.invalidData }
                            return jpeg
                        }) else { return }
                        guard photos.count < 8 else { failedPositions.append(position + 1); continue }
                        photos.append(jpeg)
                    } catch {
                        guard preparation.isCurrent(generation), !Task.isCancelled else { return }
                        failedPositions.append(position + 1)
                    }
                }
            }
        }
    }

    private var cameraButton: some View {
        Button { Task { await openCamera() } } label: {
            Label("Camera", systemImage: "camera").frame(minHeight: 44)
        }
        .buttonStyle(.glass).tint(.diaryAccent)
        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera) || photos.count >= 8 || preparation.isPreparing)
    }
    private var libraryButton: some View {
        PhotosPicker(selection: $selected, maxSelectionCount: max(1, 8 - photos.count), matching: .images) {
            Label("Photo library", systemImage: "photo.on.rectangle").frame(minHeight: 44)
        }
        .buttonStyle(.glass).tint(.diaryAccent)
        .disabled(photos.count >= 8 || preparation.isPreparing)
    }

    private var noticeTitle: String {
        if case .some(.cameraDenied) = notice { "Camera access is off" } else { "Could not import selected photos" }
    }
    private func openCamera() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized { showCamera = true }
        else if status == .notDetermined {
            if await AVCaptureDevice.requestAccess(for: .video) { showCamera = true }
            else { notice = .cameraDenied }
        } else { notice = .cameraDenied }
    }
}
