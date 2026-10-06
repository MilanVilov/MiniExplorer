import AppKit
import MiniExplorerCore
import QuickLookThumbnailing
import SwiftUI

struct LargeIconGridView: View {
  @ObservedObject var model: FileBrowserModel
  @Environment(\.explorerPalette) private var palette
  @EnvironmentObject private var terminalController: TerminalLauncherController
  @State private var isCreatingFile = false
  @State private var isCreatingFolder = false
  @State private var dropTargetID: URL?
  @State private var itemFrames: [URL: CGRect] = [:]
  @State private var marqueeOrigin: CGPoint?
  @State private var marqueeCurrent: CGPoint?
  @State private var marqueeBaseline: [URL] = []
  @State private var marqueeToggles = false

  private let columns = [
    GridItem(.adaptive(minimum: 126, maximum: 160), spacing: 14, alignment: .top)
  ]

  var body: some View {
    GeometryReader { geometry in
      ScrollViewReader { proxy in
        ScrollView {
          ZStack(alignment: .topLeading) {
            Color.clear
              .contentShape(Rectangle())
              .onTapGesture {
                model.handleBackgroundInteraction()
              }
              .gesture(marqueeGesture)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
              ForEach(model.items) { item in
                LargeIconItemView(item: item, model: model, dropTargetID: $dropTargetID)
                  .reportsMarqueeFrame(for: item.id, coordinateSpace: "large-icon-area")
                  .id(item.id)
              }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            if let rectangle = marqueeRectangle {
              MarqueeRectangleView(rectangle: rectangle)
            }
          }
          .coordinateSpace(name: "large-icon-area")
          .onPreferenceChange(MarqueeItemFramePreferenceKey.self) { itemFrames = $0 }
          .frame(
            maxWidth: .infinity,
            minHeight: geometry.size.height,
            alignment: .topLeading
          )
        }
        .onChange(of: model.previewCloseRequest) { _, _ in
          guard let id = model.primaryItem?.id else { return }
          withAnimation { proxy.scrollTo(id, anchor: .center) }
        }
      }
      .background(palette.contentBackground)
      .contentShape(Rectangle())
      .dropDestination(for: URL.self) { urls, _ in
        receive(urls, into: model.currentURL)
        return true
      }
      .contextMenu {
        Button("New Folder…") { isCreatingFolder = true }
        Button("New File…") { isCreatingFile = true }
        Divider()
        Button("Paste") {
          Task { await model.paste() }
        }
        .disabled(!model.canPaste)
        Button("Clipboard History…") { model.showClipboardHistory() }
        Button(terminalController.actionTitle) {
          terminalController.open(directory: model.currentURL, model: model)
        }
        Divider()
        Button("Refresh") {
          Task { await model.refreshCurrentDirectory() }
        }
        Button("Save Current Folder as Shortcut") {
          Task { await model.saveCurrentFolderShortcut() }
        }
        Button(model.showsHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files") {
          Task { await model.toggleHiddenFiles() }
        }
        Divider()
        Button("List View") { model.viewMode = .list }
        Button("Large Icons") { model.viewMode = .largeIcons }
          .disabled(true)
      }
      .sheet(isPresented: $isCreatingFile) {
        NewFileView(model: model, isPresented: $isCreatingFile)
      }
      .sheet(isPresented: $isCreatingFolder) {
        NewFolderView(model: model, isPresented: $isCreatingFolder)
      }
      .accessibilityIdentifier("large-icon-grid")
    }
  }

  private func receive(_ urls: [URL], into directory: URL) {
    let internalSources = model.draggedItemURLs
    let transferredURLs = internalSources.isEmpty ? urls : internalSources
    Task {
      await model.receiveDrop(
        transferredURLs,
        into: directory,
        internalSources: internalSources
      )
      model.endDragging()
    }
  }

  private var marqueeRectangle: CGRect? {
    guard let origin = marqueeOrigin, let current = marqueeCurrent else { return nil }
    return MarqueeSelection.rectangle(from: origin, to: current)
  }

