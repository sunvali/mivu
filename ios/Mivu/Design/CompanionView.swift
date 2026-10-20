import SwiftUI

struct CompanionView: View {
    let presentation: CompanionOutput
    let darkMode: Bool
    let size: CGFloat
    let runtime: CompanionRuntime
    var surface: CompanionSurface = .today
    var onTouch: (CompanionTouch) -> Void = { _ in }

    /// Coach is `size` wide; Today is `size` tall. Both match the rig's crop so nothing overflows.
    private var frame: CGSize {
        let aspect = runtime.cropAspect(for: surface)
        return surface == .coach ? CGSize(width: size, height: size / aspect) : CGSize(width: size * aspect, height: size)
    }

    private var animated: Bool { presentation.playback == .animated }

    var body: some View {
        Group {
            if presentation.playback != .hidden, let rig = runtime.rig {
                CompanionRigHost(rig: rig, onWindow: runtime.resumeBreathing)
                    .id(ObjectIdentifier(rig))
                    .task { await runtime.reconcileMount(rig) }
            } else {
                // Only while the rig loads or when it failed to load. The square fallback overflows its crop by transparent margin only, like the rig's framing.
                Image(runtime.fallbackAssetName(for: surface)).resizable().scaledToFit()
                    .frame(width: max(frame.width, frame.height), height: max(frame.width, frame.height))
            }
        }
        .frame(width: frame.width, height: frame.height)
        .environment(\.colorScheme, darkMode ? .dark : .light)
        .contentShape(Rectangle())
        // A hold must not also count as a tap, so the pat is tried first and the tap only follows its failure.
        .gesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            onTouch(.pat)
        }.exclusively(before: TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTouch(.tap)
        }), including: animated ? .all : .none)
        .accessibilityHidden(true)
    }
}

struct CompanionRigHost: UIViewRepresentable {
    let rig: PipRigView
    var onWindow: () -> Void = {}

    final class Container: UIView {
        var onWindow: () -> Void = {}
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { onWindow() }
        }
    }

    func makeCoordinator() -> PipRigView { rig }
    func makeUIView(context: Context) -> UIView {
        let container = Container()
        container.onWindow = onWindow
        Self.install(rig, in: container)
        return container
    }
    func updateUIView(_ view: UIView, context: Context) { Self.install(rig, in: view) }
    static func install(_ rig: PipRigView, in container: UIView) {
        guard rig.superview !== container else { return }
        rig.removeFromSuperview()
        rig.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(rig)
        NSLayoutConstraint.activate([
            rig.leadingAnchor.constraint(equalTo: container.leadingAnchor), rig.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rig.topAnchor.constraint(equalTo: container.topAnchor), rig.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
    static func dismantleUIView(_ view: UIView, coordinator: PipRigView) {
        guard coordinator.superview === view else { return }
        coordinator.removeFromSuperview()
    }
}
