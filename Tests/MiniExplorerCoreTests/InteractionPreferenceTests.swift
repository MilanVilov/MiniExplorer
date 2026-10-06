import Foundation
import MiniExplorerCore

enum InteractionPreferenceTests {
  static func runAll() throws {
    try run("Quick double-click opens files, folders, and packages", doubleClickRouting)
    try run("A delayed second click on the sole selection starts Rename", delayedSecondClickRenames)
    try run("Rapid, stale, changed, and multi-selected clicks do not rename", unsafeClickSequencesDoNotRename)
    try run("Rename keeps file extensions outside the editable name", renamePreservesExtensions)
    try run("Rename leaves folders and extensionless dotfiles fully editable", renameHandlesSpecialNames)
    try run("Terminal preference restores a valid saved application", restoresTerminalPreference)
    try run("Terminal preference falls back from Ghostty to Apple Terminal", fallsBackToInstalledTerminal)
    try run("Terminal preference persists its bundle identifier", persistsTerminalPreference)
  }

  private static func doubleClickRouting() throws {
    try expectEqual(
      FileItemInteraction.doubleClickAction(isDirectory: false, isPackage: false),
      .open
    )
    try expectEqual(
      FileItemInteraction.doubleClickAction(isDirectory: true, isPackage: false),
      .open
    )
    try expectEqual(
      FileItemInteraction.doubleClickAction(isDirectory: true, isPackage: true),
      .open
    )
  }

  private static func delayedSecondClickRenames() throws {
    var tracker = SlowRenameClickTracker<String>(
      minimumDelay: 0.5,
      maximumDelay: 1.5
    )

    try expectEqual(
      tracker.registerClick(on: "report.pdf", at: 10, isOnlySelectedItem: false),
      .select
    )
    try expectEqual(
      tracker.registerClick(on: "report.pdf", at: 10.7, isOnlySelectedItem: true),
      .rename
    )
  }

  private static func unsafeClickSequencesDoNotRename() throws {
    var tracker = SlowRenameClickTracker<String>(
      minimumDelay: 0.5,
      maximumDelay: 1.5
    )

    _ = tracker.registerClick(on: "report.pdf", at: 10, isOnlySelectedItem: false)
    try expectEqual(
      tracker.registerClick(on: "report.pdf", at: 10.2, isOnlySelectedItem: true),
      .select
    )
    try expectEqual(
      tracker.registerClick(on: "report.pdf", at: 12, isOnlySelectedItem: true),
      .select
    )
    try expectEqual(
      tracker.registerClick(on: "other.txt", at: 12.7, isOnlySelectedItem: true),
      .select
    )
    try expectEqual(
      tracker.registerClick(on: "other.txt", at: 13.4, isOnlySelectedItem: false),
      .select
    )
  }

  private static func renamePreservesExtensions() throws {
    let parts = RenameNameParts(
      displayName: "report.final.pdf",
      isDirectory: false,
      isPackage: false
    )

    try expectEqual(parts.editableName, "report.final")
    try expectEqual(parts.preservedSuffix, ".pdf")
    try expectEqual(parts.completeName(editableName: "summary"), "summary.pdf")
    try expectEqual(parts.completeName(editableName: "summary.pdf"), "summary.pdf")
  }

  private static func renameHandlesSpecialNames() throws {
    let folder = RenameNameParts(
      displayName: "folder.with.dots",
      isDirectory: true,
      isPackage: false
    )
    let dotfile = RenameNameParts(
      displayName: ".gitignore",
      isDirectory: false,
      isPackage: false
    )

    try expectEqual(folder.editableName, "folder.with.dots")
    try expectEqual(folder.preservedSuffix, "")
    try expectEqual(dotfile.editableName, ".gitignore")
    try expectEqual(dotfile.preservedSuffix, "")
  }

  private static func restoresTerminalPreference() throws {
    try expectEqual(
      TerminalPreferenceResolver.resolve(
        savedBundleIdentifier: "com.googlecode.iterm2",
        availableBundleIdentifiers: [
          "com.apple.Terminal",
          "com.googlecode.iterm2",
          "com.mitchellh.ghostty",
        ]
      ),
      "com.googlecode.iterm2"
    )
  }

  private static func fallsBackToInstalledTerminal() throws {
    try expectEqual(
      TerminalPreferenceResolver.resolve(
        savedBundleIdentifier: "missing.terminal",
        availableBundleIdentifiers: ["com.apple.Terminal", "com.mitchellh.ghostty"]
      ),
      "com.mitchellh.ghostty"
    )
    try expectEqual(
      TerminalPreferenceResolver.resolve(
        savedBundleIdentifier: nil,
        availableBundleIdentifiers: ["com.apple.Terminal"]
      ),
      "com.apple.Terminal"
    )
  }

  private static func persistsTerminalPreference() throws {
    let suiteName = "MiniExplorer.TerminalPreferenceTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw InteractionTestFailure("Could not create isolated UserDefaults")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsTerminalPreferenceStore(defaults: defaults)

    store.saveTerminalBundleIdentifier("dev.warp.Warp-Stable")

    try expectEqual(store.loadTerminalBundleIdentifier(), "dev.warp.Warp-Stable")
  }

  private static func run(_ name: String, _ test: () throws -> Void) throws {
    try test()
    print("PASS: \(name)")
  }

  private static func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    guard actual == expected else {
      throw InteractionTestFailure(
        "Expected \(String(describing: expected)), got \(String(describing: actual))",
        file: file,
        line: line
      )
    }
  }
}

private struct InteractionTestFailure: Error, CustomStringConvertible {
  let message: String
  let file: StaticString
  let line: UInt

  init(
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    self.message = message
    self.file = file
    self.line = line
  }

  var description: String { "\(file):\(line): \(message)" }
}
