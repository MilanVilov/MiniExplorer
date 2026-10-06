# Hybrid Folder and Preview Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add independent folder and built-in preview tabs inside every MiniExplorer window.

**Architecture:** Each window owns an `ExplorerTabManager`; every `ExplorerTab` owns a distinct `FileBrowserModel` and optional text session. Item activation flows through one disposition-aware route, while focused scene objects keep menu commands attached to the active window and tab.

**Tech Stack:** Swift 6.2, SwiftUI on macOS 15, AppKit integration, the existing executable test harness.

**Spec:** `docs/superpowers/specs/2026-09-08-hybrid-tabs-design.md`

## Global Constraints

- Normal activation reuses the active tab; Command-modified activation opens a foreground tab.
- Matching standardized URLs focus an existing tab in the same window.
- Folder navigation, preview state, history, selection, search, view mode, and edits are isolated per tab and per window.
- Global theme and terminal preferences remain shared.
- Unsupported files continue opening through macOS.
- Dirty text is never silently discarded.
- Tab restoration, tab dragging, pinning, split panes, and external-file tabs are excluded.

---

### Task 1: Core Tab Identity and Selection

**Files:**
- Create: `Sources/MiniExplorerCore/ExplorerTab.swift`
- Create: `Sources/MiniExplorerCore/ExplorerTabManager.swift`
- Modify: `Tests/MiniExplorerCoreTests/BrowserModelTests.swift`

**Interfaces:**
- Consumes: `FileBrowserModelFactory.makeModel() -> FileBrowserModel`.
- Produces: `ExplorerTab`, `ExplorerOpenDisposition`, and `ExplorerTabManager` with tab creation, selection, cycling, and removal.

- [ ] **Step 1: Write failing manager tests**

Add literal assertions covering one initial tab, fresh model identity, foreground creation, selection wrapping, deterministic neighbor selection, and a final-tab close result:

```swift
let manager = ExplorerTabManager(modelFactory: factory)
try expectEqual(manager.tabs.count, 1)
let firstID = manager.activeTabID
let second = manager.newHomeTab()
try expectEqual(manager.activeTabID, second.id)
try expect(manager.tabs[0].model !== second.model, "Tabs shared a browser model")
manager.selectNextTab()
try expectEqual(manager.activeTabID, firstID)
try expectEqual(manager.requestClose(tabID: firstID), .tabClosed)
try expectEqual(manager.requestClose(tabID: second.id), .windowShouldClose)
```

- [ ] **Step 2: Run tests and verify the missing types fail compilation**

Run: `./Scripts/test.sh`

Expected: FAIL because `ExplorerTabManager` and `ExplorerTabCloseResult` do not exist.

- [ ] **Step 3: Implement minimal tab state and manager**

Create these public main-actor interfaces:

```swift
public enum ExplorerOpenDisposition: Equatable, Sendable {
  case currentTab
  case newTab
}

public enum ExplorerTabCloseResult: Equatable, Sendable {
  case tabClosed
  case windowShouldClose
  case notFound
}

@MainActor
public final class ExplorerTab: ObservableObject, Identifiable {
  public let id: UUID
  public let model: FileBrowserModel

  public init(id: UUID = UUID(), model: FileBrowserModel) {
    self.id = id
    self.model = model
  }
}

@MainActor
public final class ExplorerTabManager: ObservableObject {
  @Published public private(set) var tabs: [ExplorerTab]
  @Published public var activeTabID: UUID

  public init(modelFactory: FileBrowserModelFactory)
  public var activeTab: ExplorerTab? { get }
  @discardableResult public func newHomeTab() -> ExplorerTab
  public func select(tabID: UUID)
  public func selectNextTab()
  public func selectPreviousTab()
  @discardableResult public func requestClose(tabID: UUID) -> ExplorerTabCloseResult
}
```

When removing the active tab, select the tab that moves into the removed index, or the preceding tab when the removed tab was last.

- [ ] **Step 4: Run tests and verify they pass**

Run: `./Scripts/test.sh`

Expected: all tests pass.

- [ ] **Step 5: Commit the core tab collection**

```bash
git add Sources/MiniExplorerCore/ExplorerTab.swift Sources/MiniExplorerCore/ExplorerTabManager.swift Tests/MiniExplorerCoreTests/BrowserModelTests.swift
git commit -m "Add independent explorer tab state"
```

---

### Task 2: Tab-Aware Item Opening

