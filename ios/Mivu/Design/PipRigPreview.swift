#if DEBUG
import SwiftUI

/// Debug screen for judging Pip's motion at shipping sizes; launch with `-PipRigPreview`.
/// Every `PipGestureLibrary.all` entry gets a button, so a new gesture is reviewable immediately.
struct PipRigPreview: View {
    @State private var set = PipPose.BodySet.standing
    @State private var driver = Driver()
    @State private var caption = " "

    var body: some View {
        VStack(spacing: 12) {
            Picker("Set", selection: $set) {
                Text("Today").tag(PipPose.BodySet.standing)
                Text("Coach").tag(PipPose.BodySet.seated)
            }
            .pickerStyle(.segmented)
            HStack(alignment: .bottom, spacing: 24) {
                RigRepresentable(driver: driver, set: set).id(set).frame(width: 260, height: 260)
                RigRepresentable(driver: driver, set: set).id(set).frame(width: 64, height: 64)
            }
            Text(caption).font(.headline).accessibilityIdentifier("pip-caption")
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                    button("Play all") { await playAll() }
                    button("Gaze sweep") { await gazeSweep() }
                    button("Blink") { driver.rigs.forEach { $0.blink() } }
                    button("Double blink") { driver.rigs.forEach { $0.blink(double: true) } }
                    button("Eyes lead turn") { await eyesLeadTurn() }
                    ForEach(PipGestureLibrary.all, id: \.name) { gesture in
                        button(gesture.name) { await play(gesture) }
                    }
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
            .frame(minHeight: 44)
            .accessibilityLabel(title)
    }

    private func play(_ gesture: PipGesture) async {
        caption = gesture.name
        let wait = gesture.loops ? 2.8 : gesture.duration + 0.5
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            driver.rigs.forEach { $0.play(gesture) { _ in } }
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { done.resume() }
        }
        driver.rigs.forEach { $0.removeAllMotion(); $0.apply(.rest.withSet(set), animated: true) }
    }

    private func gazeSweep() async {
        caption = "gaze sweep"
        for point in [CGPoint(x: 1, y: 0), CGPoint(x: -1, y: 0), CGPoint(x: 0, y: -1), CGPoint(x: 0, y: 1), .zero] {
            driver.rigs.forEach { $0.look(at: point) }
            try? await Task.sleep(for: .milliseconds(700))
        }
    }

    private func eyesLeadTurn() async {
        caption = "eyes lead turn"
        for turn in [CGFloat(-1), 0, 1] {
            await play(PipGesture("turn") { $0.at(0.3) { $0.turn(turn) }; $0.at(0.8) { $0.turn(turn) } })
        }
    }

    private func playAll() async {
        await gazeSweep()
        for blink in [false, true] {
            caption = blink ? "double blink" : "blink"
            driver.rigs.forEach { $0.blink(double: blink) }
            try? await Task.sleep(for: .milliseconds(900))
        }
        await eyesLeadTurn()
        for gesture in PipGestureLibrary.all { await play(gesture) }
        caption = "done"
    }

    @MainActor final class Driver {
        var all: [PipRigView] = []
        /// Only the views still on screen (changing the set rebuilds them).
        var rigs: [PipRigView] { all.filter { $0.window != nil } }
    }
}

private extension PipPose {
    func withSet(_ set: BodySet) -> PipPose { var copy = self; copy.set = set; return copy }
}

private struct RigRepresentable: UIViewRepresentable {
    let driver: PipRigPreview.Driver
    let set: PipPose.BodySet

    func makeUIView(context: Context) -> PipRigView {
        let url = Bundle.main.url(forResource: "Characters/pip/pip-rig.json", withExtension: nil)!
        let asset = try! PipRigAsset.load(Data(contentsOf: url))
        let view = PipRigView(asset: asset, set: set)
        view.visibleRect = asset.frames[set == .standing ? "today" : "coach"] ?? view.visibleRect
        driver.all.append(view)
        return view
    }

    func updateUIView(_ view: PipRigView, context: Context) {}
}

#Preview { PipRigPreview() }
#endif
