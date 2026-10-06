import Foundation
import UniformTypeIdentifiers

public actor LocalFileSystemService: FileSystemServing {
  private let fileManager: FileManager
  private let mountedVolumeProvider: @Sendable () -> [URL]
  private let trashHandler: @Sendable (URL) throws -> URL?

  public init(
    fileManager: FileManager = .default,
    mountedVolumeProvider: @escaping @Sendable () -> [URL] = {
      FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: [.volumeNameKey],
        options: [.skipHiddenVolumes]
      ) ?? []
    },
    trashHandler: @escaping @Sendable (URL) throws -> URL? = { url in
      var resultingURL: NSURL?
      try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
      return resultingURL as URL?
    }
  ) {
    self.fileManager = fileManager
    self.mountedVolumeProvider = mountedVolumeProvider
    self.trashHandler = trashHandler
  }

  public func mountedVolumes() async throws -> [FileItem] {
    let keys: Set<URLResourceKey> = [.volumeNameKey, .contentModificationDateKey]
    let items = try mountedVolumeProvider().map { url in
      let values = try url.resourceValues(forKeys: keys)
      let displayName: String
      if url.standardizedFileURL.path == "/" {
        displayName = values.volumeName ?? "Macintosh HD"
      } else {
        displayName = url.lastPathComponent
      }
      return FileItem(
        url: url,
        displayName: displayName,
        isDirectory: true,
        isPackage: false,
        isSymbolicLink: false,
        size: nil,
        modificationDate: values.contentModificationDate
      )
    }
    return items.sorted {
      $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
    }
  }

  public func list(_ directory: URL) async throws -> [FileItem] {
    try await list(directory, includesHiddenItems: false)
  }

  public func list(_ directory: URL, includesHiddenItems: Bool) async throws -> [FileItem] {
    let keys: Set<URLResourceKey> = [
      .contentModificationDateKey,
      .fileSizeKey,
      .isDirectoryKey,
      .isPackageKey,
      .isSymbolicLinkKey,
    ]
    let urls = try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: Array(keys),
      options: includesHiddenItems ? [] : [.skipsHiddenFiles]
    )

    let items = try urls.map { url in
      let values = try url.resourceValues(forKeys: keys)
      return FileItem(
        url: url,
        displayName: url.lastPathComponent,
        isDirectory: values.isDirectory ?? false,
        isPackage: values.isPackage ?? false,
        isSymbolicLink: values.isSymbolicLink ?? false,
        size: values.fileSize.map(Int64.init),
        modificationDate: values.contentModificationDate,
        isImage: isImageFile(url)
      )
    }

    return items.sorted { lhs, rhs in
      let lhsIsFolder = lhs.isDirectory && !lhs.isPackage
      let rhsIsFolder = rhs.isDirectory && !rhs.isPackage
      if lhsIsFolder != rhsIsFolder {
        return lhsIsFolder
      }
      return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }
  }

  public func copy(_ source: URL, into directory: URL) async throws {
    let destination = try validatedDestination(for: source, in: directory)
    try fileManager.copyItem(at: source, to: destination)
  }

  public func move(_ source: URL, into directory: URL) async throws {
    let destination = try validatedDestination(for: source, in: directory)
    try fileManager.moveItem(at: source, to: destination)
  }

  public func createFile(named name: String, in directory: URL) async throws -> URL {
    let destination = try validatedNewItemDestination(named: name, in: directory)
    try Data().write(to: destination, options: .withoutOverwriting)
    return destination
  }

  public func createUniqueFile(
    named name: String,
    contents: Data,
    in directory: URL
  ) async throws -> URL {
    let cleanedName = try validatedLeafName(name)
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw FileSystemError.destinationNotDirectory(directory)
    }

    let nameURL = URL(fileURLWithPath: cleanedName)
    let pathExtension = nameURL.pathExtension
    let baseName = pathExtension.isEmpty
      ? cleanedName
      : nameURL.deletingPathExtension().lastPathComponent
    var number = 1
    while true {
      let leafName: String
      if number == 1 {
        leafName = cleanedName
      } else if pathExtension.isEmpty {
        leafName = "\(baseName) \(number)"
      } else {
        leafName = "\(baseName) \(number).\(pathExtension)"
      }
      let destination = directory.appendingPathComponent(leafName).standardizedFileURL
      if !fileManager.fileExists(atPath: destination.path) {
        try contents.write(to: destination, options: .withoutOverwriting)
        return destination
      }
      number += 1
    }
  }

  public func createFolder(named name: String, in directory: URL) async throws -> URL {
    let validatedDestination = try validatedNewItemDestination(named: name, in: directory)
    let destination = URL(fileURLWithPath: validatedDestination.path, isDirectory: true)
      .standardizedFileURL
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
    return destination
  }

  public func rename(_ source: URL, to newName: String) async throws -> URL {
    guard fileManager.fileExists(atPath: source.path) else {
      throw FileSystemError.sourceMissing(source)
    }
    let cleanedName = try validatedLeafName(newName)
    let destination = source.deletingLastPathComponent()
      .appendingPathComponent(cleanedName)
      .standardizedFileURL
    guard destination != source.standardizedFileURL else { return destination }
    guard !fileManager.fileExists(atPath: destination.path) else {
      throw FileSystemError.destinationExists(destination)
    }
    try fileManager.moveItem(at: source, to: destination)
    return destination
  }

  public func duplicate(_ source: URL) async throws -> URL {
    guard fileManager.fileExists(atPath: source.path) else {
      throw FileSystemError.sourceMissing(source)
    }
    let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
    let treatsExtensionSeparately = !(values.isDirectory == true && values.isPackage != true)
    let pathExtension = treatsExtensionSeparately ? source.pathExtension : ""
    let baseName = pathExtension.isEmpty
      ? source.lastPathComponent
      : source.deletingPathExtension().lastPathComponent
    let parent = source.deletingLastPathComponent()

    var copyNumber = 1
    while true {
      let suffix = copyNumber == 1 ? " copy" : " copy \(copyNumber)"
      let leafName = pathExtension.isEmpty
        ? baseName + suffix
        : baseName + suffix + "." + pathExtension
      let destination = parent.appendingPathComponent(leafName).standardizedFileURL
      if !fileManager.fileExists(atPath: destination.path) {
        try fileManager.copyItem(at: source, to: destination)
        return destination
      }
      copyNumber += 1
    }
  }

  public func trash(_ source: URL) async throws -> URL? {
    guard fileManager.fileExists(atPath: source.path) else {
      throw FileSystemError.sourceMissing(source)
    }
    return try trashHandler(source)
  }

  public func info(for source: URL) async throws -> FileInfo {
    guard fileManager.fileExists(atPath: source.path) else {
      throw FileSystemError.sourceMissing(source)
    }
    let keys: Set<URLResourceKey> = [
      .creationDateKey,
      .contentModificationDateKey,
      .fileSizeKey,
      .isDirectoryKey,
      .isPackageKey,
      .isSymbolicLinkKey,
    ]
    let values = try source.resourceValues(forKeys: keys)
    let isDirectory = values.isDirectory ?? false
    let isPackage = values.isPackage ?? false
    let kind: String
    if isDirectory {
      kind = isPackage ? "Package" : "Folder"
    } else {
      kind = UTType(filenameExtension: source.pathExtension)?.localizedDescription ?? "File"
    }
    return FileInfo(
      url: source,
      kind: kind,
      size: values.fileSize.map(Int64.init),
      creationDate: values.creationDate,
      modificationDate: values.contentModificationDate,
      isDirectory: isDirectory,
      isPackage: isPackage,
      isSymbolicLink: values.isSymbolicLink ?? false
    )
  }

  public func isSameVolume(_ source: URL, _ destination: URL) async throws -> Bool {
    let keys: Set<URLResourceKey> = [.volumeURLKey]
    let sourceVolume = try source.resourceValues(forKeys: keys).volume
    let destinationVolume = try destination.resourceValues(forKeys: keys).volume
    return sourceVolume?.standardizedFileURL == destinationVolume?.standardizedFileURL
  }

  private func validatedDestination(for source: URL, in directory: URL) throws -> URL {
    var sourceIsDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: source.path, isDirectory: &sourceIsDirectory) else {
      throw FileSystemError.sourceMissing(source)
    }

    var destinationIsDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: directory.path, isDirectory: &destinationIsDirectory),
      destinationIsDirectory.boolValue
    else {
      throw FileSystemError.destinationNotDirectory(directory)
    }

    let resolvedSource = source.resolvingSymlinksInPath().standardizedFileURL
    let resolvedDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
    if sourceIsDirectory.boolValue,
      isSameOrDescendant(resolvedDirectory, of: resolvedSource)
    {
      throw FileSystemError.destinationInsideSource
    }

    let destination = directory.appendingPathComponent(source.lastPathComponent)
    guard !fileManager.fileExists(atPath: destination.path) else {
      throw FileSystemError.destinationExists(destination)
    }
    return destination
  }

  private func validatedNewItemDestination(named name: String, in directory: URL) throws -> URL {
    let cleanedName = try validatedLeafName(name)

    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw FileSystemError.destinationNotDirectory(directory)
    }

    let destination = directory.appendingPathComponent(cleanedName).standardizedFileURL
    guard !fileManager.fileExists(atPath: destination.path) else {
      throw FileSystemError.destinationExists(destination)
    }
    return destination
  }

  private func validatedLeafName(_ name: String) throws -> String {
    let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedName.isEmpty,
      cleanedName != ".",
      cleanedName != "..",
      !cleanedName.contains("/"),
      !cleanedName.contains("\\"),
      !cleanedName.contains("\0")
    else {
      throw FileSystemError.invalidFileName(name)
    }
    return cleanedName
  }

  private func isSameOrDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
    let ancestorPath = ancestor.path == "/" ? "/" : ancestor.path + "/"
    return candidate.path == ancestor.path || candidate.path.hasPrefix(ancestorPath)
  }

  private func isImageFile(_ url: URL) -> Bool {
    let pathExtension = url.pathExtension.lowercased()
    if UTType(filenameExtension: pathExtension)?.conforms(to: .image) == true {
      return true
    }
    return [
      "arw", "avif", "bmp", "cr2", "dng", "gif", "heic", "heif", "ico", "jpeg",
      "jpg", "jp2", "nef", "png", "psd", "tif", "tiff", "webp",
    ].contains(pathExtension)
  }
}

public enum FileSystemError: LocalizedError, Sendable {
  case sourceMissing(URL)
  case destinationNotDirectory(URL)
  case destinationExists(URL)
  case destinationInsideSource
  case invalidFileName(String)

  public var errorDescription: String? {
    switch self {
    case .sourceMissing(let url):
      "The source no longer exists: \(url.path)"
    case .destinationNotDirectory(let url):
      "The destination is not an accessible folder: \(url.path)"
    case .destinationExists(let url):
      "An item named \(url.lastPathComponent) already exists."
    case .destinationInsideSource:
      "A folder cannot be copied or moved inside itself."
    case .invalidFileName:
      "Enter a name without slashes or path traversal."
    }
  }
}
