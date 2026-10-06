# MiniExplorer Daily File Operations Design

## Goal

Add dependable daily file-management interactions to MiniExplorer while preserving its flat themed interface. The change covers multi-selection, batch clipboard operations, session clipboard history, reliable drag and drop, rename, duplicate, Trash, Get Info, hidden-file visibility, and keyboard navigation of current-folder search results. Undo remains out of scope.

## Interaction Model

MiniExplorer will use an ordered multi-selection rather than a single selected URL.

- A plain click selects only that item and makes it primary.
- Command-click toggles one item without discarding the other selected items.
- Shift-click selects the inclusive visible range between the selection anchor and clicked item.
- Command-A selects all currently visible items, including only current search results when filtering.
- The primary item receives the strongest accent treatment. All other selected items receive the normal themed selection background.
- Navigation, sorting, filtering, refresh, rename, move, and deletion normalize selection so it never contains invisible or missing items.
- Rename, preview, Open With, and ordinary activation require one compatible primary item. Batch-capable actions operate on the full selection.

The selection rules apply consistently to both the flat list and large-icon views. The classic table uses the same model-backed selected ID set.

## Clipboard and Clipboard History

`ClipboardPayload` will contain an ordered array of source URLs and an operation of copy or move. Command-C and Command-X capture the current selection. Command-V pastes the active payload into the displayed folder.

The app-local clipboard remains intentionally separate from Finder's clipboard. Its command definitions replace conflicting default pasteboard commands so the shortcuts reach MiniExplorer reliably when a file view is active. Text fields retain native editing shortcuts through focused-value routing.

Every copy or cut adds a clipboard-history entry. History is session-only, newest first, limited to 20 entries, and resets when the app exits. Identical consecutive entries are deduplicated. Missing source URLs are removed when history is displayed or activated. Users can:

- inspect history from the Edit menu and the empty-space context menu;
- activate a history entry and paste it into the displayed folder;
- clear the current session history.

A successful move removes moved URLs from the active payload and history entries. A successful copy remains reusable. Failed URLs remain available for retry.

## Drag and Drop

Dragging a selected item creates a multi-file drag containing the complete ordered selection. Dragging an unselected item first replaces selection with that item. The drag advertises standard file URLs so other macOS applications can accept it.

Drops on a real folder row, grid tile, or sidebar tree node target that folder. Internal same-volume drops move items; cross-volume and external drops copy them. Drops on explorer background target the displayed folder. Packages and symlinks are not treated as expandable folder targets.

After a drop, MiniExplorer refreshes the displayed source directory even when the destination is another folder. If the destination is displayed, it refreshes that listing as well. This prevents a successful move from appearing to have failed. The model rejects moving a folder into itself or a descendant and never overwrites existing items.

## File Operations

### Rename

Rename is available for exactly one selected item through its context menu and the File/Edit command surface. A flat themed dialog starts with the current name selected while preserving the extension for files when practical. Names are trimmed and reject emptiness, dot traversal, slashes, null bytes, and conflicts. Success refreshes the folder and selects the renamed URL.

### Duplicate

Duplicate supports all selected items in their current folder. It chooses the first available safe name using `name copy`, `name copy 2`, and subsequent numeric suffixes while preserving a file extension. Directories and packages duplicate recursively through FileManager. Created copies become selected.

### Move to Trash

Delete and the selected-item context menu invoke Move to Trash. A confirmation dialog names one item or gives the selected-item count. The implementation uses FileManager's Trash operation and never permanently deletes. Successful items disappear after refresh. Failed items remain selected, and failures are summarized.

### Get Info

Get Info presents a theme-aware sheet. One item shows name, absolute path, kind, size, created/modified dates, and relevant package/symlink flags. Multiple items show item count, folder/file counts, aggregate known size, and their common parent path. The sheet performs no mutation.

### Hidden Files

