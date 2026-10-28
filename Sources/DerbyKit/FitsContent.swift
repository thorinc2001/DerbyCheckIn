import SwiftUI

extension View {
    /// Sizes a Form or List to its content, up to `max` points, so a Settings tab is as tall as
    /// what it shows and scrolls only past `max`. Adapted from BAMA's template (MIT,
    /// github.com/daveebbelaar/bama). macOS 14 has no scroll geometry, so there it uses `fallback`.
    func fitsContent(max: CGFloat = 640, fallback: CGFloat) -> some View {
        modifier(FitsContent(max: max, fallback: fallback))
    }
}

private struct FitsContent: ViewModifier {
    var max: CGFloat
    var fallback: CGFloat
    @State private var height: CGFloat?

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                // Only the content's own height: insets change as the window resizes,
                // which would start a resize loop.
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height.rounded(.up)
                } action: { _, new in
                    if abs(new - (height ?? 0)) >= 1 { height = new }
                }
                .frame(height: height.map { min($0, max) })
                .scrollBounceBehavior(.basedOnSize)
        } else {
            content.frame(height: fallback)
        }
    }
}
