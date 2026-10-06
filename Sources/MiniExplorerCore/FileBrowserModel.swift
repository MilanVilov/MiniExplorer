import Combine
import Foundation

public struct BrowserAlert: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let title: String
  public let message: String

  public init(id: UUID = UUID(), title: String, message: String) {
    self.id = id
    self.title = title
    self.message = message
  }
}

@MainActor
public final class FileBrowserModel: ObservableObject {
  @Published public private(set) var currentURL: URL
  @Published public var addressText: String
  @Published public private(set) var addressError: String?
  @Published public private(set) var items: [FileItem] = []
  @Published public var searchText = "" {
    didSet { applyItemPresentation() }
  }
  @Published public private(set) var sortColumn: BrowserSortColumn = .name
  @Published public private(set) var sortDirection: BrowserSortDirection = .ascending
  @Published public private(set) var searchFocusRequest = 0
  @Published public private(set) var fileInteractionFocusRequest = 0
  @Published public private(set) var searchActivationRequest = 0
  @Published public private(set) var primaryItemActivationRequest = 0
  @Published public private(set) var selection = FileSelectionState()
  @Published public var selectedItemID: URL? {
    didSet {
      guard !isSynchronizingSelection else { return }
      if let selectedItemID {
        selection.select(
          selectedItemID,
          modifier: .plain,
          visibleIDs: items.map(\.id)
        )
      } else {
        selection.clear()
      }
    }
  }
  @Published public private(set) var clipboard: ClipboardPayload?
  @Published public private(set) var clipboardHistory: [ClipboardHistoryEntry] = []
  @Published public var isClipboardHistoryPresented = false
  @Published public private(set) var showsHiddenFiles = false
  @Published public var isRenamePresented = false
  @Published public var isTrashConfirmationPresented = false
  @Published public var isFileInfoPresented = false
  @Published public private(set) var fileInfoItems: [FileInfo] = []
  @Published public private(set) var volumes: [FileItem] = []
  @Published public private(set) var shortcuts: [FolderShortcut] = []
  @Published public private(set) var isLoading = false
  @Published public var viewMode: BrowserViewMode = .list
  @Published public var isPreviewVisible = false
  @Published public private(set) var previewCloseRequest = 0
  @Published public private(set) var draggedItemURLs: [URL] = []
  @Published public var alert: BrowserAlert?

  public let homeDirectory: URL

  private let service: any FileSystemServing
  private let shortcutStore: any ShortcutStoring
  private let systemClipboard: (any SystemClipboardServing)?
  private var currentVolumeRoot: URL?
  private var allItems: [FileItem] = []
  private var backHistory: [URL] = []
  private var isSynchronizingSelection = false
  private var pendingTrashURLs: [URL]?
  private var pendingTrashClosesPreview = false
  private var internalClipboardChangeCount: Int?

  public init(
    service: any FileSystemServing,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    shortcutStore: any ShortcutStoring = UserDefaultsShortcutStore(),
    systemClipboard: (any SystemClipboardServing)? = nil
  ) {
    let normalizedHome = homeDirectory.standardizedFileURL
    self.service = service
    self.shortcutStore = shortcutStore
    self.systemClipboard = systemClipboard
    self.homeDirectory = normalizedHome
    self.currentURL = normalizedHome
    self.addressText = normalizedHome.path
  }

  public func start() async {
    await loadShortcuts()
    await refreshVolumes(showUnmountAlert: false)
    await loadDirectory(homeDirectory, presentsAddressError: false, recordsHistory: false)
  }

  public func navigateFromAddress() async {
    do {
      let url = try PathResolver.resolve(addressText, homeDirectory: homeDirectory)
      await loadDirectory(url, presentsAddressError: true, recordsHistory: true)
    } catch {
      addressError = error.localizedDescription
      alert = nil
    }
  }

  public func navigate(to url: URL) async {
    await loadDirectory(url, presentsAddressError: false, recordsHistory: true)
  }

  public func navigateBack() async {
    guard let destination = backHistory.last else { return }
    if await loadDirectory(destination, presentsAddressError: false, recordsHistory: false) {
      backHistory.removeLast()
    }
  }

  public var canNavigateBack: Bool { !backHistory.isEmpty }