**Files:**
- Modify: `Sources/MiniExplorerCore/ExplorerTab.swift`
- Modify: `Sources/MiniExplorerCore/ExplorerTabManager.swift`
- Modify: `Sources/MiniExplorerCore/FileBrowserModel.swift`
- Modify: `Tests/MiniExplorerCoreTests/BrowserModelTests.swift`

**Interfaces:**
- Consumes: Task 1's manager and `FileBrowserModel.previewFileIfSupported(_:)`.
- Produces: URL-derived tab titles, duplicate detection, and `open(_:disposition:) async -> ExplorerItemOpenResult`.

- [ ] **Step 1: Write failing activation tests**

Cover folder reuse, preview reuse, new folder/file tabs, existing-tab focus, and unsupported results:

```swift
try expectEqual(await manager.open(folder, disposition: .currentTab), .handled)
try expectEqual(manager.activeTab?.model.currentURL, folder.url)
let originalID = manager.activeTabID
try expectEqual(await manager.open(image, disposition: .newTab), .handled)
try expect(manager.activeTabID != originalID, "New-tab activation reused the active tab")
let count = manager.tabs.count
try expectEqual(await manager.open(image, disposition: .newTab), .handled)
try expectEqual(manager.tabs.count, count)
try expectEqual(await manager.open(binary, disposition: .currentTab), .external)
```

- [ ] **Step 2: Run tests and verify they fail because opening is absent**

Run: `./Scripts/test.sh`

Expected: FAIL for the missing `open` API and result type.

- [ ] **Step 3: Add the opening contract**

Add:

```swift
public enum ExplorerItemOpenResult: Equatable, Sendable {
  case handled
  case external
}

public extension FileBrowserModel {
  func canPreview(_ item: FileItem) -> Bool
}

public extension ExplorerTab {
  var representedURL: URL { get }
  var title: String { get }
}

public extension ExplorerTabManager {
  func start() async
  @discardableResult
  func open(_ item: FileItem, disposition: ExplorerOpenDisposition) async
    -> ExplorerItemOpenResult
}
```

`start()` initializes the initial tab once. New-tab opening initializes a fresh model, loads the item's parent directory, opens the preview when supported, appends the completed tab, and makes it active. Current-tab opening navigates or previews using the active model. Search for `representedURL.standardizedFileURL` before either path and focus a match.

- [ ] **Step 4: Run tests and verify they pass**

Run: `./Scripts/test.sh`

Expected: all tests pass.

- [ ] **Step 5: Commit activation behavior**

```bash
git add Sources/MiniExplorerCore/ExplorerTab.swift Sources/MiniExplorerCore/ExplorerTabManager.swift Sources/MiniExplorerCore/FileBrowserModel.swift Tests/MiniExplorerCoreTests/BrowserModelTests.swift
git commit -m "Add tab-aware item activation"
```

---

### Task 3: Central Activation Route

**Files:**
- Create: `Sources/MiniExplorer/ExplorerItemActivation.swift`
- Modify: `Sources/MiniExplorer/ContentView.swift`
- Modify: `Sources/MiniExplorer/FileTableView.swift`
- Modify: `Sources/MiniExplorer/LargeIconGridView.swift`
- Modify: `Sources/MiniExplorerCore/FileItemInteraction.swift`
- Modify: `Tests/MiniExplorerCoreTests/InteractionPreferenceTests.swift`

**Interfaces:**
- Consumes: `ExplorerTabManager.open(_:disposition:)`.
- Produces: `ExplorerItemActivationAction` environment value and `FileItemInteraction.openDisposition(isCommandPressed:)`.

- [ ] **Step 1: Write the failing modifier-policy test**

```swift
try expectEqual(
  FileItemInteraction.openDisposition(isCommandPressed: false),
  .currentTab
)
try expectEqual(
  FileItemInteraction.openDisposition(isCommandPressed: true),
  .newTab
)
```

- [ ] **Step 2: Run tests and verify the policy API is missing**

Run: `./Scripts/test.sh`

Expected: FAIL because `openDisposition(isCommandPressed:)` is absent.

- [ ] **Step 3: Implement and inject one activation action**

Define:

```swift
struct ExplorerItemActivationAction {
  let perform: (FileItem, ExplorerOpenDisposition) -> Void
}

private struct ExplorerItemActivationKey: EnvironmentKey {
  static let defaultValue = ExplorerItemActivationAction { _, _ in }
}

extension EnvironmentValues {
  var explorerItemActivation: ExplorerItemActivationAction { get set }
}
```

