import SwiftUI

struct CompanionView: View {
    let presentation: CompanionOutput
    let darkMode: Bool
    let size: CGFloat
    let runtime: CompanionRuntime
    var surface: CompanionSurface = .today
    var onTouch: (CompanionTouch) -> Void = { _ in }

    private var animated: Bool { presentation.playback == .animated }

    var body: some View {
        Group {
            if animated, let rig = runtime.rig {
                CompanionRigHost(rig: rig, onWindow: runtime.resumeBreathing)
                    .id(ObjectIdentifier(rig))
                    .task { await runtime.reconcileMount(rig) }
            } else {
                Image(runtime.fallbackAssetName(for: surface)).resizable().scaledToFit()
            }
        }
        // Coach crops the rig to 76 x 66 so paws and tail are never clipped.
        .frame(width: size, height: surface == .coach ? size * 66 / 76 : size)
        .environment(\.colorScheme, darkMode ? .dark : .light)
        .contentShape(Rectangle())
        .gesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTouch(.tap)
        }, including: animated ? .all : .none)
        .gesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            onTouch(.pat)
        }, including: animated ? .all : .none)
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
