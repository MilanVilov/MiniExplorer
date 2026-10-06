# Theme, Creation Menu, and App Icon Design QA

- Source visual truth: `/Users/m.vilov/projects/MiniExplorer/design-qa-artifacts/reference-tokyo-night.png`
- Final Tokyo Night screenshot: `/Users/m.vilov/projects/MiniExplorer/design-qa-artifacts/implementation-tokyo-final.jpeg`
- Retro Craft screenshot: `/Users/m.vilov/projects/MiniExplorer/design-qa-artifacts/implementation-retro-craft.jpeg`
- New File dialog screenshot: `/Users/m.vilov/projects/MiniExplorer/design-qa-artifacts/implementation-new-file-dialog.jpeg`
- Created-file state: `/Users/m.vilov/projects/MiniExplorer/design-qa-artifacts/implementation-created-file.jpeg`
- Combined comparison: `/Users/m.vilov/projects/MiniExplorer/design-qa-artifacts/comparison-tokyo-final.png`
- Viewport: MiniExplorer window at 1224 × 768 points/pixels in the Computer Use capture.
- Dimensions and normalization: source 2560 × 1440 px; implementation 1224 × 768 px. The 16:9 source was proportionally normalized to 1365 × 768 px and placed beside the unchanged implementation. The source depicts a complete Linux desktop rather than only a file explorer, so comparison targets its application palette, icon treatment, density, and framing rather than desktop wallpaper or window geometry.
- State: Tokyo Night list view at the home directory. Additional states cover Retro Craft, the empty-folder context menu, themed New File dialog, and the newly created selected row.
- Murmur icon source: `/Users/m.vilov/projects/MiniExplorer/Resources/AppIconAssets/MiniExplorerLogo-murmur-generated.png`
- Active 1024 px icon: `/Users/m.vilov/projects/MiniExplorer/Resources/AppIcon.png`
- Small-size proof: `/Users/m.vilov/projects/MiniExplorer/Resources/AppIconAssets/MurmurIcon.iconset/icon_32x32.png`

## Full-view comparison evidence

The combined comparison shows matching near-black indigo surfaces, violet/lavender folder accents, cool blue focus structure, muted lavender text, compact monospaced density, square controls, and a thin electric-blue application frame. The title strip containing “MiniExplorer” is absent.

## Focused-region evidence

The 460 × 206 New File capture verifies the complete dialog at readable scale: blocky Retro Craft typography, square two-pixel borders, extension guidance, selected default filename, and clear Cancel/Create actions. The created-file capture verifies the resulting zero-byte row and green selected state. No additional Tokyo crop was needed because toolbar, folders, file rows, borders, text, and window edge remain readable in the original 2589 × 768 combined comparison.

## Required fidelity surfaces

- Fonts and typography: Tokyo Night uses compact regular monospaced UI text like the terminal-heavy reference. Retro Craft increases weight and uses uppercase action labels for a blockier game-interface feel. Labels truncate without layout breakage.
- Spacing and layout rhythm: both themes retain dense 29-point rows and compact toolbars. Tokyo uses thin neon structure; Retro Craft uses square two-pixel controls, a thicker selection edge, and no curves, materials, or elevation.
- Colors and visual tokens: Tokyo uses deep indigo, blue, cyan-adjacent structure, lavender text, and purple folders. Retro Craft uses night-forest green, dirt brown, near-black outlines, grass selection, wheat text, and ochre pixel folders.
- Image and asset fidelity: native file artwork remains intact. Tokyo and Retro folder icons use app-owned theme-aware shapes; Retro uses a rectilinear pixel silhouette. No wallpaper or unrelated desktop imagery was copied into the explorer.
- Copy and content: theme names are “Tokyo Night” and “Retro Craft.” New File copy explains that the extension belongs in the name and accurately names the destination folder.
- Murmur default and icon: first launch and invalid saved identifiers resolve to Murmur Flat. The icon uses a charcoal field, ochre folder, cream document, and turquoise path mark; its uncluttered silhouette remains legible at 32 px.
- New Folder: both list and large-icon empty-space menus place New Folder beside New File. The shared themed dialog defaults to `untitled folder`; the service prevents conflicts and path traversal, then refreshes and selects the created directory.

