import Foundation
import MiniExplorerCore

enum BrowserModelTests {
  @MainActor
  static func runAll() async throws {
    try await run("Browser start loads home and mounted volumes", startLoadsInitialState)
    try await run(
      "Invalid address preserves the current folder", invalidAddressPreservesCurrentFolder)
    try await run(
      "Copy paste preserves clipboard and duplicates the file", copyPastePreservesClipboard)
    try await run("Cut paste clears clipboard and moves the file", cutPasteClearsClipboard)
    try await run("Failed paste preserves clipboard and source", failedPastePreservesClipboard)
    try await run(
      "Sidebar children include only expandable folders", sidebarChildrenFilterNonExpandableItems)
    try await run("Unmounting the current volume returns home", unmountedCurrentVolumeReturnsHome)
    try await run(
      "Preview opens centrally and arrows traverse only images", previewTraversesOnlyImages)
    try await run("Internal drops move while external drops copy", dropUsesExplorerSemantics)
    try await run("Saved shortcuts load when the browser starts", shortcutsLoadOnStart)
    try await run("Shortcut paths expand home and reject duplicates", shortcutPathsAreNormalized)
    try await run("Invalid shortcut paths are not persisted", invalidShortcutIsRejected)
    try await run("Removing a shortcut updates persistent storage", shortcutRemovalPersists)
    try await run(
      "Activating an image opens the built-in preview", imageActivationUsesBuiltInPreview)
    try await run("Activating text opens the built-in preview", textActivationUsesBuiltInPreview)
    try await run("Activating PDF opens the built-in preview", pdfActivationUsesBuiltInPreview)
    try await run("Escape closes every built-in preview", escapeClosesPreview)
    try await run(
      "Image preview capture records copy and move history entries", imagePreviewCaptureRecordsHistory)
    try await run("Back navigation restores the previous folder", backNavigationRestoresFolder)
    try await run("Search filters names and clears on navigation", searchFiltersCurrentFolder)
    try await run("Column sorting toggles direction", columnSortingTogglesDirection)
    try await run("Creating a file refreshes and selects it", createFileRefreshesAndSelects)
    try await run("Creating a folder refreshes and selects it", createFolderRefreshesAndSelects)
    try await run("Browser model exposes ordered multi-selection", modelExposesOrderedSelection)
    try await run("Clipboard captures and pastes multiple selected items", clipboardHandlesMultipleItems)
    try await run("Copy publishes selected files to the macOS clipboard", copyPublishesSystemClipboard)
    try await run("External clipboard text creates a uniquely named file", externalTextClipboardCreatesFile)
    try await run("Newer external clipboard files override stale internal clipboard", externalFilesOverrideInternalClipboard)
    try await run("Clipboard history is newest first and deduplicated", clipboardHistoryIsOrdered)
    try await run("Clipboard history is limited and can be cleared", clipboardHistoryIsBounded)
    try await run("Clipboard history presentation can be requested", clipboardHistoryPresentationCanBeRequested)
    try await run("Rename refreshes and selects the renamed item", renameRefreshesSelection)
    try await run("Duplicate creates and selects copies for every selected item", duplicateSelectionCreatesCopies)
    try await run("Trash removes every selected item through the service", trashSelectionRemovesItems)
    try await run(
      "Preview Trash removes only the previewed item", previewTrashTargetsOnlyPreviewedItem)
    try await run(
      "Failed preview Trash keeps the preview open", failedPreviewTrashKeepsPreviewOpen)
    try await run("Hidden file toggle refreshes the current listing", hiddenToggleRefreshesListing)
    try await run("Get Info loads metadata for every selected item", getInfoLoadsSelectedMetadata)
    try await run("Multi-item internal drop moves selection and refreshes source", multiItemDropRefreshesSource)
    try await run("Search arrows wrap through visible results", searchArrowsWrapResults)
    try await run("Search Enter requests activation of the primary result", searchEnterRequestsActivation)
    try await run("File interaction requests keyboard focus", fileInteractionRequestsKeyboardFocus)
    try await run("Primary item activation requires a selection", primaryActivationRequiresSelection)
    try await run("Background interaction clears the complete selection", backgroundInteractionClearsSelection)
    try await run("Window models keep navigation and preview state independent", windowModelsAreIndependent)
  }

  @MainActor
  private static func windowModelsAreIndependent() async throws {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let otherFolder = home.appendingPathComponent("Other", isDirectory: true)
    let image = item(home.appendingPathComponent("photo.png"), isDirectory: false, isImage: true)
    let listings = [
      home.standardizedFileURL: [image],
      otherFolder.standardizedFileURL: [],
    ]
    let factory = FileBrowserModelFactory {
      FileBrowserModel(
        service: FakeFileSystemService(volumes: [], listings: listings),
        homeDirectory: home
      )
    }
    let firstWindow = factory.makeModel()
    let secondWindow = factory.makeModel()
    await firstWindow.start()
    await secondWindow.start()

    await firstWindow.navigate(to: otherFolder)
    _ = secondWindow.previewFileIfSupported(image)

    try expect(firstWindow !== secondWindow, "Each window must own a distinct browser model")
    try expectEqual(firstWindow.currentURL, otherFolder.standardizedFileURL)
    try expect(!firstWindow.isPreviewVisible, "Preview state leaked into the first window")
    try expectEqual(secondWindow.currentURL, home.standardizedFileURL)
    try expect(secondWindow.isPreviewVisible, "The second window did not retain its preview state")
  }