View > Show Hidden Files and Command-Shift-Period toggle hidden items. The setting is session-only. Directory enumeration accepts an `includesHiddenItems` flag rather than applying `.skipsHiddenFiles` unconditionally. Toggling refreshes the current directory and sidebar children, then normalizes selection.

## Search Keyboard Navigation

Current-folder search remains a filename filter. While its field is focused:

- Down selects the next visible match, wrapping from last to first.
- Up selects the previous visible match, wrapping from first to last.
- Enter activates the primary result: navigate into folders, open built-in previews for supported files, or open other files through NSWorkspace.
- Shift and Command selection behavior remains available after focus returns to the results view.

No matches leaves selection empty. Changing a query retains the primary item only when it is still visible; otherwise the first arrow key chooses the appropriate boundary result.

## Architecture

### Core Types

- `FileSelectionState`: ordered selected URL identities, primary ID, range anchor, click-modifier transitions, Select All, and normalization against visible items.
- `ClipboardPayload`: ordered source URLs and copy/move operation.
- `ClipboardHistoryEntry`: session identity, payload, and capture timestamp.
- `FileOperationFailure`: source URL and user-facing reason for partial batch reporting.
- `FileInfo`: metadata required by the Get Info sheet.

### Services

`FileSystemServing` gains injectable operations for listing with hidden-file policy, rename, duplicate, Trash, and metadata. Existing copy and move operations remain the primitive per-item boundaries used by batch orchestration. `LocalFileSystemService` performs validated FileManager operations. Tests use temporary directories and controlled fakes; personal files are never mutated by automated tests.

### Model

`FileBrowserModel` owns selection state, active clipboard, session history, hidden-file state, and batch-operation progress. It coordinates operations sequentially for deterministic results, refreshes once after a batch, retains failed items, updates history after partial moves, and produces one concise alert rather than one alert per item.

### Views and AppKit Integration

SwiftUI continues to own layout, themes, dialogs, sheets, and menus. Small AppKit-backed helpers provide modifier-aware click events, dependable keyboard routing when file views are focused, and multi-URL drag providers. This avoids rebuilding the application with NSTableView while addressing the reliability gaps in pure SwiftUI gesture and command routing.

## Error Handling and Safety

- No operation overwrites an existing destination.
- Folder self/descendant validation applies to paste and drag batches.
- Operations process selected URLs in visible order.
- Partial success is retained; successful work is not rolled back.
- Failed URLs remain selected and, for cut operations, remain in the active clipboard.
- Missing clipboard-history sources are pruned rather than reported repeatedly.
- Trash is recoverable through macOS; MiniExplorer offers no permanent delete action.
- Rename is disabled for multi-selection.
- Batch activation and Open With are disabled unless exactly one compatible item is primary.

## Testing and Acceptance

Automated tests will verify:

- plain, Command-toggle, Shift-range, and Select All transitions;
- selection normalization across search, sorting, refresh, rename, move, and deletion;
- multi-item copy, cut, paste, partial failure, and clipboard retention;
- session clipboard-history ordering, deduplication, maximum size, activation, clearing, successful-move updates, and stale-source pruning;
- internal same-volume moves, external/cross-volume copies, target routing, self-descendant rejection, and source refresh;
- rename validation, conflict refusal, refresh, and retained selection;
- duplicate naming and multi-item results;
- recoverable Trash behavior through temporary fixtures and partial-failure reporting;
- single and aggregate Get Info metadata;
- hidden-file listing and toggle refresh;
- search Up/Down wrapping and Enter activation requests;
- correct context-menu and command enablement for zero, one, and multiple selections.

Completion requires the full core test harness to pass, a release application build and signature to verify, installation into `/Applications`, and live inspection of both list and large-icon modes under the Murmur theme.

## Deferred

Undo, permanent deletion, Finder clipboard interoperability, arbitrary manual icon positioning, tabs, recursive content search, and background transfer progress remain outside this change.
