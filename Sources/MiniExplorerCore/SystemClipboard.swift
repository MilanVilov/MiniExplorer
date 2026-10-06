import Foundation

public enum SystemClipboardContent: Equatable, Sendable {
  case files([URL])
  case text(String)
  case binary(data: Data, preferredFilename: String)
}

public struct SystemClipboardSnapshot: Equatable, Sendable {
  public let changeCount: Int
  public let content: SystemClipboardContent

  public init(changeCount: Int, content: SystemClipboardContent) {
    self.changeCount = changeCount
    self.content = content
  }
}

@MainActor
public protocol SystemClipboardServing: AnyObject {
  var changeCount: Int { get }
  func readSnapshot() -> SystemClipboardSnapshot?
  @discardableResult func writeFileURLs(_ urls: [URL]) -> Int
}
