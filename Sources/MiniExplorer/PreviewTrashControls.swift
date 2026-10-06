import SwiftUI

struct PreviewTrashAction {
  let isEnabled: Bool
  let perform: () -> Void
}

private struct PreviewTrashActionKey: FocusedValueKey {
  typealias Value = PreviewTrashAction
}

extension FocusedValues {
  var previewTrashAction: PreviewTrashAction? {
    get { self[PreviewTrashActionKey.self] }
    set { self[PreviewTrashActionKey.self] = newValue }
  }
}

struct PreviewTrashButton: View {
  let isEnabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label("Move to Trash", systemImage: "trash")
        .labelStyle(.iconOnly)
    }
    .buttonStyle(ExplorerToolbarButtonStyle())
    .disabled(!isEnabled)
    .help(
      isEnabled
        ? "Move Previewed Item to Trash (⌘⇧D)"
        : "Save changes before moving this file to Trash."
    )
    .accessibilityLabel("Move Previewed Item to Trash")
  }
}
