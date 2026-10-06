# MiniExplorer Daily File Operations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add dependable multi-selection, batch clipboard/history, drag and drop, rename, duplicate, Trash, Get Info, hidden-file visibility, and keyboard search navigation to MiniExplorer.

**Architecture:** Keep the themed SwiftUI application and introduce focused core types for ordered selection, multi-item clipboard history, operation results, and metadata. `FileBrowserModel` coordinates deterministic batch operations over injectable `FileSystemServing` primitives; small view-level AppKit event helpers supply modifier-aware selection and activation without replacing the visual layer.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Foundation/FileManager, UniformTypeIdentifiers, Swift Package Manager, macOS 15+

**Spec:** `docs/superpowers/specs/2026-09-01-daily-file-operations-design.md`

## Global Constraints

- Preserve all four themes and keep Murmur Flat as the first-launch default.
- Keep the app local-only, unsandboxed, single-window, and independent from Finder's clipboard.
- Move items to macOS Trash; never permanently delete.
- Never overwrite an existing destination.
- Clipboard history is session-only, newest first, deduplicated, and limited to 20 entries.
- Undo remains out of scope.
- Automated filesystem tests operate only in temporary directories.

---

### Task 1: Ordered Multi-Selection Core

**Files:**
- Create: `Sources/MiniExplorerCore/FileSelectionState.swift`
- Create: `Tests/MiniExplorerCoreTests/FileSelectionStateTests.swift`
- Modify: `Tests/MiniExplorerCoreTests/LocalFileSystemServiceTests.swift`
- Modify: `Sources/MiniExplorerCore/FileBrowserModel.swift`

**Interfaces:**
- Produces: `FileSelectionModifier`, `FileSelectionState`, `select(_:modifier:visibleIDs:)`, `selectAll(_:)`, `normalize(visibleIDs:)`, `selectedIDs`, `primaryID`, and `anchorID`.
- Later tasks consume the ordered selection and primary identity from `FileBrowserModel`.

- [ ] **Step 1: Write failing selection-transition tests**

Add a runner that asserts literal selection order for plain click, Command toggle, Shift range, Select All, and normalization:

```swift
let ids = ["a", "b", "c", "d"].map { URL(fileURLWithPath: "/\($0)") }
var selection = FileSelectionState()
selection.select(ids[1], modifier: .plain, visibleIDs: ids)
selection.select(ids[3], modifier: .shift, visibleIDs: ids)
try expectEqual(selection.selectedIDs, [ids[1], ids[2], ids[3]])
selection.select(ids[2], modifier: .command, visibleIDs: ids)
try expectEqual(selection.selectedIDs, [ids[1], ids[3]])
selection.normalize(visibleIDs: [ids[3]])
try expectEqual(selection.selectedIDs, [ids[3]])
```

- [ ] **Step 2: Run the harness and verify RED**

Run: `./Scripts/test.sh`

Expected: compilation fails because `FileSelectionState` and `FileSelectionModifier` do not exist.

- [ ] **Step 3: Implement the ordered selection state**

Create value semantics with standardized URL identity and deterministic visible ordering:

```swift
public enum FileSelectionModifier: Sendable {
  case plain
  case command
  case shift
}

public struct FileSelectionState: Equatable, Sendable {
  public private(set) var selectedIDs: [URL] = []
  public private(set) var primaryID: URL?
  public private(set) var anchorID: URL?

  public init() {}

  public mutating func select(
    _ id: URL,
    modifier: FileSelectionModifier,
    visibleIDs: [URL]
  ) {
    let id = id.standardizedFileURL
    let visible = visibleIDs.map(\.standardizedFileURL)
    switch modifier {
    case .plain:
      selectedIDs = [id]
      primaryID = id
      anchorID = id
    case .command:
      var selected = Set(selectedIDs)
      if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
      selectedIDs = visible.filter(selected.contains)
      primaryID = selected.contains(id) ? id : selectedIDs.last
      anchorID = primaryID
    case .shift:
      let anchor = anchorID ?? primaryID ?? id
      guard let start = visible.firstIndex(of: anchor),
        let end = visible.firstIndex(of: id)
      else {
        selectedIDs = [id]
        primaryID = id
        anchorID = id
        return
      }
      selectedIDs = Array(visible[min(start, end)...max(start, end)])
      primaryID = id
      anchorID = anchor
    }
  }

  public mutating func selectAll(_ visibleIDs: [URL]) {
    selectedIDs = visibleIDs.map(\.standardizedFileURL)
    primaryID = selectedIDs.first
    anchorID = selectedIDs.first
  }
  public mutating func clear() { self = FileSelectionState() }
  public mutating func normalize(visibleIDs: [URL]) {
    let visible = visibleIDs.map(\.standardizedFileURL)
    let selected = Set(selectedIDs)
    selectedIDs = visible.filter(selected.contains)
    if primaryID.map({ selectedIDs.contains($0.standardizedFileURL) }) != true {
      primaryID = selectedIDs.last
    }
    if anchorID.map({ visible.contains($0.standardizedFileURL) }) != true {
      anchorID = primaryID
    }
  }
}
```

