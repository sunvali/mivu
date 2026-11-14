import SwiftUI
import AVFoundation

/// Cycles Auto, On, Off. `flash` is the stored `AVCaptureDevice.FlashMode` raw value.
struct CoachCameraFlashButton: View {
    @Binding var flash: Int
    var body: some View {
        let mode = AVCaptureDevice.FlashMode(rawValue: flash) ?? .auto
        let (icon, name, next): (String, String, AVCaptureDevice.FlashMode) = switch mode {
        case .on: ("bolt.fill", "On", .off)
        case .off: ("bolt.slash.fill", "Off", .auto)
        default: ("bolt.badge.automatic.fill", "Auto", .on)
        }
        Button { flash = next.rawValue } label: {
            Image(systemName: icon).font(.title3).foregroundStyle(mode == .on ? .yellow : .white)
                .frame(width: 44, height: 44).background(.black.opacity(0.35), in: .circle)
        }
        .accessibilityLabel("Flash").accessibilityValue(name).accessibilityIdentifier("cameraFlash")
    }
}

/// One button per back lens; the lens in use shows the live zoom. Sliding a finger along the buttons turns a zoom
/// dial, as in the system camera. Hidden on a single-lens camera.
struct CoachCameraLensBar: View {
    let state: CoachCameraSession.State
    let camera: CoachCameraSession
    /// How far the finger has slid while the dial is up.
    @State private var slid: CGFloat?
    var body: some View {
        if state.isRunning, state.lenses.count > 1 {
            let current = state.lenses.last { $0 <= state.zoom + 0.01 } ?? state.lenses[0]
            HStack(spacing: 8) {
                ForEach(state.lenses, id: \.self) { lens in
                    let active = lens == current
                    Button { Task { await camera.setZoom(lens) } } label: {
                        Text(active ? "\(zoomText(state.zoom))×" : zoomText(lens)).font(.footnote.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(active ? .yellow : .white)
                            .frame(width: 44, height: 44).background(.black.opacity(0.35), in: .circle)
                    }
                    .accessibilityLabel("\(zoomText(lens)) times zoom").accessibilityAddTraits(active ? .isSelected : [])
                    .accessibilityIdentifier("cameraLens\(zoomText(lens))")
                }
            }
            .overlay(alignment: .top) {
                if slid != nil {
                    // Lifted by its own height plus a gap, so it sits clear above the buttons.
                    CoachCameraZoomDial(zoom: state.zoom, lenses: state.lenses)
                        .offset(y: -(CoachCameraZoomDial.height + 8)).transition(.opacity)
                }
            }
            // A still finger is a tap on a lens; only a slide turns the dial.
            .highPriorityGesture(DragGesture(minimumDistance: 10)
                .onChanged { drag in
                    // Sent as a ratio, like a pinch, so steps that arrive out of order land on the same zoom.
                    let step = drag.translation.width - (slid ?? 0)
                    if slid == nil { withAnimation(.easeOut(duration: 0.15)) { slid = drag.translation.width } } else { slid = drag.translation.width }
                    Task { await camera.zoom(by: pow(2, -step / CoachCameraZoomDial.pointsPerDoubling)) }
                }
                .onEnded { _ in withAnimation(.easeOut(duration: 0.3)) { slid = nil } })
            .sensoryFeedback(.selection, trigger: current)
        }
    }
}

/// The arc of ticks above the lens buttons. Each doubling of zoom is the same distance, so the wheel follows the finger.
struct CoachCameraZoomDial: View {
    static let pointsPerDoubling: CGFloat = 90
    static let height: CGFloat = 76
    let zoom: CGFloat
    let lenses: [CGFloat]
    var body: some View {
        Canvas { context, size in
            let radius: CGFloat = 300, top: CGFloat = 26
            let center = CGPoint(x: size.width / 2, y: top + radius)
            func mark(_ value: CGFloat, lens: Bool) {
                let angle = log2(value / zoom) * Self.pointsPerDoubling / radius
                guard abs(angle) < 0.5 else { return }
                func point(_ distance: CGFloat) -> CGPoint { CGPoint(x: center.x + sin(angle) * distance, y: center.y - cos(angle) * distance) }
                var tick = Path(); tick.move(to: point(radius)); tick.addLine(to: point(radius - (lens ? 12 : 6)))
                context.stroke(tick, with: .color(.white.opacity(lens ? 1 : 0.5)), lineWidth: lens ? 2 : 1)
                if lens { context.draw(Text(zoomText(value)).font(.caption2.weight(.semibold)).foregroundStyle(.white), at: point(radius - 24)) }
            }
            guard let widest = lenses.first, let longest = lenses.last else { return }
            for step in 0...Int(log2(longest * 2 / widest) * 10) { mark(widest * pow(2, CGFloat(step) / 10), lens: false) }
            for lens in lenses { mark(lens, lens: true) }
            var needle = Path(); needle.move(to: CGPoint(x: center.x, y: top - 6)); needle.addLine(to: CGPoint(x: center.x, y: top + 16))
            context.stroke(needle, with: .color(.yellow), lineWidth: 2)
            context.draw(Text("\(zoomText(zoom))×").font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.yellow), at: CGPoint(x: center.x, y: 9))
        }
        .frame(width: 280, height: Self.height)
        .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .leading, endPoint: .trailing))
        .background(.black.opacity(0.35), in: .rect(cornerRadius: 18))
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private func zoomText(_ zoom: CGFloat) -> String {
    let tenths = (zoom * 10).rounded() / 10
    return tenths == tenths.rounded() ? String(Int(tenths)) : String(format: "%.1f", tenths)
}
