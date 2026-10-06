import Foundation

public enum ClipboardOperation: String, Equatable, Sendable {
  case copy
  case move
}

public struct ClipboardPayload: Equatable, Sendable {
  public let sourceURLs: [URL]
  public let operation: ClipboardOperation

  public init(sourceURLs: [URL], operation: ClipboardOperation) {
    self.sourceURLs = sourceURLs.map(\.standardizedFileURL)
    self.operation = operation
  }
}
