import MiniExplorerCore
import SwiftUI

struct RenameItemView: View {
  @ObservedObject var model: FileBrowserModel
  @State private var name: String
  private let nameParts: RenameNameParts
  @FocusState private var isFocused: Bool
  @Environment(\.explorerPalette) private var palette

  init(model: FileBrowserModel) {
    self.model = model
    let item = model.primaryItem
    let parts = RenameNameParts(
      displayName: item?.displayName ?? "",
      isDirectory: item?.isDirectory ?? false,
      isPackage: item?.isPackage ?? false
    )
    nameParts = parts
    _name = State(initialValue: parts.editableName)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 10) {
        Image(systemName: "pencil")
          .font(.system(size: 20, weight: .bold))
          .foregroundStyle(palette.accent)
        Text("RENAME ITEM")
          .font(.system(size: 17, weight: .bold, design: .monospaced))
      }

      Text("Enter a new name. MiniExplorer will not overwrite another item.")
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(palette.secondaryText)

      HStack(spacing: 0) {
        TextField("New name", text: $name)
          .textFieldStyle(.plain)
          .focused($isFocused)
          .focusedValue(\.fileActionsDisabled, true)
          .onSubmit(rename)
          .accessibilityIdentifier("rename-item-name")
        if !nameParts.preservedSuffix.isEmpty {
          Text(nameParts.preservedSuffix)
            .foregroundStyle(palette.secondaryText)
            .accessibilityIdentifier("rename-item-extension")
        }
      }
      .font(.system(size: 13, design: .monospaced))
      .padding(.horizontal, 10)
      .frame(height: 32)
      .explorerInputSurface()

      HStack(spacing: 10) {
        Spacer()
        Button("CANCEL") { model.isRenamePresented = false }
          .buttonStyle(ExplorerToolbarButtonStyle(width: 90))
          .keyboardShortcut(.cancelAction)
        Button("RENAME") { rename() }
          .buttonStyle(ExplorerToolbarButtonStyle(width: 90))
          .keyboardShortcut(.defaultAction)
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 460)
    .foregroundStyle(palette.primaryText)
    .background(palette.contentBackground)
    .onAppear {
      isFocused = true
      DispatchQueue.main.async {
        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
      }
    }
  }

  private func rename() {
    Task {
      _ = await model.renamePrimaryItem(to: nameParts.completeName(editableName: name))
    }
  }
}
