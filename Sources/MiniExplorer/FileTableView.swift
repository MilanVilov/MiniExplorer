import AppKit
import MiniExplorerCore
import SwiftUI

struct FileTableView: View {
  @ObservedObject var model: FileBrowserModel
  @State private var sortOrder = [KeyPathComparator(\FileItem.displayName)]
  @State private var openWithItem: FileItem?
  @State private var isCreatingFile = false
  @State private var isCreatingFolder = false
  @State private var slowRenameTracker = SlowRenameClickTracker<URL>(
    minimumDelay: NSEvent.doubleClickInterval,
    maximumDelay: 1.5
  )
  @State private var classicItemFrames: [URL: CGRect] = [:]
  @State private var classicMarqueeOrigin: CGPoint?
  @State private var classicMarqueeCurrent: CGPoint?
  @State private var classicMarqueeBaseline: [URL] = []
  @State private var classicMarqueeToggles = false
  @State private var classicMarqueeBlocked = false
  @Environment(\.explorerPalette) private var palette
  @EnvironmentObject private var terminalController: TerminalLauncherController

  var body: some View {
    Group {
      if palette.isFlat {
        FlatFileListView(
          model: model,
          openWithItem: $openWithItem,
          isCreatingFile: $isCreatingFile,
          isCreatingFolder: $isCreatingFolder
        )
      } else {
        classicTable
      }
    }
    .sheet(item: $openWithItem) { item in
      OpenWithChooserView(item: item)
    }
    .sheet(isPresented: $isCreatingFile) {
      NewFileView(model: model, isPresented: $isCreatingFile)
    }
    .sheet(isPresented: $isCreatingFolder) {
      NewFolderView(model: model, isPresented: $isCreatingFolder)
    }
  }

  private var classicTable: some View {
    Table(of: FileItem.self, selection: tableSelection, sortOrder: $sortOrder) {
      TableColumn(
        "Name",
        sortUsing: KeyPathComparator(\FileItem.displayName)
      ) { item in
        HStack(spacing: 7) {
          ExplorerItemIcon(item: item, size: 18)
          HighlightedFileName(name: item.displayName, query: model.searchText)
            .font(.system(size: 12.5))
            .lineLimit(1)
        }
        .reportsMarqueeFrame(for: item.id, coordinateSpace: "classic-file-area")
        .contentShape(Rectangle())
        .simultaneousGesture(
          TapGesture(count: 1).onEnded {
            handleSlowRenameClick(item)
          }
        )
      }
      .width(min: 220, ideal: 420)

      TableColumn(
        "Size",
        sortUsing: KeyPathComparator(\FileItem.size)
      ) { item in
        if let size = item.size, !item.isDirectory {
          Text(size, format: .byteCount(style: .file))
            .foregroundStyle(palette.secondaryText)
        } else {
          Text("—")
            .foregroundStyle(palette.secondaryText.opacity(0.65))
        }
      }
      .width(min: 80, ideal: 100, max: 130)

      TableColumn(
        "Modified",
        sortUsing: KeyPathComparator(\FileItem.modificationDate)
      ) { item in
        if let date = item.modificationDate {
          Text(date, format: .dateTime.year().month().day().hour().minute())
            .foregroundStyle(palette.secondaryText)
        } else {
          Text("—")
            .foregroundStyle(palette.secondaryText.opacity(0.65))
        }
      }
      .width(min: 145, ideal: 170, max: 210)
    } rows: {
      ForEach(model.items) { item in
        TableRow(item)
          .draggable(item.url)
          .dropDestination(for: URL.self) { urls in
            guard item.isDirectory, !item.isPackage else { return }
            receive(urls, into: item.url)
          }
      }
    }
    .contextMenu(forSelectionType: URL.self) { selection in
      selectionMenu(selection)
    } primaryAction: { selection in
      guard let id = selection.first, let item = item(withID: id) else { return }
      handleDoubleClick(item)
    }
    .dropDestination(for: URL.self) { urls, _ in
      receive(urls, into: model.currentURL)
      return true
    }
    .controlSize(.small)
    .alternatingRowBackgrounds(.enabled)
    .tint(palette.accent)
    .foregroundStyle(palette.primaryText)
    .background(palette.contentBackground)
    .coordinateSpace(name: "classic-file-area")
    .simultaneousGesture(classicMarqueeGesture)
    .onPreferenceChange(MarqueeItemFramePreferenceKey.self) { classicItemFrames = $0 }
    .overlay(alignment: .topLeading) {
      if let rectangle = classicMarqueeRectangle {
        MarqueeRectangleView(rectangle: rectangle)
      }
    }
    .accessibilityIdentifier("file-table")
    .onChange(of: sortOrder) { _, newOrder in
      guard let comparator = newOrder.first else { return }
      applySort(comparator)
    }
  }

