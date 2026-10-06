import Foundation

public enum FileItemDoubleClickAction: Equatable, Sendable {
  case open
  case rename
}

public enum FileItemInteraction {
  public static func doubleClickAction(
    isDirectory _: Bool,
    isPackage _: Bool
  ) -> FileItemDoubleClickAction {
    .open
  }
}

public enum SlowRenameClickAction: Equatable, Sendable {
  case select
  case rename
}

public struct SlowRenameClickTracker<ItemID: Hashable & Sendable>: Sendable {
  private let minimumDelay: TimeInterval
  private let maximumDelay: TimeInterval
  private var previousClick: (itemID: ItemID, timestamp: TimeInterval)?

  public init(minimumDelay: TimeInterval, maximumDelay: TimeInterval) {
    self.minimumDelay = minimumDelay
    self.maximumDelay = maximumDelay
  }

  public mutating func registerClick(
    on itemID: ItemID,
    at timestamp: TimeInterval,
    isOnlySelectedItem: Bool
  ) -> SlowRenameClickAction {
    guard isOnlySelectedItem,
      let previousClick,
      previousClick.itemID == itemID
    else {
      previousClick = (itemID, timestamp)
      return .select
    }

    let delay = timestamp - previousClick.timestamp
    guard delay >= minimumDelay, delay <= maximumDelay else {
      self.previousClick = (itemID, timestamp)
      return .select
    }

    self.previousClick = nil
    return .rename
  }

  public mutating func reset() {
    previousClick = nil
  }
}

public struct RenameNameParts: Equatable, Sendable {
  public let editableName: String
  public let preservedSuffix: String

  public init(displayName: String, isDirectory: Bool, isPackage: Bool) {
    let preservesExtension = !isDirectory || isPackage
    let pathExtension = preservesExtension
      ? URL(fileURLWithPath: displayName).pathExtension
      : ""
    if pathExtension.isEmpty {
      editableName = displayName
      preservedSuffix = ""
    } else {
      editableName = String(displayName.dropLast(pathExtension.count + 1))
      preservedSuffix = ".\(pathExtension)"
    }
  }

  public func completeName(editableName: String) -> String {
    guard !preservedSuffix.isEmpty else { return editableName }
    if editableName.lowercased().hasSuffix(preservedSuffix.lowercased()) {
      return editableName
    }
    return editableName + preservedSuffix
  }
}
