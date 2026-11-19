import SwiftUI

/// Below the intake card on Today while a newer App Store version has been out a week.
struct UpdateCard: View {
    let version: String
    let onDismiss: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mivu \(version) is available").font(.headline).foregroundStyle(Color.diaryText)
                    Text("A newer version is ready in the App Store.").font(.subheadline).foregroundStyle(Color.diarySecondary)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(Color.diarySecondary)
                        .frame(width: 30, height: 30).background(Circle().fill(Color.diaryCanvas))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).padding(.top, -7).padding(.trailing, -7)
                .accessibilityLabel("Hide update").accessibilityIdentifier("updateCardDismiss")
            }
            Button("Update in App Store") { openURL(MivuLinks.appStore) }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(.diaryAccent).controlSize(.large)
                .accessibilityIdentifier("updateCardStore")
        }
        .diarySummaryCard(padding: 16, fill: Color.diaryAccent.opacity(0.08))
        .accessibilityElement(children: .contain).accessibilityIdentifier("updateCard")
    }
}

/// Pip's one-time highlights after updating into a feature release.
struct WhatsNewCard: View {
    let version: String
    let lines: [LocalizedStringResource]
    let onDone: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if !typeSize.isAccessibilitySize {
                    Image("PipResting").resizable().scaledToFit().frame(width: 56, height: 56).accessibilityHidden(true)
                }
                Text("New in Mivu \(version)").font(.headline).foregroundStyle(Color.diaryText).accessibilityAddTraits(.isHeader)
            }
            ForEach(lines.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "sparkle").foregroundStyle(Color.diaryAccent).accessibilityHidden(true)
                    Text(lines[index]).foregroundStyle(Color.diaryText)
                }
                .font(.subheadline)
            }
            Button(action: onDone) { Text("Got it").foregroundStyle(Color.diaryActionText).frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(.diaryAccent).controlSize(.large)
                .accessibilityIdentifier("whatsNewDone")
        }
        .diarySummaryCard()
        .accessibilityElement(children: .contain).accessibilityIdentifier("whatsNewCard")
    }
}

/// Covers the app when the website's minimum is above this version. The diary stays reachable through export.
struct UpdateRequiredView: View {
    @Bindable var model: DiaryViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 12) {
                    if !typeSize.isAccessibilitySize {
                        Image("PipResting").resizable().scaledToFit().frame(width: 112, height: 112).accessibilityHidden(true)
                    }
                    Text("Please update Mivu").font(.title2.weight(.bold)).foregroundStyle(Color.diaryText).accessibilityAddTraits(.isHeader)
                    Text("This version of Mivu needs an update to keep working. Your diary stays on this iPhone.")
                        .foregroundStyle(Color.diarySecondary)
                }
                .multilineTextAlignment(.center).padding(24)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            }
            VStack(spacing: 12) {
                Button { openURL(MivuLinks.appStore) } label: {
                    Text("Update in App Store").foregroundStyle(Color.diaryActionText).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.diaryAccent).controlSize(.large)
                .buttonBorderShape(typeSize.isAccessibilitySize ? .roundedRectangle(radius: 20) : .capsule)
                    .accessibilityIdentifier("updateRequiredStore")
                DiaryExportButton(model: model, title: "Export my diary", caption: "Saves a copy to Files")
                    .accessibilityIdentifier("updateRequiredExport")
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
        }
        .background(Color.diaryCanvas.ignoresSafeArea())
        .accessibilityElement(children: .contain).accessibilityIdentifier("updateRequired")
    }
}
