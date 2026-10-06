import MiniExplorerCore
import SwiftUI

struct TextPreviewView: View {
  let item: FileItem
  let kind: PreviewContentKind
  @ObservedObject var model: FileBrowserModel
  @StateObject private var session: TextPreviewSession
  @StateObject private var findController = PreviewFindController()
  @State private var markdownMode: MarkdownEditorMode = .writing
  @State private var showsMarkdownCheatSheet = false
  @Environment(\.explorerPalette) private var palette

  init(item: FileItem, kind: PreviewContentKind, model: FileBrowserModel) {
    self.item = item
    self.kind = kind
    self.model = model
    _session = StateObject(wrappedValue: TextPreviewSession(url: item.url))
  }

  var body: some View {
    VStack(spacing: 0) {
      previewHeader
      if findController.state.isPresented {
        PreviewFindBar(controller: findController)
      }
      Divider()

      if session.isLoading {
        ProgressView("Loading \(item.displayName)…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let error = session.errorMessage {
        ContentUnavailableView(
          "Cannot Preview Text",
          systemImage: "doc.text.magnifyingglass",
          description: Text(error)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if kind == .markdown {
        MarkdownWritingEditor(
          text: $session.text,
          mode: markdownMode,
          theme: palette.id,
          findController: findController
        )
          .focusedValue(\.fileActionsDisabled, true)
          .accessibilityIdentifier("markdown-writing-editor")
      } else {
        ScrollableTextEditor(
          text: $session.text,
          theme: palette.id,
          findController: findController
        )
          .focusedValue(\.fileActionsDisabled, true)
          .accessibilityIdentifier(kind == .csv ? "csv-editor" : "text-editor")
      }
    }
    .task { await session.load() }
    .onChange(of: session.text) { _, _ in
      guard kind == .markdown, session.isDirty else { return }
      session.scheduleAutosave()
    }
    .onDisappear {
      guard kind == .markdown, session.isDirty else { return }
      Task { await session.save() }
    }
    .focusedSceneValue(\.savePreviewAction) {
      Task { await session.save() }
    }
    .focusedSceneValue(
      \.previewTrashAction,
      PreviewTrashAction(isEnabled: canTrashPreview) {
        model.requestPreviewTrashConfirmation()
      }
    )
    .focusedSceneValue(
      \.previewFindActions,
      PreviewFindActions(
        present: { findController.present() },
        dismissIfPresented: { findController.dismissIfPresented() }
      )
    )
    .accessibilityIdentifier("text-preview")
  }

  private var previewHeader: some View {
    HStack(spacing: 10) {
      Image(systemName: kind == .markdown ? "text.document.fill" : "doc.plaintext.fill")
        .foregroundStyle(palette.accent)
      Text(item.displayName)
        .font(.system(size: 13, weight: .semibold))
        .lineLimit(1)

      if kind == .markdown {
        ForEach(MarkdownEditorMode.allCases, id: \.self) { mode in
          Button(mode.rawValue) { markdownMode = mode }
            .buttonStyle(ExplorerToolbarButtonStyle(isSelected: markdownMode == mode, width: 82))
        }

        Button {
          showsMarkdownCheatSheet.toggle()
        } label: {
          Image(systemName: "questionmark")
        }
        .buttonStyle(ExplorerToolbarButtonStyle(width: 30))
        .help("Markdown Cheat Sheet")
        .accessibilityLabel("Markdown Cheat Sheet")
        .accessibilityIdentifier("markdown-cheat-sheet")
        .popover(isPresented: $showsMarkdownCheatSheet, arrowEdge: .bottom) {
          MarkdownCheatSheetView()
        }
      }

      Spacer()
      saveStatus
      PreviewTrashButton(isEnabled: canTrashPreview) {
        model.requestPreviewTrashConfirmation()
      }
      Text(
        kind == .markdown
          ? "⌘B bold · ⌘I italic · ⌘K link · ⌘S save"
          : "⌘S to save · Esc to close"
      )
      .font(.system(size: 11))
      .foregroundStyle(palette.secondaryText.opacity(0.7))
    }
    .padding(.horizontal, 14)
    .frame(height: 44)
    .background(palette.toolbarBackground)
  }

  @ViewBuilder
  private var saveStatus: some View {
    if session.isSaving {
      Label("Saving…", systemImage: "arrow.triangle.2.circlepath")
        .foregroundStyle(palette.accent)
        .font(.system(size: 11, weight: .medium))
    } else if let saveError = session.saveErrorMessage {
      Label(saveError, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(palette.warning)
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
        .help(saveError)
    } else if session.isDirty {
      Label("Unsaved changes", systemImage: "circle.fill")
        .foregroundStyle(palette.warning)
        .font(.system(size: 11, weight: .medium))
    } else if let savedAt = session.lastSavedAt {
      Text("Saved at \(savedAt.formatted(date: .omitted, time: .shortened))")
        .foregroundStyle(palette.success)
        .font(.system(size: 11, weight: .medium))
    } else {
      Text("Saved")
        .foregroundStyle(palette.secondaryText)
        .font(.system(size: 11))
    }
  }

  private var canTrashPreview: Bool {
    !session.isLoading && session.errorMessage == nil && !session.isDirty
  }

}

private struct MarkdownCheatSheetView: View {
  @Environment(\.explorerPalette) private var palette

  private let examples: [(label: String, syntax: String)] = [
    ("Heading", "# Heading"),
    ("Bold", "**bold**"),
    ("Italic", "*italic*"),
    ("Bullet list", "- item"),
    ("Numbered list", "1. item"),
    ("Link", "[label](https://example.com)"),
    ("Image", "![alt](image.png)"),
    ("Quote", "> quoted text"),
    ("Inline code", "`code`"),
    ("Code block", "```swift\nlet value = 1\n```"),
    ("Table", "| Name | Value |\n| --- | --- |\n| One | Two |"),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("MARKDOWN CHEAT SHEET")
        .font(.system(size: 13, weight: .bold, design: .monospaced))
        .foregroundStyle(palette.primaryText)
        .padding(14)

      Rectangle().fill(palette.border).frame(height: palette.borderWidth)

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(examples, id: \.label) { example in
            VStack(alignment: .leading, spacing: 4) {
              Text(example.label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
              Text(example.syntax)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.primaryText)
                .textSelection(.enabled)
            }
          }

          Text("SHORTCUTS")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(palette.secondaryText)
          Text("⌘B bold   ⌘I italic   ⌘K link   ⌘S save")
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(palette.primaryText)
        }
        .padding(14)
      }
    }
    .frame(width: 360, height: 500)
    .background(palette.contentBackground)
  }
}

private struct SavePreviewActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var savePreviewAction: (() -> Void)? {
    get { self[SavePreviewActionKey.self] }
    set { self[SavePreviewActionKey.self] = newValue }
  }
}