  @MainActor
  private static func fileInteractionRequestsKeyboardFocus() async throws {
    let root = URL(fileURLWithPath: "/Focus", isDirectory: true)
    let model = FileBrowserModel(
      service: FakeFileSystemService(volumes: [], listings: [:]),
      homeDirectory: root
    )

    try expectEqual(model.fileInteractionFocusRequest, 0)
    model.requestFileInteractionFocus()
    try expectEqual(model.fileInteractionFocusRequest, 1)
    model.requestFileInteractionFocus()
    try expectEqual(model.fileInteractionFocusRequest, 2)
  }

  @MainActor
  private static func backgroundInteractionClearsSelection() async throws {
    let root = URL(fileURLWithPath: "/Background", isDirectory: true)
    let first = item(root.appendingPathComponent("a.txt"), isDirectory: false)
    let second = item(root.appendingPathComponent("b.txt"), isDirectory: false)
    let model = FileBrowserModel(
      service: FakeFileSystemService(
        volumes: [],
        listings: [root.standardizedFileURL: [first, second]]
      ),
      homeDirectory: root
    )
    await model.start()
    model.selectAllVisibleItems()

    model.handleBackgroundInteraction()

    try expect(model.selectedItems.isEmpty, "Expected empty-space interaction to clear every item")
    try expectEqual(model.fileInteractionFocusRequest, 1)
  }

  @MainActor
  private static func primaryActivationRequiresSelection() async throws {
    let root = URL(fileURLWithPath: "/Activation", isDirectory: true)
    let document = item(root.appendingPathComponent("notes.txt"), isDirectory: false)
    let model = FileBrowserModel(
      service: FakeFileSystemService(
        volumes: [],
        listings: [root.standardizedFileURL: [document]]
      ),
      homeDirectory: root
    )
    await model.start()

    model.requestPrimaryItemActivation()
    try expectEqual(model.primaryItemActivationRequest, 0)

    model.selectItem(document.id)
    model.requestPrimaryItemActivation()
    try expectEqual(model.primaryItemActivationRequest, 1)
  }

  @MainActor
  private static func startLoadsInitialState() async throws {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let volume = URL(fileURLWithPath: "/", isDirectory: true)
    let child = item(home.appendingPathComponent("note.txt"), isDirectory: false)
    let service = FakeFileSystemService(
      volumes: [item(volume, name: "Macintosh HD", isDirectory: true)],
      listings: [home.standardizedFileURL: [child]]
    )
    let model = FileBrowserModel(service: service, homeDirectory: home)

    await model.start()

    try expectEqual(model.currentURL, home.standardizedFileURL)
    try expectEqual(model.items, [child])
    try expectEqual(model.volumes.map(\.displayName), ["Macintosh HD"])
  }

  @MainActor
  private static func invalidAddressPreservesCurrentFolder() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let service = LocalFileSystemService(mountedVolumeProvider: { [root] })
    let model = FileBrowserModel(service: service, homeDirectory: root)
    await model.start()
    let originalItems = model.items
    model.addressText = root.appendingPathComponent("Missing").path

    await model.navigateFromAddress()

