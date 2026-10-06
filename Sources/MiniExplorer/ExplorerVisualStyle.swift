import AppKit
import MiniExplorerCore
import SwiftUI

struct ExplorerPalette {
  let id: ExplorerThemeID
  let accent: Color
  let toolbarBackground: Color
  let sidebarBackground: Color
  let contentBackground: Color
  let inputBackground: Color
  let selectionBackground: Color
  let primaryText: Color
  let secondaryText: Color
  let border: Color
  let folderLight: Color
  let folderDark: Color
  let success: Color
  let warning: Color
  let error: Color

  var isFlat: Bool { id != .classic }
  var isRetro: Bool { id == .retroCraft }
  var borderWidth: CGFloat { isRetro ? 2 : 1 }
  var cornerRadius: CGFloat { isFlat ? 0 : 7 }

  static func palette(for id: ExplorerThemeID) -> ExplorerPalette {
    switch id {
    case .classic:
      ExplorerPalette(
        id: id,
        accent: Color(red: 0.12, green: 0.43, blue: 0.78),
        toolbarBackground: Color(nsColor: .controlBackgroundColor),
        sidebarBackground: Color(nsColor: .underPageBackgroundColor),
        contentBackground: Color(nsColor: .textBackgroundColor),
        inputBackground: Color(nsColor: .textBackgroundColor),
        selectionBackground: Color(red: 0.12, green: 0.43, blue: 0.78),
        primaryText: Color(nsColor: .labelColor),
        secondaryText: Color(nsColor: .secondaryLabelColor),
        border: Color(nsColor: .separatorColor),
        folderLight: Color(red: 1.0, green: 0.84, blue: 0.34),
        folderDark: Color(red: 0.91, green: 0.61, blue: 0.10),
        success: .green,
        warning: .orange,
        error: .red
      )
    case .murmurFlat:
      ExplorerPalette(
        id: id,
        accent: Color(red: 0.45, green: 0.76, blue: 0.74),
        toolbarBackground: Color(red: 0.16, green: 0.20, blue: 0.23),
        sidebarBackground: Color(red: 0.15, green: 0.19, blue: 0.22),
        contentBackground: Color(red: 0.17, green: 0.21, blue: 0.24),
        inputBackground: Color(red: 0.19, green: 0.23, blue: 0.25),
        selectionBackground: Color(red: 0.31, green: 0.33, blue: 0.33),
        primaryText: Color(red: 0.86, green: 0.80, blue: 0.67),
        secondaryText: Color(red: 0.66, green: 0.62, blue: 0.51),
        border: Color(red: 0.24, green: 0.29, blue: 0.31),
        folderLight: Color(red: 0.88, green: 0.79, blue: 0.55),
        folderDark: Color(red: 0.76, green: 0.64, blue: 0.36),
        success: Color(red: 0.61, green: 0.72, blue: 0.57),
        warning: Color(red: 0.88, green: 0.79, blue: 0.55),
        error: Color(red: 0.86, green: 0.49, blue: 0.44)
      )
    case .tokyoNight:
      ExplorerPalette(
        id: id,
        accent: Color(red: 0.48, green: 0.64, blue: 0.97),
        toolbarBackground: Color(red: 0.086, green: 0.086, blue: 0.13),
        sidebarBackground: Color(red: 0.12, green: 0.14, blue: 0.21),
        contentBackground: Color(red: 0.10, green: 0.11, blue: 0.16),
        inputBackground: Color(red: 0.14, green: 0.16, blue: 0.23),
        selectionBackground: Color(red: 0.20, green: 0.24, blue: 0.39),
        primaryText: Color(red: 0.75, green: 0.79, blue: 0.96),
        secondaryText: Color(red: 0.66, green: 0.69, blue: 0.84),
        border: Color(red: 0.73, green: 0.60, blue: 0.97),
        folderLight: Color(red: 0.73, green: 0.60, blue: 0.97),
        folderDark: Color(red: 0.48, green: 0.64, blue: 0.97),
        success: Color(red: 0.62, green: 0.81, blue: 0.42),
        warning: Color(red: 0.88, green: 0.69, blue: 0.41),
        error: Color(red: 0.97, green: 0.46, blue: 0.56)
      )
    case .retroCraft:
      ExplorerPalette(
        id: id,
        accent: Color(red: 0.48, green: 0.68, blue: 0.27),
        toolbarBackground: Color(red: 0.16, green: 0.12, blue: 0.086),
        sidebarBackground: Color(red: 0.23, green: 0.18, blue: 0.12),
        contentBackground: Color(red: 0.105, green: 0.14, blue: 0.095),
        inputBackground: Color(red: 0.29, green: 0.22, blue: 0.15),
        selectionBackground: Color(red: 0.29, green: 0.43, blue: 0.19),
        primaryText: Color(red: 0.95, green: 0.90, blue: 0.75),
        secondaryText: Color(red: 0.76, green: 0.66, blue: 0.47),
        border: Color(red: 0.055, green: 0.038, blue: 0.024),
        folderLight: Color(red: 0.79, green: 0.61, blue: 0.27),
        folderDark: Color(red: 0.49, green: 0.32, blue: 0.12),
        success: Color(red: 0.48, green: 0.68, blue: 0.27),
        warning: Color(red: 0.87, green: 0.70, blue: 0.33),
        error: Color(red: 0.79, green: 0.32, blue: 0.25)
      )
    }
  }
}