Expose model helpers `selectItem(_:modifier:)`, `selectAllVisibleItems()`, `selectedItems`, `primaryItem`, and compatibility accessors while migrating away from the single `selectedItemID` source of truth.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `./Scripts/test.sh`

Expected: all existing tests plus selection tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MiniExplorerCore/FileSelectionState.swift Sources/MiniExplorerCore/FileBrowserModel.swift Tests/MiniExplorerCoreTests
git commit -m "Add ordered multi-selection model"
```

---

### Task 2: Multi-Item Clipboard and Session History

**Files:**
- Modify: `Sources/MiniExplorerCore/ClipboardPayload.swift`
- Create: `Sources/MiniExplorerCore/ClipboardHistory.swift`
- Modify: `Sources/MiniExplorerCore/FileBrowserModel.swift`
- Modify: `Sources/MiniExplorer/FileActionCommands.swift`
- Create: `Sources/MiniExplorer/ClipboardHistoryView.swift`
- Modify: `Tests/MiniExplorerCoreTests/BrowserModelTests.swift`

**Interfaces:**
- Consumes: `FileSelectionState.selectedIDs` and `FileBrowserModel.selectedItems`.
- Produces: `ClipboardPayload(sourceURLs:operation:)`, `ClipboardHistoryEntry`, `clipboardHistory`, `activateClipboardHistoryEntry(_:)`, and `clearClipboardHistory()`.

- [ ] **Step 1: Write failing clipboard/history tests**

Cover multiple ordered sources, copy retention, cut partial removal, newest-first history, consecutive deduplication, a literal maximum of 20 entries, stale-source pruning, activation, and clearing:

```swift
model.selectAllVisibleItems()
model.copySelection()
try expectEqual(model.clipboard?.sourceURLs, [first.id, second.id])
try expectEqual(model.clipboardHistory.count, 1)
model.copySelection()
try expectEqual(model.clipboardHistory.count, 1)
model.clearClipboardHistory()
try expectEqual(model.clipboardHistory, [])
```

- [ ] **Step 2: Run the harness and verify RED**

Run: `./Scripts/test.sh`

Expected: compilation fails because payloads still expose one `sourceURL` and history APIs are absent.

- [ ] **Step 3: Implement clipboard payload/history and batch paste**

Use these public shapes:

```swift
public struct ClipboardPayload: Equatable, Sendable {
  public let sourceURLs: [URL]
  public let operation: ClipboardOperation
}

public struct ClipboardHistoryEntry: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let payload: ClipboardPayload
  public let capturedAt: Date
}
```

Store at most 20 entries in `FileBrowserModel`. Batch paste sequentially, refresh once, retain copy payloads, and remove only successfully moved URLs from cut payloads and history.

Replace the default pasteboard command group rather than appending conflicting shortcuts:

```swift
CommandGroup(replacing: .pasteboard) {
  Button("Cut Items") { model.cutSelection() }.keyboardShortcut("x", modifiers: .command)
  Button("Copy Items") { model.copySelection() }.keyboardShortcut("c", modifiers: .command)
  Button("Paste Items") { Task { await model.paste() } }
    .keyboardShortcut("v", modifiers: .command)
}
```

Keep native text editing active when `.fileActionsDisabled` is focused. Add a flat clipboard-history sheet/menu showing operation, count, filenames, capture time, Activate and Clear actions.

- [ ] **Step 4: Run tests and build**

Run: `./Scripts/test.sh && swift build --product MiniExplorer`

Expected: tests and debug application build pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MiniExplorerCore/ClipboardPayload.swift Sources/MiniExplorerCore/ClipboardHistory.swift Sources/MiniExplorerCore/FileBrowserModel.swift Sources/MiniExplorer/FileActionCommands.swift Sources/MiniExplorer/ClipboardHistoryView.swift Tests/MiniExplorerCoreTests/BrowserModelTests.swift
git commit -m "Add batch clipboard and session history"
```

