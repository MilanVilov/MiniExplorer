import AppKit
import MiniExplorerCore
import SwiftUI

enum MarkdownEditorMode: String, CaseIterable {
  case writing = "Writing"
  case raw = "Raw"
}

struct MarkdownWritingEditor: NSViewRepresentable {
  @Binding var text: String
  let mode: MarkdownEditorMode
  let theme: ExplorerThemeID
  let findController: PreviewFindController

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, findController: findController)
  }

  func makeNSView(context: Context) -> CenteredMarkdownScrollView {
    let scrollView = CenteredMarkdownScrollView()
    let textView = MarkdownNSTextView()
    let container = CenteredMarkdownContainer(textView: textView)

    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = true
    scrollView.backgroundColor = ExplorerAppKitPalette.palette(for: theme).background
    scrollView.documentView = container
    scrollView.editorContainer = container

    textView.delegate = context.coordinator
    textView.isEditable = true
    textView.isSelectable = true
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.drawsBackground = false
    textView.textContainerInset = NSSize(width: 18, height: 18)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.string = text
    textView.formattingHandler = { [weak textView] command in
      guard let textView else { return }
      apply(command, to: textView)
    }

    context.coordinator.textView = textView
    context.coordinator.container = container
    context.coordinator.scrollView = scrollView
    findController.attach(textView: textView)
    applyStyles(to: textView)
    scrollView.updateDocumentLayout()
    return scrollView
  }

  func updateNSView(_ scrollView: CenteredMarkdownScrollView, context: Context) {
    guard let textView = scrollView.editorContainer?.textView else { return }
    scrollView.backgroundColor = ExplorerAppKitPalette.palette(for: theme).background
    if textView.string != text {
      let selection = textView.selectedRanges
      textView.string = text
      textView.selectedRanges = selection
      findController.textContentDidChange()
    }
    applyStyles(to: textView)
    scrollView.updateDocumentLayout()
    findController.attach(textView: textView)
  }

  static func dismantleNSView(
    _ scrollView: CenteredMarkdownScrollView,
    coordinator: Coordinator
  ) {
    guard let textView = coordinator.textView else { return }
    coordinator.findController.detach(textView: textView)
  }

  private func applyStyles(to textView: NSTextView) {
    guard !textView.hasMarkedText(), let storage = textView.textStorage else { return }
    let selection = textView.selectedRanges
    let fullRange = NSRange(location: 0, length: storage.length)
    let paragraphStyle = NSMutableParagraphStyle()
    let colors = ExplorerAppKitPalette.palette(for: theme)
    paragraphStyle.lineSpacing = mode == .writing ? 7 : 5
    paragraphStyle.paragraphSpacing = mode == .writing ? 5 : 2

    storage.beginEditing()
    storage.setAttributes(
      [
        .font: NSFont.monospacedSystemFont(
          ofSize: mode == .writing ? 18 : 16,
          weight: .regular
        ),
        .foregroundColor: colors.text,
        .paragraphStyle: paragraphStyle,
      ],
      range: fullRange
    )

    if mode == .writing {
      for span in MarkdownWritingStyle.spans(in: textView.string) {
        guard NSMaxRange(span.range) <= storage.length else { continue }
        storage.addAttributes(attributes(for: span.kind, colors: colors), range: span.range)
      }
    }
    storage.endEditing()
    textView.selectedRanges = selection
  }

  private func attributes(
    for kind: MarkdownWritingStyle.Kind,
    colors: ExplorerAppKitPalette
  ) -> [NSAttributedString.Key: Any] {
    switch kind {
    case .heading(let level):
      let size: CGFloat = level == 1 ? 30 : level == 2 ? 24 : level == 3 ? 21 : 18
      return [
        .font: NSFont.monospacedSystemFont(ofSize: size, weight: .bold),
        .foregroundColor: colors.text,
      ]
    case .bold:
      return [.font: NSFont.monospacedSystemFont(ofSize: 18, weight: .bold)]
    case .italic:
      let font = NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)
      return [.font: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)]
    case .link:
      return [
        .foregroundColor: colors.accent,
        .underlineStyle: NSUnderlineStyle.single.rawValue,
      ]
    case .inlineCode:
      return [
        .font: NSFont.monospacedSystemFont(ofSize: 17, weight: .medium),
        .backgroundColor: colors.surface,
      ]
    case .codeBlock:
      return [
        .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .regular),
        .backgroundColor: colors.surface,
      ]
    case .listMarker, .quoteMarker:
      return [
        .foregroundColor: colors.warning,
        .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .bold),
      ]
    case .syntax:
      return [.foregroundColor: colors.secondaryText]
    }
  }

  private func apply(_ command: MarkdownCommand, to textView: NSTextView) {
    let original = textView.string
    let selection = textView.selectedRange()
    let result: MarkdownEditResult
    switch command {
    case .bold:
      result = MarkdownEditing.bold(original, selection: selection)
    case .italic:
      result = MarkdownEditing.italic(original, selection: selection)
    case .link:
      result = MarkdownEditing.link(original, selection: selection)
    }

    let originalLength = (original as NSString).length
    let replacementLength = (result.text as NSString).length - originalLength + selection.length
    let replacementRange = NSRange(location: selection.location, length: replacementLength)
    let replacement = (result.text as NSString).substring(with: replacementRange)
    textView.insertText(replacement, replacementRange: selection)
    textView.setSelectedRange(result.selection)
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    @Binding private var text: String
    weak var textView: NSTextView?
    weak var container: CenteredMarkdownContainer?
    weak var scrollView: CenteredMarkdownScrollView?
    let findController: PreviewFindController

    init(text: Binding<String>, findController: PreviewFindController) {
      _text = text
      self.findController = findController
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      text = textView.string
      findController.textContentDidChange()
      container?.updateEditorLayout(viewportHeight: scrollView?.contentSize.height ?? 0)
    }
  }
}