    try expectEqual(model.currentURL, root.standardizedFileURL)
    try expectEqual(model.items, originalItems)
    try expect(model.addressError != nil, "Invalid navigation must show an inline address error")
    try expect(model.alert == nil, "Invalid address must not show a modal alert")
  }

  @MainActor
  private static func copyPastePreservesClipboard() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.txt")
    let destination = try createDirectory(named: "Destination", in: root)
    try Data("hello".utf8).write(to: source)
    let model = FileBrowserModel(
      service: LocalFileSystemService(mountedVolumeProvider: { [root] }),
      homeDirectory: root
    )
    await model.start()
    model.selectedItemID = source.standardizedFileURL
    model.copySelection()
    await model.navigate(to: destination)

    await model.paste()

    try expect(
      FileManager.default.fileExists(atPath: destination.appendingPathComponent("source.txt").path),
      "Paste did not copy the file")
    try expectEqual(model.clipboard?.operation, .copy)
  }

  @MainActor
  private static func cutPasteClearsClipboard() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.txt")
    let destination = try createDirectory(named: "Destination", in: root)
    try Data("hello".utf8).write(to: source)
    let model = FileBrowserModel(
      service: LocalFileSystemService(mountedVolumeProvider: { [root] }),
      homeDirectory: root
    )
    await model.start()
    model.selectedItemID = source.standardizedFileURL
    model.cutSelection()
    await model.navigate(to: destination)

    await model.paste()

    try expect(!FileManager.default.fileExists(atPath: source.path), "Cut paste left the source")
    try expect(model.clipboard == nil, "Successful cut paste must clear the clipboard")
  }

  @MainActor
  private static func failedPastePreservesClipboard() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.txt")
    let destination = try createDirectory(named: "Destination", in: root)
    try Data("source".utf8).write(to: source)
    try Data("existing".utf8).write(to: destination.appendingPathComponent("source.txt"))
    let model = FileBrowserModel(
      service: LocalFileSystemService(mountedVolumeProvider: { [root] }),
      homeDirectory: root
    )
    await model.start()
    model.selectedItemID = source.standardizedFileURL
    model.cutSelection()
    await model.navigate(to: destination)

    await model.paste()

    try expect(
      FileManager.default.fileExists(atPath: source.path), "Failed paste removed the source")
    try expectEqual(model.clipboard?.operation, .move)
    try expect(model.alert != nil, "Failed paste must show an alert")
  }

  @MainActor
  private static func sidebarChildrenFilterNonExpandableItems() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = try createDirectory(named: "Folder", in: root)
    try createDirectory(named: "Example.app", in: root)
    try Data().write(to: root.appendingPathComponent("note.txt"))
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("Folder Link"),
      withDestinationURL: folder
    )
    let model = FileBrowserModel(
      service: LocalFileSystemService(mountedVolumeProvider: { [root] }),
      homeDirectory: root
    )

    let children = await model.sidebarChildren(of: root)

    try expectEqual(children.map(\.displayName), ["Folder"])
  }

  @MainActor
  private static func unmountedCurrentVolumeReturnsHome() async throws {
    let rootVolume = URL(fileURLWithPath: "/", isDirectory: true)
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let external = URL(fileURLWithPath: "/Volumes/External", isDirectory: true)
    let service = FakeFileSystemService(
      volumes: [
        item(rootVolume, name: "Macintosh HD", isDirectory: true),
        item(external, name: "External", isDirectory: true),
      ],
      listings: [
        home.standardizedFileURL: [],
        external.standardizedFileURL: [],
      ]
    )
    let model = FileBrowserModel(service: service, homeDirectory: home)
    await model.start()
    await model.navigate(to: external)
    await service.setVolumes([item(rootVolume, name: "Macintosh HD", isDirectory: true)])

    await model.refreshVolumes()

    try expectEqual(model.currentURL, home.standardizedFileURL)
    try expect(model.alert != nil, "Unmount fallback must explain what happened")
  }

  @MainActor
  private static func previewTraversesOnlyImages() async throws {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let first = item(home.appendingPathComponent("01.png"), isDirectory: false, isImage: true)
    let text = item(home.appendingPathComponent("notes.txt"), isDirectory: false)
    let second = item(home.appendingPathComponent("02.jpg"), isDirectory: false, isImage: true)
    let service = FakeFileSystemService(
      volumes: [item(URL(fileURLWithPath: "/"), name: "Mac", isDirectory: true)],
      listings: [home.standardizedFileURL: [first, text, second]]
    )
    let model = FileBrowserModel(service: service, homeDirectory: home)
    await model.start()
    model.selectedItemID = first.id

    model.togglePreview()
    model.selectNextPreviewImage()

    try expect(model.isPreviewVisible, "Preview should become visible")
    try expectEqual(model.selectedItemID, second.id)
    try expectEqual(model.previewItem?.id, second.id)

    model.selectNextPreviewImage()
    try expectEqual(model.selectedItemID, first.id)
    model.selectPreviousPreviewImage()
    try expectEqual(model.selectedItemID, second.id)
  }

  @MainActor
  private static func dropUsesExplorerSemantics() async throws {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let destination = home.appendingPathComponent("Destination", isDirectory: true)
    let internalFile = item(home.appendingPathComponent("inside.txt"), isDirectory: false)
    let externalURL = URL(fileURLWithPath: "/tmp/outside.txt")
    let service = FakeFileSystemService(
      volumes: [item(URL(fileURLWithPath: "/"), name: "Mac", isDirectory: true)],
      listings: [home.standardizedFileURL: [internalFile]]
    )
    let model = FileBrowserModel(service: service, homeDirectory: home)
    await model.start()

    await model.receiveDrop([internalFile.url], into: destination, internalSources: [internalFile.url])
    await model.receiveDrop([externalURL], into: destination, internalSources: [])

    let operations = await service.recordedOperations()
    try expectEqual(operations, ["move:inside.txt", "copy:outside.txt"])
  }

  @MainActor
  private static func shortcutsLoadOnStart() async throws {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let pictures = home.appendingPathComponent("Pictures", isDirectory: true)
    let store = MemoryShortcutStore(paths: [pictures.path])
    let service = FakeFileSystemService(
      volumes: [item(URL(fileURLWithPath: "/"), name: "Mac", isDirectory: true)],
      listings: [home.standardizedFileURL: []]
    )
    let model = FileBrowserModel(
      service: service,
      homeDirectory: home,
      shortcutStore: store
    )

    await model.start()

    try expectEqual(model.shortcuts.map(\.url), [pictures.standardizedFileURL])
  }

  @MainActor
  private static func shortcutPathsAreNormalized() async throws {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let pictures = home.appendingPathComponent("Pictures", isDirectory: true)
    let store = MemoryShortcutStore()
    let service = FakeFileSystemService(
      volumes: [],
      listings: [home.standardizedFileURL: [], pictures.standardizedFileURL: []]
    )
    let model = FileBrowserModel(
      service: service,
      homeDirectory: home,
      shortcutStore: store
    )
    await model.start()

    await model.addShortcut(path: "~/Pictures")
    await model.addShortcut(path: pictures.path)

    try expectEqual(model.shortcuts.map(\.url), [pictures.standardizedFileURL])
    try expectEqual(await store.savedPaths(), [pictures.path])
  }

  @MainActor
  private static func invalidShortcutIsRejected() async throws {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let store = MemoryShortcutStore()
    let service = FakeFileSystemService(
      volumes: [],
      listings: [home.standardizedFileURL: []]
    )
    let model = FileBrowserModel(
      service: service,
      homeDirectory: home,
      shortcutStore: store
    )
    await model.start()

    await model.addShortcut(path: "~/Missing")

    try expect(model.shortcuts.isEmpty, "An inaccessible folder must not be saved")
    try expect(model.alert != nil, "Invalid shortcut entry must explain the failure")
    try expectEqual(await store.savedPaths(), [])
  }

  @MainActor
  private static func shortcutRemovalPersists() async throws {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let pictures = home.appendingPathComponent("Pictures", isDirectory: true)
    let store = MemoryShortcutStore(paths: [pictures.path])
    let service = FakeFileSystemService(
      volumes: [],
      listings: [home.standardizedFileURL: []]
    )
    let model = FileBrowserModel(
      service: service,
      homeDirectory: home,
      shortcutStore: store
    )
    await model.start()

    await model.removeShortcut(pictures)

    try expect(model.shortcuts.isEmpty, "Removed shortcut remained visible")
    try expectEqual(await store.savedPaths(), [])
  }

  @MainActor
  private static func imageActivationUsesBuiltInPreview() async throws {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let image = item(home.appendingPathComponent("photo.jpg"), isDirectory: false, isImage: true)
    let service = FakeFileSystemService(
      volumes: [],
      listings: [home.standardizedFileURL: [image]]
    )
    let model = FileBrowserModel(service: service, homeDirectory: home)
    await model.start()

    let handled = model.previewImageIfSupported(image)

    try expect(handled, "Image activation should be handled inside MiniExplorer")
    try expect(model.isPreviewVisible, "Image activation did not reveal the preview")
    try expectEqual(model.previewItem?.id, image.id)
  }

  @MainActor
  private static func textActivationUsesBuiltInPreview() async throws {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let script = item(home.appendingPathComponent("app.js"), isDirectory: false)
    let service = FakeFileSystemService(
      volumes: [],
      listings: [home.standardizedFileURL: [script]]
    )
    let model = FileBrowserModel(service: service, homeDirectory: home)
    await model.start()

    let handled = model.previewFileIfSupported(script)

    try expect(handled, "JavaScript should open in MiniExplorer's text preview")
    try expectEqual(model.previewItem?.id, script.id)
    try expectEqual(model.previewKind, .text)
  }

  @MainActor
  private static func pdfActivationUsesBuiltInPreview() async throws {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let document = item(home.appendingPathComponent("manual.pdf"), isDirectory: false)
    let service = FakeFileSystemService(
      volumes: [],
      listings: [home.standardizedFileURL: [document]]
    )
    let model = FileBrowserModel(service: service, homeDirectory: home)
    await model.start()

    let handled = model.previewFileIfSupported(document)

    try expect(handled, "PDF activation should be handled inside MiniExplorer")
    try expect(model.isPreviewVisible, "PDF activation did not reveal the preview")
    try expectEqual(model.previewItem?.id, document.id)
    try expectEqual(model.previewKind, .pdf)
  }

  @MainActor
  private static func escapeClosesPreview() async throws {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let markdown = item(home.appendingPathComponent("README.md"), isDirectory: false)
    let service = FakeFileSystemService(
      volumes: [],
      listings: [home.standardizedFileURL: [markdown]]
    )
    let model = FileBrowserModel(service: service, homeDirectory: home)
    await model.start()
    _ = model.previewFileIfSupported(markdown)

    model.closePreview()

    try expect(!model.isPreviewVisible, "Closing preview must restore the explorer")
    try expectEqual(model.previewCloseRequest, 1)
    try expectEqual(model.primaryItem?.id, markdown.id)
  }

  @MainActor
  private static func imagePreviewCaptureRecordsHistory() async throws {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let image = item(home.appendingPathComponent("photo.png"), isDirectory: false, isImage: true)
    let model = FileBrowserModel(
      service: FakeFileSystemService(
        volumes: [],
        listings: [home.standardizedFileURL: [image]]
      ),
      homeDirectory: home
    )
    await model.start()
    _ = model.previewFileIfSupported(image)

    try expect(model.capturePreviewedImage(operation: .copy), "Image preview copy was not captured")
    try expect(!model.capturePreviewedImage(operation: .copy), "Duplicate copy should not add history")
    try expect(model.capturePreviewedImage(operation: .move), "Image preview move was not captured")

    try expectEqual(model.clipboardHistory.map(\.payload.operation), [.move, .copy])
    try expectEqual(model.clipboardHistory.map { $0.payload.sourceURLs }, [[image.id], [image.id]])
    model.clearClipboardHistory()
    try expect(model.clipboardHistory.isEmpty, "Clear must remove preview capture history")
  }

  @MainActor
  private static func backNavigationRestoresFolder() async throws {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let pictures = home.appendingPathComponent("Pictures", isDirectory: true)
    let service = FakeFileSystemService(
      volumes: [],
      listings: [
        home.standardizedFileURL: [item(pictures, isDirectory: true)],
        pictures.standardizedFileURL: [],
      ]
    )
    let model = FileBrowserModel(service: service, homeDirectory: home)
    await model.start()

    await model.navigate(to: pictures)
    try expect(model.canNavigateBack, "Entering a folder should enable Back")

    await model.navigateBack()

    try expectEqual(model.currentURL, home.standardizedFileURL)
    try expect(!model.canNavigateBack, "Returning to the first location should disable Back")
  }

  @MainActor
  private static func searchFiltersCurrentFolder() async throws {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let pictures = home.appendingPathComponent("Pictures", isDirectory: true)
    let report = item(home.appendingPathComponent("Annual Report.pdf"), isDirectory: false)
    let notes = item(home.appendingPathComponent("notes.txt"), isDirectory: false)
    let service = FakeFileSystemService(
      volumes: [],
      listings: [
        home.standardizedFileURL: [report, notes, item(pictures, isDirectory: true)],
        pictures.standardizedFileURL: [],
      ]
    )
    let model = FileBrowserModel(service: service, homeDirectory: home)
    await model.start()

    model.searchText = "REPORT"
    try expectEqual(model.items.map(\.displayName), ["Annual Report.pdf"])

    model.searchText = ""
    try expectEqual(model.items.map(\.displayName), ["Pictures", "Annual Report.pdf", "notes.txt"])

    model.searchText = "notes"
    await model.navigate(to: pictures)
    try expectEqual(model.searchText, "")
  }

  @MainActor
  private static func columnSortingTogglesDirection() async throws {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let folder = item(home.appendingPathComponent("Folder"), isDirectory: true)
    let large = item(home.appendingPathComponent("large.dat"), isDirectory: false, size: 100)
    let small = item(home.appendingPathComponent("small.dat"), isDirectory: false, size: 10)
    let service = FakeFileSystemService(
      volumes: [],
      listings: [home.standardizedFileURL: [folder, large, small]]
    )
    let model = FileBrowserModel(service: service, homeDirectory: home)
    await model.start()

    model.sort(by: .size)
    try expectEqual(model.items.map(\.displayName), ["Folder", "small.dat", "large.dat"])
    try expectEqual(model.sortDirection, .ascending)

    model.sort(by: .size)
    try expectEqual(model.items.map(\.displayName), ["Folder", "large.dat", "small.dat"])
    try expectEqual(model.sortDirection, .descending)
  }

  private static func item(
    _ url: URL,
    name: String? = nil,
    isDirectory: Bool,
    isImage: Bool = false,
    size: Int64? = nil,
    modificationDate: Date? = nil
  ) -> FileItem {
    FileItem(
      url: url,
      displayName: name ?? url.lastPathComponent,
      isDirectory: isDirectory,
      isPackage: false,
      isSymbolicLink: false,
      size: size,
      modificationDate: modificationDate,
      isImage: isImage
    )
  }

  @MainActor
  private static func createFileRefreshesAndSelects() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = FileBrowserModel(
      service: LocalFileSystemService(mountedVolumeProvider: { [root] }),
      homeDirectory: root
    )
    await model.start()

    let succeeded = await model.createFile(named: "fresh.js")

    let created = root.appendingPathComponent("fresh.js").standardizedFileURL
    try expect(succeeded, "Expected file creation to succeed")
    try expectEqual(model.items.map(\.displayName), ["fresh.js"])
    try expectEqual(model.selectedItemID, created)
  }

  @MainActor
  private static func createFolderRefreshesAndSelects() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let model = FileBrowserModel(
      service: LocalFileSystemService(mountedVolumeProvider: { [root] }),
      homeDirectory: root
    )
    await model.start()

    let succeeded = await model.createFolder(named: "New Project")

    let created = root.appendingPathComponent("New Project").standardizedFileURL
    try expect(succeeded, "Expected folder creation to succeed")
    try expectEqual(model.items.map(\.displayName), ["New Project"])
    try expectEqual(model.selectedItemID, created)
    try expect(model.items.first?.isDirectory == true, "Created item must be a folder")
  }

  @MainActor
  private static func modelExposesOrderedSelection() async throws {
    let root = URL(fileURLWithPath: "/Selection", isDirectory: true)
    let first = item(root.appendingPathComponent("a.txt"), isDirectory: false)
    let second = item(root.appendingPathComponent("b.txt"), isDirectory: false)
    let third = item(root.appendingPathComponent("c.txt"), isDirectory: false)
    let model = FileBrowserModel(
      service: FakeFileSystemService(volumes: [], listings: [root.standardizedFileURL: [first, second, third]]),
      homeDirectory: root
    )
    await model.start()

    model.selectItem(first.id, modifier: .plain)
    model.selectItem(third.id, modifier: .command)

    try expectEqual(model.selectedItems.map(\.id), [first.id, third.id])
    try expectEqual(model.primaryItem?.id, third.id)
    try expectEqual(model.selectedItemID, third.id)

    model.selectAllVisibleItems()
    try expectEqual(model.selectedItems.map(\.id), [first.id, second.id, third.id])
  }

  @MainActor
  private static func clipboardHandlesMultipleItems() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("a.txt")
    let second = root.appendingPathComponent("b.txt")
    let destination = try createDirectory(named: "Destination", in: root)
    try Data("a".utf8).write(to: first)
    try Data("b".utf8).write(to: second)
    let model = FileBrowserModel(
      service: LocalFileSystemService(mountedVolumeProvider: { [root] }),
      homeDirectory: root
    )
    await model.start()
    model.selectItem(first, modifier: .plain)
    model.selectItem(second, modifier: .command)

    model.copySelection()

    try expectEqual(model.clipboard?.sourceURLs, [first.standardizedFileURL, second.standardizedFileURL])
    try expectEqual(model.clipboardHistory.count, 1)
    await model.navigate(to: destination)
    await model.paste()
    try expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("a.txt").path), "First copied file is missing")
    try expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("b.txt").path), "Second copied file is missing")
    try expectEqual(model.clipboard?.operation, .copy)
  }

  @MainActor
  private static func copyPublishesSystemClipboard() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("note.txt")
    try Data().write(to: file)
    let systemClipboard = FakeSystemClipboard()
    let model = FileBrowserModel(
      service: LocalFileSystemService(mountedVolumeProvider: { [root] }),
      homeDirectory: root,
      systemClipboard: systemClipboard
    )
    await model.start()
    model.selectItem(file)

    model.copySelection()

    try expectEqual(systemClipboard.writtenURLs, [file.standardizedFileURL])
  }

  @MainActor
  private static func externalTextClipboardCreatesFile() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("existing".utf8).write(to: root.appendingPathComponent("Clipboard.txt"))
    let systemClipboard = FakeSystemClipboard(
      changeCount: 7,
      content: .text("hello from clipboard")
    )
    let model = FileBrowserModel(
      service: LocalFileSystemService(mountedVolumeProvider: { [root] }),
      homeDirectory: root,
      systemClipboard: systemClipboard
    )
    await model.start()

    await model.paste()

    let created = root.appendingPathComponent("Clipboard 2.txt")
    try expectEqual(try String(contentsOf: created, encoding: .utf8), "hello from clipboard")
    try expectEqual(model.primaryItem?.id, created.standardizedFileURL)
  }

  @MainActor
  private static func externalFilesOverrideInternalClipboard() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let destination = try createDirectory(named: "Destination", in: root)
    let internalFile = root.appendingPathComponent("internal.txt")
    let externalFile = root.appendingPathComponent("external.txt")
    try Data("internal".utf8).write(to: internalFile)
    try Data("external".utf8).write(to: externalFile)
    let systemClipboard = FakeSystemClipboard()
    let model = FileBrowserModel(
      service: LocalFileSystemService(mountedVolumeProvider: { [root] }),
      homeDirectory: root,
      systemClipboard: systemClipboard
    )
    await model.start()
    model.selectItem(internalFile)
    model.copySelection()
    systemClipboard.replaceContent(.files([externalFile]))
    await model.navigate(to: destination)

    await model.paste()

    try expect(
      FileManager.default.fileExists(atPath: destination.appendingPathComponent("external.txt").path),
      "The newer external file was not copied"
    )
    try expect(
      !FileManager.default.fileExists(atPath: destination.appendingPathComponent("internal.txt").path),
      "Stale internal clipboard content was pasted"
    )
  }

  @MainActor
  private static func clipboardHistoryIsOrdered() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("note.txt")
    try Data().write(to: file)
    let model = FileBrowserModel(
      service: LocalFileSystemService(mountedVolumeProvider: { [root] }),
      homeDirectory: root
    )
    await model.start()
    model.selectItem(file)

    model.copySelection()
    model.copySelection()
    try expectEqual(model.clipboardHistory.count, 1)
    model.cutSelection()

    try expectEqual(model.clipboardHistory.map(\.payload.operation), [.move, .copy])
    let copyEntry = try require(model.clipboardHistory.last, "Missing copy history entry")
    model.activateClipboardHistoryEntry(copyEntry.id)
    try expectEqual(model.clipboard?.operation, .copy)
  }

  @MainActor
  private static func clipboardHistoryIsBounded() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("note.txt")
    try Data().write(to: file)
    let model = FileBrowserModel(
      service: LocalFileSystemService(mountedVolumeProvider: { [root] }),
      homeDirectory: root
    )
    await model.start()
    model.selectItem(file)

    for index in 0..<25 {
      if index.isMultiple(of: 2) { model.copySelection() } else { model.cutSelection() }
    }
    try expectEqual(model.clipboardHistory.count, 20)
    model.clearClipboardHistory()
    try expectEqual(model.clipboardHistory.count, 0)
  }

  @MainActor
  private static func clipboardHistoryPresentationCanBeRequested() throws {
    let root = URL(fileURLWithPath: "/Clipboard", isDirectory: true)
    let model = FileBrowserModel(
      service: FakeFileSystemService(volumes: [], listings: [root.standardizedFileURL: []]),
      homeDirectory: root
    )
    try expect(!model.isClipboardHistoryPresented, "History must start closed")
    model.showClipboardHistory()
    try expect(model.isClipboardHistoryPresented, "History request did not open the sheet")
  }

  @MainActor
  private static func renameRefreshesSelection() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("draft.txt")
    try Data("draft".utf8).write(to: source)
    let model = FileBrowserModel(service: LocalFileSystemService(), homeDirectory: root)
    await model.start()
    model.selectItem(source)

    let succeeded = await model.renamePrimaryItem(to: "report.txt")

    let renamed = root.appendingPathComponent("report.txt").standardizedFileURL
    try expect(succeeded, "Rename was expected to succeed")
    try expectEqual(model.items.map(\.displayName), ["report.txt"])
    try expectEqual(model.primaryItem?.id, renamed)
  }

  @MainActor
  private static func duplicateSelectionCreatesCopies() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("a.txt")
    let second = root.appendingPathComponent("b.txt")
    try Data("a".utf8).write(to: first)
    try Data("b".utf8).write(to: second)
    let model = FileBrowserModel(service: LocalFileSystemService(), homeDirectory: root)
    await model.start()
    model.selectItem(first)
    model.selectItem(second, modifier: .command)

    await model.duplicateSelection()

    try expectEqual(model.selectedItems.map(\.displayName), ["a copy.txt", "b copy.txt"])
    try expectEqual(
      model.items.map(\.displayName),
      ["a copy.txt", "a.txt", "b copy.txt", "b.txt"]
    )
  }

  @MainActor
  private static func trashSelectionRemovesItems() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("a.txt")
    let second = root.appendingPathComponent("b.txt")
    try Data().write(to: first)
    try Data().write(to: second)
    let service = LocalFileSystemService(trashHandler: { url in
      try FileManager.default.removeItem(at: url)
      return nil
    })
    let model = FileBrowserModel(service: service, homeDirectory: root)
    await model.start()
    model.selectAllVisibleItems()

    await model.trashSelection()

    try expectEqual(model.items, [])
    try expectEqual(model.selectedItems, [])
  }

  @MainActor
  private static func previewTrashTargetsOnlyPreviewedItem() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let keep = root.appendingPathComponent("keep.txt")
    let remove = root.appendingPathComponent("remove.txt")
    try Data().write(to: keep)
    try Data().write(to: remove)
    let service = LocalFileSystemService(trashHandler: { url in
      try FileManager.default.removeItem(at: url)
      return nil
    })
    let model = FileBrowserModel(service: service, homeDirectory: root)
    await model.start()
    let keepItem = try require(
      model.items.first { $0.url.standardizedFileURL == keep.standardizedFileURL },
      "Missing keep fixture"
    )
    let removeItem = try require(
      model.items.first { $0.url.standardizedFileURL == remove.standardizedFileURL },
      "Missing remove fixture"
    )
    model.selectItem(keepItem.id)
    model.selectItem(removeItem.id, modifier: .command)
    model.togglePreview()

    model.requestPreviewTrashConfirmation()
    try expectEqual(model.trashConfirmationItemCount, 1)
    try expectEqual(model.trashConfirmationDisplayName, "remove.txt")
    await model.trashSelection()

    try expect(FileManager.default.fileExists(atPath: keep.path), "Preview Trash removed another selected item")
    try expect(!FileManager.default.fileExists(atPath: remove.path), "Previewed item was not trashed")
    try expect(!model.isPreviewVisible, "Successful preview Trash must close the preview")
  }

  @MainActor
  private static func failedPreviewTrashKeepsPreviewOpen() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let document = root.appendingPathComponent("protected.txt")
    try Data().write(to: document)
    let service = LocalFileSystemService(trashHandler: { _ in
      throw CocoaError(.fileWriteNoPermission)
    })
    let model = FileBrowserModel(service: service, homeDirectory: root)
    await model.start()
    let item = try require(model.items.first, "Missing protected fixture")
    _ = model.previewFileIfSupported(item)

    model.requestPreviewTrashConfirmation()
    await model.trashSelection()

    try expect(model.isPreviewVisible, "Failed preview Trash unexpectedly closed the preview")
    try expect(FileManager.default.fileExists(atPath: document.path), "Failed Trash removed its source")
    try expectEqual(model.alert?.title, "Move to Trash Failed")
  }

  @MainActor
  private static func hiddenToggleRefreshesListing() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data().write(to: root.appendingPathComponent("visible.txt"))
    try Data().write(to: root.appendingPathComponent(".hidden.txt"))
    let model = FileBrowserModel(service: LocalFileSystemService(), homeDirectory: root)
    await model.start()
    try expectEqual(model.items.map(\.displayName), ["visible.txt"])

    await model.toggleHiddenFiles()

    try expect(model.showsHiddenFiles, "Hidden-files state was not enabled")
    try expectEqual(model.items.map(\.displayName), [".hidden.txt", "visible.txt"])
  }

  @MainActor
  private static func getInfoLoadsSelectedMetadata() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("a.txt")
    let second = root.appendingPathComponent("b.txt")
    try Data("a".utf8).write(to: first)
    try Data("bb".utf8).write(to: second)
    let model = FileBrowserModel(service: LocalFileSystemService(), homeDirectory: root)
    await model.start()
    model.selectAllVisibleItems()

    await model.showSelectedFileInfo()

    try expect(model.isFileInfoPresented, "Get Info did not request its sheet")
    try expectEqual(model.fileInfoItems.map(\.size), [1, 2])
  }

  @MainActor
  private static func multiItemDropRefreshesSource() async throws {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let destinationURL = home.appendingPathComponent("Destination", isDirectory: true)
    let destination = item(destinationURL, isDirectory: true)
    let first = item(home.appendingPathComponent("a.txt"), isDirectory: false)
    let second = item(home.appendingPathComponent("b.txt"), isDirectory: false)
    let service = FakeFileSystemService(
      volumes: [],
      listings: [
        home.standardizedFileURL: [destination, first, second],
        destinationURL.standardizedFileURL: [],
      ]
    )
    let model = FileBrowserModel(service: service, homeDirectory: home)
    await model.start()
    model.selectItem(first.id)
    model.selectItem(second.id, modifier: .command)

    model.beginDragging(first.url)
    try expectEqual(model.draggedItemURLs, [first.url, second.url])
    await model.receiveDrop(
      model.draggedItemURLs,
      into: destinationURL,
      internalSources: model.draggedItemURLs
    )

    try expectEqual(await service.recordedOperations(), ["move:a.txt", "move:b.txt"])
    try expectEqual(model.items.map(\.displayName), ["Destination"])
  }

  @MainActor
  private static func searchArrowsWrapResults() async throws {
    let root = URL(fileURLWithPath: "/Search", isDirectory: true)
    let first = item(root.appendingPathComponent("report-a.txt"), isDirectory: false)
    let second = item(root.appendingPathComponent("report-b.txt"), isDirectory: false)
    let third = item(root.appendingPathComponent("report-c.txt"), isDirectory: false)
    let ignored = item(root.appendingPathComponent("notes.txt"), isDirectory: false)
    let model = FileBrowserModel(
      service: FakeFileSystemService(
        volumes: [],
        listings: [root.standardizedFileURL: [first, second, third, ignored]]
      ),
      homeDirectory: root
    )
    await model.start()
    model.searchText = "report"

    model.selectNextSearchResult()
    try expectEqual(model.primaryItem?.id, first.id)
    model.selectPreviousSearchResult()
    try expectEqual(model.primaryItem?.id, third.id)
    model.selectNextSearchResult()
    try expectEqual(model.primaryItem?.id, first.id)
  }

  @MainActor
  private static func searchEnterRequestsActivation() async throws {
    let root = URL(fileURLWithPath: "/Search", isDirectory: true)
    let result = item(root.appendingPathComponent("report.txt"), isDirectory: false)
    let model = FileBrowserModel(
      service: FakeFileSystemService(
        volumes: [],
        listings: [root.standardizedFileURL: [result]]
      ),
      homeDirectory: root
    )
    await model.start()
    model.searchText = "report"
    model.selectNextSearchResult()
    let previousRequest = model.searchActivationRequest

    model.requestSearchResultActivation()

    try expectEqual(model.searchActivationRequest, previousRequest + 1)
  }

  private static func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
  }

  @discardableResult
  private static func createDirectory(named name: String, in parent: URL) throws -> URL {
    let url = parent.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
  }

  @MainActor
  private static func run(_ name: String, _ test: () async throws -> Void) async throws {
    try await test()
    print("PASS: \(name)")
  }

  private static func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    guard condition() else { throw BrowserTestFailure(message, file: file, line: line) }
  }

  private static func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    guard actual == expected else {
      throw BrowserTestFailure(
        "Expected \(String(describing: expected)), got \(String(describing: actual))",
        file: file,
        line: line
      )
    }
  }

  private static func require<T>(
    _ value: T?,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws -> T {
    guard let value else { throw BrowserTestFailure(message, file: file, line: line) }
    return value
  }
}

