import SwiftUI
@preconcurrency import RiveRuntime

struct CompanionView: View {
    let presentation: CompanionOutput
    let darkMode: Bool
    let size: CGFloat
    let runtime: CompanionRuntime

    private var fallbackPose: CompanionPose {
        presentation.playback == .animated && !runtime.isReady && !runtime.loadFailed
            ? .resting : presentation.pose
    }

    var body: some View {
        Group {
            if presentation.playback == .animated, let player = runtime.player {
                CompanionRiveView(player: player, paused: runtime.isPaused,
                                  fps: presentation.pose == .thinking ? 30 : 60)
                    .id(ObjectIdentifier(player))
            } else {
                Image(runtime.fallbackAssetName(for: fallbackPose))
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .environment(\.colorScheme, darkMode ? .dark : .light)
        .accessibilityHidden(true)
    }
}

private struct CompanionRiveView: UIViewRepresentable {
    let player: RiveViewModel
    let paused: Bool
    let fps: Int

    func makeCoordinator() -> RiveViewModel { player }

    func makeUIView(context: Context) -> RiveView {
        let view = player.createRiveView()
        if !paused { player.play() }
        return view
    }

    func updateUIView(_ view: RiveView, context: Context) {
        player.update(view: view)
        player.setPreferredFramesPerSecond(preferredFramesPerSecond: fps)
        if paused { player.pause() }
    }

    static func dismantleUIView(_ view: RiveView, coordinator: RiveViewModel) {
        coordinator.pause()
        coordinator.deregisterView()
    }
}
