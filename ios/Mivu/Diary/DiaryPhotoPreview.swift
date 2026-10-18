import SwiftUI

extension Notification.Name { static let coachThumbnailDidPublish = Notification.Name("Mivu.CoachThumbnailDidPublish") }

struct DiaryPhotoRequest: Hashable, Sendable {
    var profileID: UUID?
    var epoch: UInt64?
    var timeline: UUID?
    var reference: DiaryPhotoReference.Identity
    var generation: UInt64
}

struct DiaryPhotoPreview: View {
    @Bindable var model: DiaryViewModel
    let reference: DiaryPhotoReference
    var height: CGFloat = 180
    var afterLoad: (@Sendable (DiaryPhotoRequest, DiaryPhotoThumbnail) async -> Void)? = nil
    var onAssignment: (@MainActor (DiaryPhotoRequest, Bool) -> Void)? = nil
    var onCompletion: (@MainActor (DiaryPhotoRequest, Bool) -> Void)? = nil
    @State private var image: CGImage?
    @State private var requestID = UUID()
    private var request: DiaryPhotoRequest { DiaryPhotoRequest(profileID: model.selection?.identity.profileID,
        epoch: model.selection?.selectionEpoch, timeline: model.selection?.identity.timelineGeneration,
        reference: reference.id, generation: model.photoRequestGeneration) }
    var body: some View {
        Group {
            if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(Color.diarySecondary) }
        }
        .frame(maxWidth: .infinity).frame(height: height).clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore).accessibilityLabel("Saved attachment").accessibilityHidden(false)
        .accessibilityIdentifier("coachPhoto-" + reference.photoID.uuidString)
        .accessibilityValue(image == nil ? "Loading photo" : "Photo loaded")
        .task(id: request) {
            let captured = request, operation = UUID(); requestID = operation; image = nil
            guard !model.isChangingProfile, captured.profileID == captured.reference.profileID,
                  captured.epoch != nil, captured.timeline != nil, let loader = model.photoLoader else {
                onCompletion?(captured, false); return
            }
            do {
                let result = try await loader.thumbnail(for: reference, pixelSize: 512)
                await afterLoad?(captured, result)
                #if DEBUG
                if DiaryLaunch.isCoachHistoryFixture, ProcessInfo.processInfo.arguments.contains("--history-hold-photos") {
                    await CoachHistoryPhotoGate.shared.wait()
                }
                #endif
                guard !Task.isCancelled, !model.isChangingProfile, captured == request, captured.profileID == captured.reference.profileID, requestID == operation else { onCompletion?(captured, false); return }
                image = result.image; onAssignment?(captured, true); onCompletion?(captured, true)
                #if DEBUG
                if DiaryLaunch.isCoachHistoryFixture { NotificationCenter.default.post(name: .coachThumbnailDidPublish, object: nil, userInfo: ["photoID": reference.photoID]) }
                #endif
            } catch {
                guard !Task.isCancelled, !model.isChangingProfile, captured == request, captured.profileID == captured.reference.profileID, requestID == operation else { onCompletion?(captured, false); return }
                image = nil; onAssignment?(captured, false); onCompletion?(captured, true)
            }
        }
    }
}