struct ExplorerAppKitPalette {
  let background: NSColor
  let text: NSColor
  let secondaryText: NSColor
  let accent: NSColor
  let surface: NSColor
  let warning: NSColor

  static func palette(for id: ExplorerThemeID) -> ExplorerAppKitPalette {
    if id == .murmurFlat {
      return ExplorerAppKitPalette(
        background: NSColor(red: 0.17, green: 0.21, blue: 0.24, alpha: 1),
        text: NSColor(red: 0.86, green: 0.80, blue: 0.67, alpha: 1),
        secondaryText: NSColor(red: 0.66, green: 0.62, blue: 0.51, alpha: 1),
        accent: NSColor(red: 0.45, green: 0.76, blue: 0.74, alpha: 1),
        surface: NSColor(red: 0.19, green: 0.23, blue: 0.25, alpha: 1),
        warning: NSColor(red: 0.88, green: 0.79, blue: 0.55, alpha: 1)
      )
    } else if id == .tokyoNight {
      return ExplorerAppKitPalette(
        background: NSColor(red: 0.10, green: 0.11, blue: 0.16, alpha: 1),
        text: NSColor(red: 0.75, green: 0.79, blue: 0.96, alpha: 1),
        secondaryText: NSColor(red: 0.66, green: 0.69, blue: 0.84, alpha: 1),
        accent: NSColor(red: 0.48, green: 0.64, blue: 0.97, alpha: 1),
        surface: NSColor(red: 0.14, green: 0.16, blue: 0.23, alpha: 1),
        warning: NSColor(red: 0.88, green: 0.69, blue: 0.41, alpha: 1)
      )
    } else if id == .retroCraft {
      return ExplorerAppKitPalette(
        background: NSColor(red: 0.105, green: 0.14, blue: 0.095, alpha: 1),
        text: NSColor(red: 0.95, green: 0.90, blue: 0.75, alpha: 1),
        secondaryText: NSColor(red: 0.76, green: 0.66, blue: 0.47, alpha: 1),
        accent: NSColor(red: 0.48, green: 0.68, blue: 0.27, alpha: 1),
        surface: NSColor(red: 0.29, green: 0.22, blue: 0.15, alpha: 1),
        warning: NSColor(red: 0.87, green: 0.70, blue: 0.33, alpha: 1)
      )
    } else {
      return ExplorerAppKitPalette(
        background: .textBackgroundColor,
        text: .textColor,
        secondaryText: .tertiaryLabelColor,
        accent: .linkColor,
        surface: .controlBackgroundColor,
        warning: .systemYellow
      )
    }
  }
}

private struct ExplorerPaletteKey: EnvironmentKey {
  static let defaultValue = ExplorerPalette.palette(for: .classic)
}

extension EnvironmentValues {
  var explorerPalette: ExplorerPalette {
    get { self[ExplorerPaletteKey.self] }
    set { self[ExplorerPaletteKey.self] = newValue }
  }
}

struct ExplorerItemIcon: View {
  let item: FileItem
  var size: CGFloat
  var isVolumeRoot = false
  @Environment(\.explorerPalette) private var palette

  var body: some View {
    Group {
      if isVolumeRoot {
        Image(systemName: "internaldrive.fill")
          .resizable().scaledToFit().symbolRenderingMode(.monochrome)
          .foregroundStyle(palette.secondaryText)
      } else if item.usesExplorerFolderIcon {
        ClassicFolderIcon()
      } else {
        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
          .resizable().scaledToFit()
      }
    }
    .frame(width: size, height: size)
  }
}

