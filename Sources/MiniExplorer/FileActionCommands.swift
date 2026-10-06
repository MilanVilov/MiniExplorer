import AppKit
import MiniExplorerCore
import SwiftUI

struct FileActionCommands: Commands {
  @ObservedObject var themeController: ExplorerThemeController
  @ObservedObject var terminalController: TerminalLauncherController
  @FocusedObject private var model: FileBrowserModel?
  @FocusedValue(\.fileActionsDisabled) private var fileActionsDisabled
  @FocusedValue(\.savePreviewAction) private var savePreviewAction
  @FocusedValue(\.previewTrashAction) private var previewTrashAction
  @FocusedValue(\.previewFindActions) private var previewFindActions

  var body: some Commands {
    CommandGroup(replacing: .saveItem) {
      Button("Save Previewed File") {
        savePreviewAction?()
      }
      .keyboardShortcut("s", modifiers: .command)
      .disabled(savePreviewAction == nil)

      Divider()

      Button("Move Previewed Item to Trash…") {
        previewTrashAction?.perform()
      }
      .keyboardShortcut("d", modifiers: [.command, .shift])
      .disabled(previewTrashAction?.isEnabled != true)
    }

    CommandGroup(after: .newItem) {
      Button("Open Selected Item") {
        model?.requestPrimaryItemActivation()
      }
      .keyboardShortcut(.return, modifiers: [])
      .disabled(
        fileActionsDisabled == true || model?.primaryItem == nil || model?.isPreviewVisible == true
      )

      Button(terminalController.actionTitle) {
        guard let model else { return }
        terminalController.open(directory: model.currentURL, model: model)
      }
      .keyboardShortcut("t", modifiers: [.command, .option])
      .disabled(fileActionsDisabled == true || model == nil)
    }

    CommandGroup(replacing: .pasteboard) {
      Button("Cut") {
        if fileActionsDisabled == true {
          NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
        } else {
          model?.cutSelection()
        }
      }
      .keyboardShortcut("x", modifiers: .command)
      .disabled(fileActionsDisabled != true && model?.canCopyOrCut != true)

      Button("Copy") {
        if fileActionsDisabled == true {
          NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
        } else {
          model?.copySelection()
        }
      }
      .keyboardShortcut("c", modifiers: .command)
      .disabled(fileActionsDisabled != true && model?.canCopyOrCut != true)

      Button("Paste") {
        if fileActionsDisabled == true {
          NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        } else {
          Task { await model?.paste() }
        }
      }
      .keyboardShortcut("v", modifiers: .command)
      .disabled(fileActionsDisabled != true && model?.canPaste != true)

      Button("Select All") {
        if fileActionsDisabled == true {
          NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        } else {
          model?.selectAllVisibleItems()
        }
      }
      .keyboardShortcut("a", modifiers: .command)

      Divider()

      Button("Clipboard History…") {
        model?.showClipboardHistory()
      }
      .keyboardShortcut("v", modifiers: [.command, .shift])

      Divider()

      Button("Rename…") {
        model?.requestRename()
      }
      .disabled(fileActionsDisabled == true || model?.canRename != true)

      Button("Duplicate") {
        Task { await model?.duplicateSelection() }
      }
      .keyboardShortcut("d", modifiers: .command)
      .disabled(fileActionsDisabled == true || model?.canOperateOnSelection != true)

      Button("Move to Trash…") {
        model?.requestTrashConfirmation()
      }
      .keyboardShortcut(.delete, modifiers: [])
      .disabled(fileActionsDisabled == true || model?.canOperateOnSelection != true)

      Button("Get Info") {
        Task { await model?.showSelectedFileInfo() }
      }
      .keyboardShortcut("i", modifiers: .command)
      .disabled(fileActionsDisabled == true || model?.canOperateOnSelection != true)
    }

    CommandMenu("View") {
      Button(model?.isPreviewVisible == true ? "Find in Preview" : "Find in Current Folder") {
        if let previewFindActions {
          previewFindActions.present()
        } else {
          model?.requestSearchFocus()
        }
      }
      .keyboardShortcut("f", modifiers: .command)
      .disabled(model == nil || (model?.isPreviewVisible == true && previewFindActions == nil))

      Divider()

      Button(model?.showsHiddenFiles == true ? "Hide Hidden Files" : "Show Hidden Files") {
        Task { await model?.toggleHiddenFiles() }
      }
      .keyboardShortcut(".", modifiers: [.command, .shift])
      .disabled(model == nil)

      Divider()

      Button("List") {
        model?.viewMode = .list
        model?.closePreview()
      }
      .keyboardShortcut("1", modifiers: .command)

      Button("Large Icons") {
        model?.viewMode = .largeIcons
        model?.closePreview()
      }
      .keyboardShortcut("2", modifiers: .command)

      Divider()

      Button(model?.isPreviewVisible == true ? "Close Preview" : "Preview Item") {
        model?.togglePreview()
      }
      .keyboardShortcut("y", modifiers: .command)
      .disabled(model == nil)

      Button("Previous Image") {
        model?.selectPreviousPreviewImage()
      }
      .keyboardShortcut(.leftArrow, modifiers: [])
      .disabled(model?.previewKind != .image)

      Button("Next Image") {
        model?.selectNextPreviewImage()
      }
      .keyboardShortcut(.rightArrow, modifiers: [])
      .disabled(model?.previewKind != .image)

      Divider()

      Button("Add Image to Clipboard History (Copy)") {
        model?.capturePreviewedImage(operation: .copy)
      }
      .keyboardShortcut("p", modifiers: [])
      .disabled(model?.isPreviewVisible != true || model?.previewKind != .image)

      Button("Add Image to Clipboard History (Move)") {
        model?.capturePreviewedImage(operation: .move)
      }
      .keyboardShortcut("m", modifiers: [])
      .disabled(model?.isPreviewVisible != true || model?.previewKind != .image)

      Divider()

      Menu("Theme") {
        ForEach(ExplorerThemeID.allCases) { theme in
          Button {
            themeController.select(theme)
          } label: {
            if themeController.selection == theme {
              Label(theme.displayName, systemImage: "checkmark")
            } else {
              Text(theme.displayName)
            }
          }
        }
      }
    }
  }
}

private struct FileActionsDisabledKey: FocusedValueKey {
  typealias Value = Bool
}

extension FocusedValues {
  var fileActionsDisabled: Bool? {
    get { self[FileActionsDisabledKey.self] }
    set { self[FileActionsDisabledKey.self] = newValue }
  }
}
