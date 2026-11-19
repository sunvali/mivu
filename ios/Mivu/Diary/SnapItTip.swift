import SwiftUI
import TipKit
import WidgetKit

/// Teaches that Snap It also lives outside the app. iOS offers no way to add the control for the user, so Mivu shows the steps.
struct SnapItTip: Tip {
    /// One photo log whose toast ran its course; the tip waits for the third so it reaches people who already use Snap It.
    static let logged = Tips.Event(id: "snapItLogged")
    @Parameter static var controlAdded: Bool = false

    var title: Text { Text("Snap faster") }
    var message: Text? { Text("Add Snap It to your Lock Screen, Control Center or Action button.") }
    var actions: [Action] { Action(id: "how") { Text("Show me how") } }
    var rules: [Rule] {
        #Rule(Self.logged) { $0.donations.count >= 3 }
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
        guard let controls = try? await ControlCenter.shared.currentControls() else { return }
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
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Open the camera straight from your iPhone, without opening Mivu first.")
                        .font(.subheadline).foregroundStyle(Color.diarySecondary)
                        .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }
                steps("Lock Screen", symbol: "lock.fill", [
                    "Touch and hold the Lock Screen and tap Customize. If asked, choose Lock Screen.",
                    "Remove one of the bottom buttons, then tap +.",
                    "Search for Snap It.",
                ])
                steps("Control Center", symbol: "switch.2", [
                    "Swipe down from the top-right corner.",
                    "Touch and hold an empty area, then tap Add a Control.",
                    "Search for Snap It.",
                ])
                steps("Action button", symbol: "button.programmable", [
                    "Open Settings and tap Action Button.",
                    "Swipe to Controls and tap Choose a Control.",
                    "Search for Snap It.",
                ], footer: "On iPhone 15 Pro and later.")
            }
            .navigationTitle("Snap It shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("doneSnapItShortcuts") } }
        }
        .tint(.diaryAccent)
    }

    private func steps(_ title: LocalizedStringKey, symbol: String, _ steps: [LocalizedStringKey], footer: LocalizedStringKey? = nil) -> some View {
        Section {
            ForEach(steps.indices, id: \.self) { index in
                // Not a Label: at accessibility sizes a Label drops its text under the number and the list stops reading as steps.
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: "\(index + 1).circle.fill").foregroundStyle(Color.diaryAccent).accessibilityHidden(true)
                    Text(steps[index])
                }
                .frame(minHeight: 44)
            }
        } header: {
            Label(title, systemImage: symbol)
        } footer: {
            if let footer { Text(footer) }
        }
    }
}
