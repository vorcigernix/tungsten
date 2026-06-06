import AppKit
import SwiftUI

/// Small favicon image with a neutral rounded placeholder and SF Symbol
/// fallback. Shared by the tab strip and any other chrome surface that needs
/// a site glyph.
struct FaviconIcon: View {
    let faviconURLString: String?
    let fallbackSystemName: String
    let size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.quaternary)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                Image(systemName: fallbackSystemName)
                    .font(.system(size: size * 0.62, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .task(id: faviconURLString) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let faviconURLString else {
            image = nil
            return
        }

        image = await FaviconLoader.shared.image(for: faviconURLString)
    }
}
