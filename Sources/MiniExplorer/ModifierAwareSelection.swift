import AppKit
import MiniExplorerCore

@MainActor
func currentFileSelectionModifier() -> FileSelectionModifier {
  let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
  if flags.contains(.shift) { return .shift }
  if flags.contains(.command) { return .command }
  return .plain
}