---

### Task 3: Validated Filesystem Operations and Hidden Listing

**Files:**
- Create: `Sources/MiniExplorerCore/FileInfo.swift`
- Modify: `Sources/MiniExplorerCore/FileSystemServing.swift`
- Modify: `Sources/MiniExplorerCore/LocalFileSystemService.swift`
- Modify: `Tests/MiniExplorerCoreTests/LocalFileSystemServiceTests.swift`

**Interfaces:**
- Produces: `list(_:includesHiddenItems:)`, `rename(_:to:)`, `duplicate(_:)`, `trash(_:)`, `info(for:)`, and `FileInfo`.
- The model in Task 4 consumes these operations one URL at a time for deterministic batch results.

- [ ] **Step 1: Write failing real-filesystem tests**

Use temporary roots to verify hidden listing, rename validation/conflicts, extension-preserving duplicate names, recursive directory duplication, Trash through an injected trash handler, and literal metadata:

```swift
let hidden = root.appendingPathComponent(".env")
try Data("KEY=value".utf8).write(to: hidden)
try expectEqual(try await service.list(root, includesHiddenItems: false), [])
try expectEqual(
  try await service.list(root, includesHiddenItems: true).map(\.displayName),
  [".env"]
)
let renamed = try await service.rename(hidden, to: "settings.env")
try expectEqual(renamed.lastPathComponent, "settings.env")
let copy = try await service.duplicate(renamed)
try expectEqual(copy.lastPathComponent, "settings copy.env")
```

- [ ] **Step 2: Run the harness and verify RED**

Run: `./Scripts/test.sh`

Expected: compilation fails because the new service methods and `FileInfo` are absent.

- [ ] **Step 3: Implement safe FileManager primitives**

Define:

```swift
public struct FileInfo: Equatable, Sendable {
  public let url: URL
  public let kind: String
  public let size: Int64?
  public let creationDate: Date?
  public let modificationDate: Date?
  public let isDirectory: Bool
  public let isPackage: Bool
  public let isSymbolicLink: Bool
}
```

Centralize validated leaf-name handling. `rename` moves only within the same parent and refuses conflicts. `duplicate` probes `copy`, then `copy 2`, preserving extensions. `trash` calls an injectable closure defaulting to `FileManager.trashItem`. `list` chooses no options or `.skipsHiddenFiles` from its Boolean input.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `./Scripts/test.sh`