## Findings

No actionable P0, P1, or P2 findings remain. The macOS traffic-light controls remain for close/minimize/full-screen functionality, but the separate native title label and title strip requested by the user are removed.

## Comparison history

1. Initial Tokyo pass: P2 — palette and purple folders matched, but the source's defining electric-blue application frame was understated.
2. Fix: added a theme-specific two-pixel blue frame around the complete Tokyo Night explorer surface.
3. Post-fix evidence: `implementation-tokyo-final.jpeg` and `comparison-tokyo-final.png` show the stronger reference-aligned edge with no remaining P0/P1/P2 mismatch.

## Interaction checks

- Confirmed View → Theme lists Classic Explorer, Murmur Flat, Tokyo Night, and Retro Craft.
- Switched into both new themes and visually inspected their complete list states.
- Confirmed the title text/strip is absent while window controls remain operational.
- Right-clicked empty space in a disposable empty directory and confirmed New File is available.
- Confirmed New Folder is wired into the same empty-space menus in list and large-icon modes.
- Opened the themed New File dialog, entered `qa-created.md`, created it, and confirmed an empty selected row appeared.
- Verified the disposable file was exactly zero bytes.
- Automated tests cover theme fallback, file/folder success, conflict protection, path-traversal rejection, list refresh, and selection.

## Daily file operations extension

- Live evidence: `/Users/m.vilov/projects/MiniExplorer/design-qa-artifacts/implementation-multi-selection.jpeg`
- Live evidence: `/Users/m.vilov/projects/MiniExplorer/design-qa-artifacts/implementation-clipboard-history.jpeg`
- Shift-click and Command-click use one ordered selection model in list and large-icon modes; the primary item receives the stronger accent edge.
- Command-C, Command-X, Command-V, and Command-A are routed through MiniExplorer when a file view is active and through native text editing when a text field is focused.
- Clipboard History is a flat themed session sheet with newest-first Copy/Cut entries, activation, and Clear.
- Selected-item menus expose Rename, Duplicate, Move to Trash, and Get Info. Rename and Get Info use flat themed sheets; Trash requires confirmation and uses macOS Trash.
- Internal multi-item drops move the complete selection into list, icon, and sidebar folder targets and refresh the displayed source folder. External drops remain copies.
- Show Hidden Files is session-only and available from View and empty-space menus.
- Search Up/Down wraps through filtered results; Enter navigates, previews, or opens the primary result.
- Automated coverage includes ordered multi-selection, batch clipboard/history, safe filesystem operations, batch action orchestration, drop refresh, and search keyboard traversal.

### Live interaction verification

- Restarted the installed `/Applications/MiniExplorer.app` so the inspection exercised the current signed binary rather than the previously running process.
- Confirmed the selected-item context menu exposes Open With, Copy, Cut, Rename, Duplicate, Move to Trash, Get Info, and Paste. Trash was not confirmed during QA.
- Renamed disposable `alpha.txt` to `alpha-renamed.txt` and confirmed the refreshed row.
- Confirmed Command-A selects all five visible entries after a row click, and Command-C records all five in the session clipboard history.
- Confirmed Command-C followed by Command-V copied `beta.txt` into the disposable `Target` folder.
- Confirmed the empty-space menu exposes New Folder, New File, Paste, Clipboard History, Refresh, Save Current Folder as Shortcut, Show Hidden Files, and view switching with unavailable actions disabled.
- Confirmed search filters the view to the two matching names, Down selects the first match, Enter opens the built-in text preview, and Escape closes it.
- The Computer Use harness' instantaneous synthetic drag did not initiate an AppKit drag session in either view. The tap recognizers were changed to simultaneous gestures so they no longer suppress the app's drag recognizers; transfer semantics and multi-item source refresh remain covered by automated tests.

## Follow-up polish