  public func sort(by column: BrowserSortColumn) {
    if sortColumn == column {
      sortDirection = sortDirection == .ascending ? .descending : .ascending
    } else {
      sortColumn = column
      sortDirection = .ascending
    }
    applyItemPresentation()
  }

  public func requestSearchFocus() {
    searchFocusRequest += 1
  }

  public func requestFileInteractionFocus() {
    fileInteractionFocusRequest += 1
  }

  public func handleBackgroundInteraction() {
    clearSelection()
    requestFileInteractionFocus()
  }

  public func selectNextSearchResult() {
    selectSearchResult(offset: 1)
  }

  public func selectPreviousSearchResult() {
    selectSearchResult(offset: -1)
  }

  public func requestSearchResultActivation() {
    guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      primaryItem != nil
    else { return }
    searchActivationRequest += 1
  }

  public func requestPrimaryItemActivation() {
    guard primaryItem != nil else { return }
    primaryItemActivationRequest += 1
  }

  public func selectItem(_ id: URL, modifier: FileSelectionModifier = .plain) {
    selection.select(id, modifier: modifier, visibleIDs: items.map(\.id))
    synchronizeLegacySelection()
  }

  public func selectAllVisibleItems() {
    selection.selectAll(items.map(\.id))
    synchronizeLegacySelection()
  }

  public func replaceSelection(with ids: Set<URL>) {
    let ordered = items.map(\.id).filter { ids.contains($0) }
    selectURLs(ordered)
  }

  public func clearSelection() {
    selection.clear()
    synchronizeLegacySelection()
  }

  public var selectedItems: [FileItem] {
    let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    return selection.selectedIDs.compactMap { itemsByID[$0.standardizedFileURL] }
  }

  public var primaryItem: FileItem? {
    guard let id = selection.primaryID else { return nil }
    return items.first { $0.id == id.standardizedFileURL }
  }

  @discardableResult
  private func loadDirectory(
    _ url: URL,
    presentsAddressError: Bool,
    recordsHistory: Bool
  ) async -> Bool {
    let normalizedURL = url.standardizedFileURL
    isLoading = true
    defer { isLoading = false }
    do {
      let newItems = try await service.list(
        normalizedURL,
        includesHiddenItems: showsHiddenFiles
      )
      let previousURL = currentURL
      if recordsHistory, normalizedURL != previousURL.standardizedFileURL {
        backHistory.append(previousURL.standardizedFileURL)
      }
      currentURL = normalizedURL
      addressText = normalizedURL.path
      searchText = ""
      allItems = newItems
      applyItemPresentation()
      selectedItemID = nil
      isPreviewVisible = false
      currentVolumeRoot = matchingVolume(for: normalizedURL)
      addressError = nil
      alert = nil
      return true
    } catch {
      if presentsAddressError {
        addressError = error.localizedDescription
        alert = nil
      } else {
        showError(error, title: "Cannot Open Folder")
      }
      return false
    }
  }

  public func refreshCurrentDirectory() async {
    do {
      allItems = try await service.list(currentURL, includesHiddenItems: showsHiddenFiles)
      applyItemPresentation()
      selectedItemID = nil
    } catch {
      showError(error, title: "Cannot Refresh Folder")
    }
  }

  public func sidebarChildren(of directory: URL) async -> [FileItem] {
    do {
      return try await service.list(
        directory,
        includesHiddenItems: showsHiddenFiles
      ).filter(\.canExpandInSidebar)
    } catch {
      showError(error, title: "Cannot Expand Folder")
      return []
    }
  }

  public func copySelection() {
    setClipboard(operation: .copy)
  }

  public func cutSelection() {
    setClipboard(operation: .move)
  }

  public func paste() async {
    if let snapshot = externalClipboardSnapshot {
      await pasteExternal(snapshot.content)
      return
    }
    await pasteInternal()
  }