Expected: every filesystem and existing test passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/MiniExplorerCore/FileInfo.swift Sources/MiniExplorerCore/FileSystemServing.swift Sources/MiniExplorerCore/LocalFileSystemService.swift Tests/MiniExplorerCoreTests/LocalFileSystemServiceTests.swift
git commit -m "Add safe rename duplicate trash and metadata operations"
```

---

### Task 4: Batch Operations and Themed Action UI

**Files:**
- Modify: `Sources/MiniExplorerCore/FileBrowserModel.swift`
- Create: `Sources/MiniExplorer/RenameItemView.swift`
- Create: `Sources/MiniExplorer/FileInfoView.swift`
- Modify: `Sources/MiniExplorer/FileTableView.swift`
- Modify: `Sources/MiniExplorer/LargeIconGridView.swift`
- Modify: `Sources/MiniExplorer/FileActionCommands.swift`
- Modify: `Tests/MiniExplorerCoreTests/BrowserModelTests.swift`

**Interfaces:**
- Consumes: Task 1 selection, Task 2 clipboard/history, and Task 3 service operations.
- Produces: `renamePrimaryItem(to:)`, `duplicateSelection()`, `trashSelection()`, `selectedFileInfo()`, `showsHiddenFiles`, and command/context-menu enablement properties.

- [ ] **Step 1: Write failing model batch-operation tests**

Test success and partial failure with literal selection outcomes:

```swift
model.selectItem(first.id, modifier: .plain)
model.selectItem(second.id, modifier: .command)
await model.duplicateSelection()
try expectEqual(model.selectedItems.map(\.displayName), ["first copy.txt", "second copy.txt"])
await model.trashSelection()
try expectEqual(model.items.map(\.displayName), ["first.txt", "second.txt"])
```

Add rename success/conflict, failed-item retention, aggregate info, and hidden-toggle refresh cases.

- [ ] **Step 2: Run the harness and verify RED**

Run: `./Scripts/test.sh`

Expected: compilation fails on absent model action APIs.

- [ ] **Step 3: Implement model orchestration and views**

Add a reusable result accumulator:

```swift
public struct FileOperationFailure: Equatable, Sendable {
  public let sourceURL: URL
  public let reason: String
}
```

Process batches in selected visible order, collect successes and failures, refresh once, select created/renamed results or failed sources, and issue one alert such as `"3 items completed; 1 failed: report.txt already exists."`.

Add Rename, Duplicate, Move to Trash, and Get Info to both list and icon selected-item menus. Confirm Trash with a themed alert. Add Delete, Command-D, Command-I, Return/rename menu actions where they do not conflict with search activation. Add Show Hidden Files under View with Command-Shift-Period.

- [ ] **Step 4: Run tests and build**

Run: `./Scripts/test.sh && swift build --product MiniExplorer`

Expected: full tests and app compilation pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MiniExplorerCore/FileBrowserModel.swift Sources/MiniExplorer/RenameItemView.swift Sources/MiniExplorer/FileInfoView.swift Sources/MiniExplorer/FileTableView.swift Sources/MiniExplorer/LargeIconGridView.swift Sources/MiniExplorer/FileActionCommands.swift Tests/MiniExplorerCoreTests/BrowserModelTests.swift
git commit -m "Add batch file actions and themed dialogs"
```

---

### Task 5: Reliable Multi-Item Drag and Modifier-Aware Views

**Files:**
- Create: `Sources/MiniExplorer/ModifierAwareSelection.swift`
- Modify: `Sources/MiniExplorer/FileTableView.swift`
- Modify: `Sources/MiniExplorer/LargeIconGridView.swift`
- Modify: `Sources/MiniExplorer/SidebarView.swift`
- Modify: `Sources/MiniExplorerCore/FileBrowserModel.swift`
- Modify: `Tests/MiniExplorerCoreTests/BrowserModelTests.swift`

**Interfaces:**
- Consumes: ordered selection and service batch primitives.
- Produces: consistent plain/Command/Shift click routing, `draggedItemURLs`, and refreshed source listing after drops.

- [ ] **Step 1: Write failing drop-routing tests**

Assert that a multi-item same-volume internal drop records moves in order and always refreshes the displayed source even when destination differs:

```swift
model.selectAllVisibleItems()
await model.receiveDrop(
  model.selectedItems.map(\.url),
  into: destination,
  internalSources: model.selectedItems.map(\.url)
)
try expectEqual(await service.recordedOperations(), ["move:a.txt", "move:b.txt"])
try expectEqual(model.items.map(\.displayName), [])
```

- [ ] **Step 2: Run the harness and verify RED**

Run: `./Scripts/test.sh`

Expected: compilation fails because drop APIs still accept one internal source and do not refresh the source.

- [ ] **Step 3: Implement modifier clicks and multi-file drags**

Map `NSEvent.modifierFlags` to selection modifiers:

```swift
let modifier: FileSelectionModifier
if event.modifierFlags.contains(.shift) {
  modifier = .shift
} else if event.modifierFlags.contains(.command) {
  modifier = .command
} else {
  modifier = .plain
}
model.selectItem(item.id, modifier: modifier)
```

Provide every selected URL through `NSItemProvider`/file URL transfer. Use consistent folder-target drop handlers in list, grid, and sidebar. Refresh the current listing after any internal move, including moves into child folders, and retain failed sources selected.

- [ ] **Step 4: Run tests and build**

Run: `./Scripts/test.sh && swift build --product MiniExplorer`

