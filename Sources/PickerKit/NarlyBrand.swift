import AppKit
import ImageIO
import SwiftUI

/// The menu-bar template is derived from the app artwork's narwhal.
@MainActor
public enum NarlyBrand {
    // Keep the full-resolution pixels until SwiftUI renders at the display scale.
    // Going through a small logical NSImage can rasterize the artwork too early.
    static let artwork: CGImage? = {
        guard let url = Bundle.main.url(forResource: "Narly-AppIcon", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()

    public static func image(size: CGFloat, template: Bool = false) -> NSImage {
        // In-app branding uses the original artwork, which already has its border.
        // The compiled system icon adds an enclosure intended for Dock and Finder.
        let url = template
            ? Bundle.main.url(forResource: "Narly-MenuBar", withExtension: "png")
            : Bundle.main.url(forResource: "Narly-AppIcon", withExtension: "png")
        let image: NSImage
        if let url,
           let artwork = NSImage(contentsOf: url) {
            image = artwork
        } else {
            image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Narly") ?? NSImage()
        }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = template
        image.accessibilityDescription = "Narly"
        return image
    }
}

struct NarlyBrandImage: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let artwork = NarlyBrand.artwork {
                Image(decorative: artwork, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
