import SwiftUI
import PhotosUI

struct CoachCameraView: View {
    @Bindable var draft: CoachAttachmentDraft
    let presentationID: UUID
    var retaking: UUID?
    @State private var camera = CoachCameraSession()
    @State private var state = CoachCameraSession.State()
    @State private var showLibrary = false
    @State private var selected: [PhotosPickerItem] = []
    @State private var error: String?
    @State private var importing: Task<Void, Never>?
    @State private var closing = false
    @State private var shotsAdded = 0
    @State private var countdown: Int?
    @Environment(\.scenePhase) private var scene
    @Environment(\.duoPosture) private var posture
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        cameraSurface
        .foregroundStyle(.white).tint(.white)
        .photosPicker(isPresented: $showLibrary, selection: $selected, maxSelectionCount: retaking == nil ? max(1, 8 - draft.attachments.count) : 1,
                      matching: .images, preferredItemEncoding: .current)
        .onChange(of: showLibrary) { _, visible in
            if !visible && selected.isEmpty { Task { try? await camera.libraryCancelled() } }
        }
        .onChange(of: selected) { _, items in startImport(items) }
        .alert("Could not add photo", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil; selected = []; Task { try? await camera.libraryCancelled() } }
        } message: { Text(error ?? "") }
        .task { await observeCamera() }
        .onChange(of: scene) { _, phase in Task { guard !closing else { return }; try? await camera.setForeground(phase == .active) } }
        .onDisappear {
            closing = true; importing?.cancel()
            Task { try? await draft.endPresentation(presentationID); try? await camera.close(presentationID: presentationID) }
        }
    }
    /// Propped on a table: the preview fills the standing half, the controls sit on the flat half, and the camera
    /// stays open so several plates can be snapped before Done.
    private var atTable: Bool { posture == .table && retaking == nil }
    private var cameraSurface: some View {
        DuoSplit(axis: .vertical, showsSecondary: atTable) {
            ZStack {
                Color.black.ignoresSafeArea()
                CoachCameraPreview(camera: camera, presentationID: presentationID).ignoresSafeArea(edges: atTable ? [.top, .horizontal] : .all)
                if scene != .active || !state.isRunning { statusCover }
                if let countdown {
                    Text("\(countdown)").font(.system(size: 96, weight: .bold, design: .rounded)).monospacedDigit()
                        .shadow(radius: 8).accessibilityLabel("Taking photo in \(countdown)")
                }
                if !atTable { cameraControls }
            }
        } secondary: {
            tableControls
        }
        .background(Color.black.ignoresSafeArea())
    }
    private var tableControls: some View {
        VStack(spacing: 20) {
            topControls
            Spacer(minLength: 0)
            Text(shotsAdded == 0 ? "Snap when ready." : shotsAdded == 1 ? "1 photo added" : "\(shotsAdded) photos added")
                .font(.headline).accessibilityIdentifier("coachCameraTally")
            HStack(spacing: 16) {
                libraryButton.frame(maxWidth: .infinity, alignment: .leading)
                shutterButton
                timerButton.frame(maxWidth: .infinity, alignment: .trailing)
            }
            if (DiaryLaunch.isSampleMode || DiaryLaunch.isCoachUITest), state.phase == .unavailable { syntheticButton }
            Spacer(minLength: 0)
        }.padding(24)
    }
    private var timerButton: some View {
        Button { startTimer() } label: {
            Label("3-second timer", systemImage: "timer").labelStyle(.iconOnly).font(.title2).frame(minWidth: 52, minHeight: 52)
        }
        .disabled(shutterDisabled)
        .accessibilityIdentifier("coachCameraTimer")
    }
    private var statusCover: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: state.phase == .denied ? "camera.fill.badge.ellipsis" : "camera").font(.largeTitle)
                Text(status).font(.headline).multilineTextAlignment(.center)
                if state.phase == .denied { settingsButton }
                if state.phase == .interrupted || state.phase == .failed { retryButton }
            }.padding(32)
        }
    }
    private var settingsButton: some View {
        Button("Open Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }.frame(minHeight: 44)
    }
    private var retryButton: some View {
        Button("Try camera again") {
            Task { do { try await camera.retry() } catch { self.error = "Camera could not restart. Choose photos or close." } }
        }.frame(minHeight: 44)
    }
    private var cameraControls: some View {
        VStack {
            topControls
            Spacer()
            bottomControls
            if (DiaryLaunch.isSampleMode || DiaryLaunch.isCoachUITest), state.phase == .unavailable { syntheticButton }
        }.padding(24)
    }
    private var topControls: some View {
        HStack {
            if shotsAdded > 0 {
                Button("Done") { finish() }.fontWeight(.semibold).frame(minWidth: 64, minHeight: 44).accessibilityIdentifier("coachCameraDone")
            } else {
                Button("Close") { finish() }.frame(minWidth: 64, minHeight: 44).accessibilityIdentifier("coachCameraClose")
            }
            Spacer()
            if draft.isPreparing { ProgressView("Preparing photo").tint(.white) }
        }
    }
    private var bottomControls: some View {
        HStack(spacing: 28) {
            libraryButton
            Spacer(minLength: 0)
            shutterButton
        }
    }
    private var libraryButton: some View {
        Button { choosePhotos() } label: {
            Label("Choose photos", systemImage: "photo.on.rectangle").labelStyle(.titleAndIcon).frame(minHeight: 52)
        }
        .accessibilityIdentifier("coachCameraLibrary")
        .disabled(draft.isPreparing || (retaking == nil && draft.attachments.count >= 8))
    }
    private var shutterButton: some View {
        Button { shutter() } label: {
            Circle().fill(.white).frame(width: 68, height: 68)
                .overlay { Circle().stroke(.black.opacity(0.6), lineWidth: 3).padding(5) }
        }
        .frame(minWidth: 80, minHeight: 80)
        .disabled(shutterDisabled)
        .opacity(state.isRunning ? 1 : 0.4)
        .accessibilityLabel(retaking == nil ? "Take photo" : "Retake photo")
        .accessibilityIdentifier("coachCameraShutter")
    }
    private var shutterDisabled: Bool {
        !state.isRunning || state.isCapturing || draft.isPreparing || scene != .active || closing || countdown != nil
            || (atTable && draft.attachments.count >= 8)
    }
    private func startTimer() {
        importing = Task {
            for second in (1...3).reversed() {
                countdown = second
                guard (try? await Task.sleep(for: .seconds(1))) != nil, !closing else { countdown = nil; return }
            }
            countdown = nil
            guard !shutterDisabled else { return }
            shutter()
        }
    }
    /// At the table the camera stays for the next plate; otherwise a photo returns straight to Coach.
    private func added() {
        guard !Task.isCancelled, !closing else { return }
        if atTable { shotsAdded += 1 } else { finish() }
    }
    private var syntheticButton: some View {
        Button(DiaryLaunch.isSampleMode ? "Add synthetic apple photo" : "Add synthetic test photo") {
            guard let data = PhotoImport.syntheticApple() else { return }
            importData(data)
        }.frame(minHeight: 44).accessibilityIdentifier("syntheticPhoto")
    }
    private func startImport(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        importing?.cancel()
        importing = Task {
            do {
                let selections = items.map { item in CoachAttachmentDraft.Selection {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw DiaryError.invalidData }; return data
                } }
                if let retaking, let selection = selections.first { try await draft.retake(retaking, selection: selection, presentationID: presentationID) }
                else {
                    let failures = try await draft.importSelections(selections, presentationID: presentationID)
                    if !failures.isEmpty { error = "Some photos could not be imported. Your note and other photos are kept."; return }
                }
                guard !Task.isCancelled, !closing else { return }; finish()
            } catch { if !Task.isCancelled, !closing { self.error = "Could not import photo. Your note and other photos are kept." } }
        }
    }
    private func observeCamera() async {
        let updates = await camera.updates()
        let opening: Task<Void, Never> = Task { await openCurrentCamera() }
        await withTaskCancellationHandler {
            for await value in updates { guard !Task.isCancelled else { break }; state = value }
        } onCancel: { opening.cancel() }
    }
    private func openCurrentCamera() async {
        do {
            try Task.checkCancellation()
            guard !closing, draft.isPresentationCurrent(presentationID), let owner = draft.ownership else { return }
            try await camera.setForeground(scene == .active)
            try Task.checkCancellation()
            guard !closing, draft.isPresentationCurrent(presentationID), draft.ownership == owner else { return }
            try await camera.open(presentationID: presentationID, ownership: owner)
        } catch { if !Task.isCancelled, !closing { self.error = "Camera is unavailable. Choose photos or close." } }
    }
    private var status: String {
        switch state.phase {
        case .denied: "Allow camera access in Settings, or choose photos."
        case .unavailable: "Camera is unavailable. Choose photos instead."
        case .interrupted: "Camera was interrupted. Your input is kept."
        case .failed: "Camera could not continue. Your input is kept."
        default: "Preparing camera…"
        }
    }
    private func choosePhotos() {
        Task { try? await camera.choosePhotos(); guard !closing else { return }; selected = []; showLibrary = true }
    }
    private func shutter() {
        importing = Task {
            do { try await draft.capture(using: camera, presentationID: presentationID, replacing: retaking); added() }
            catch { if !Task.isCancelled, !closing { self.error = "Could not take photo. Your note and other photos are kept." } }
        }
    }
    private func importData(_ data: Data) {
        importing = Task {
            do { _ = try await draft.importSelections([.init { data }], presentationID: presentationID); added() }
            catch { if !Task.isCancelled, !closing { self.error = "Could not add photo. Your input is kept." } }
        }
    }
    private func finish() {
        guard !closing else { return }; closing = true; importing?.cancel()
        Task { try? await draft.endPresentation(presentationID); try? await camera.close(presentationID: presentationID); dismiss() }
    }
}