  private var marqueeGesture: some Gesture {
    DragGesture(minimumDistance: 4, coordinateSpace: .named("large-icon-area"))
      .onChanged { value in
        if marqueeOrigin == nil {
          marqueeOrigin = value.startLocation
          marqueeBaseline = model.selection.selectedIDs
          if case .command = currentFileSelectionModifier() {
            marqueeToggles = true
          } else {
            marqueeToggles = false
          }
          model.requestFileInteractionFocus()
        }
        marqueeCurrent = value.location
        applyMarqueeSelection()
      }
      .onEnded { _ in
        marqueeOrigin = nil
        marqueeCurrent = nil
        marqueeBaseline = []
      }
  }

  private func applyMarqueeSelection() {
    guard let rectangle = marqueeRectangle else { return }
    let hits = MarqueeSelection.intersectingIDs(
      visibleIDs: model.items.map(\.id),
      frames: itemFrames,
      rectangle: rectangle
    )
    let resolved = MarqueeSelection.resolvedIDs(
      baseline: marqueeBaseline,
      hits: hits,
      togglesBaseline: marqueeToggles,
      visibleIDs: model.items.map(\.id)
    )
    model.replaceSelection(with: Set(resolved))
  }
}

private struct LargeIconItemView: View {
  let item: FileItem
  @ObservedObject var model: FileBrowserModel
  @Binding var dropTargetID: URL?
  @State private var showsOpenWith = false
  @State private var slowRenameTracker = SlowRenameClickTracker<URL>(
    minimumDelay: NSEvent.doubleClickInterval,
    maximumDelay: 1.5
  )
  @Environment(\.explorerPalette) private var palette

  private var isSelected: Bool { model.selection.selectedIDs.contains(item.id) }
  private var isPrimary: Bool { model.selection.primaryID == item.id }
  private var isDropTarget: Bool { dropTargetID == item.id }

