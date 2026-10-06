import Foundation
import MiniExplorerCore

@main
struct MiniExplorerCoreTestRunner {
  @MainActor
  static func main() async throws {
    try await run("Directory listings omit hidden items", listOmitsHiddenItems)
    try await run("Directory listings sort folders before files", listSortsFoldersBeforeFiles)
    try await run(
      "Directory listings identify packages and symlinks", listIdentifiesPackagesAndSymlinks)
    try await run("Directory listings identify image files", listIdentifiesImageFiles)
    try await run(
      "Folder icon eligibility excludes packages and files", folderIconEligibility)
    try await run("Copy preserves the source and creates the destination", copyPreservesSource)
    try await run("Copy refuses to overwrite an existing destination", copyRefusesOverwrite)
    try await run("Move removes the source after creating the destination", moveRelocatesSource)
    try await run(
      "Folder operations reject destinations inside the source",
      operationRejectsDescendantDestination)
    try await run("Path resolution expands the home-directory shorthand", pathResolutionExpandsHome)
    try await run("Path resolution rejects relative paths", pathResolutionRejectsRelativePaths)
    try await run("Mounted volumes use stable display names and sorting", mountedVolumesAreSorted)
    try await run("New file creation makes an empty file", createsEmptyFile)
    try await run("Clipboard files receive a unique name without overwriting", createsUniqueClipboardFile)
    try await run("New file creation refuses conflicts", createFileRefusesConflict)
    try await run("New file creation rejects path traversal", createFileRejectsTraversal)
    try await run("New folder creation makes an empty directory", createsEmptyFolder)
    try await run("New folder creation refuses conflicts", createFolderRefusesConflict)
    try await run("New folder creation rejects path traversal", createFolderRejectsTraversal)
    try await run("Hidden listing can be enabled per request", hiddenListingCanBeEnabled)
    try await run("Rename changes only the leaf name and refuses conflicts", renameIsSafe)
    try await run("Duplicate preserves extensions and chooses a free copy name", duplicateChoosesSafeName)
    try await run("Trash uses the injected recoverable operation", trashUsesInjectedOperation)
    try await run("File info exposes real filesystem metadata", fileInfoUsesResourceMetadata)
    try await PreviewContentTests.runAll()
    try await BrowserModelTests.runAll()
    try FileSelectionStateTests.runAll()
    try ThemeTests.runAll()
    try InteractionPreferenceTests.runAll()
  }

  private static func listOmitsHiddenItems() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    FileManager.default.createFile(
      atPath: directory.appendingPathComponent("visible.txt").path,
      contents: Data()
    )
    FileManager.default.createFile(
      atPath: directory.appendingPathComponent(".hidden.txt").path,
      contents: Data()
    )

    let items = try await LocalFileSystemService().list(directory)

