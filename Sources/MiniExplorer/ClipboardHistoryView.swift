import MiniExplorerCore
import SwiftUI

struct ClipboardHistoryView: View {
  @ObservedObject var model: FileBrowserModel
  @Environment(\.explorerPalette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 9) {
        Image(systemName: "clipboard")
          .foregroundStyle(palette.accent)
        Text("CLIPBOARD HISTORY")
          .font(.system(size: 16, weight: .bold, design: .monospaced))
        Spacer()
        Text("THIS SESSION")
          .font(.system(size: 10.5, weight: .bold, design: .monospaced))
          .foregroundStyle(palette.secondaryText)
      }
      .padding(16)
      .background(palette.toolbarBackground)
      .overlay(alignment: .bottom) {
        Rectangle().fill(palette.border).frame(height: palette.borderWidth)
      }

      if model.clipboardHistory.isEmpty {
        ContentUnavailableView(
          "Clipboard History Is Empty",
          systemImage: "clipboard",
          description: Text("Copy or cut files to add them for this session.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(model.clipboardHistory) { entry in
              historyRow(entry)
            }
          }
        }
      }

      HStack(spacing: 10) {
        Button("CLEAR") { model.clearClipboardHistory() }
          .buttonStyle(ExplorerToolbarButtonStyle(width: 90))
          .disabled(model.clipboardHistory.isEmpty)
        Spacer()
        Button("CLOSE") { model.isClipboardHistoryPresented = false }
          .buttonStyle(ExplorerToolbarButtonStyle(width: 90))
          .keyboardShortcut(.cancelAction)
      }
      .padding(14)
      .background(palette.toolbarBackground)
      .overlay(alignment: .top) {
        Rectangle().fill(palette.border).frame(height: palette.borderWidth)
      }
    }
    .frame(width: 520, height: 410)
    .foregroundStyle(palette.primaryText)
    .background(palette.contentBackground)
  }

  private func historyRow(_ entry: ClipboardHistoryEntry) -> some View {
    Button {
      model.activateClipboardHistoryEntry(entry.id)
      model.isClipboardHistoryPresented = false
    } label: {
      HStack(spacing: 10) {
        Image(systemName: entry.payload.operation == .copy ? "doc.on.doc" : "scissors")
          .frame(width: 20)
          .foregroundStyle(palette.accent)

        VStack(alignment: .leading, spacing: 3) {
          Text(entry.payload.sourceURLs.map(\.lastPathComponent).joined(separator: ", "))
            .lineLimit(1)
          Text("\(entry.payload.operation == .copy ? "COPY" : "CUT") · \(entry.payload.sourceURLs.count) ITEM\(entry.payload.sourceURLs.count == 1 ? "" : "S")")
            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
            .foregroundStyle(palette.secondaryText)
        }
        Spacer()
        Text(entry.capturedAt, style: .time)
          .font(.system(size: 10.5, design: .monospaced))
          .foregroundStyle(palette.secondaryText)
      }
      .padding(.horizontal, 14)
      .frame(height: 52)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .overlay(alignment: .bottom) {
      Rectangle().fill(palette.border.opacity(0.7)).frame(height: palette.borderWidth)
    }
  }
}