  var body: some View {
    VStack(spacing: 7) {
      FileThumbnailView(item: item, size: CGSize(width: 104, height: 88))

      HighlightedFileName(name: item.displayName, query: model.searchText)
        .font(.system(size: 12.5))
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .foregroundStyle(isSelected ? palette.primaryText : palette.primaryText)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .top)
    }
    .contentShape(Rectangle())
    .simultaneousGesture(
      TapGesture(count: 1).onEnded {
        handleSlowRenameClick()
      }
    )
    .padding(.horizontal, 8)
    .padding(.vertical, 9)
    .frame(maxWidth: .infinity, minHeight: 138, alignment: .top)
    .background(isSelected ? palette.selectionBackground : Color.clear)
    .overlay {
      ZStack {
        if isSelected && palette.isFlat {
          Rectangle().stroke(
            palette.accent,
            lineWidth: isPrimary ? max(2, palette.borderWidth) : palette.borderWidth
          )
        }
        if isDropTarget {
          Rectangle()
            .fill(palette.accent.opacity(0.16))
            .overlay {
              Rectangle().stroke(palette.accent, lineWidth: max(2, palette.borderWidth))
            }
            .allowsHitTesting(false)
        }
      }
    }
    .contentShape(Rectangle())
    .simultaneousGesture(
      TapGesture(count: 1).onEnded {
        model.requestFileInteractionFocus()
        model.selectItem(item.id, modifier: currentFileSelectionModifier())
      }
    )
    .simultaneousGesture(
      TapGesture(count: 2).onEnded {
        model.requestFileInteractionFocus()
        model.selectItem(item.id)
        handleDoubleClick()
      }
    )
    .onDrag {
      model.beginDragging(item.url)
      return NSItemProvider(contentsOf: item.url) ?? NSItemProvider(object: item.url as NSURL)
    }
    .dropDestination(for: URL.self) { urls, _ in
      guard item.isDirectory, !item.isPackage else { return false }
      receive(urls, into: item.url)
      return true
    } isTargeted: { isTargeted in
      guard item.isDirectory, !item.isPackage else { return }
      if isTargeted {
        dropTargetID = item.id
      } else if dropTargetID == item.id {
        dropTargetID = nil
      }
    }
    .contextMenu {
      Button("Open With…") {
        model.selectItem(item.id)
        showsOpenWith = true
      }
      .disabled(item.isDirectory)
      Divider()
      Button("Copy") {
        prepareContextSelection()
        model.copySelection()
      }
      Button("Cut") {
        prepareContextSelection()
        model.cutSelection()
      }
      Divider()
      Button("Rename…") {
        prepareContextSelection()
        model.requestRename()
      }
      .disabled(model.selection.selectedIDs.contains(item.id) && model.selectedItems.count != 1)
      Button("Duplicate") {
        prepareContextSelection()
        Task { await model.duplicateSelection() }
      }
      Button("Move to Trash…") {
        prepareContextSelection()
        model.requestTrashConfirmation()
      }
      Button("Get Info") {
        prepareContextSelection()
        Task { await model.showSelectedFileInfo() }
      }
      Divider()
      Button("Paste") {
        Task { await model.paste() }
      }
      .disabled(!model.canPaste)
    }
    .sheet(isPresented: $showsOpenWith) {
      OpenWithChooserView(item: item)
    }
  }

  private func receive(_ urls: [URL], into directory: URL) {
    let internalSources = model.draggedItemURLs
    let transferredURLs = internalSources.isEmpty ? urls : internalSources
    Task {
      await model.receiveDrop(
        transferredURLs,
        into: directory,
        internalSources: internalSources
      )
      model.endDragging()
    }
  }

  private func prepareContextSelection() {
    if !model.selection.selectedIDs.contains(item.id) {
      model.selectItem(item.id)
    }
  }

  private func activate() {
    if item.isDirectory && !item.isPackage {
      Task { await model.navigate(to: item.url) }
    } else if model.previewFileIfSupported(item) {
      return
    } else if !NSWorkspace.shared.open(item.url) {
      model.alert = BrowserAlert(
        title: "Cannot Open Item",
        message: "macOS could not find an application to open \(item.displayName)."
      )
    }
  }

  private func handleDoubleClick() {
    switch FileItemInteraction.doubleClickAction(
      isDirectory: item.isDirectory,
      isPackage: item.isPackage
    ) {
    case .open:
      activate()
    case .rename:
      model.selectItem(item.id)
      model.requestRename()
    }
  }

  private func handleSlowRenameClick() {
    switch currentFileSelectionModifier() {
    case .plain:
      break
    case .command, .shift:
      slowRenameTracker.reset()
      return
    }

    let isOnlySelectedItem = model.selection.selectedIDs.count == 1
      && model.selection.selectedIDs.contains(item.id)
    let action = slowRenameTracker.registerClick(
      on: item.id,
      at: ProcessInfo.processInfo.systemUptime,
      isOnlySelectedItem: isOnlySelectedItem
    )
    guard action == .rename else { return }
    model.selectItem(item.id)
    model.requestRename()
  }
}

private struct FileThumbnailView: View {
  let item: FileItem
  let size: CGSize

  @State private var thumbnail: NSImage?

  var body: some View {
    Group {
      if item.usesExplorerFolderIcon {
        ExplorerItemIcon(item: item, size: min(size.width, size.height))
      } else if let thumbnail {
        Image(nsImage: thumbnail)
          .resizable()
          .scaledToFit()
      } else {
        ExplorerItemIcon(item: item, size: min(size.width, size.height))
      }
    }
    .frame(width: size.width, height: size.height)
    .task(id: item.id) {
      guard !item.usesExplorerFolderIcon else { return }
      let request = QLThumbnailGenerator.Request(
        fileAt: item.url,
        size: size,
        scale: NSScreen.main?.backingScaleFactor ?? 2,
        representationTypes: .thumbnail
      )
      thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        .nsImage
    }
  }
}
