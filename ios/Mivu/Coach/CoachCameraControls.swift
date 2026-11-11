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

/// One button per back lens; the lens in use shows the live zoom. Hidden on a single-lens camera.
struct CoachCameraLensBar: View {
    let state: CoachCameraSession.State
    let camera: CoachCameraSession
    var body: some View {
        if state.isRunning, state.lenses.count > 1 {
            let current = state.lenses.last { $0 <= state.zoom + 0.01 } ?? state.lenses[0]
            HStack(spacing: 8) {
                ForEach(state.lenses, id: \.self) { lens in
                    let active = lens == current
                    Button { Task { await camera.setZoom(lens) } } label: {
                        Text(active ? "\(Self.text(state.zoom))×" : Self.text(lens)).font(.footnote.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(active ? .yellow : .white)
                            .frame(width: 44, height: 44).background(.black.opacity(0.35), in: .circle)
                    }
                    .accessibilityLabel("\(Self.text(lens)) times zoom").accessibilityAddTraits(active ? .isSelected : [])
                    .accessibilityIdentifier("cameraLens\(Self.text(lens))")
                }
            }
        }
    }
    private static func text(_ zoom: CGFloat) -> String {
        let tenths = (zoom * 10).rounded() / 10
        return tenths == tenths.rounded() ? String(Int(tenths)) : String(format: "%.1f", tenths)
    }
}
