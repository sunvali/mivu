import AVFoundation
import SwiftUI
import TipKit
import WidgetKit

/// Teaches that Snap It also lives outside the app. iOS offers no way to add the control for the user, so Mivu shows the steps.
struct SnapItTip: Tip {
    /// One photo log whose toast ran its course; the tip follows the first, when the user has just seen what Snap It does.
    static let logged = Tips.Event(id: "snapItLogged")
    @Parameter static var controlAdded: Bool = false

    var title: Text { Text("Snap faster") }
    var message: Text? { Text("Add Snap It to your Lock Screen, Control Center or Action button.") }
    var actions: [Action] { Action(id: "how") { Text("Show me how") } }
    var rules: [Rule] {
        #Rule(Self.logged) { $0.donations.count >= 1 }
        #Rule(Self.$controlAdded) { !$0 }
    }

    static func start() {
        // UI tests see no tip unless one asks for it; that test starts from a clean store.
        if DiaryLaunch.isUITest {
            if CommandLine.arguments.contains("--snap-it-tip") { try? Tips.resetDatastore() } else { Tips.hideAllTipsForTesting() }
        }
        try? Tips.configure()
    }

    /// Someone who already placed the control needs no tip.
    static func refreshControlAdded() async {
        // UI tests must not depend on which controls the simulator happens to have placed.
        guard !DiaryLaunch.isUITest, let controls = try? await ControlCenter.shared.currentControls() else { return }
        controlAdded = controls.contains { $0.kind == LogFoodIntent.controlKind }
    }
}

/// The stock tip action is a second filled button stacked on Snap It; a text link keeps Snap It the one primary action.
struct SnapItTipStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                configuration.title?.font(.headline).foregroundStyle(Color.diaryText)
                configuration.message?.font(.subheadline).foregroundStyle(Color.diarySecondary).fixedSize(horizontal: false, vertical: true)
                ForEach(configuration.actions) { action in
                    Button(action: action.handler) {
                        action.label().font(.subheadline.weight(.semibold)).foregroundStyle(Color.diaryAccent).frame(minHeight: 44)
                    }
                }
            }
            Spacer(minLength: 0)
            Button { configuration.tip.invalidate(reason: .tipClosed) } label: {
                Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(Color.diarySecondary).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close").accessibilityIdentifier("closeSnapItTip")
        }
        .padding(.leading, 16).padding(.top, 12)
        // Capped like the capture bar it sits in, so the tip never takes Today over at the largest sizes.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

struct SnapItShortcutsView: View {
    private enum Place: String, CaseIterable, Identifiable {
        case lockScreen = "lock-screen", controlCenter = "control-center", actionButton = "action-button"
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .lockScreen: "Lock Screen"
            case .controlCenter: "Control Center"
            case .actionButton: "Action button"
            }
        }
        var steps: [LocalizedStringKey] {
            switch self {
            case .lockScreen: ["Touch and hold the Lock Screen and tap Customize. If asked, choose Lock Screen.",
                               "Remove one of the bottom buttons, then tap +.", "Search for Snap It."]
            case .controlCenter: ["Swipe down from the top-right corner.",
                                  "Touch and hold an empty area, then tap Add a Control.", "Search for Snap It."]
            case .actionButton: ["Open Settings and tap Action Button.",
                                 "Swipe to Controls and tap Choose a Control.", "Search for Snap It."]
            }
        }
    }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var place = Place.lockScreen
    // Read once at creation, so a Reduce Motion user never sees the first frames move.
    @State private var playing = !UIAccessibility.isReduceMotionEnabled
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Open the camera straight from your iPhone, without opening Mivu first.")
                        .font(.subheadline).foregroundStyle(Color.diarySecondary)
                    Picker("Place", selection: $place) {
                        ForEach(Place.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).accessibilityIdentifier("snapItPlace")
                    video
                }
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4))
                Section {
                    ForEach(place.steps.indices, id: \.self) { index in
                        // Not a Label: at accessibility sizes a Label drops its text under the number and the list stops reading as steps.
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: "\(index + 1).circle.fill").foregroundStyle(Color.diaryAccent).accessibilityHidden(true)
                            Text(place.steps[index])
                        }
                        .frame(minHeight: 44)
                    }
                } footer: {
                    if place == .actionButton { Text("On iPhone 15 Pro and later.") }
                }
            }
            .navigationTitle("Snap It shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("doneSnapItShortcuts") } }
        }
        .tint(.diaryAccent)
    }

    /// A screen recording of the steps below; tap to pause, and it waits for a tap when Reduce Motion is on.
    private var video: some View {
        Button { playing.toggle() } label: {
            // iOS pauses the player in the background; the phase makes it resume when the user returns from adding the control.
            LoopingVideo(name: "snap-it-\(place.rawValue)", playing: playing && phase == .active).id(place)
                .aspectRatio(600.0 / 1304.0, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 24))
                .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Color.diaryRule, lineWidth: 1) }
                .overlay {
                    if !playing {
                        Image(systemName: "play.fill").font(.title).foregroundStyle(.white)
                            .frame(width: 64, height: 64).background(.black.opacity(0.55), in: .circle)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 320)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How-to video").accessibilityValue(playing ? Text("Playing") : Text("Paused"))
        .accessibilityIdentifier("snapItVideo")
    }
}

/// A silent clip that loops; it has no audio track, so it never interrupts the user's music.
private struct LoopingVideo: UIViewRepresentable {
    let name: String
    let playing: Bool
    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        let player = AVQueuePlayer()
        var looper: AVPlayerLooper?
    }
    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.player.isMuted = true
        view.player.preventsDisplaySleepDuringVideoPlayback = false
        (view.layer as? AVPlayerLayer)?.player = view.player
        if let url = Bundle.main.url(forResource: name, withExtension: "mp4") {
            view.looper = AVPlayerLooper(player: view.player, templateItem: AVPlayerItem(url: url))
        }
        return view
    }
    func updateUIView(_ view: PlayerView, context: Context) {
        if playing { view.player.play() } else { view.player.pause() }
    }
}
