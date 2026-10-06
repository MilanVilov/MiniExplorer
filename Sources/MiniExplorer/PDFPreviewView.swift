import AppKit
import PDFKit
import MiniExplorerCore
import SwiftUI

struct PDFPreviewView: View {
  let item: FileItem
  @ObservedObject var model: FileBrowserModel
  @StateObject private var session: PDFPreviewSession
  @StateObject private var findController = PreviewFindController()
  @Environment(\.explorerPalette) private var palette

  init(item: FileItem, model: FileBrowserModel) {
    self.item = item
    self.model = model
    _session = StateObject(wrappedValue: PDFPreviewSession(url: item.url))
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
      } else if let errorMessage = session.errorMessage {
        ContentUnavailableView(
          "Cannot Preview PDF",
          systemImage: "doc.text.magnifyingglass",
          description: Text(errorMessage)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        PDFKitDocumentView(
          session: session,
          findController: findController,
          backgroundColor: palette.contentBackground.nsColor
        )
      }
    }
    .task { session.load() }
    .focusedValue(\.fileActionsDisabled, true)
    .focusedSceneValue(
      \.previewTrashAction,
      PreviewTrashAction(isEnabled: true) {
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
    .accessibilityIdentifier("pdf-preview")
  }

  private var previewHeader: some View {
    HStack(spacing: 8) {
      Image(systemName: "doc.richtext.fill")
        .foregroundStyle(palette.accent)
      Text(item.displayName)
        .font(.system(size: 13, weight: .semibold))
        .lineLimit(1)

      PreviewTrashButton(isEnabled: true) {
        model.requestPreviewTrashConfirmation()
      }

      Spacer()

      controlButton("Previous Page", systemImage: "chevron.left") {
        session.goToPreviousPage()
      }
      .disabled(!session.canGoToPreviousPage)

      Text(session.pageSummary)
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(palette.secondaryText)
        .frame(minWidth: 58)
        .accessibilityIdentifier("pdf-page-count")

      controlButton("Next Page", systemImage: "chevron.right") {
        session.goToNextPage()
      }
      .disabled(!session.canGoToNextPage)

      Divider().frame(height: 20)

      controlButton("Zoom Out", systemImage: "minus.magnifyingglass") {
        session.zoomOut()
      }

      Text("\(session.zoomPercent)%")
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(palette.secondaryText)
        .frame(minWidth: 46)
        .accessibilityIdentifier("pdf-zoom-percent")

      controlButton("Zoom In", systemImage: "plus.magnifyingglass") {
        session.zoomIn()
      }

      Button("Fit Width") { session.fitWidth() }
        .buttonStyle(ExplorerToolbarButtonStyle(width: 72))
        .help("Fit PDF to Width")

      Button("Fit Page") { session.fitPage() }
        .buttonStyle(ExplorerToolbarButtonStyle(width: 68))
        .help("Fit the Current PDF Page")
    }
    .padding(.horizontal, 14)
    .frame(height: 44)
    .background(palette.toolbarBackground)
  }

  private func controlButton(
    _ label: String,
    systemImage: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(label, systemImage: systemImage)
        .labelStyle(.iconOnly)
    }
    .buttonStyle(ExplorerToolbarButtonStyle())
    .help(label)
  }
}

@MainActor
private final class PDFPreviewSession: NSObject, ObservableObject {
  @Published private(set) var document: PDFDocument?
  @Published private(set) var isLoading = true
  @Published private(set) var errorMessage: String?
  @Published private(set) var currentPageIndex = 0
  @Published private(set) var pageCount = 0
  @Published private(set) var zoomPercent = 100

  let url: URL
  private weak var pdfView: PDFView?
  private var keepsFittingWidth = true

  init(url: URL) {
    self.url = url
  }

  var pageSummary: String {
    pageCount == 0 ? "0 / 0" : "\(currentPageIndex + 1) / \(pageCount)"
  }

  var canGoToPreviousPage: Bool {
    currentPageIndex > 0
  }

  var canGoToNextPage: Bool {
    currentPageIndex + 1 < pageCount
  }

  func load() {
    isLoading = true
    errorMessage = nil
    document = nil
    currentPageIndex = 0
    pageCount = 0

    guard FileManager.default.isReadableFile(atPath: url.path),
      let loadedDocument = PDFDocument(url: url)
    else {
      fail("MiniExplorer could not read this PDF document.")
      return
    }
    guard !loadedDocument.isLocked else {
      fail("This PDF is password-protected and cannot be previewed without its password.")
      return
    }
    guard loadedDocument.pageCount > 0 else {
      fail("This PDF does not contain any readable pages.")
      return
    }

    document = loadedDocument
    pageCount = loadedDocument.pageCount
    isLoading = false
    installDocumentIfReady()
  }

