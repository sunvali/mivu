import SwiftUI

extension CoachReply {
    /// Who wrote the quoted content, as the person reads it.
    var author: String {
        switch target {
        case .message(_, true): String(localized: "Pip")
        case .message: String(localized: "You")
        case .meal, .item, .day: String(localized: "Diary")
        case .weight, .workout: String(localized: "Progress")
        }
    }
    var spokenLabel: String {
        if case .message(_, false) = target { return String(localized: "Reply to your message: \(excerpt)") }
        return String(localized: "Reply to \(author): \(excerpt)")
    }
    var composerTitle: String {
        switch target {
        case .message(_, true): String(localized: "Replying to Pip")
        case .message: String(localized: "Replying to you")
        case .meal, .item, .day: String(localized: "From Diary")
        case .weight, .workout: String(localized: "From Progress")
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
        HStack(spacing: 8) {
            Capsule().fill(inMessage ? Color.white.opacity(0.7) : Color.diaryAccent).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold))
                    .foregroundStyle(inMessage ? Color.white : Color.diaryAccent)
                // One line in the composer, two in a sent message; more only at accessibility sizes.
                Text(reply.excerpt).font(.footnote)
                    .lineLimit((inMessage ? 2 : 1) + (typeSize.isAccessibilitySize ? 1 : 0))
                    .foregroundStyle(inMessage ? Color.white.opacity(0.8) : Color.diarySecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reply.spokenLabel)
    }
}
