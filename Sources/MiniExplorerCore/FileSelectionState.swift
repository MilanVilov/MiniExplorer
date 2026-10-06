import Foundation

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
      if selected.contains(id) {
        selected.remove(id)
      } else {
        selected.insert(id)
      }
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

  public mutating func clear() {
    self = FileSelectionState()
  }

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