  func attach(_ view: PDFView) {
    if pdfView !== view {
      detach()
      pdfView = view
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(pageChanged(_:)),
        name: .PDFViewPageChanged,
        object: view
      )
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(scaleChanged(_:)),
        name: .PDFViewScaleChanged,
        object: view
      )
    }
    configure(view)
    if let view = view as? LayoutAwarePDFView {
      view.layoutHandler = { [weak self] in
        self?.refitWidthAfterLayout()
      }
      view.userZoomHandler = { [weak self] in
        self?.keepsFittingWidth = false
      }
    }
    installDocumentIfReady()
  }

  func detach() {
    guard let pdfView else { return }
    if let view = pdfView as? LayoutAwarePDFView {
      view.layoutHandler = nil
      view.userZoomHandler = nil
    }
    NotificationCenter.default.removeObserver(
      self,
      name: .PDFViewPageChanged,
      object: pdfView
    )
    NotificationCenter.default.removeObserver(
      self,
      name: .PDFViewScaleChanged,
      object: pdfView
    )
    self.pdfView = nil
  }

  func goToPreviousPage() {
    pdfView?.goToPreviousPage(nil)
    synchronizePage()
  }

  func goToNextPage() {
    pdfView?.goToNextPage(nil)
    synchronizePage()
  }

  func zoomOut() {
    keepsFittingWidth = false
    setScale((pdfView?.scaleFactor ?? 1) / 1.2)
  }

  func zoomIn() {
    keepsFittingWidth = false
    setScale((pdfView?.scaleFactor ?? 1) * 1.2)
  }

  func fitWidth() {
    keepsFittingWidth = true
    refitWidthAfterLayout()
  }

  func fitPage() {
    guard let pdfView, let page = pdfView.currentPage ?? document?.page(at: 0) else { return }
    keepsFittingWidth = false
    let pageBounds = page.bounds(for: pdfView.displayBox)
    guard pageBounds.width > 0, pageBounds.height > 0 else { return }
    let availableWidth = max(pdfView.bounds.width - 32, 1)
    let availableHeight = max(pdfView.bounds.height - 32, 1)
    setScale(min(availableWidth / pageBounds.width, availableHeight / pageBounds.height))
  }

  @objc private func pageChanged(_ notification: Notification) {
    synchronizePage()
    refitWidthAfterLayout()
  }

  @objc private func scaleChanged(_ notification: Notification) {
    synchronizeScale()
  }

  private func configure(_ view: PDFView) {
    view.displayMode = .singlePageContinuous
    view.displayDirection = .vertical
    view.displaysPageBreaks = true
    view.pageShadowsEnabled = false
    view.autoScales = false
    view.minScaleFactor = 0.25
    view.maxScaleFactor = 8
  }

  private func installDocumentIfReady() {
    guard let pdfView, let document else { return }
    guard pdfView.document !== document else { return }
    pdfView.document = document
    if let firstPage = document.page(at: 0) {
      pdfView.go(to: firstPage)
    }
    fitWidth()
    synchronizePage()
  }

  private func refitWidthAfterLayout() {
    guard keepsFittingWidth, let pdfView,
      let page = pdfView.currentPage ?? document?.page(at: 0),
      pdfView.bounds.width > 1
    else { return }
    let pageBounds = page.bounds(for: pdfView.displayBox)
    let scale = PDFPreviewSizing.fitWidthScale(
      viewWidth: Double(pdfView.bounds.width),
      pageWidth: Double(pageBounds.width),
      horizontalInset: 40,
      minimumScale: Double(pdfView.minScaleFactor),
      maximumScale: Double(pdfView.maxScaleFactor)
    )
    if abs(pdfView.scaleFactor - CGFloat(scale)) > 0.005 {
      setScale(CGFloat(scale))
    } else {
      synchronizeScale()
    }
  }

  private func setScale(_ scale: CGFloat) {
    guard let pdfView else { return }
    pdfView.autoScales = false
    pdfView.scaleFactor = min(max(scale, pdfView.minScaleFactor), pdfView.maxScaleFactor)
    synchronizeScale()
  }

  private func synchronizePage() {
    guard let pdfView, let document, let page = pdfView.currentPage else { return }
    let index = document.index(for: page)
    guard index != NSNotFound else { return }
    currentPageIndex = index
  }

  private func synchronizeScale() {
    guard let pdfView else { return }
    zoomPercent = Int((pdfView.scaleFactor * 100).rounded())
  }

  private func fail(_ message: String) {
    errorMessage = message
    isLoading = false
  }
}

private struct PDFKitDocumentView: NSViewRepresentable {
  @ObservedObject var session: PDFPreviewSession
  @ObservedObject var findController: PreviewFindController
  let backgroundColor: NSColor

  final class Coordinator {
    let session: PDFPreviewSession
    let findController: PreviewFindController

    init(session: PDFPreviewSession, findController: PreviewFindController) {
      self.session = session
      self.findController = findController
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(session: session, findController: findController)
  }

  func makeNSView(context: Context) -> PDFView {
    let view = LayoutAwarePDFView()
    view.backgroundColor = backgroundColor
    session.attach(view)
    findController.attach(pdfView: view)
    return view
  }

  func updateNSView(_ view: PDFView, context: Context) {
    view.backgroundColor = backgroundColor
    session.attach(view)
    findController.attach(pdfView: view)
  }

  static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
    coordinator.session.detach()
    coordinator.findController.detach(pdfView: view)
    view.document = nil
  }
}

@MainActor
private final class LayoutAwarePDFView: PDFView {
  var layoutHandler: (() -> Void)?
  var userZoomHandler: (() -> Void)?

  override func layout() {
    super.layout()
    layoutHandler?()
  }

  override func magnify(with event: NSEvent) {
    userZoomHandler?()
    super.magnify(with: event)
  }
}

private extension Color {
  var nsColor: NSColor {
    NSColor(self)
  }
}
