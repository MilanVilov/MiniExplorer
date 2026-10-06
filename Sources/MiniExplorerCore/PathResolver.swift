import Foundation

public enum PathResolutionError: LocalizedError, Sendable {
  case emptyPath
  case relativePathNotSupported

  public var errorDescription: String? {
    switch self {
    case .emptyPath:
      "Enter a folder path."
    case .relativePathNotSupported:
      "Enter an absolute path or a path beginning with ~."
    }
  }
}

public enum PathResolver {
  public static func resolve(
    _ rawPath: String,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) throws -> URL {
    let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty else {
      throw PathResolutionError.emptyPath
    }

    let expandedPath: String
    if path == "~" {
      expandedPath = homeDirectory.path
    } else if path.hasPrefix("~/") {
      expandedPath =
        homeDirectory
        .appendingPathComponent(String(path.dropFirst(2)))
        .path
    } else {
      guard path.hasPrefix("/") else {
        throw PathResolutionError.relativePathNotSupported
      }
      expandedPath = path
    }

    return URL(fileURLWithPath: (expandedPath as NSString).standardizingPath)
      .standardizedFileURL
  }
}
