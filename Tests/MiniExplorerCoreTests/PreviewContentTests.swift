import Foundation
import MiniExplorerCore

enum PreviewContentTests {
  @MainActor
  static func runAll() async throws {
    try await run("Text preview recognizes common text and source formats", recognizesTextFormats)
    try await run("PDF preview recognizes PDF documents", recognizesPDFDocuments)
    try await run("PDF fit width uses the available document surface", calculatesPDFFitWidth)
    try await run("Text preview loads UTF-8 content and rejects binary data", loadsTextSafely)
    try await run("Text preview rejects files above its size limit", rejectsOversizedFiles)
    try await run("Text edits remain dirty until Command-S saves them", savesEditedText)
    try await run("Markdown edits autosave after the typing delay", autosavesEditedMarkdown)
    try await run(
      "Markdown save failures keep the document editable",
      keepsMarkdownEditableAfterSaveFailure
    )
    try await run("Open With search filters apps and keeps compatible apps first", filtersApps)
    try await run("Markdown parser preserves block structure", parsesMarkdownBlocks)
    try await run("Markdown writing styles update source ranges", findsLiveMarkdownStyles)
    try await run("Markdown formatting commands preserve the selected text", formatsSelection)
    try await run("Document search finds every case-insensitive match", findsDocumentMatches)
    try await run("Document search navigation wraps in both directions", wrapsDocumentSearchNavigation)
    try await run("Document Find closes before its preview", dismissesDocumentFindFirst)
  }

  private static func recognizesTextFormats() throws {
    let expectations: [(String, PreviewContentKind)] = [
      ("README.md", .markdown),
      ("records.csv", .csv),
      ("app.js", .text),
      ("server.log", .text),
      ("config.yml", .text),
      ("Dockerfile", .text),
    ]

    for (name, expected) in expectations {
      try expectEqual(PreviewContentKind.forFile(named: name), expected)
    }
  }

  private static func recognizesPDFDocuments() throws {
    try expectEqual(PreviewContentKind.forFile(named: "Manual.PDF"), .pdf)
  }

  private static func findsDocumentMatches() throws {
    let search = DocumentSearchIndex(text: "Alpha beta ALPHA alphabet", query: "alpha")

    try expectEqual(
      search.ranges,
      [
        NSRange(location: 0, length: 5),
        NSRange(location: 11, length: 5),
        NSRange(location: 17, length: 5),
      ]
    )
    try expectEqual(DocumentSearchIndex(text: "Alpha", query: "").ranges, [])
  }

  private static func wrapsDocumentSearchNavigation() throws {
    try expectEqual(DocumentSearchIndex.nextMatch(after: nil, count: 3), 0)
    try expectEqual(DocumentSearchIndex.nextMatch(after: 2, count: 3), 0)
    try expectEqual(DocumentSearchIndex.previousMatch(before: nil, count: 3), 2)
    try expectEqual(DocumentSearchIndex.previousMatch(before: 0, count: 3), 2)
    try expectEqual(DocumentSearchIndex.nextMatch(after: nil, count: 0), nil)
  }

  private static func dismissesDocumentFindFirst() throws {
    var state = DocumentFindState()
    state.present()
    state.updateMatchCount(3)
    state.selectNextMatch()
    try expectEqual(state.currentMatchIndex, 1)

    try expect(state.dismissIfPresented(), "The first Escape must close Document Find")
    try expect(!state.isPresented, "Document Find must no longer be visible")
    try expect(!state.dismissIfPresented(), "A second Escape must be available to close the preview")
  }

  private static func calculatesPDFFitWidth() throws {
    let scale = PDFPreviewSizing.fitWidthScale(
      viewWidth: 1_000,
      pageWidth: 500,
      horizontalInset: 40,
      minimumScale: 0.25,
      maximumScale: 8
    )

    try expectEqual(scale, 1.92)
  }

  private static func loadsTextSafely() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let textURL = root.appendingPathComponent("app.js")
    let binaryURL = root.appendingPathComponent("binary.log")
    try Data("const answer = 42;".utf8).write(to: textURL)
    try Data([0x41, 0x00, 0x42]).write(to: binaryURL)
    let service = LocalTextFileService(maximumBytes: 1_024)

    let text = try await service.load(textURL)
    try expectEqual(text, "const answer = 42;")

    do {
      _ = try await service.load(binaryURL)
      throw PreviewTestFailure("Expected binary text rejection", file: #filePath, line: #line)
    } catch TextPreviewError.binaryContent {
      return
    }
  }

  private static func rejectsOversizedFiles() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("large.txt")
    try Data(repeating: 0x41, count: 17).write(to: url)

    do {
      _ = try await LocalTextFileService(maximumBytes: 16).load(url)
      throw PreviewTestFailure("Expected oversized text rejection", file: #filePath, line: #line)
    } catch TextPreviewError.fileTooLarge {
      return
    }
  }

  @MainActor
  private static func savesEditedText() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("notes.txt")
    try Data("before".utf8).write(to: url)
    let session = TextPreviewSession(url: url, service: LocalTextFileService())

    await session.load()
    session.text = "after"
    try expect(session.isDirty, "An edit must be marked unsaved")

    await session.save()

