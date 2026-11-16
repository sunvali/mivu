import ImageIO
import SwiftUI

struct PipStickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var missingWhatsApp = false
    // The launch-argument default lets UI tests exercise the still path; the simulator ignores it for the system flag.
    private var still: Bool { reduceMotion || UserDefaults.standard.bool(forKey: "UIAccessibilityReduceMotionEnabled") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Tap a sticker to share it.").font(.subheadline).foregroundStyle(Color.diarySecondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 12) {
                        ForEach(PipStickers.all) { sticker in
                            if let url = sticker.shareURL {
                                ShareLink(item: url) { cell(sticker, url: url) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(sticker.accessibilityText)
                                    .accessibilityValue(sticker.animated && !still ? "animated" : "")
                                    .accessibilityIdentifier("pipSticker-" + sticker.id)
                            }
                        }
                    }
                    VStack(spacing: 12) {
                        addButton(String(localized: "Add “Pip” to WhatsApp"), animated: false, id: "addPipToWhatsApp").buttonStyle(.borderedProminent)
                        addButton(String(localized: "Add “Pip moves” to WhatsApp"), animated: true, id: "addPipMovesToWhatsApp").buttonStyle(.bordered)
                        Text("Also in Messages: tap + then Stickers.").font(.footnote).foregroundStyle(Color.diarySecondary).multilineTextAlignment(.center)
                    }
                }.padding()
            }
            .background(Color.diaryCanvas)
            .navigationTitle("Pip stickers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("WhatsApp isn't installed", isPresented: $missingWhatsApp) {
                Button("Get WhatsApp") { UIApplication.shared.open(URL(string: "https://apps.apple.com/app/id310633997")!) }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Install WhatsApp to add Pip stickers.") }
        }
    }

    private func cell(_ sticker: PipStickerItem, url: URL) -> some View {
        StickerImage(url: url, animate: sticker.animated && !still)
            .aspectRatio(1, contentMode: .fit)
            .frame(minHeight: 72)
            .background(Color.diarySurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func addButton(_ title: String, animated: Bool, id: String) -> some View {
        Button {
            // shortcut: a payload failure also reads as "not installed", acceptable while the payload is a bundled constant.
            missingWhatsApp = !((try? PipStickers.sendToWhatsApp(animated: animated)) ?? false)
        } label: { Text(title).frame(maxWidth: .infinity, minHeight: 44) }
            .controlSize(.large)
            .accessibilityIdentifier(id)
    }
}

/// Plays a bundled GIF with ImageIO, or shows its first frame.
private struct StickerImage: UIViewRepresentable {
    let url: URL
    let animate: Bool

    final class Coordinator { var stopped = false }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        if animate {
            let coordinator = context.coordinator
            CGAnimateImageAtURLWithBlock(url as CFURL, nil) { [weak view] _, frame, stop in
                if coordinator.stopped || view == nil { stop.pointee = true; return }
                view?.image = UIImage(cgImage: frame)
            }
        } else if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let frame = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            view.image = UIImage(cgImage: frame)
        }
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {}
    static func dismantleUIView(_ view: UIImageView, coordinator: Coordinator) { coordinator.stopped = true }
}
