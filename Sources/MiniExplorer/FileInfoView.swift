import MiniExplorerCore
import SwiftUI

struct FileInfoView: View {
  @ObservedObject var model: FileBrowserModel
  @Environment(\.explorerPalette) private var palette

  private var infos: [FileInfo] { model.fileInfoItems }
  private var totalSize: Int64 { infos.compactMap(\.size).reduce(0, +) }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "info.square")
          .foregroundStyle(palette.accent)
        Text("GET INFO")
          .font(.system(size: 17, weight: .bold, design: .monospaced))
        Spacer()
      }
      .padding(16)
      .background(palette.toolbarBackground)
      .overlay(alignment: .bottom) {
        Rectangle().fill(palette.border).frame(height: palette.borderWidth)
      }

      VStack(alignment: .leading, spacing: 12) {
        if infos.count == 1, let info = infos.first {
          detail("NAME", info.url.lastPathComponent)
          detail("PATH", info.url.path)
          detail("KIND", info.kind)
          detail("SIZE", info.size.map(ByteCountFormatter.string) ?? "—")
          detail("CREATED", info.creationDate.map(DateFormatter.infoDate.string) ?? "—")
          detail("MODIFIED", info.modificationDate.map(DateFormatter.infoDate.string) ?? "—")
        } else {
          detail("ITEMS", "\(infos.count)")
          detail("FILES", "\(infos.filter { !$0.isDirectory }.count)")
          detail("FOLDERS", "\(infos.filter(\.isDirectory).count)")
          detail("KNOWN SIZE", ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
          detail("LOCATION", commonParentPath)
        }
      }
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)

      Spacer()

      HStack {
        Spacer()
        Button("CLOSE") { model.isFileInfoPresented = false }
          .buttonStyle(ExplorerToolbarButtonStyle(width: 90))
          .keyboardShortcut(.cancelAction)
      }
      .padding(14)
      .background(palette.toolbarBackground)
      .overlay(alignment: .top) {
        Rectangle().fill(palette.border).frame(height: palette.borderWidth)
      }
    }
    .frame(width: 520, height: infos.count == 1 ? 390 : 320)
    .foregroundStyle(palette.primaryText)
    .background(palette.contentBackground)
  }

  private func detail(_ label: String, _ value: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Text(label)
        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
        .foregroundStyle(palette.secondaryText)
        .frame(width: 88, alignment: .leading)
      Text(value)
        .font(.system(size: 12.5, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var commonParentPath: String {
    let parents = Set(infos.map { $0.url.deletingLastPathComponent().path })
    return parents.count == 1 ? parents.first ?? "—" : "Multiple locations"
  }
}

private extension ByteCountFormatter {
  static func string(_ bytes: Int64) -> String {
    string(fromByteCount: bytes, countStyle: .file)
  }
}

private extension DateFormatter {
  static let infoDate: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
  }()
}