private struct ClassicFolderIcon: View {
  @Environment(\.explorerPalette) private var palette

  var body: some View {
    Group {
      if palette.isRetro {
        RetroFolderShape()
          .fill(palette.folderLight)
          .overlay {
            RetroFolderShape().stroke(palette.border, lineWidth: palette.borderWidth)
          }
      } else {
        ClassicFolderShape()
          .fill(
            palette.isFlat
              ? AnyShapeStyle(palette.folderLight)
              : AnyShapeStyle(
                LinearGradient(
                  colors: [palette.folderLight, palette.folderDark],
                  startPoint: .top,
                  endPoint: .bottom
                )
              )
          )
          .overlay {
            ClassicFolderShape().stroke(
              palette.isFlat ? palette.folderLight : palette.folderDark,
              lineWidth: 0.75
            )
          }
          .shadow(color: palette.isFlat ? .clear : .black.opacity(0.12), radius: 0.5, y: 0.5)
      }
    }
  }
}

private struct RetroFolderShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + 1, y: rect.height * 0.25))
    path.addLine(to: CGPoint(x: rect.width * 0.42, y: rect.height * 0.25))
    path.addLine(to: CGPoint(x: rect.width * 0.52, y: rect.height * 0.40))
    path.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.height * 0.40))
    path.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.maxY - 1))
    path.addLine(to: CGPoint(x: rect.minX + 1, y: rect.maxY - 1))
    path.closeSubpath()
    return path
  }
}

private struct ClassicFolderShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let top = rect.height * 0.15
    let shoulder = rect.height * 0.31
    let tabEnd = rect.width * 0.42
    let tabSlopeEnd = rect.width * 0.52
    path.move(to: CGPoint(x: rect.minX + 0.7, y: shoulder))
    path.addLine(to: CGPoint(x: rect.minX + 0.7, y: top + 1.5))
    path.addQuadCurve(to: CGPoint(x: rect.minX + 2.2, y: top), control: CGPoint(x: rect.minX + 0.7, y: top))
    path.addLine(to: CGPoint(x: rect.minX + tabEnd, y: top))
    path.addLine(to: CGPoint(x: rect.minX + tabSlopeEnd, y: shoulder))
    path.addLine(to: CGPoint(x: rect.maxX - 1.4, y: shoulder))
    path.addQuadCurve(to: CGPoint(x: rect.maxX - 0.7, y: shoulder + 1.1), control: CGPoint(x: rect.maxX - 0.7, y: shoulder))
    path.addLine(to: CGPoint(x: rect.maxX - 1.7, y: rect.maxY - 1.2))
    path.addQuadCurve(to: CGPoint(x: rect.minX + 1.5, y: rect.maxY - 1.2), control: CGPoint(x: rect.midX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX + 0.7, y: shoulder))
    path.closeSubpath()
    return path
  }
}

struct ExplorerToolbarButtonStyle: ButtonStyle {
  var isSelected = false
  var width: CGFloat = 26
  @Environment(\.explorerPalette) private var palette

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(palette.primaryText)
      .frame(width: width, height: 24)
      .background(configuration.isPressed || isSelected ? palette.selectionBackground : palette.toolbarBackground)
      .overlay { Rectangle().stroke(palette.border, lineWidth: palette.borderWidth) }
  }
}

private struct FlatSurfaceModifier: ViewModifier {
  @Environment(\.explorerPalette) private var palette
  func body(content: Content) -> some View {
    content.background(palette.inputBackground).overlay {
      Rectangle().stroke(palette.border, lineWidth: palette.borderWidth)
    }
  }
}

extension View {
  func explorerInputSurface() -> some View { modifier(FlatSurfaceModifier()) }
}

struct HighlightedFileName: View {
  let name: String
  let query: String
  @Environment(\.explorerPalette) private var palette

  var body: some View { Text(attributedName) }

  private var attributedName: AttributedString {
    var attributed = AttributedString(name)
    guard !query.isEmpty else { return attributed }
    var searchStart = name.startIndex
    while searchStart < name.endIndex,
      let match = name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchStart..<name.endIndex)
    {
      if let attributedRange = Range(match, in: attributed) {
        attributed[attributedRange].backgroundColor = palette.warning
        attributed[attributedRange].foregroundColor = palette.isFlat ? palette.contentBackground : .black
      }
      searchStart = match.upperBound
    }
    return attributed
  }
}
