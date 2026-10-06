import Foundation

public struct FileInfo: Equatable, Sendable {
  public let url: URL
  public let kind: String
  public let size: Int64?
  public let creationDate: Date?
  public let modificationDate: Date?
  public let isDirectory: Bool
  public let isPackage: Bool
  public let isSymbolicLink: Bool

  public init(
    url: URL,
    kind: String,
    size: Int64?,
    creationDate: Date?,
    modificationDate: Date?,
    isDirectory: Bool,
    isPackage: Bool,
    isSymbolicLink: Bool
  ) {
    self.url = url.standardizedFileURL
    self.kind = kind
    self.size = size
    self.creationDate = creationDate
    self.modificationDate = modificationDate
    self.isDirectory = isDirectory
    self.isPackage = isPackage
    self.isSymbolicLink = isSymbolicLink
  }
}
