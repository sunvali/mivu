import LinkPresentation
import UIKit

/// The "Share Mivu" invite: one string, so Copy and apps that drop a separate message still get both the pitch and the link,
/// with link metadata so the share sheet header shows Mivu and Pip instead of a plain-text tile. (ShareLink's preview drops Copy.)
final class MivuInvite: NSObject, UIActivityItemSource {
    let text = String(localized: "I've been logging my meals with Mivu: just snap a photo and it does the counting. Try it:") + " " + MivuLinks.shareApp.absoluteString

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { text }
    func activityViewController(_ controller: UIActivityViewController, itemForActivityType type: UIActivity.ActivityType?) -> Any? { text }
    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = "Mivu"
        if let pip = UIImage(named: "PipPreview") { metadata.iconProvider = NSItemProvider(object: pip) }
        return metadata
    }
}
