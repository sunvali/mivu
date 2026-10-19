#if DEBUG
import SwiftUI

/// Debug screen for judging the layered head at shipping sizes; launch with `-PipRigPreview`.
struct PipRigPreview: View {
    @State private var pose = PipPose.rest
    @State private var flick = 0

    var body: some View {
        VStack(spacing: 24) {
            HStack(alignment: .bottom, spacing: 24) {
                RigRepresentable(pose: pose, flick: flick).frame(width: 200, height: 200)
                RigRepresentable(pose: pose, flick: flick).frame(width: 64, height: 64)
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 12) {
                GridRow {
                    button("Blink") { await hold { $0.eyes = .closedSleepy } }
                    button("Glance") { await hold(for: 600) { $0.gaze = CGPoint(x: 1, y: -0.4) } }
                    button("Talk") { await talk() }
                    button("Ear flick") { flick += 1 }
                }
                GridRow {
                    button("Turn left") { pose.headTurn = -1 }
                    button("Turn front") { pose.headTurn = 0 }
                    button("Turn right") { pose.headTurn = 1 }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func button(_ title: String, _ action: @escaping () async -> Void) -> some View {
        Button(title) { Task { await action() } }
            .buttonStyle(.bordered)
            .fixedSize().frame(minHeight: 44)
            .accessibilityLabel(title)
    }

    private func hold(for milliseconds: Int = 120, _ change: (inout PipPose) -> Void) async {
        let before = pose
        change(&pose)
        try? await Task.sleep(for: .milliseconds(milliseconds))
        pose = before
    }

    private func talk() async {
        let before = pose
        for mouth in [PipPose.MouthShape.smallOpen, .bigOpen, .o, .smallOpen, .bigOpen, before.mouth] {
            pose.mouth = mouth
            try? await Task.sleep(for: .milliseconds(120))
        }
    }
}

private struct RigRepresentable: UIViewRepresentable {
    let pose: PipPose
    let flick: Int

    final class Coordinator { var flick = 0 }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PipRigView {
        let url = Bundle.main.url(forResource: "Characters/pip/pip-rig.json", withExtension: nil)!
        let view = PipRigView(asset: try! PipRigAsset.load(Data(contentsOf: url)), set: .seated)
        view.visibleRect = CGRect(x: 30, y: 22, width: 280, height: 280)
        context.coordinator.flick = flick
        return view
    }

    func updateUIView(_ view: PipRigView, context: Context) {
        view.apply(pose, animated: true)
        guard context.coordinator.flick != flick else { return }
        context.coordinator.flick = flick
        for ear in ["ear-l", "ear-r"] {
            guard let layer = view.visibleViews.first.flatMap({ view.layer(named: "\(ear)@\($0)") }) else { continue }
            let spring = CASpringAnimation(keyPath: "transform.rotation.z")
            spring.fromValue = -0.35
            spring.toValue = 0
            spring.mass = 1; spring.stiffness = 220; spring.damping = 6
            spring.duration = spring.settlingDuration
            spring.isAdditive = true
            layer.add(spring, forKey: "flick")
        }
    }
}

#Preview { PipRigPreview() }
#endif