At the tab host, inject an action that awaits the manager. If the result is `.external`, call `NSWorkspace.shared.open`; on failure set the originating model's existing `BrowserAlert`.

Replace each duplicated `activate` implementation in `ContentView`, both table implementations, and `LargeIconGridView` with the environment action. Double-click reads `NSEvent.modifierFlags.contains(.command)`. Return uses `.currentTab`; Command-Return uses `.newTab`. Add **Open in New Tab** to supported context menus.

- [ ] **Step 4: Run tests and build the app**

Run: `./Scripts/test.sh`

Expected: all tests pass.

Run: `./Scripts/build-app.sh`

Expected: release build and ad-hoc signing complete.

- [ ] **Step 5: Commit centralized activation**

```bash
git add Sources/MiniExplorer/ExplorerItemActivation.swift Sources/MiniExplorer/ContentView.swift Sources/MiniExplorer/FileTableView.swift Sources/MiniExplorer/LargeIconGridView.swift Sources/MiniExplorerCore/FileItemInteraction.swift Tests/MiniExplorerCoreTests/InteractionPreferenceTests.swift
git commit -m "Route item opening through tab actions"
```

---

### Task 4: Window Tab Strip and Focused Commands

**Files:**
- Create: `Sources/MiniExplorer/ExplorerTabStrip.swift`
- Modify: `Sources/MiniExplorer/MiniExplorerApp.swift`
- Modify: `Sources/MiniExplorer/FileActionCommands.swift`
- Modify: `Sources/MiniExplorer/ContentView.swift`

**Interfaces:**
- Consumes: `ExplorerTabManager`, `ExplorerTab.title`, and Task 3 activation.
- Produces: visible tab UI plus focused manager/model routing.

- [ ] **Step 1: Add accessibility contracts before UI code**

The tab strip must expose `explorer-tab-strip`; each tab must expose `explorer-tab-<UUID>` and the close button `close-explorer-tab-<UUID>`. Extend the UI smoke script or add an AppKit-hosted check that asserts two distinct tab elements after Command-T.

- [ ] **Step 2: Run the UI check and verify it fails because no tab strip exists**

Run: `./Scripts/build-app.sh`

Expected: build succeeds, while the tab accessibility check cannot find `explorer-tab-strip`.

- [ ] **Step 3: Build the tab host**

Change `MiniExplorerWindow` to own the manager:

```swift
@StateObject private var tabManager: ExplorerTabManager

init(modelFactory: FileBrowserModelFactory) {
  _tabManager = StateObject(
    wrappedValue: ExplorerTabManager(modelFactory: modelFactory)
  )
}
```

Render `ExplorerTabStrip` above a `ZStack` of tab contents. Keep all tab roots mounted; only the active one has opacity `1` and hit testing enabled. Publish both `tabManager` and `tabManager.activeTab?.model` as focused scene objects.

Update commands:

```swift
@FocusedObject private var tabManager: ExplorerTabManager?
@FocusedObject private var model: FileBrowserModel?
```

Add Command-T, Command-W, Control-Tab, Control-Shift-Tab, and Command-Return. Existing file commands continue using the focused active model.

- [ ] **Step 4: Run tests, build, and inspect the tab accessibility tree**

Run: `./Scripts/test.sh`

Expected: all tests pass.

Run: `./Scripts/build-app.sh`

Expected: release build and signing complete; Command-T exposes two tab elements and switching leaves their locations distinct.

- [ ] **Step 5: Commit the tab UI**

```bash
git add Sources/MiniExplorer/ExplorerTabStrip.swift Sources/MiniExplorer/MiniExplorerApp.swift Sources/MiniExplorer/FileActionCommands.swift Sources/MiniExplorer/ContentView.swift
git commit -m "Add the MiniExplorer tab strip"
```

---

### Task 5: Dirty Text Ownership and Protected Replacement

**Files:**
- Modify: `Sources/MiniExplorerCore/ExplorerTab.swift`
- Modify: `Sources/MiniExplorerCore/ExplorerTabManager.swift`
- Modify: `Sources/MiniExplorerCore/PreviewContent.swift`
- Modify: `Sources/MiniExplorer/TextPreviewView.swift`
- Modify: `Sources/MiniExplorer/MiniExplorerApp.swift`
- Create: `Sources/MiniExplorer/WindowCloseGuard.swift`
- Modify: `Tests/MiniExplorerCoreTests/PreviewContentTests.swift`
- Modify: `Tests/MiniExplorerCoreTests/BrowserModelTests.swift`

