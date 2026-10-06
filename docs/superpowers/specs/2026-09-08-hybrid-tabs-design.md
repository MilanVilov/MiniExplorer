# Hybrid Folder and Preview Tabs

## Goal

Add browser-style tabs inside each MiniExplorer window. A tab may show either a folder or a built-in file preview, and it retains its own navigation, selection, search, view mode, preview, and editing state. Windows remain independent from one another.

Tabs are session-only in this iteration. MiniExplorer will not restore them after relaunch.

## Interaction Model

The tab strip appears above the address bar. Each tab displays an icon, a title, and a close control. A folder tab uses the current folder name as its title. A preview tab uses the file name. A text preview with unsaved changes displays a dirty indicator.

Normal item activation reuses the active tab:

- Opening a folder navigates the active tab to that folder.
- Opening a supported file changes the active tab to its built-in preview while retaining the underlying folder. Escape closes the preview and returns to that folder.
- Opening an unsupported file delegates to the normal macOS application and does not change MiniExplorer tabs.

Holding Command while activating a supported file or folder opens it in a new foreground tab. If any tab in the same window already represents that exact folder or file, MiniExplorer focuses the existing tab instead of creating a duplicate. Duplicate detection uses standardized file URLs. Tabs in other windows do not participate.

Keyboard behavior:

- Command-T creates and selects a new tab at the home directory.
- Command-W closes the active tab.
- Control-Tab selects the next tab, wrapping at the end.
- Control-Shift-Tab selects the previous tab, wrapping at the beginning.
- Closing the final tab closes its window.

Context menus expose **Open in New Tab** for folders and files that MiniExplorer can preview. Normal Return activation reuses the active tab; Command-Return opens in a new tab.

## Architecture

### Window ownership

Each `MiniExplorerWindow` owns one `ExplorerTabManager`. The manager is never shared between windows. Global preferences, including theme and terminal selection, remain app-owned and shared.

The window publishes its active tab and manager through focused-scene values. App menu commands therefore operate on the currently focused window and active tab.

### Tab state

`ExplorerTab` is an identifiable main-actor observable object. It owns:

- A distinct `FileBrowserModel`.
- Stable tab identity.
- Preview editor state for the currently previewed text document.
- Derived title, icon, represented URL, and dirty state.

Every tab starts with a fresh browser model. A home tab starts at the home directory. A new folder tab starts at home and then navigates to the requested folder through the normal model API. A new file tab starts in the file's parent folder and then opens its preview.

The tab manager owns the ordered tabs and active tab identifier. It implements new-tab creation, activation disposition, duplicate focusing, cycling, close requests, and the final-tab close signal.

### Activation routing

Introduce one item-activation route shared by `ContentView`, list views, and the large-icon view. The route accepts the item and an explicit disposition:

- `currentTab`
- `newTab`

Mouse and keyboard handlers translate current modifier flags into a disposition before calling this route. Selection modifiers remain unchanged. This removes the existing duplicated folder/preview/external-open logic from the individual file views.

### View lifetime and editor state

The window keeps each tab's root content alive for the tab's lifetime and displays only the active tab. This preserves scroll position and SwiftUI-owned view state when switching tabs.

Text document state moves to the owning `ExplorerTab` so the tab strip and close workflow can observe whether it is dirty. `TextPreviewView` receives the existing session instead of constructing an inaccessible private session. When the active tab changes to another preview, its old text session is released only after the replacement is allowed by the dirty-document workflow.

## Dirty Document Workflow

Replacing or closing a tab with dirty text presents Save / Discard / Cancel:

- **Save** waits for the existing atomic save operation. The requested replacement or close proceeds only if the session is no longer dirty after saving.
- **Discard** performs the requested replacement or close without writing.
- **Cancel** leaves the tab and active selection unchanged.

Closing a window with multiple dirty tabs is handled one tab at a time. If the user cancels or a save fails, the window stays open and the affected tab becomes active. Markdown's delayed autosave remains in place; an in-flight dirty document still uses the same close guard.

## Error Handling

- Failed folder navigation keeps the tab on its previous folder and uses the existing browser error presentation.
- Failed preview loading keeps the tab open and displays the existing preview error.
- Failed saving keeps the tab open, preserves the dirty text, and displays the existing save error.
- Failure to open an unsupported file through macOS uses the existing browser alert in the originating tab.

No tab operation may silently discard dirty text.

## Testing

Core tests will cover:

- A new window starts with one home tab.
- Normal folder and supported-file activation reuse the active tab.
- New-tab activation creates an independent tab and selects it.
- Matching standardized URLs focus an existing tab instead of duplicating it.
- Switching tabs preserves independent folder, history, selection, search, and preview state.
- Next and previous tab selection wrap.
- Closing selects a deterministic neighboring tab.
- Closing the last tab requests window closure.
- Save, discard, cancel, and failed-save outcomes protect dirty text correctly.
- Command-modified activation selects the new-tab disposition.

Verification also includes the full test suite, a release app build, and a UI smoke test that opens two tabs, navigates them independently, switches between them, and exercises focused commands.

## Out of Scope

- Restoring tabs after relaunch.
- Dragging tabs between windows.
- Reordering tabs by dragging.
- Pinning tabs.
- Split-pane previews.
- Tabs for files that open in external macOS applications.