    try expectEqual(items.map(\.displayName), ["visible.txt"])
  }

  private static func listSortsFoldersBeforeFiles() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try createDirectory(named: "zFolder", in: directory)
    try createDirectory(named: "AFolder", in: directory)
    try Data().write(to: directory.appendingPathComponent("z.txt"))
    try Data().write(to: directory.appendingPathComponent("a.txt"))

    let items = try await LocalFileSystemService().list(directory)

    try expectEqual(
      items.map(\.displayName),
      ["AFolder", "zFolder", "a.txt", "z.txt"]
    )
  }

  private static func listIdentifiesPackagesAndSymlinks() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let folder = try createDirectory(named: "Folder", in: directory)
    try createDirectory(named: "Example.app", in: directory)
    let link = directory.appendingPathComponent("Folder Link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)

    let items = try await LocalFileSystemService().list(directory)
    let package = try requireItem(named: "Example.app", in: items)
    let symlink = try requireItem(named: "Folder Link", in: items)

    try expect(package.isPackage, "Expected Example.app to be a package")
    try expect(!package.canExpandInSidebar, "Packages must not expand in the sidebar")
    try expect(symlink.isSymbolicLink, "Expected Folder Link to be a symlink")
    try expect(!symlink.canExpandInSidebar, "Symlinks must not expand in the sidebar")
  }

  private static func listIdentifiesImageFiles() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try Data().write(to: directory.appendingPathComponent("photo.PNG"))
    try Data().write(to: directory.appendingPathComponent("notes.txt"))

    let items = try await LocalFileSystemService().list(directory)

    let image = try requireItem(named: "photo.PNG", in: items)
    let text = try requireItem(named: "notes.txt", in: items)
    try expect(image.isImage, "PNG files should be available to image preview")
    try expect(
      !text.isImage,
      "Text files must not be included in image preview navigation"
    )
  }

  private static func folderIconEligibility() throws {
    let folder = FileItem(
      url: URL(fileURLWithPath: "/Folder"),
      displayName: "Folder",
      isDirectory: true,
      isPackage: false,
      isSymbolicLink: false,
      size: nil,
      modificationDate: nil
    )
    let package = FileItem(
      url: URL(fileURLWithPath: "/Example.app"),
      displayName: "Example.app",
      isDirectory: true,
      isPackage: true,
      isSymbolicLink: false,
      size: nil,
      modificationDate: nil
    )
    let file = FileItem(
      url: URL(fileURLWithPath: "/note.txt"),
      displayName: "note.txt",
      isDirectory: false,
      isPackage: false,
      isSymbolicLink: false,
      size: 4,
      modificationDate: nil
    )

    try expect(folder.usesExplorerFolderIcon, "Folders should use the yellow explorer icon")
    try expect(!package.usesExplorerFolderIcon, "Packages should keep their native icon")
    try expect(!file.usesExplorerFolderIcon, "Files should keep their native icon")
  }

  private static func copyPreservesSource() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.txt")
    let destination = try createDirectory(named: "Destination", in: root)
    try Data("hello".utf8).write(to: source)

    try await LocalFileSystemService().copy(source, into: destination)

    try expect(FileManager.default.fileExists(atPath: source.path), "Copy removed its source")
    let copied = try Data(contentsOf: destination.appendingPathComponent("source.txt"))
    try expectEqual(copied, Data("hello".utf8))
  }

  private static func copyRefusesOverwrite() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.txt")
    let destination = try createDirectory(named: "Destination", in: root)
    let existing = destination.appendingPathComponent("source.txt")
    try Data("new".utf8).write(to: source)
    try Data("existing".utf8).write(to: existing)

    do {
      try await LocalFileSystemService().copy(source, into: destination)
      throw TestFailure("Expected a destinationExists error", file: #filePath, line: #line)
    } catch FileSystemError.destinationExists(let url) {
      try expectEqual(url.standardizedFileURL, existing.standardizedFileURL)
    }

    try expectEqual(try Data(contentsOf: existing), Data("existing".utf8))
    try expect(
      FileManager.default.fileExists(atPath: source.path), "Failed copy removed its source")
  }

  private static func moveRelocatesSource() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.txt")
    let destination = try createDirectory(named: "Destination", in: root)
    try Data("hello".utf8).write(to: source)

    try await LocalFileSystemService().move(source, into: destination)

    try expect(!FileManager.default.fileExists(atPath: source.path), "Move left its source behind")
    let moved = try Data(contentsOf: destination.appendingPathComponent("source.txt"))
    try expectEqual(moved, Data("hello".utf8))
  }

  private static func operationRejectsDescendantDestination() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try createDirectory(named: "Source", in: root)
    let nested = try createDirectory(named: "Nested", in: source)

    do {
      try await LocalFileSystemService().copy(source, into: nested)
      throw TestFailure("Expected a destinationInsideSource error", file: #filePath, line: #line)
    } catch FileSystemError.destinationInsideSource {
      return
    }
  }

  private static func pathResolutionExpandsHome() throws {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let resolved = try PathResolver.resolve("~/Documents", homeDirectory: home)
    try expectEqual(resolved.path, "/Users/example/Documents")
  }

  private static func pathResolutionRejectsRelativePaths() throws {
    do {
      _ = try PathResolver.resolve(
        "Documents", homeDirectory: URL(fileURLWithPath: "/Users/example"))
      throw TestFailure("Expected relativePathNotSupported", file: #filePath, line: #line)
    } catch PathResolutionError.relativePathNotSupported {
      return
    }
  }

  private static func mountedVolumesAreSorted() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let zebra = try createDirectory(named: "Zebra", in: root)
    let alpha = try createDirectory(named: "Alpha", in: root)
    let service = LocalFileSystemService(
      mountedVolumeProvider: { [zebra, alpha] }
    )

    let volumes = try await service.mountedVolumes()

    try expectEqual(volumes.map(\.displayName), ["Alpha", "Zebra"])
    try expect(volumes.allSatisfy(\.canExpandInSidebar), "Volume roots must expand")
  }

  private static func createsEmptyFile() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let created = try await LocalFileSystemService().createFile(named: "notes.md", in: root)

    try expectEqual(created, root.appendingPathComponent("notes.md").standardizedFileURL)
    try expectEqual(try Data(contentsOf: created), Data())
  }

  private static func createsUniqueClipboardFile() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("existing".utf8).write(to: root.appendingPathComponent("Clipboard.txt"))

    let created = try await LocalFileSystemService().createUniqueFile(
      named: "Clipboard.txt",
      contents: Data("new".utf8),
      in: root
    )

    try expectEqual(created.lastPathComponent, "Clipboard 2.txt")
    try expectEqual(try Data(contentsOf: created), Data("new".utf8))
    try expectEqual(
      try Data(contentsOf: root.appendingPathComponent("Clipboard.txt")),
      Data("existing".utf8)
    )
  }

  private static func createFileRefusesConflict() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let existing = root.appendingPathComponent("notes.txt")
    try Data("keep".utf8).write(to: existing)

    do {
      _ = try await LocalFileSystemService().createFile(named: "notes.txt", in: root)
      throw TestFailure("Expected a destinationExists error", file: #filePath, line: #line)
    } catch FileSystemError.destinationExists(let url) {
      try expectEqual(url.standardizedFileURL, existing.standardizedFileURL)
    }
    try expectEqual(try Data(contentsOf: existing), Data("keep".utf8))
  }

  private static func createFileRejectsTraversal() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    do {
      _ = try await LocalFileSystemService().createFile(named: "../escape.txt", in: root)
      throw TestFailure("Expected an invalidFileName error", file: #filePath, line: #line)
    } catch FileSystemError.invalidFileName {
      try expect(
        !FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("escape.txt").path),
        "Invalid file creation escaped the destination folder"
      )
    }
  }

  private static func createsEmptyFolder() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let created = try await LocalFileSystemService().createFolder(named: "Projects", in: root)

    var isDirectory: ObjCBool = false
    try expectEqual(created, root.appendingPathComponent("Projects").standardizedFileURL)
    try expect(
      FileManager.default.fileExists(atPath: created.path, isDirectory: &isDirectory)
        && isDirectory.boolValue,
      "Folder creation did not produce a directory"
    )
  }

  private static func createFolderRefusesConflict() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let existing = try createDirectory(named: "Projects", in: root)

    do {
      _ = try await LocalFileSystemService().createFolder(named: "Projects", in: root)
      throw TestFailure("Expected a destinationExists error", file: #filePath, line: #line)
    } catch FileSystemError.destinationExists(let url) {
      try expectEqual(url.standardizedFileURL, existing.standardizedFileURL)
    }
  }

  private static func createFolderRejectsTraversal() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    do {
      _ = try await LocalFileSystemService().createFolder(named: "../Escape", in: root)
      throw TestFailure("Expected an invalidFileName error", file: #filePath, line: #line)
    } catch FileSystemError.invalidFileName {
      try expect(
        !FileManager.default.fileExists(
          atPath: root.deletingLastPathComponent().appendingPathComponent("Escape").path
        ),
        "Invalid folder creation escaped the destination folder"
      )
    }
  }

  private static func hiddenListingCanBeEnabled() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data().write(to: root.appendingPathComponent(".env"))

    let service = LocalFileSystemService()
    try expectEqual(try await service.list(root).map(\.displayName), [])
    try expectEqual(
      try await service.list(root, includesHiddenItems: true).map(\.displayName),
      [".env"]
    )
  }

  private static func renameIsSafe() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("draft.txt")
    let conflict = root.appendingPathComponent("existing.txt")
    try Data("draft".utf8).write(to: source)
    try Data("existing".utf8).write(to: conflict)
    let service = LocalFileSystemService()

    let renamed = try await service.rename(source, to: "report.txt")
    try expectEqual(renamed, root.appendingPathComponent("report.txt").standardizedFileURL)
    try expectEqual(try Data(contentsOf: renamed), Data("draft".utf8))

    do {
      _ = try await service.rename(renamed, to: "existing.txt")
      throw TestFailure("Expected a destinationExists error", file: #filePath, line: #line)
    } catch FileSystemError.destinationExists(let url) {
      try expectEqual(url, conflict.standardizedFileURL)
    }
  }

  private static func duplicateChoosesSafeName() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("report.md")
    try Data("source".utf8).write(to: source)
    try Data("first copy".utf8).write(to: root.appendingPathComponent("report copy.md"))

    let duplicate = try await LocalFileSystemService().duplicate(source)

    try expectEqual(duplicate.lastPathComponent, "report copy 2.md")
    try expectEqual(try Data(contentsOf: duplicate), Data("source".utf8))
  }

  private static func trashUsesInjectedOperation() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("discard.txt")
    try Data().write(to: source)
    let service = LocalFileSystemService(trashHandler: { url in
      try FileManager.default.removeItem(at: url)
      return URL(fileURLWithPath: "/Trash").appendingPathComponent(url.lastPathComponent)
    })

    let trashedURL = try await service.trash(source)

    try expectEqual(trashedURL?.lastPathComponent, "discard.txt")
    try expect(!FileManager.default.fileExists(atPath: source.path), "Injected Trash handler did not remove its fixture")
  }

  private static func fileInfoUsesResourceMetadata() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("info.log")
    try Data("hello".utf8).write(to: file)

    let info = try await LocalFileSystemService().info(for: file)

    try expectEqual(info.url, file.standardizedFileURL)
    try expectEqual(info.size, 5)
    try expect(!info.isDirectory, "A regular file was reported as a folder")
    try expect(info.modificationDate != nil, "Missing modification date")
  }

  private static func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: false
    )
    return url
  }

  @discardableResult
  private static func createDirectory(named name: String, in parent: URL) throws -> URL {
    let url = parent.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
  }

  private static func requireItem(named name: String, in items: [FileItem]) throws -> FileItem {
    guard let item = items.first(where: { $0.displayName == name }) else {
      throw TestFailure("Missing item named \(name)", file: #filePath, line: #line)
    }
    return item
  }

  private static func run(
    _ name: String,
    _ test: () async throws -> Void
  ) async throws {
    try await test()
    print("PASS: \(name)")
  }

  private static func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    guard condition() else {
      throw TestFailure(message, file: file, line: line)
    }
  }

  private static func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    guard actual == expected else {
      throw TestFailure(
        "Expected \(String(describing: expected)), got \(String(describing: actual))",
        file: file,
        line: line
      )
    }
  }
}

private struct TestFailure: Error, CustomStringConvertible {
  let message: String
  let file: StaticString
  let line: UInt

  init(_ message: String, file: StaticString, line: UInt) {
    self.message = message
    self.file = file
    self.line = line
  }

  var description: String {
    "\(file):\(line): \(message)"
  }
}
