import SwiftUI
import Lottie

struct CompanionView: View {
    let presentation: CompanionOutput
    let darkMode: Bool
    let size: CGFloat
    let runtime: CompanionRuntime
    var surface: CompanionSurface = .today

    private var fallbackPose: CompanionPose {
        presentation.playback == .animated && !runtime.isReady && !runtime.loadFailed ? .resting : presentation.pose
    }

    var body: some View {
        Group {
            if presentation.playback == .animated, let player = runtime.player {
                CompanionLottieView(player: player, paused: runtime.isPaused)
                    .id(ObjectIdentifier(player))
                    .task { await runtime.reconcileMount(player) }
            } else {
                Image(surface == .coach ? runtime.character.fallbackAssetPrefix + "Coach" : runtime.fallbackAssetName(for: fallbackPose)).resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .environment(\.colorScheme, darkMode ? .dark : .light)
        .accessibilityHidden(true)
    }
}

struct CompanionLottieView: UIViewRepresentable {
    let player: LottieAnimationView
    let paused: Bool

    func makeCoordinator() -> LottieAnimationView { player }
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        Self.install(player, in: container)
        return container
    }
    func updateUIView(_ view: UIView, context: Context) {
        Self.install(player, in: view)
        if paused { player.pause() }
    }
    static func install(_ player: LottieAnimationView, in container: UIView) {
        guard player.superview !== container else { return }
        player.removeFromSuperview()
        player.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(player)
        NSLayoutConstraint.activate([
            player.leadingAnchor.constraint(equalTo: container.leadingAnchor), player.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            player.topAnchor.constraint(equalTo: container.topAnchor), player.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
    static func dismantleUIView(_ view: UIView, coordinator: LottieAnimationView) {
        guard coordinator.superview === view else { return }
        coordinator.pause()
        coordinator.removeFromSuperview()
    }
}