  private var tableSelection: Binding<Set<URL>> {
    Binding(
      get: { Set(model.selection.selectedIDs) },
      set: { model.replaceSelection(with: $0) }
    )
  }

  @ViewBuilder
  private func selectionMenu(_ selection: Set<URL>) -> some View {
    if selection.isEmpty {
      directoryMenu
    } else {
      Button("Open With…") {
        select(selection)
        openWithItem = model.selectedItem
      }
      .disabled(
        selection.count != 1
          || selection.first.flatMap(item(withID:))?.isDirectory != false
      )

      Divider()

      Button("Copy") {
        select(selection)
        model.copySelection()
      }

      Button("Cut") {
        select(selection)
        model.cutSelection()
      }

      Divider()

      Button("Rename…") {
        select(selection)
        model.requestRename()
      }
      .disabled(selection.count != 1)

      Button("Duplicate") {
        select(selection)
        Task { await model.duplicateSelection() }
      }

      Button("Move to Trash…") {
        select(selection)
        model.requestTrashConfirmation()
      }

      Button("Get Info") {
        select(selection)
        Task { await model.showSelectedFileInfo() }
      }

      Divider()

      Button("Paste") {
        Task { await model.paste() }
      }
      .disabled(!model.canPaste)
    }
  }

  @ViewBuilder
  private var directoryMenu: some View {
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

    Button("List View") {
      model.viewMode = .list
    }
    .disabled(model.viewMode == .list)
    Button("Large Icons") {
      model.viewMode = .largeIcons
    }
    .disabled(model.viewMode == .largeIcons)
  }

  private func select(_ selection: Set<URL>) {
    let ordered = model.items.map(\.id).filter(selection.contains)
    for (index, id) in ordered.enumerated() {
      model.selectItem(id, modifier: index == 0 ? .plain : .command)
    }
  }