    try expect(!session.isDirty, "A successful save must clear the dirty state")
    try expect(session.lastSavedAt != nil, "A successful save must record its time")
    try expectEqual(try String(contentsOf: url, encoding: .utf8), "after")
  }

  @MainActor
  private static func autosavesEditedMarkdown() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("notes.md")
    try Data("before".utf8).write(to: url)
    let session = TextPreviewSession(url: url, service: LocalTextFileService())

    await session.load()
    session.text = "after"
    session.scheduleAutosave(after: .milliseconds(20))
    try await Task.sleep(for: .milliseconds(80))

    try expect(!session.isDirty, "Autosave must clear the dirty state")
    try expect(session.lastSavedAt != nil, "Autosave must record its save time")
    try expectEqual(try String(contentsOf: url, encoding: .utf8), "after")
  }

  @MainActor
  private static func keepsMarkdownEditableAfterSaveFailure() async throws {
    let url = URL(fileURLWithPath: "/tmp/notes.md")
    let session = TextPreviewSession(url: url, service: FailingSaveTextFileService())

    await session.load()
    session.text = "after"
    await session.save()

    try expectEqual(session.text, "after")
    try expect(session.isDirty, "A failed save must leave the edit marked unsaved")
    try expect(session.errorMessage == nil, "A save failure must not become a load failure")
    try expect(session.saveErrorMessage != nil, "A failed save must expose a save error")
  }

  private static func filtersApps() throws {
    let compatible = ApplicationChoice(
      url: URL(fileURLWithPath: "/Applications/CodeEdit.app"),
      displayName: "CodeEdit",
      isCompatible: true
    )
    let other = ApplicationChoice(
      url: URL(fileURLWithPath: "/Applications/JavaScript Helper.app"),
      displayName: "JavaScript Helper",
      isCompatible: false
    )
    let unrelated = ApplicationChoice(
      url: URL(fileURLWithPath: "/Applications/Photos.app"),
      displayName: "Photos",
      isCompatible: true
    )

    let filtered = ApplicationChoice.filtered([other, unrelated, compatible], query: "edit")

    try expectEqual(filtered.map(\.displayName), ["CodeEdit"])
    let all = ApplicationChoice.filtered([other, unrelated, compatible], query: "")
    try expectEqual(all.map(\.displayName), ["CodeEdit", "Photos", "JavaScript Helper"])
  }

  private static func parsesMarkdownBlocks() throws {
    let source = """
      # Title

      A short **paragraph**.

      - First
      - Second

      ```js
      const answer = 42
      ```
      """

    let blocks = MarkdownDocument.parse(source)

    try expectEqual(
      blocks,
      [
        .heading(level: 1, text: "Title"),
        .paragraph("A short **paragraph**."),
        .unorderedList(["First", "Second"]),
        .code(language: "js", text: "const answer = 42"),
      ]
    )
  }

  private static func findsLiveMarkdownStyles() throws {
    let source = """
      # Heading

      **bold** and *italic* with [link](https://example.com)

      ```js
      const answer = 42
      ```
      """

    let spans = MarkdownWritingStyle.spans(in: source)

    try expectEqual(texts(for: .heading(level: 1), in: source, spans: spans), ["# Heading"])
    try expectEqual(texts(for: .bold, in: source, spans: spans), ["bold"])
    try expectEqual(texts(for: .italic, in: source, spans: spans), ["italic"])
    try expectEqual(texts(for: .link, in: source, spans: spans), ["link"])
    try expectEqual(
      texts(for: .codeBlock, in: source, spans: spans),
      ["```js\nconst answer = 42\n```"]
    )
  }

  private static func formatsSelection() throws {
    let bold = MarkdownEditing.bold("hello", selection: NSRange(location: 0, length: 5))
    try expectEqual(bold.text, "**hello**")
    try expectEqual(bold.selection, NSRange(location: 2, length: 5))

    let italic = MarkdownEditing.italic("hello", selection: NSRange(location: 0, length: 5))
    try expectEqual(italic.text, "*hello*")
    try expectEqual(italic.selection, NSRange(location: 1, length: 5))

    let link = MarkdownEditing.link("OpenAI", selection: NSRange(location: 0, length: 6))
    try expectEqual(link.text, "[OpenAI](https://)")
    try expectEqual(link.selection, NSRange(location: 9, length: 8))
  }

  private static func texts(
    for kind: MarkdownWritingStyle.Kind,
    in source: String,
    spans: [MarkdownWritingStyle.Span]
  ) -> [String] {
    let string = source as NSString
    return spans.filter { $0.kind == kind }.map { string.substring(with: $0.range) }
  }

  private static func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
  }

  @MainActor
  private static func run(_ name: String, _ test: () async throws -> Void) async throws {
    try await test()
    print("PASS: \(name)")
  }

  private static func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    guard condition() else { throw PreviewTestFailure(message, file: file, line: line) }
  }

  private static func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    guard actual == expected else {
      throw PreviewTestFailure(
        "Expected \(String(describing: expected)), got \(String(describing: actual))",
        file: file,
        line: line
      )
    }
  }
}

private actor FailingSaveTextFileService: TextFileServing {
  func load(_ url: URL) async throws -> String { "before" }

  func save(_ text: String, to url: URL) async throws {
    throw CocoaError(.fileWriteNoPermission)
  }
}

private struct PreviewTestFailure: Error, CustomStringConvertible {
  let message: String
  let file: StaticString
  let line: UInt

  init(_ message: String, file: StaticString, line: UInt) {
    self.message = message
    self.file = file
    self.line = line
  }

  var description: String { "\(file):\(line): \(message)" }
}
