import Foundation

public struct FolderShortcut: Identifiable, Hashable, Sendable {
  public let url: URL

  public var id: URL { url.standardizedFileURL }

  public var displayName: String {
    url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
  }

  public init(url: URL) {
    self.url = URL(fileURLWithPath: url.path, isDirectory: true).standardizedFileURL
  }
}

public protocol ShortcutStoring: Sendable {
  func loadPaths() async -> [String]
  func savePaths(_ paths: [String]) async
}

public actor UserDefaultsShortcutStore: ShortcutStoring {
  private let defaults: UserDefaults
  private let key: String

  public init(
    defaults: UserDefaults = .standard,
    key: String = "MiniExplorer.folderShortcuts"
  ) {
    self.defaults = defaults
    self.key = key
  }

  public func loadPaths() async -> [String] {
    defaults.stringArray(forKey: key) ?? []
  }

  public func savePaths(_ paths: [String]) async {
    defaults.set(paths, forKey: key)
  }
}
