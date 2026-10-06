import MiniExplorerCore
import SwiftUI

struct NewFileView: View {
  @ObservedObject var model: FileBrowserModel
  @Binding var isPresented: Bool

  var body: some View {
    NewItemView(model: model, isPresented: $isPresented, kind: .file)
  }
}

struct NewFolderView: View {
  @ObservedObject var model: FileBrowserModel
  @Binding var isPresented: Bool

  var body: some View {
    NewItemView(model: model, isPresented: $isPresented, kind: .folder)
  }
}

private enum NewItemKind {
  case file
  case folder

  var title: String { self == .file ? "NEW FILE" : "NEW FOLDER" }
  var icon: String { self == .file ? "doc.badge.plus" : "folder.badge.plus" }
  var initialName: String { self == .file ? "untitled.txt" : "untitled folder" }
  var prompt: String {
    self == .file
      ? "Create an empty file. Include the extension in its name."
      : "Create an empty folder."
  }
  var accessibilityName: String { self == .file ? "new-file-name" : "new-folder-name" }
  var accessibilityConfirm: String {
    self == .file ? "create-file-confirm" : "create-folder-confirm"
  }
}

private struct NewItemView: View {
  @ObservedObject var model: FileBrowserModel
  @Binding var isPresented: Bool
  let kind: NewItemKind
  @State private var itemName: String
  @FocusState private var isNameFocused: Bool
  @Environment(\.explorerPalette) private var palette

  init(model: FileBrowserModel, isPresented: Binding<Bool>, kind: NewItemKind) {
    self.model = model
    _isPresented = isPresented
    self.kind = kind
    _itemName = State(initialValue: kind.initialName)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 10) {
        Image(systemName: kind.icon)
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(palette.accent)
        Text(kind.title)
          .font(.system(size: 17, weight: .bold, design: .monospaced))
      }

      Text("\(kind.prompt) It will be added to \(model.currentURL.lastPathComponent).")
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(palette.secondaryText)

      TextField(kind == .file ? "example.txt" : "folder name", text: $itemName)
        .textFieldStyle(.plain)
        .font(.system(size: 13, weight: palette.isRetro ? .bold : .regular, design: .monospaced))
        .padding(.horizontal, 10)
        .frame(height: 32)
        .explorerInputSurface()
        .focused($isNameFocused)
        .focusedValue(\.fileActionsDisabled, true)
        .onSubmit(create)
        .accessibilityIdentifier(kind.accessibilityName)

      HStack(spacing: 10) {
        Spacer()
        Button("CANCEL") { isPresented = false }
          .buttonStyle(
            ExplorerToolbarButtonStyle(width: 90)
          )
          .keyboardShortcut(.cancelAction)

        Button("CREATE") { create() }
          .buttonStyle(
            ExplorerToolbarButtonStyle(width: 90)
          )
          .keyboardShortcut(.defaultAction)
          .disabled(itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .accessibilityIdentifier(kind.accessibilityConfirm)
      }
    }
    .padding(20)
    .frame(width: 460)
    .foregroundStyle(palette.primaryText)
    .background(palette.contentBackground)
    .onAppear { isNameFocused = true }
  }

  private func create() {
    Task {
      let succeeded = switch kind {
      case .file:
        await model.createFile(named: itemName)
      case .folder:
        await model.createFolder(named: itemName)
      }
      if succeeded {
        isPresented = false
      }
    }
  }
}
