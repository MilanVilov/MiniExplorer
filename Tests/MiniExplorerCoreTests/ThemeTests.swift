import Foundation
import MiniExplorerCore

enum ThemeTests {
  @MainActor
  static func runAll() throws {
    try run("Theme defaults to Murmur Flat", defaultsToMurmur)
    try run("Theme restores the saved Murmur choice", restoresSavedTheme)
    try run("Theme changes persist immediately", selectionPersists)
    try run("Tokyo Night restores from persisted settings", restoresTokyoNight)
    try run("Retro Craft restores from persisted settings", restoresRetroCraft)
    try run("Unknown saved themes fall back to Murmur Flat", invalidValueFallsBack)
  }

  @MainActor
  private static func defaultsToMurmur() throws {
    let controller = ExplorerThemeController(store: MemoryThemeStore())
    try expectEqual(controller.selection, .murmurFlat)
  }

  @MainActor
  private static func restoresSavedTheme() throws {
    let controller = ExplorerThemeController(
      store: MemoryThemeStore(value: ExplorerThemeID.murmurFlat.rawValue)
    )
    try expectEqual(controller.selection, .murmurFlat)
  }

  @MainActor
  private static func selectionPersists() throws {
    let store = MemoryThemeStore()
    let controller = ExplorerThemeController(store: store)

    controller.select(.murmurFlat)

    try expectEqual(controller.selection, .murmurFlat)
    try expectEqual(store.value, ExplorerThemeID.murmurFlat.rawValue)
  }

  @MainActor
  private static func restoresTokyoNight() throws {
    let controller = ExplorerThemeController(
      store: MemoryThemeStore(value: ExplorerThemeID.tokyoNight.rawValue)
    )
    try expectEqual(controller.selection, .tokyoNight)
  }

  @MainActor
  private static func restoresRetroCraft() throws {
    let controller = ExplorerThemeController(
      store: MemoryThemeStore(value: ExplorerThemeID.retroCraft.rawValue)
    )
    try expectEqual(controller.selection, .retroCraft)
  }

  @MainActor
  private static func invalidValueFallsBack() throws {
    let controller = ExplorerThemeController(store: MemoryThemeStore(value: "glossy-aqua"))
    try expectEqual(controller.selection, .murmurFlat)
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
      throw ThemeTestFailure(
        "Expected \(String(describing: expected)), got \(String(describing: actual))",
        file: file,
        line: line
      )
    }
  }
}

private final class MemoryThemeStore: ThemeStoring {
  var value: String?

  init(value: String? = nil) {
    self.value = value
  }

  func loadThemeIdentifier() -> String? {
    value
  }

  func saveThemeIdentifier(_ identifier: String) {
    value = identifier
  }
}

private struct ThemeTestFailure: Error, CustomStringConvertible {
  let message: String
  let file: StaticString
  let line: UInt

  init(_ message: String, file: StaticString, line: UInt) {
    self.message = message
    self.file = file
    self.line = line
  }

  var description: String {
    "\(file):\(line): \(message)"
  }
}