**Interfaces:**
- Consumes: Task 2 opening and Task 4 close requests.
- Produces: observable tab dirty state and pending Save / Discard / Cancel actions.

- [ ] **Step 1: Write failing dirty-action tests**

Use a real `TextPreviewSession` with the existing fake text service. Assert that a dirty active tab does not close or replace immediately, cancel preserves it, discard completes the operation, save completes only after a successful write, and failed save keeps it open:

```swift
let result = manager.requestClose(tabID: dirtyTab.id)
try expectEqual(result, .needsDirtyDecision)
try expect(manager.tabs.contains { $0.id == dirtyTab.id }, "Dirty tab closed immediately")
await manager.resolvePendingDirtyAction(.cancel)
try expect(manager.tabs.contains { $0.id == dirtyTab.id }, "Cancel discarded the tab")
```

- [ ] **Step 2: Run tests and verify the dirty workflow is absent**

Run: `./Scripts/test.sh`

Expected: FAIL for missing dirty result and resolution APIs.

- [ ] **Step 3: Move text sessions into tab state**

Add:

```swift
public enum DirtyTabDecision: Equatable, Sendable {
  case save
  case discard
  case cancel
}

public extension ExplorerTab {
  var textSession: TextPreviewSession? { get }
  var isDirty: Bool { get }
}

public extension ExplorerTabManager {
  var pendingDirtyTab: ExplorerTab? { get }
  func resolvePendingDirtyAction(_ decision: DirtyTabDecision) async
}
```

`ExplorerTab` creates or reuses the session for its represented text URL. Pass that session into `TextPreviewView`; remove the view's private session construction. Queue close or current-tab replacement when dirty. Save awaits `TextPreviewSession.save()` and checks `isDirty`; discard executes the queued action; cancel clears the queue.

Present a window-level confirmation dialog with Save, Discard, and Cancel. If the final tab closes, call SwiftUI's window dismissal only after the manager returns `.windowShouldClose`. A failed save selects the affected tab and leaves its existing error visible.

Attach `WindowCloseGuard` as an `NSViewRepresentable` background view. Its coordinator adopts `NSWindowDelegate`, preserves and forwards the window's previous delegate, and returns `false` from `windowShouldClose(_:)` while any tab is dirty. It asks the manager to process dirty tabs in tab order; after every tab is clean, saved, or discarded, it calls `window.performClose(nil)`. Cancel or save failure stops the sequence and keeps the affected tab active.

- [ ] **Step 4: Run tests and build the app**

Run: `./Scripts/test.sh`

Expected: all dirty-action and existing tests pass.

Run: `./Scripts/build-app.sh`

Expected: release build and signing complete.

- [ ] **Step 5: Commit dirty-document protection**

```bash
git add Sources/MiniExplorerCore/ExplorerTab.swift Sources/MiniExplorerCore/ExplorerTabManager.swift Sources/MiniExplorerCore/PreviewContent.swift Sources/MiniExplorer/TextPreviewView.swift Sources/MiniExplorer/MiniExplorerApp.swift Sources/MiniExplorer/WindowCloseGuard.swift Tests/MiniExplorerCoreTests/PreviewContentTests.swift Tests/MiniExplorerCoreTests/BrowserModelTests.swift
git commit -m "Protect unsaved text across tab actions"
```

---

### Task 6: Final Verification

**Files:**
- Modify only files required by failures found in this task.

**Interfaces:**
- Consumes: the complete tab subsystem.
- Produces: verified release artifact at `.build/app/MiniExplorer.app`.

- [ ] **Step 1: Run the complete automated test suite**

Run: `./Scripts/test.sh`

Expected: every test prints `PASS` and the command exits 0.

- [ ] **Step 2: Build the packaged release app**

Run: `./Scripts/build-app.sh`

Expected: SwiftPM reports a completed release build, code signing succeeds, and the app path is printed.

- [ ] **Step 3: Check patch hygiene**

Run: `git diff --check`

Expected: no output and exit 0.

- [ ] **Step 4: Run the UI smoke scenario**

Launch the rebuilt app in a fresh process. Open a second tab with Command-T, navigate it to `/tmp`, switch to the first tab, and verify the first remains at the home directory. Open a supported text file in the current tab, Command-open another supported file, switch between them, and verify each title and preview remains stable. Exercise Command-W and Control-Tab.

- [ ] **Step 5: Commit verification fixes if any source changed**

```bash
git add Sources Tests
git commit -m "Polish hybrid tab behavior"
```