private actor FakeFileSystemService: FileSystemServing {
  private var volumeItems: [FileItem]
  private var listings: [URL: [FileItem]]
  private var operations: [String] = []

  init(volumes: [FileItem], listings: [URL: [FileItem]]) {
    self.volumeItems = volumes
    self.listings = listings
  }

  func mountedVolumes() async throws -> [FileItem] { volumeItems }

  func list(_ directory: URL) async throws -> [FileItem] {
    guard let result = listings[directory.standardizedFileURL] else {
      throw CocoaError(.fileNoSuchFile)
    }
    return result
  }

  func copy(_ source: URL, into directory: URL) async throws {
    operations.append("copy:\(source.lastPathComponent)")
  }
  func move(_ source: URL, into directory: URL) async throws {
    operations.append("move:\(source.lastPathComponent)")
    for key in listings.keys {
      listings[key]?.removeAll { $0.id == source.standardizedFileURL }
    }
  }
  func createFile(named name: String, in directory: URL) async throws -> URL {
    let url = directory.appendingPathComponent(name).standardizedFileURL
    operations.append("create:\(name)")
    listings[directory.standardizedFileURL, default: []].append(
      FileItem(
        url: url,
        displayName: name,
        isDirectory: false,
        isPackage: false,
        isSymbolicLink: false,
        size: 0,
        modificationDate: nil
      )
    )
    return url
  }
  func createFolder(named name: String, in directory: URL) async throws -> URL {
    let url = directory.appendingPathComponent(name).standardizedFileURL
    operations.append("create-folder:\(name)")
    listings[directory.standardizedFileURL, default: []].append(
      FileItem(
        url: url,
        displayName: name,
        isDirectory: true,
        isPackage: false,
        isSymbolicLink: false,
        size: nil,
        modificationDate: nil
      )
    )
    return url
  }
  func isSameVolume(_ source: URL, _ destination: URL) async throws -> Bool { true }

  func recordedOperations() -> [String] { operations }

  func setVolumes(_ volumes: [FileItem]) {
    volumeItems = volumes
  }
}