  private func pasteInternal() async {
    guard let clipboard else { return }
    isLoading = true
    defer { isLoading = false }
    var succeeded: [URL] = []
    var failures: [(URL, Error)] = []

    for sourceURL in clipboard.sourceURLs {
      do {
      switch clipboard.operation {
      case .copy:
          try await service.copy(sourceURL, into: currentURL)
      case .move:
          try await service.move(sourceURL, into: currentURL)
        }
        succeeded.append(sourceURL)
      } catch {
        failures.append((sourceURL, error))
      }
    }

    do {
      allItems = try await service.list(currentURL, includesHiddenItems: showsHiddenFiles)
      applyItemPresentation()
      clearSelection()
    } catch {
      failures.append((currentURL, error))
    }

    if clipboard.operation == .move {
      let succeededIDs = Set(succeeded.map(\.standardizedFileURL))
      let remaining = clipboard.sourceURLs.filter {
        !succeededIDs.contains($0.standardizedFileURL)
      }
      self.clipboard = remaining.isEmpty
        ? nil
        : ClipboardPayload(sourceURLs: remaining, operation: .move)
      removeMovedURLsFromHistory(succeededIDs)
    }

    if let failure = failures.first {
      alert = BrowserAlert(
        title: "Paste Failed",
        message: failures.count == 1
          ? failure.1.localizedDescription
          : "\(failures.count) items could not be pasted. \(failure.0.lastPathComponent): \(failure.1.localizedDescription)"
      )
    } else {
      alert = nil
    }
  }

  @discardableResult
  public func createFile(named name: String) async -> Bool {
    isLoading = true
    defer { isLoading = false }
    do {
      let createdURL = try await service.createFile(named: name, in: currentURL)
      allItems = try await service.list(currentURL, includesHiddenItems: showsHiddenFiles)
      applyItemPresentation()
      selectedItemID = createdURL.standardizedFileURL
      isPreviewVisible = false
      alert = nil
      return true
    } catch {
      showError(error, title: "Cannot Create File")
      return false
    }
  }

  @discardableResult
  public func createFolder(named name: String) async -> Bool {
    isLoading = true
    defer { isLoading = false }
    do {
      let createdURL = try await service.createFolder(named: name, in: currentURL)
      allItems = try await service.list(currentURL, includesHiddenItems: showsHiddenFiles)
      applyItemPresentation()
      selectedItemID = createdURL.standardizedFileURL
      isPreviewVisible = false
      alert = nil
      return true
    } catch {
      showError(error, title: "Cannot Create Folder")
      return false
    }
  }

  @discardableResult
  public func renamePrimaryItem(to newName: String) async -> Bool {
    guard selectedItems.count == 1, let source = primaryItem?.url else { return false }
    isLoading = true
    defer { isLoading = false }
    do {
      let renamedURL = try await service.rename(source, to: newName)
      allItems = try await service.list(currentURL, includesHiddenItems: showsHiddenFiles)
      applyItemPresentation()
      selectItem(renamedURL)
      isRenamePresented = false
      alert = nil
      return true
    } catch {
      showError(error, title: "Cannot Rename Item")
      return false
    }
  }

  public func duplicateSelection() async {
    let sources = selectedItems.map(\.url)
    guard !sources.isEmpty else { return }
    isLoading = true
    defer { isLoading = false }
    var created: [URL] = []
    var failures: [(URL, Error)] = []
    for source in sources {
      do {
        created.append(try await service.duplicate(source))
      } catch {
        failures.append((source, error))
      }
    }
    await finishBatch(createdSelection: created, failedSources: failures, title: "Duplicate Failed")
  }

  public func trashSelection() async {
    let sources = pendingTrashURLs ?? selectedItems.map(\.url)
    let closesPreviewOnSuccess = pendingTrashClosesPreview
    guard !sources.isEmpty else { return }
    isLoading = true
    defer { isLoading = false }
    var failures: [(URL, Error)] = []
    for source in sources {
      do {
        _ = try await service.trash(source)
      } catch {
        failures.append((source, error))
      }
    }
    isTrashConfirmationPresented = false
    pendingTrashURLs = nil
    pendingTrashClosesPreview = false
    await finishBatch(createdSelection: [], failedSources: failures, title: "Move to Trash Failed")
    if failures.isEmpty && closesPreviewOnSuccess {
      isPreviewVisible = false
    }
  }

