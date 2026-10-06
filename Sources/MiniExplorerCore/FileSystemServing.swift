import Foundation

public protocol FileSystemServing: Sendable {
  func mountedVolumes() async throws -> [FileItem]
  func list(_ directory: URL) async throws -> [FileItem]
  func list(_ directory: URL, includesHiddenItems: Bool) async throws -> [FileItem]
  func copy(_ source: URL, into directory: URL) async throws
  func move(_ source: URL, into directory: URL) async throws
  func createFile(named name: String, in directory: URL) async throws -> URL
  func createUniqueFile(named name: String, contents: Data, in directory: URL) async throws -> URL
  func createFolder(named name: String, in directory: URL) async throws -> URL
  func rename(_ source: URL, to newName: String) async throws -> URL
  func duplicate(_ source: URL) async throws -> URL
  func trash(_ source: URL) async throws -> URL?
  func info(for source: URL) async throws -> FileInfo
  func isSameVolume(_ source: URL, _ destination: URL) async throws -> Bool
}

public extension FileSystemServing {
  func list(_ directory: URL, includesHiddenItems: Bool) async throws -> [FileItem] {
    try await list(directory)
  }

  func rename(_ source: URL, to newName: String) async throws -> URL {
    throw CocoaError(.featureUnsupported)
  }

  func createUniqueFile(named name: String, contents: Data, in directory: URL) async throws -> URL {
    throw CocoaError(.featureUnsupported)
  }

  func duplicate(_ source: URL) async throws -> URL {
    throw CocoaError(.featureUnsupported)
  }

  func trash(_ source: URL) async throws -> URL? {
    throw CocoaError(.featureUnsupported)
  }

  func info(for source: URL) async throws -> FileInfo {
    throw CocoaError(.featureUnsupported)
  }
}