Expected: tests and app build pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MiniExplorer/ModifierAwareSelection.swift Sources/MiniExplorer/FileTableView.swift Sources/MiniExplorer/LargeIconGridView.swift Sources/MiniExplorer/SidebarView.swift Sources/MiniExplorerCore/FileBrowserModel.swift Tests/MiniExplorerCoreTests/BrowserModelTests.swift
git commit -m "Fix multi-item selection and drag routing"
```

---

### Task 6: Search Keyboard Traversal and Activation

**Files:**
- Modify: `Sources/MiniExplorerCore/FileBrowserModel.swift`
- Modify: `Sources/MiniExplorer/AddressBarView.swift`
- Modify: `Sources/MiniExplorer/ContentView.swift`
- Modify: `Tests/MiniExplorerCoreTests/BrowserModelTests.swift`

**Interfaces:**
- Produces: `selectNextSearchResult()`, `selectPreviousSearchResult()`, and `searchActivationRequest` consumed by ContentView.

- [ ] **Step 1: Write failing search navigation tests**

Use three literal filtered results and verify boundary selection, wrapping, filtering normalization, no-match clearing, and activation requests:

```swift
model.searchText = "report"
model.selectNextSearchResult()
try expectEqual(model.primaryItem?.displayName, "report-a.txt")
model.selectPreviousSearchResult()
try expectEqual(model.primaryItem?.displayName, "report-c.txt")
let previousRequest = model.searchActivationRequest
model.requestSearchResultActivation()
try expectEqual(model.searchActivationRequest, previousRequest + 1)
```

- [ ] **Step 2: Run the harness and verify RED**

Run: `./Scripts/test.sh`

Expected: compilation fails on missing search traversal APIs.

- [ ] **Step 3: Implement focused key handling and activation**

Attach macOS 15 key handlers to the search field:

```swift
.onKeyPress(.downArrow) { model.selectNextSearchResult(); return .handled }
.onKeyPress(.upArrow) { model.selectPreviousSearchResult(); return .handled }
.onSubmit { model.requestSearchResultActivation() }
```

Observe `searchActivationRequest` in ContentView and activate the primary item using the existing folder navigation, built-in preview, and NSWorkspace open rules. Do nothing when there is no match.

- [ ] **Step 4: Run tests and build**

Run: `./Scripts/test.sh && swift build --product MiniExplorer`

Expected: all tests and compilation pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MiniExplorerCore/FileBrowserModel.swift Sources/MiniExplorer/AddressBarView.swift Sources/MiniExplorer/ContentView.swift Tests/MiniExplorerCoreTests/BrowserModelTests.swift
git commit -m "Add keyboard navigation for search results"
```

---

### Task 7: Documentation, Release Verification, and Installation

**Files:**
- Modify: `README.md`
- Modify: `design-qa.md`
- Create: `design-qa-artifacts/implementation-multi-selection.jpeg`
- Create: `design-qa-artifacts/implementation-clipboard-history.jpeg`
- Create: `design-qa-artifacts/implementation-file-actions.jpeg`

**Interfaces:**
- Consumes the complete application.
- Produces user documentation, visual QA evidence, a signed app bundle, and the installed `/Applications/MiniExplorer.app`.

- [ ] **Step 1: Update durable documentation**

Document Shift/Command selection, batch shortcuts, clipboard-history lifetime, drag semantics, Rename, Duplicate, Trash, Get Info, Show Hidden Files, and search keyboard navigation. Remove rename/delete from deferred features.

- [ ] **Step 2: Run full automated verification**

Run: `./Scripts/test.sh`

Expected: exit 0 with every named test printing `PASS`.

- [ ] **Step 3: Build and verify the release bundle**

Run:

```bash
./Scripts/build-app.sh
codesign --verify --deep --strict .build/app/MiniExplorer.app
```

Expected: release build exits 0 and codesign reports no error.

- [ ] **Step 4: Perform live Murmur-theme inspection**

Inspect list and icon modes. Verify Shift range, Command toggle, right-click enablement, batch drag into a temporary folder, clipboard history activation, rename, duplicate, Trash confirmation, Get Info, hidden toggle, and search Up/Down/Enter. Capture the three named QA artifacts without permanently deleting personal files.

- [ ] **Step 5: Install and compare the verified bundle**

Run:

```bash
ditto .build/app/MiniExplorer.app /Applications/MiniExplorer.app
cmp .build/app/MiniExplorer.app/Contents/MacOS/MiniExplorer /Applications/MiniExplorer.app/Contents/MacOS/MiniExplorer
```

Expected: both commands exit 0.

- [ ] **Step 6: Commit**

```bash
git add README.md design-qa.md design-qa-artifacts
git commit -m "Document and verify daily file operations"
```
