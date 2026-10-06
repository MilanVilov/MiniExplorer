import AppKit
import MiniExplorerCore
import PDFKit
import SwiftUI

struct PreviewFindActions {
  let present: () -> Void
  let dismissIfPresented: () -> Bool
}

private struct PreviewFindActionsKey: FocusedValueKey {
  typealias Value = PreviewFindActions
}

extension FocusedValues {
  var previewFindActions: PreviewFindActions? {
    get { self[PreviewFindActionsKey.self] }
    set { self[PreviewFindActionsKey.self] = newValue }
  }
}

@MainActor
final class PreviewFindController: ObservableObject {
  @Published var query = "" {
    didSet { refreshMatches() }
  }
  @Published private(set) var state = DocumentFindState()
  @Published private(set) var focusRequest = 0

  private weak var textView: NSTextView?
  private weak var pdfView: PDFView?
  private weak var attachedPDFDocument: PDFDocument?
  private var textRanges: [NSRange] = []
  private var pdfSelections: [PDFSelection] = []

  var matchSummary: String {
    guard let current = state.currentMatchIndex, state.matchCount > 0 else { return "0 / 0" }
    return "\(current + 1) / \(state.matchCount)"
  }

  func present() {
    var updated = state
    updated.present()
    state = updated
    focusRequest += 1
  }

  @discardableResult
  func dismissIfPresented() -> Bool {
    var updated = state
    guard updated.dismissIfPresented() else { return false }
    state = updated
    query = ""
    return true
  }

  func selectNextMatch() {
    var updated = state
    updated.selectNextMatch()
    state = updated
    revealCurrentMatch()
  }

  func selectPreviousMatch() {
    var updated = state
    updated.selectPreviousMatch()
    state = updated
    revealCurrentMatch()
  }

  func attach(textView: NSTextView) {
    guard self.textView !== textView else { return }
    self.textView = textView
    pdfView = nil
    attachedPDFDocument = nil
    refreshMatches()
  }

  func textContentDidChange() {
    guard textView != nil else { return }
    refreshMatches()
  }

  func detach(textView: NSTextView) {
    guard self.textView === textView else { return }
    clearTextHighlights()
    self.textView = nil
  }

  func attach(pdfView: PDFView) {
    if self.pdfView === pdfView, attachedPDFDocument === pdfView.document { return }
    self.pdfView = pdfView
    attachedPDFDocument = pdfView.document
    textView = nil
    refreshMatches()
  }

  func detach(pdfView: PDFView) {
    guard self.pdfView === pdfView else { return }
    pdfView.highlightedSelections = nil
    self.pdfView = nil
    attachedPDFDocument = nil
  }

  private func refreshMatches() {
    if let textView {
      refreshTextMatches(in: textView)
    } else if let pdfView {
      refreshPDFMatches(in: pdfView)
    } else {
      updateMatchCount(0)
    }
  }

  private func refreshTextMatches(in textView: NSTextView) {
    clearTextHighlights()
    textRanges = DocumentSearchIndex(text: textView.string, query: query).ranges
    if let layoutManager = textView.layoutManager {
      for range in textRanges {
        layoutManager.addTemporaryAttribute(
          .backgroundColor,
          value: NSColor.systemYellow.withAlphaComponent(0.48),
          forCharacterRange: range
        )
      }
    }
    updateMatchCount(textRanges.count)
    revealCurrentMatch()
  }

  private func refreshPDFMatches(in pdfView: PDFView) {
    if query.isEmpty {
      pdfSelections = []
    } else {
      pdfSelections = pdfView.document?.findString(
        query,
        withOptions: [.caseInsensitive, .diacriticInsensitive]
      ) ?? []
    }
    for selection in pdfSelections {
      selection.color = NSColor.systemYellow.withAlphaComponent(0.55)
    }
    pdfView.highlightedSelections = pdfSelections
    updateMatchCount(pdfSelections.count)
    revealCurrentMatch()
  }

  private func updateMatchCount(_ count: Int) {
    var updated = state
    updated.updateMatchCount(count)
    if updated != state {
      state = updated
    }
  }

  private func revealCurrentMatch() {
    guard let index = state.currentMatchIndex else { return }
    if let textView, textRanges.indices.contains(index) {
      textView.setSelectedRange(textRanges[index])
      textView.scrollRangeToVisible(textRanges[index])
    } else if let pdfView, pdfSelections.indices.contains(index) {
      for (selectionIndex, selection) in pdfSelections.enumerated() {
        selection.color = selectionIndex == index
          ? NSColor.systemOrange.withAlphaComponent(0.82)
          : NSColor.systemYellow.withAlphaComponent(0.55)
      }
      pdfView.highlightedSelections = pdfSelections
      pdfView.go(to: pdfSelections[index])
    }
  }

  private func clearTextHighlights() {
    guard let textView, let layoutManager = textView.layoutManager else { return }
    layoutManager.removeTemporaryAttribute(
      .backgroundColor,
      forCharacterRange: NSRange(location: 0, length: (textView.string as NSString).length)
    )
    textRanges = []
  }
}

struct PreviewFindBar: View {
  @ObservedObject var controller: PreviewFindController
  @FocusState private var isSearchFocused: Bool
  @Environment(\.explorerPalette) private var palette

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(palette.secondaryText)
      TextField("Find in document", text: $controller.query)
        .textFieldStyle(.plain)
        .focused($isSearchFocused)
        .focusedValue(\.fileActionsDisabled, true)
        .onSubmit { controller.selectNextMatch() }
        .onKeyPress(keys: [.return]) { press in
          if press.modifiers.contains(.shift) {
            controller.selectPreviousMatch()
          } else {
            controller.selectNextMatch()
          }
          return .handled
        }
        .accessibilityIdentifier("preview-find-field")

      Text(controller.matchSummary)
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(palette.secondaryText)
        .frame(minWidth: 48)

      findButton("Previous Match", systemImage: "chevron.up") {
        controller.selectPreviousMatch()
      }
      findButton("Next Match", systemImage: "chevron.down") {
        controller.selectNextMatch()
      }
      findButton("Close Find", systemImage: "xmark") {
        controller.dismissIfPresented()
      }
    }
    .padding(.horizontal, 14)
    .frame(height: 38)
    .background(palette.toolbarBackground)
    .overlay(alignment: .bottom) {
      Rectangle().fill(palette.border).frame(height: palette.borderWidth)
    }
    .onAppear { isSearchFocused = true }
    .onChange(of: controller.focusRequest) { _, _ in isSearchFocused = true }
    .accessibilityIdentifier("preview-find-bar")
  }

  private func findButton(
    _ label: String,
    systemImage: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(label, systemImage: systemImage).labelStyle(.iconOnly)
    }
    .buttonStyle(ExplorerToolbarButtonStyle())
    .help(label)
  }
}