  public func toggleHiddenFiles() async {
    showsHiddenFiles.toggle()
    do {
      allItems = try await service.list(currentURL, includesHiddenItems: showsHiddenFiles)
      applyItemPresentation()
      alert = nil
    } catch {
      showsHiddenFiles.toggle()
      showError(error, title: "Cannot Change Hidden Files")
    }
  }

  public func showSelectedFileInfo() async {
    let sources = selectedItems.map(\.url)
    guard !sources.isEmpty else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      var loaded: [FileInfo] = []
      for source in sources {
        loaded.append(try await service.info(for: source))
      }
      fileInfoItems = loaded
      isFileInfoPresented = true
      alert = nil
    } catch {
      showError(error, title: "Cannot Get Info")
    }
  }

  public func requestRename() {
    guard canRename else { return }
    isRenamePresented = true
  }

  public func requestTrashConfirmation() {
    guard canOperateOnSelection else { return }
    pendingTrashURLs = selectedItems.map(\.url)
    pendingTrashClosesPreview = false
    isTrashConfirmationPresented = true
  }

  public func requestPreviewTrashConfirmation() {
    guard let previewItem else { return }
    pendingTrashURLs = [previewItem.url]
    pendingTrashClosesPreview = true
    isTrashConfirmationPresented = true
  }

  public var trashConfirmationItemCount: Int {
    pendingTrashURLs?.count ?? selectedItems.count
  }

  public var trashConfirmationDisplayName: String? {
    let sources = pendingTrashURLs ?? selectedItems.map(\.url)
    guard sources.count == 1 else { return nil }
    let source = sources[0].standardizedFileURL
    return items.first(where: { $0.id == source })?.displayName ?? source.lastPathComponent
  }

  public func togglePreview() {
    if isPreviewVisible {
      closePreview()
      return
    }

    if previewItem == nil {
      selectedItemID = items.first(where: { previewKind(for: $0) != nil })?.id
    }
    guard previewItem != nil else {
      alert = BrowserAlert(
        title: "Nothing to Preview",
        message: "This folder does not contain a supported previewable file."
      )
      return
    }
    isPreviewVisible = true
  }

  @discardableResult
  public func previewImageIfSupported(_ item: FileItem) -> Bool {
    guard item.isImage else { return false }
    return previewFileIfSupported(item)
  }

  @discardableResult
  public func previewFileIfSupported(_ item: FileItem) -> Bool {
    guard previewKind(for: item) != nil else { return false }
    selectedItemID = item.id
    isPreviewVisible = true
    alert = nil
    return true
  }

  @discardableResult
  public func addShortcut(path: String) async -> Bool {
    do {
      let resolvedURL = try PathResolver.resolve(path, homeDirectory: homeDirectory)
      let url = URL(fileURLWithPath: resolvedURL.path, isDirectory: true).standardizedFileURL
      _ = try await service.list(url, includesHiddenItems: showsHiddenFiles)
      await saveShortcut(url)
      return true
    } catch {
      showError(error, title: "Cannot Save Shortcut")
      return false
    }
  }

  public func saveCurrentFolderShortcut() async {
    await saveShortcut(currentURL)
  }

  public func removeShortcut(_ url: URL) async {
    let id = url.standardizedFileURL
    shortcuts.removeAll { $0.id == id }
    await persistShortcuts()
  }

  public var previewItem: FileItem? {
    guard let selectedItem, previewKind(for: selectedItem) != nil else { return nil }
    return selectedItem
  }

  public var previewKind: PreviewContentKind? {
    guard let previewItem else { return nil }
    return previewKind(for: previewItem)
  }

  public func closePreview() {
    guard isPreviewVisible else { return }
    isPreviewVisible = false
    previewCloseRequest += 1
    requestFileInteractionFocus()
  }

  @discardableResult
  public func capturePreviewedImage(operation: ClipboardOperation) -> Bool {
    guard previewKind == .image, let previewItem else { return false }
    return setClipboard(
      ClipboardPayload(sourceURLs: [previewItem.url], operation: operation)
    )
  }

  public func selectNextPreviewImage() {
    selectPreviewImage(offset: 1)
  }

  public func selectPreviousPreviewImage() {
    selectPreviewImage(offset: -1)
  }

  public func receiveDrop(
    _ urls: [URL],
    into destination: URL,
    internalSources: [URL]
  ) async {
    guard !urls.isEmpty else { return }
    isLoading = true
    defer { isLoading = false }

    let internalIDs = Set(internalSources.map(\.standardizedFileURL))
    var failures: [(URL, Error)] = []
    for url in urls {
      do {
        let isInternal = internalIDs.contains(url.standardizedFileURL)
        if isInternal, try await service.isSameVolume(url, destination) {
          try await service.move(url, into: destination)
        } else {
          try await service.copy(url, into: destination)
        }
      } catch {
        failures.append((url, error))
      }
    }

    do {
      allItems = try await service.list(currentURL, includesHiddenItems: showsHiddenFiles)
      applyItemPresentation()
      selectURLs(failures.map(\.0))
    } catch {
      failures.append((currentURL, error))
    }

    if let firstFailure = failures.first {
      alert = BrowserAlert(
        title: "Drop Failed",
        message: failures.count == 1
          ? firstFailure.1.localizedDescription
          : "\(failures.count) items failed. \(firstFailure.0.lastPathComponent): \(firstFailure.1.localizedDescription)"
      )
    } else {
      alert = nil
    }
  }

  public func receiveDrop(
    _ urls: [URL],
    into destination: URL,
    internalSource: URL?
  ) async {
    await receiveDrop(
      urls,
      into: destination,
      internalSources: internalSource.map { [$0] } ?? []
    )
  }

  public func beginDragging(_ url: URL) {
    let id = url.standardizedFileURL
    if selection.selectedIDs.contains(id) {
      draggedItemURLs = selectedItems.map(\.url)
    } else {
      selectItem(id)
      draggedItemURLs = [id]
    }
  }

  public func endDragging() {
    draggedItemURLs = []
  }

  public var draggedItemURL: URL? { draggedItemURLs.first }

  public func refreshVolumes() async {
    await refreshVolumes(showUnmountAlert: true)
  }

  public var selectedItem: FileItem? {
    primaryItem
  }

  public var canCopyOrCut: Bool { selectedItem != nil }
  public var canPaste: Bool {
    if externalClipboardSnapshot != nil { return true }
    guard let systemClipboard else { return clipboard != nil }
    return systemClipboard.changeCount == internalClipboardChangeCount && clipboard != nil
  }
  public var canRename: Bool { selectedItems.count == 1 }
  public var canOperateOnSelection: Bool { !selectedItems.isEmpty }

  public func activateClipboardHistoryEntry(_ id: UUID) {
    pruneClipboardHistory()
    clipboard = clipboardHistory.first(where: { $0.id == id })?.payload
    if let clipboard {
      internalClipboardChangeCount = systemClipboard?.writeFileURLs(clipboard.sourceURLs)
    }
  }

  public func clearClipboardHistory() {
    clipboardHistory.removeAll()
  }

  public func showClipboardHistory() {
    pruneClipboardHistory()
    isClipboardHistoryPresented = true
  }

  public func pruneClipboardHistory() {
    clipboardHistory = clipboardHistory.compactMap { entry in
      let existingURLs = entry.payload.sourceURLs.filter {
        FileManager.default.fileExists(atPath: $0.path)
      }
      guard !existingURLs.isEmpty else { return nil }
      guard existingURLs != entry.payload.sourceURLs else { return entry }
      return ClipboardHistoryEntry(
        id: entry.id,
        payload: ClipboardPayload(
          sourceURLs: existingURLs,
          operation: entry.payload.operation
        ),
        capturedAt: entry.capturedAt
      )
    }
  }

  private func refreshVolumes(showUnmountAlert: Bool) async {
    let previousRoot = currentVolumeRoot
    do {
      let newVolumes = try await service.mountedVolumes()
      volumes = newVolumes

      if let previousRoot,
        !newVolumes.contains(where: { $0.id == previousRoot.standardizedFileURL })
      {
        _ = await loadDirectory(
          homeDirectory,
          presentsAddressError: false,
          recordsHistory: false
        )
        backHistory.removeAll()
        if showUnmountAlert {
          alert = BrowserAlert(
            title: "Volume Unmounted",
            message:
              "The current volume is no longer available. MiniExplorer returned to your home folder."
          )
        }
      } else {
        currentVolumeRoot = matchingVolume(for: currentURL)
      }
    } catch {
      showError(error, title: "Cannot Load Volumes")
    }
  }

  private func setClipboard(operation: ClipboardOperation) {
    let sourceURLs = selectedItems.map(\.url)
    guard !sourceURLs.isEmpty else { return }
    let payload = ClipboardPayload(sourceURLs: sourceURLs, operation: operation)
    _ = setClipboard(payload)
  }

  @discardableResult
  private func setClipboard(_ payload: ClipboardPayload) -> Bool {
    clipboard = payload
    internalClipboardChangeCount = systemClipboard?.writeFileURLs(payload.sourceURLs)
    if clipboardHistory.first?.payload != payload {
      clipboardHistory.insert(ClipboardHistoryEntry(payload: payload), at: 0)
      if clipboardHistory.count > 20 {
        clipboardHistory.removeLast(clipboardHistory.count - 20)
      }
      return true
    }
    return false
  }

  private var externalClipboardSnapshot: SystemClipboardSnapshot? {
    guard let systemClipboard,
      systemClipboard.changeCount != internalClipboardChangeCount
    else { return nil }
    return systemClipboard.readSnapshot()
  }

  private func pasteExternal(_ content: SystemClipboardContent) async {
    isLoading = true
    defer { isLoading = false }

    switch content {
    case .files(let sourceURLs):
      var created: [URL] = []
      var failures: [(URL, Error)] = []
      for sourceURL in sourceURLs {
        do {
          try await service.copy(sourceURL, into: currentURL)
          created.append(
            currentURL.appendingPathComponent(sourceURL.lastPathComponent).standardizedFileURL
          )
        } catch {
          failures.append((sourceURL, error))
        }
      }
      await finishBatch(
        createdSelection: created,
        failedSources: failures,
        title: "Paste Failed"
      )

    case .text(let text):
      await createExternalClipboardFile(
        named: "Clipboard.txt",
        contents: Data(text.utf8)
      )

    case .binary(let data, let preferredFilename):
      await createExternalClipboardFile(named: preferredFilename, contents: data)
    }
  }

  private func createExternalClipboardFile(named name: String, contents: Data) async {
    do {
      let created = try await service.createUniqueFile(
        named: name,
        contents: contents,
        in: currentURL
      )
      await finishBatch(createdSelection: [created], failedSources: [], title: "Paste Failed")
    } catch {
      showError(error, title: "Paste Failed")
    }
  }

  private func removeMovedURLsFromHistory(_ movedIDs: Set<URL>) {
    guard !movedIDs.isEmpty else { return }
    clipboardHistory = clipboardHistory.compactMap { entry in
      let remaining = entry.payload.sourceURLs.filter {
        !movedIDs.contains($0.standardizedFileURL)
      }
      guard !remaining.isEmpty else { return nil }
      return ClipboardHistoryEntry(
        id: entry.id,
        payload: ClipboardPayload(
          sourceURLs: remaining,
          operation: entry.payload.operation
        ),
        capturedAt: entry.capturedAt
      )
    }
  }

  private func finishBatch(
    createdSelection: [URL],
    failedSources: [(URL, Error)],
    title: String
  ) async {
    do {
      allItems = try await service.list(currentURL, includesHiddenItems: showsHiddenFiles)
      applyItemPresentation()
      selectURLs(failedSources.map(\.0) + createdSelection)
    } catch {
      showError(error, title: title)
      return
    }

    if let firstFailure = failedSources.first {
      alert = BrowserAlert(
        title: title,
        message: failedSources.count == 1
          ? firstFailure.1.localizedDescription
          : "\(failedSources.count) items failed. \(firstFailure.0.lastPathComponent): \(firstFailure.1.localizedDescription)"
      )
    } else {
      alert = nil
    }
  }

  private func selectURLs(_ urls: [URL]) {
    selection.clear()
    for (index, url) in urls.enumerated() {
      selection.select(
        url,
        modifier: index == 0 ? .plain : .command,
        visibleIDs: items.map(\.id)
      )
    }
    synchronizeLegacySelection()
  }

  private func previewKind(for item: FileItem) -> PreviewContentKind? {
    guard !item.isDirectory, !item.isPackage else { return nil }
    if item.isImage { return .image }
    return PreviewContentKind.forFile(named: item.displayName)
  }

  private func applyItemPresentation() {
    let query = searchText
    let filteredItems: [FileItem]
    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      filteredItems = allItems
    } else {
      filteredItems = allItems.filter {
        $0.displayName.localizedCaseInsensitiveContains(query)
      }
    }

    items = filteredItems.sorted(by: itemComesBefore)
    let hadSelection = !selection.selectedIDs.isEmpty
    selection.normalize(visibleIDs: items.map(\.id))
    synchronizeLegacySelection()
    if hadSelection && selection.selectedIDs.isEmpty {
      isPreviewVisible = false
    }
  }

  private func synchronizeLegacySelection() {
    isSynchronizingSelection = true
    selectedItemID = selection.primaryID
    isSynchronizingSelection = false
  }

  private func itemComesBefore(_ lhs: FileItem, _ rhs: FileItem) -> Bool {
    let lhsIsFolder = lhs.isDirectory && !lhs.isPackage
    let rhsIsFolder = rhs.isDirectory && !rhs.isPackage
    if lhsIsFolder != rhsIsFolder {
      return lhsIsFolder
    }

    let comparison: ComparisonResult
    switch sortColumn {
    case .name:
      comparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
    case .size:
      comparison = compare(lhs.size ?? 0, rhs.size ?? 0)
    case .modified:
      comparison = compare(
        lhs.modificationDate ?? .distantPast,
        rhs.modificationDate ?? .distantPast
      )
    }

    let resolvedComparison =
      comparison == .orderedSame
      ? lhs.displayName.localizedStandardCompare(rhs.displayName)
      : comparison
    if resolvedComparison == .orderedSame { return false }
    return sortDirection == .ascending
      ? resolvedComparison == .orderedAscending
      : resolvedComparison == .orderedDescending
  }

  private func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
    if lhs < rhs { return .orderedAscending }
    if lhs > rhs { return .orderedDescending }
    return .orderedSame
  }

  private func loadShortcuts() async {
    var seen = Set<URL>()
    shortcuts = await shortcutStore.loadPaths().compactMap { path in
      guard path.hasPrefix("/") else { return nil }
      let shortcut = FolderShortcut(url: URL(fileURLWithPath: path, isDirectory: true))
      guard seen.insert(shortcut.id).inserted else { return nil }
      return shortcut
    }
  }

  private func saveShortcut(_ url: URL) async {
    let shortcut = FolderShortcut(url: url)
    guard !shortcuts.contains(where: { $0.id == shortcut.id }) else { return }
    shortcuts.append(shortcut)
    await persistShortcuts()
    alert = nil
  }

  private func persistShortcuts() async {
    await shortcutStore.savePaths(shortcuts.map(\.url.path))
  }

  private func selectPreviewImage(offset: Int) {
    let images = items.filter(\.isImage)
    guard !images.isEmpty else { return }
    guard let selectedItemID,
      let currentIndex = images.firstIndex(where: { $0.id == selectedItemID })
    else {
      self.selectedItemID = offset >= 0 ? images.first?.id : images.last?.id
      return
    }
    let nextIndex = (currentIndex + offset + images.count) % images.count
    self.selectedItemID = images[nextIndex].id
  }

  private func selectSearchResult(offset: Int) {
    guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !items.isEmpty
    else { return }
    guard let primaryID = selection.primaryID,
      let currentIndex = items.firstIndex(where: { $0.id == primaryID })
    else {
      selectItem(offset >= 0 ? items[0].id : items[items.count - 1].id)
      return
    }
    let nextIndex = (currentIndex + offset + items.count) % items.count
    selectItem(items[nextIndex].id)
  }

  private func matchingVolume(for url: URL) -> URL? {
    let path = url.standardizedFileURL.path
    return
      volumes
      .map(\.url)
      .filter { volumeURL in
        let rootPath = volumeURL.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath == "/" ? "/" : rootPath + "/")
      }
      .max { $0.path.count < $1.path.count }?
      .standardizedFileURL
  }

  private func showError(_ error: Error, title: String) {
    alert = BrowserAlert(title: title, message: error.localizedDescription)
  }
}
