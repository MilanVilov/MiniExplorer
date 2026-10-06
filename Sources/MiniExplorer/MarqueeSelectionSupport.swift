import MiniExplorerCore
import SwiftUI

struct MarqueeItemFramePreferenceKey: PreferenceKey {
  static let defaultValue: [URL: CGRect] = [:]

  static func reduce(value: inout [URL: CGRect], nextValue: () -> [URL: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}

extension View {
  func reportsMarqueeFrame(for id: URL, coordinateSpace: String) -> some View {
    background {
      GeometryReader { geometry in
        Color.clear.preference(
          key: MarqueeItemFramePreferenceKey.self,
          value: [id.standardizedFileURL: geometry.frame(in: .named(coordinateSpace))]
        )
      }
    }
  }
}

struct MarqueeRectangleView: View {
  let rectangle: CGRect
  @Environment(\.explorerPalette) private var palette

  var body: some View {
    Rectangle()
      .fill(palette.accent.opacity(0.16))
      .overlay {
        Rectangle().stroke(palette.accent, lineWidth: max(1, palette.borderWidth))
      }
      .frame(width: rectangle.width, height: rectangle.height)
      .position(x: rectangle.midX, y: rectangle.midY)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}
