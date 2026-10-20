import SwiftUI

extension CoachReply {
    /// Who wrote the quoted content, as the person reads it.
    var author: String {
        switch target {
        case .message(_, true): "Pip"
        case .message: "You"
        case .meal, .item, .day: "Diary"
        }
    }
    var composerTitle: String {
        switch target {
        case .message(_, true): "Replying to Pip"
        case .message: "Replying to you"
        case .meal, .item, .day: "From Diary"
        }
    }
}

/// The quote shown above the composer and inside a sent message: an accent rule, author, and excerpt.
struct CoachReplyQuote: View {
    let reply: CoachReply
    let title: String
    var inMessage = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 10) {
            Capsule().fill(inMessage ? Color.white.opacity(0.85) : Color.diaryAccent).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.footnote.weight(.semibold))
                    .foregroundStyle(inMessage ? Color.white : Color.diaryAccent)
                Text(reply.excerpt).font(.subheadline).lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                    .foregroundStyle(inMessage ? Color.white.opacity(0.85) : Color.diarySecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reply to \(reply.author == "You" ? "your message" : reply.author): \(reply.excerpt)")
    }
}