  private func item(withID id: URL) -> FileItem? {
    model.items.first { $0.id == id.standardizedFileURL }
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

  private func isVisibleItem(_ url: URL) -> Bool {
    model.items.contains { $0.id == url.standardizedFileURL }
  }

  private func applySort(_ comparator: KeyPathComparator<FileItem>) {
    let column: BrowserSortColumn
    if comparator.keyPath == \FileItem.size {
      column = .size
    } else if comparator.keyPath == \FileItem.modificationDate {
      column = .modified
    } else {
      column = .name
    }

    let direction: BrowserSortDirection =
      comparator.order == .forward ? .ascending : .descending
    if model.sortColumn != column {
      model.sort(by: column)
    }
    if model.sortDirection != direction {
      model.sort(by: column)
    }
  }

  private func activate(_ item: FileItem) {
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

  private func handleDoubleClick(_ item: FileItem) {
    switch FileItemInteraction.doubleClickAction(
      isDirectory: item.isDirectory,
      isPackage: item.isPackage
    ) {
    case .open:
      activate(item)
    case .rename:
      model.selectItem(item.id)
      model.requestRename()
    }
  }

  private func handleSlowRenameClick(_ item: FileItem) {
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

  private var classicMarqueeRectangle: CGRect? {
    guard let origin = classicMarqueeOrigin, let current = classicMarqueeCurrent else {
      return nil
    }
    return MarqueeSelection.rectangle(from: origin, to: current)
  }

  private var classicMarqueeGesture: some Gesture {
    DragGesture(minimumDistance: 4, coordinateSpace: .named("classic-file-area"))
      .onChanged { value in
        if classicMarqueeOrigin == nil && !classicMarqueeBlocked {
          let startsOnRow = classicItemFrames.values.contains {
            value.startLocation.y >= $0.minY && value.startLocation.y <= $0.maxY
          }
          if startsOnRow {
            classicMarqueeBlocked = true
            return
          }
          classicMarqueeOrigin = value.startLocation
          classicMarqueeBaseline = model.selection.selectedIDs
          if case .command = currentFileSelectionModifier() {
            classicMarqueeToggles = true
          } else {
            classicMarqueeToggles = false
          }
          model.requestFileInteractionFocus()
        }
        guard classicMarqueeOrigin != nil, !classicMarqueeBlocked else { return }
        classicMarqueeCurrent = value.location
        applyClassicMarqueeSelection()
      }
      .onEnded { _ in
        classicMarqueeOrigin = nil
        classicMarqueeCurrent = nil
        classicMarqueeBaseline = []
        classicMarqueeBlocked = false
      }
  }

  private func applyClassicMarqueeSelection() {
    guard let rectangle = classicMarqueeRectangle else { return }
    let hits = MarqueeSelection.intersectingIDs(
      visibleIDs: model.items.map(\.id),
      frames: classicItemFrames,
      rectangle: rectangle
    )
    let resolved = MarqueeSelection.resolvedIDs(
      baseline: classicMarqueeBaseline,
      hits: hits,
      togglesBaseline: classicMarqueeToggles,
      visibleIDs: model.items.map(\.id)
    )
    model.replaceSelection(with: Set(resolved))
  }
}

private struct FlatFileListView: View {
  @ObservedObject var model: FileBrowserModel
  @Binding var openWithItem: FileItem?
  @Binding var isCreatingFile: Bool
  @Binding var isCreatingFolder: Bool
  @State private var dropTargetID: URL?
  @State private var slowRenameTracker = SlowRenameClickTracker<URL>(
    minimumDelay: NSEvent.doubleClickInterval,
    maximumDelay: 1.5
  )
  @State private var itemFrames: [URL: CGRect] = [:]
  @State private var marqueeOrigin: CGPoint?
  @State private var marqueeCurrent: CGPoint?
  @State private var marqueeBaseline: [URL] = []
  @State private var marqueeToggles = false
  @Environment(\.explorerPalette) private var palette
  @EnvironmentObject private var terminalController: TerminalLauncherController

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        sortHeader("Name", column: .name)
          .frame(maxWidth: .infinity, alignment: .leading)
        sortHeader("Size", column: .size)
          .frame(width: 120, alignment: .leading)
        sortHeader("Modified", column: .modified)
          .frame(width: 190, alignment: .leading)
      }
      .padding(.horizontal, 10)
      .frame(height: 29)
      .background(palette.inputBackground)
      .overlay(alignment: .bottom) {
        Rectangle().fill(palette.border).frame(height: palette.borderWidth)
      }

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

              LazyVStack(spacing: 0) {
                ForEach(model.items) { item in
                  row(item).id(item.id)
                }
              }
              .padding(.vertical, 4)
              .frame(maxWidth: .infinity, alignment: .topLeading)

              if let rectangle = marqueeRectangle {
                MarqueeRectangleView(rectangle: rectangle)
              }
            }
            .coordinateSpace(name: "flat-file-area")
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
        .contentShape(Rectangle())
        .contextMenu { directoryMenu }
        .dropDestination(for: URL.self) { urls, _ in
          receive(urls, into: model.currentURL)
          return true
        }
      }
    }
    .foregroundStyle(palette.primaryText)
    .background(palette.contentBackground)
    .accessibilityIdentifier("file-table")
  }

  private func sortHeader(_ title: String, column: BrowserSortColumn) -> some View {
    Button {
      model.sort(by: column)
    } label: {
      HStack(spacing: 5) {
        Text(title.uppercased())
          .font(.system(size: 11.5, weight: .bold, design: .monospaced))
        if model.sortColumn == column {
          Image(systemName: model.sortDirection == .ascending ? "chevron.up" : "chevron.down")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(palette.accent)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func row(_ item: FileItem) -> some View {
    let isSelected = model.selection.selectedIDs.contains(item.id)
    let isPrimary = model.selection.primaryID == item.id
    let isDropTarget = dropTargetID == item.id
    return HStack(spacing: 0) {
      HStack(spacing: 8) {
        ExplorerItemIcon(item: item, size: 18)
        HighlightedFileName(name: item.displayName, query: model.searchText)
          .lineLimit(1)
      }
      .contentShape(Rectangle())
      .simultaneousGesture(
        TapGesture(count: 1).onEnded {
          handleSlowRenameClick(item)
        }
      )
      .frame(maxWidth: .infinity, alignment: .leading)

      Group {
        if let size = item.size, !item.isDirectory {
          Text(size, format: .byteCount(style: .file))
        } else {
          Text("—")
        }
      }
      .frame(width: 120, alignment: .leading)

      Group {
        if let date = item.modificationDate {
          Text(date, format: .dateTime.year().month().day().hour().minute())
        } else {
          Text("—")
        }
      }
      .frame(width: 190, alignment: .leading)
    }
    .font(
      .system(
        size: 12.5,
        weight: palette.isRetro ? .bold : .regular,
        design: .monospaced
      )
    )
    .foregroundStyle(isSelected ? palette.primaryText : palette.secondaryText)
    .padding(.horizontal, 10)
    .frame(height: 29)
    .reportsMarqueeFrame(for: item.id, coordinateSpace: "flat-file-area")
    .background(isSelected ? palette.selectionBackground : Color.clear)
    .overlay(alignment: .leading) {
      if isSelected {
        Rectangle().fill(palette.accent).frame(width: isPrimary ? (palette.isRetro ? 5 : 4) : 2)
      }
    }
    .overlay {
      if isDropTarget {
        Rectangle()
          .fill(palette.accent.opacity(0.16))
          .overlay {
            Rectangle().stroke(palette.accent, lineWidth: max(2, palette.borderWidth))
          }
          .allowsHitTesting(false)
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
        handleDoubleClick(item)
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
        openWithItem = item
      }
      .disabled(item.isDirectory)
      Divider()
      Button("Copy") {
        prepareContextSelection(item)
        model.copySelection()
      }
      Button("Cut") {
        prepareContextSelection(item)
        model.cutSelection()
      }
      Divider()
      Button("Rename…") {
        prepareContextSelection(item)
        model.requestRename()
      }
      .disabled(model.selection.selectedIDs.contains(item.id) && model.selectedItems.count != 1)
      Button("Duplicate") {
        prepareContextSelection(item)
        Task { await model.duplicateSelection() }
      }
      Button("Move to Trash…") {
        prepareContextSelection(item)
        model.requestTrashConfirmation()
      }
      Button("Get Info") {
        prepareContextSelection(item)
        Task { await model.showSelectedFileInfo() }
      }
      Divider()
      Button("Paste") { Task { await model.paste() } }
        .disabled(!model.canPaste)
    }
  }

  @ViewBuilder
  private var directoryMenu: some View {
    Button("New Folder…") { isCreatingFolder = true }
    Button("New File…") { isCreatingFile = true }
    Divider()
    Button("Paste") { Task { await model.paste() } }
      .disabled(!model.canPaste)
    Button("Clipboard History…") { model.showClipboardHistory() }
    Button(terminalController.actionTitle) {
      terminalController.open(directory: model.currentURL, model: model)
    }
    Divider()
    Button("Refresh") { Task { await model.refreshCurrentDirectory() } }
    Button("Save Current Folder as Shortcut") {
      Task { await model.saveCurrentFolderShortcut() }
    }
    Button(model.showsHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files") {
      Task { await model.toggleHiddenFiles() }
    }
    Divider()
    Button("List View") { model.viewMode = .list }.disabled(true)
    Button("Large Icons") { model.viewMode = .largeIcons }
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

  private func prepareContextSelection(_ item: FileItem) {
    if !model.selection.selectedIDs.contains(item.id) {
      model.selectItem(item.id)
    }
  }

  private func activate(_ item: FileItem) {
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

  private func handleDoubleClick(_ item: FileItem) {
    switch FileItemInteraction.doubleClickAction(
      isDirectory: item.isDirectory,
      isPackage: item.isPackage
    ) {
    case .open:
      activate(item)
    case .rename:
      model.selectItem(item.id)
      model.requestRename()
    }
  }

  private func handleSlowRenameClick(_ item: FileItem) {
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

  private var marqueeRectangle: CGRect? {
    guard let origin = marqueeOrigin, let current = marqueeCurrent else { return nil }
    return MarqueeSelection.rectangle(from: origin, to: current)
  }

  private var marqueeGesture: some Gesture {
    DragGesture(minimumDistance: 4, coordinateSpace: .named("flat-file-area"))
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
