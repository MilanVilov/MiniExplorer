import AppKit
import MiniExplorerCore
import SwiftUI

struct ScrollableTextEditor: NSViewRepresentable {
  @Binding var text: String
  var isEditable = true
  let theme: ExplorerThemeID
  let findController: PreviewFindController

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, findController: findController)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    let colors = ExplorerAppKitPalette.palette(for: theme)
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.borderType = .noBorder
    scrollView.drawsBackground = true
    scrollView.backgroundColor = colors.background

    let textView = NSTextView()
    textView.delegate = context.coordinator
    textView.isEditable = isEditable
    textView.isSelectable = true
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = true
    textView.autoresizingMask = [.width]
    textView.minSize = .zero
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.textContainer?.containerSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.textContainer?.widthTracksTextView = false
    textView.textContainer?.heightTracksTextView = false
    textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    textView.textColor = colors.text
    textView.insertionPointColor = colors.accent
    textView.backgroundColor = colors.background
    textView.textContainerInset = NSSize(width: 14, height: 12)
    textView.string = text
    scrollView.documentView = textView
    context.coordinator.textView = textView
    findController.attach(textView: textView)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? NSTextView else { return }
    let colors = ExplorerAppKitPalette.palette(for: theme)
    textView.isEditable = isEditable
    scrollView.backgroundColor = colors.background
    textView.textColor = colors.text
    textView.insertionPointColor = colors.accent
    textView.backgroundColor = colors.background
    if textView.string != text {
      let selection = textView.selectedRanges
      textView.string = text
      textView.selectedRanges = selection
      findController.textContentDidChange()
    }
    findController.attach(textView: textView)
  }

  static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
    guard let textView = coordinator.textView else { return }
    coordinator.findController.detach(textView: textView)
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    @Binding private var text: String
    let findController: PreviewFindController
    weak var textView: NSTextView?

    init(text: Binding<String>, findController: PreviewFindController) {
      _text = text
      self.findController = findController
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      text = textView.string
      findController.textContentDidChange()
    }
  }
}