private actor MemoryShortcutStore: ShortcutStoring {
  private var paths: [String]

  init(paths: [String] = []) {
    self.paths = paths
  }

  func loadPaths() async -> [String] { paths }

  func savePaths(_ paths: [String]) async {
    self.paths = paths
  }

  func savedPaths() -> [String] { paths }
}

@MainActor
private final class FakeSystemClipboard: SystemClipboardServing {
  private(set) var changeCount: Int
  private var content: SystemClipboardContent?
  private(set) var writtenURLs: [URL] = []

  init(changeCount: Int = 0, content: SystemClipboardContent? = nil) {
    self.changeCount = changeCount
    self.content = content
  }

  func readSnapshot() -> SystemClipboardSnapshot? {
    content.map { SystemClipboardSnapshot(changeCount: changeCount, content: $0) }
  }

  func writeFileURLs(_ urls: [URL]) -> Int {
    writtenURLs = urls.map(\.standardizedFileURL)
    changeCount += 1
    content = .files(urls)
    return changeCount
  }

  func replaceContent(_ content: SystemClipboardContent) {
    changeCount += 1
    self.content = content
  }
}

private struct BrowserTestFailure: Error, CustomStringConvertible {
  let message: String
  let file: StaticString
  let line: UInt

  init(_ message: String, file: StaticString, line: UInt) {
    self.message = message
    self.file = file
    self.line = line
  }

  var description: String { "\(file):\(line): \(message)" }
}
