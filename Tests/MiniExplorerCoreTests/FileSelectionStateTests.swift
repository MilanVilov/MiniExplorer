import CoreGraphics
import Foundation
import MiniExplorerCore

enum FileSelectionStateTests {
  static func runAll() throws {
    try run("Plain selection replaces prior items", plainSelectionReplacesItems)
    try run("Command selection toggles individual items", commandSelectionTogglesItems)
    try run("Shift selection chooses an inclusive visible range", shiftSelectionChoosesRange)
    try run("Select All preserves visible order", selectAllPreservesVisibleOrder)
    try run("Normalization removes hidden items and repairs primary selection", normalizationRepairsSelection)
    try run("Marquee geometry selects every intersecting item in visible order", marqueeSelectsIntersections)
    try run("Command marquee toggles hits against the starting selection", marqueeTogglesBaseline)
  }

  private static func plainSelectionReplacesItems() throws {
    let ids = fixtureIDs()
    var selection = FileSelectionState()
    selection.select(ids[0], modifier: .plain, visibleIDs: ids)
    selection.select(ids[2], modifier: .plain, visibleIDs: ids)
    try expectEqual(selection.selectedIDs, [ids[2]])
    try expectEqual(selection.primaryID, ids[2])
    try expectEqual(selection.anchorID, ids[2])
  }

  private static func commandSelectionTogglesItems() throws {
    let ids = fixtureIDs()
    var selection = FileSelectionState()
    selection.select(ids[0], modifier: .plain, visibleIDs: ids)
    selection.select(ids[2], modifier: .command, visibleIDs: ids)
    try expectEqual(selection.selectedIDs, [ids[0], ids[2]])
    selection.select(ids[0], modifier: .command, visibleIDs: ids)
    try expectEqual(selection.selectedIDs, [ids[2]])
    try expectEqual(selection.primaryID, ids[2])
  }

  private static func shiftSelectionChoosesRange() throws {
    let ids = fixtureIDs()
    var selection = FileSelectionState()
    selection.select(ids[1], modifier: .plain, visibleIDs: ids)
    selection.select(ids[3], modifier: .shift, visibleIDs: ids)
    try expectEqual(selection.selectedIDs, [ids[1], ids[2], ids[3]])
    try expectEqual(selection.primaryID, ids[3])
    try expectEqual(selection.anchorID, ids[1])
  }

  private static func selectAllPreservesVisibleOrder() throws {
    let ids = fixtureIDs()
    var selection = FileSelectionState()
    selection.selectAll([ids[2], ids[0], ids[3]])
    try expectEqual(selection.selectedIDs, [ids[2], ids[0], ids[3]])
    try expectEqual(selection.primaryID, ids[2])
  }

  private static func normalizationRepairsSelection() throws {
    let ids = fixtureIDs()
    var selection = FileSelectionState()
    selection.selectAll(ids)
    selection.select(ids[2], modifier: .plain, visibleIDs: ids)
    selection.select(ids[3], modifier: .command, visibleIDs: ids)
    selection.normalize(visibleIDs: [ids[0], ids[3]])
    try expectEqual(selection.selectedIDs, [ids[3]])
    try expectEqual(selection.primaryID, ids[3])
    try expectEqual(selection.anchorID, ids[3])
  }

  private static func marqueeSelectsIntersections() throws {
    let ids = ["a", "b", "c"]
    let frames = [
      "a": CGRect(x: 10, y: 10, width: 40, height: 40),
      "b": CGRect(x: 70, y: 10, width: 40, height: 40),
      "c": CGRect(x: 130, y: 10, width: 40, height: 40),
    ]
    let rectangle = MarqueeSelection.rectangle(
      from: CGPoint(x: 120, y: 60),
      to: CGPoint(x: 45, y: 5)
    )

    try expectEqual(
      MarqueeSelection.intersectingIDs(
        visibleIDs: ids,
        frames: frames,
        rectangle: rectangle
      ),
      ["a", "b"]
    )
  }

  private static func marqueeTogglesBaseline() throws {
    try expectEqual(
      MarqueeSelection.resolvedIDs(
        baseline: ["a", "b"],
        hits: ["b", "c"],
        togglesBaseline: true,
        visibleIDs: ["a", "b", "c", "d"]
      ),
      ["a", "c"]
    )
    try expectEqual(
      MarqueeSelection.resolvedIDs(
        baseline: ["a"],
        hits: ["c", "b"],
        togglesBaseline: false,
        visibleIDs: ["a", "b", "c", "d"]
      ),
      ["b", "c"]
    )
  }

  private static func fixtureIDs() -> [URL] {
    ["a", "b", "c", "d"].map {
      URL(fileURLWithPath: "/tmp/mini-explorer-selection/\($0)").standardizedFileURL
    }
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
      throw SelectionTestFailure(
        "Expected \(String(describing: expected)), got \(String(describing: actual))",
        file: file,
        line: line
      )
    }
  }
}

private struct SelectionTestFailure: Error, CustomStringConvertible {
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