- P3: Retro Craft intentionally uses the system monospaced font rather than bundling a third-party Minecraft-like font, preserving licensing simplicity and crisp native rendering.

final result: passed

---

# MiniWriter Obsidian theme QA

## Evidence

- Source visual truth: `/Users/m.vilov/projects/MiniExplorer/design-qa-artifacts/implementation-markdown.jpeg`
- Final dark implementation: `/Users/m.vilov/projects/MiniExplorer/design-qa-artifacts/miniwriter-dark-final.png`
- Final light implementation: `/Users/m.vilov/projects/MiniExplorer/design-qa-artifacts/miniwriter-light-final.png`
- Combined dark comparison: `/Users/m.vilov/projects/MiniExplorer/design-qa-artifacts/miniwriter-comparison-dark.png`
- Viewport: 1040 × 680 CSS pixels at device density 1.
- Dimensions and normalization: source 1040 × 680 px; implementation 1040 × 680 px. No density normalization was needed. The combined comparison places the images side by side without scaling either half.
- State: focused Markdown reading surface with the navigation sidebar visible. Dark and light appearances were both captured; the MiniExplorer source provides the dark visual truth.

## Full-view comparison evidence

The final dark capture preserves MiniExplorer's blue-charcoal canvas, warm sand prose, centered writing column, 18-pixel monospaced rhythm, bold heading hierarchy, teal links, gold structural markers, flat sidebar, and hairline separators. The source is a native editor while the implementation fixture represents Obsidian's Reading view, so their application toolbars and note content intentionally differ.

The light capture keeps the same dimensions and hierarchy while translating the palette to warm paper, dark ink, teal links, ochre structure, and restrained aqua selection.

## Focused-region evidence

No separate crop was needed: the 1040 × 680 captures keep headings, body copy, italics, bold text, links, blockquotes, lists, sidebar selection, border treatment, and the appearance control readable at their rendered size.

## Required fidelity surfaces

- Fonts and typography: four embedded iA Writer Mono S faces render correctly. Body text is 18px at 1.7 line height; headings match MiniExplorer's 30/24/21/18px scale and use real bold and italic faces rather than synthesized styles.
- Spacing and layout rhythm: the writing surface caps at 780px and also preserves MiniExplorer's 48px side gutters in narrower panes. The corrected dark capture aligns the first prose column closely with the source.
- Colors and visual tokens: dark values are derived directly from MiniExplorer's Murmur palette. The light mode uses warm-paper equivalents with readable ink, teal links, ochre structure, and visible focus states.
- Image quality and asset fidelity: the visual target contains no app-owned raster illustrations or non-standard icons to reproduce. The embedded font binaries retain their original TrueType data.
- Copy and content: sample copy exists only in `preview.html`; the shipped CSS does not inject or alter vault content. Theme metadata and installation instructions consistently use the name “MiniWriter.”

## Findings

No actionable P0, P1, or P2 findings remain. Browser console inspection returned no warnings or errors in either appearance.

## Comparison history

1. Initial pass: P2 — the 780px column filled nearly the complete note pane, putting prose too close to the sidebar compared with MiniExplorer's consistent 48px editor gutters.
2. Fix: applied `width: calc(100% - 96px)` alongside the 780px cap, with a full-width mobile override below 700px.
3. Post-fix evidence: `miniwriter-dark-final.png` and `miniwriter-comparison-dark.png` show the corrected left inset and source-aligned content density.

## Interaction checks

- Loaded all four embedded font faces from the self-contained theme stylesheet.
- Switched from Murmur dark to Warm Paper light using the preview control and confirmed the root appearance class changed.
- Confirmed the dark and light states render without browser console warnings or errors.
- Confirmed the responsive rule restores full width and smaller padding below the 700px breakpoint in the stylesheet contract.

## Follow-up polish

- P3: a live Obsidian vault may expose plugin-specific surfaces not represented by the core theme preview; those plugins will inherit the supplied Obsidian color and typography variables but may require their own selectors.

final result: passed
