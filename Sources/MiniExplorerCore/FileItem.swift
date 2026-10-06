import Foundation

public struct FileItem: Identifiable, Hashable, Sendable {
  public let url: URL
  public let displayName: String
  public let isDirectory: Bool
  public let isPackage: Bool
  public let isSymbolicLink: Bool
  public let size: Int64?
  public let modificationDate: Date?
  public let isImage: Bool

  public var id: URL { url.standardizedFileURL }
  public var canExpandInSidebar: Bool {
    isDirectory && !isPackage && !isSymbolicLink
  }

  public var usesExplorerFolderIcon: Bool {
    isDirectory && !isPackage
  }

  public init(
    url: URL,
    displayName: String,
    isDirectory: Bool,
    isPackage: Bool,
    isSymbolicLink: Bool,
    size: Int64?,
    modificationDate: Date?,
    isImage: Bool = false
  ) {
    self.url = url
    self.displayName = displayName
    self.isDirectory = isDirectory
    self.isPackage = isPackage
    self.isSymbolicLink = isSymbolicLink
    self.size = size
    self.modificationDate = modificationDate
    self.isImage = isImage
  }
}