enum MarkdownCommand {
  case bold
  case italic
  case link
}

final class MarkdownNSTextView: NSTextView {
  var formattingHandler: ((MarkdownCommand) -> Void)?

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard modifiers == .command,
      let key = event.charactersIgnoringModifiers?.lowercased()
    else { return super.performKeyEquivalent(with: event) }

    let command: MarkdownCommand?
    switch key {
    case "b": command = .bold
    case "i": command = .italic
    case "k": command = .link
    default: command = nil
    }
    guard let command else { return super.performKeyEquivalent(with: event) }
    formattingHandler?(command)
    return true
  }
}

final class CenteredMarkdownContainer: NSView {
  let textView: MarkdownNSTextView
  private let maximumEditorWidth: CGFloat = 780

  init(textView: MarkdownNSTextView) {
    self.textView = textView
    super.init(frame: .zero)
    addSubview(textView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override var isFlipped: Bool { true }

  override func layout() {
    super.layout()
    updateEditorLayout(viewportHeight: superview?.bounds.height ?? 0)
  }

  func updateEditorLayout(viewportHeight: CGFloat) {
    let sidePadding: CGFloat = 48
    let editorWidth = min(maximumEditorWidth, max(360, bounds.width - sidePadding * 2))
    textView.textContainer?.containerSize = NSSize(
      width: editorWidth - textView.textContainerInset.width * 2,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    let usedHeight = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0
    let editorHeight = max(
      viewportHeight - 84,
      usedHeight + textView.textContainerInset.height * 2 + 20
    )
    let editorX = max(sidePadding, (bounds.width - editorWidth) / 2)
    textView.frame = NSRect(x: editorX, y: 32, width: editorWidth, height: editorHeight)
    let requiredHeight = max(viewportHeight, editorHeight + 76)
    if abs(frame.height - requiredHeight) > 0.5 {
      frame.size.height = requiredHeight
    }
  }
}

final class CenteredMarkdownScrollView: NSScrollView {
  weak var editorContainer: CenteredMarkdownContainer?

  override func layout() {
    super.layout()
    updateDocumentLayout()
  }

  func updateDocumentLayout() {
    guard let editorContainer else { return }
    let viewport = contentSize
    if abs(editorContainer.frame.width - viewport.width) > 0.5 {
      editorContainer.frame.size.width = viewport.width
    }
    editorContainer.updateEditorLayout(viewportHeight: viewport.height)
  }
}
