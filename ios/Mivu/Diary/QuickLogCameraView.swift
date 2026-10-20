import SwiftUI
import AVFoundation

/// The Log Food camera: one shutter tap saves the photo as a meal on this iPhone; analysis follows on Today.
struct QuickLogCameraView: View {
    let model: DiaryViewModel
    let ownership: DiarySelectionOwnership
    let onLogged: (UUID) -> Void
    @State private var camera = CoachCameraSession()
    @State private var state = CoachCameraSession.State()
    @State private var presentationID = UUID()
    @State private var unsaved: MealDraft?
    @State private var saving = false
    @State private var error: String?
    @AppStorage("quickLogFlash") private var flash = AVCaptureDevice.FlashMode.auto.rawValue
    @Environment(\.scenePhase) private var scene
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CoachCameraPreview(camera: camera, presentationID: presentationID).ignoresSafeArea()
            if scene != .active || !state.isRunning { statusCover }
            controls
        }
        .foregroundStyle(.white).tint(.white)
        .task { await observeCamera() }
        .onChange(of: scene) { _, phase in Task { try? await camera.setForeground(phase == .active) } }
        .onDisappear { Task { try? await camera.close(presentationID: presentationID) } }
        .alert("Could not log photo", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            if let unsaved { Button("Try Again") { save(unsaved) } }
            Button(unsaved == nil ? "OK" : "Discard Photo", role: unsaved == nil ? .cancel : .destructive) { unsaved = nil }
        } message: { Text(error ?? "") }
    }
    private var statusCover: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: state.phase == .denied ? "camera.fill.badge.ellipsis" : "camera").font(.largeTitle)
                Text(status).font(.headline).multilineTextAlignment(.center)
                if state.phase == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }.frame(minHeight: 44)
                }
                if state.phase == .interrupted || state.phase == .failed {
                    Button("Try camera again") { Task { try? await camera.retry() } }.frame(minHeight: 44)
                }
            }.padding(32)
        }
    }
    private var status: String {
        switch state.phase {
        case .denied: "Allow camera access in Settings to log meals with a photo."
        case .unavailable: "Camera is unavailable on this device."
        case .interrupted: "Camera was interrupted."
        case .failed: "Camera could not continue."
        default: "Preparing camera…"
        }
    }
    private var controls: some View {
        VStack {
            HStack {
                Button("Close") { dismiss() }.frame(minWidth: 64, minHeight: 44).disabled(saving).accessibilityIdentifier("quickLogClose")
                Spacer()
                if state.hasFlash { flashButton }
            }
            Spacer()
            if saving { ProgressView("Logging meal").tint(.white) }
            else { Text("Snap your meal to log it").font(.subheadline).shadow(radius: 4).accessibilityHidden(true) }
            shutterButton.padding(.top, 12)
            if (DiaryLaunch.isSampleMode || DiaryLaunch.isUITest), state.phase == .unavailable {
                Button("Add synthetic test photo") { if let data = PhotoImport.syntheticApple() { save(MealDraft(photos: [data])) } }
                    .frame(minHeight: 44).disabled(saving).accessibilityIdentifier("quickLogSyntheticPhoto")
            }
        }.padding(24)
    }
    private var flashButton: some View {
        let mode = AVCaptureDevice.FlashMode(rawValue: flash) ?? .auto
        let (icon, name, next): (String, String, AVCaptureDevice.FlashMode) = switch mode {
        case .on: ("bolt.fill", "On", .off)
        case .off: ("bolt.slash.fill", "Off", .auto)
        default: ("bolt.badge.automatic.fill", "Auto", .on)
        }
        return Button { flash = next.rawValue } label: {
            Image(systemName: icon).font(.title3).foregroundStyle(mode == .on ? .yellow : .white)
                .frame(width: 44, height: 44).background(.black.opacity(0.35), in: .circle)
        }
        .accessibilityLabel("Flash").accessibilityValue(name).accessibilityIdentifier("quickLogFlash")
    }
    private var shutterButton: some View {
        Button { shutter() } label: {
            Circle().fill(.white).frame(width: 68, height: 68)
                .overlay { Circle().stroke(.black.opacity(0.6), lineWidth: 3).padding(5) }
        }
        .frame(minWidth: 80, minHeight: 80)
        .disabled(!state.isRunning || state.isCapturing || saving || scene != .active)
        .opacity(state.isRunning ? 1 : 0.4)
        .accessibilityLabel("Take photo and log meal")
        .accessibilityIdentifier("quickLogShutter")
    }
    private func observeCamera() async {
        let updates = await camera.updates()
        let opening = Task {
            try? await camera.setForeground(scene == .active)
            try? await camera.open(presentationID: presentationID, ownership: ownership)
        }
        await withTaskCancellationHandler {
            for await value in updates { guard !Task.isCancelled else { break }; state = value }
        } onCancel: { opening.cancel() }
    }
    private func shutter() {
        saving = true
        Task {
            do {
                let photo = try await camera.capture(flash: AVCaptureDevice.FlashMode(rawValue: flash) ?? .auto)
                save(MealDraft(photos: [try await CoachAttachmentDraft.normalize(photo, source: .camera)]))
            } catch { saving = false; self.error = "Could not take photo. Try again." }
        }
    }
    // Try Again resends the same draft, so its submission ID lets the diary recognise a save that already landed.
    private func save(_ draft: MealDraft) {
        saving = true; unsaved = draft
        Task {
            let result = await model.capture(draft, destination: .automatic, expectedSelection: ownership)
            saving = false
            if case .saved(let id) = result { unsaved = nil; onLogged(id); return }
            // Shown here because the root alert cannot appear over this full-screen camera.
            error = model.errorMessage ?? "The photo was not saved. Try again."
            model.errorMessage = nil
        }
    }
}
