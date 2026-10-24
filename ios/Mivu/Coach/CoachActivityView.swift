import SwiftUI

struct CoachActivityView: View {
    let activity: CoachActivity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if reduceMotion {
                    Image(systemName: "circle.dotted")
                        .foregroundStyle(Color.diaryLeaf)
                } else {
                    ProgressView()
                        .tint(.diaryLeaf)
                }
            }
            .frame(width: 24, height: 24)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.diaryText)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.diarySurface, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("Your message is saved.")
        .accessibilityIdentifier("coachActivity")
    }

    private var title: String {
        switch activity {
        case .preparingPhotos: "Looking at your photos…"
        case .thinking: "Thinking…"
        case .reading: "Checking your diary…"
        case .saving: "Saving…"
        }
    }
}
