import Combine
import Foundation

public enum PreviewContentKind: String, Equatable, Sendable {
  case image
  case pdf
  case markdown
  case csv
  case text

  public static func forFile(named name: String) -> PreviewContentKind? {
    let lowercasedName = name.lowercased()
    let pathExtension = URL(fileURLWithPath: lowercasedName).pathExtension
    if pathExtension == "pdf" {
      return .pdf
    }
    if ["md", "markdown", "mdown", "mkd"].contains(pathExtension) {
      return .markdown
    }
    if ["csv", "tsv"].contains(pathExtension) {
      return .csv
    }
    if pathExtension.isEmpty, !lowercasedName.hasSuffix(".") {
      return .text
    }
    return textExtensions.contains(pathExtension) ? .text : nil
  }

  private static let textExtensions: Set<String> = [
    "bash", "c", "cc", "cfg", "clj", "conf", "cpp", "css", "dart", "diff", "env",
    "erl", "ex", "exs", "fish", "go", "gradle", "graphql", "h", "hpp", "htm", "html",
    "ini", "java", "js", "json", "jsx", "kt", "kts", "less", "log", "lua", "m", "mm",
    "php", "plist", "properties", "proto", "py", "r", "rb", "rs", "sass", "scala", "scss",
    "sh", "sql", "swift", "tex", "text", "toml", "ts", "tsx", "txt", "vue", "xml", "yaml",
    "yml", "zsh",
  ]
}

public enum MarkdownBlock: Equatable, Sendable {
  case heading(level: Int, text: String)
  case paragraph(String)
  case unorderedList([String])
  case orderedList([String])
  case blockquote(String)
  case code(language: String?, text: String)
  case divider
}

public enum MarkdownDocument {
  public static func parse(_ source: String) -> [MarkdownBlock] {
    let lines = source.components(separatedBy: .newlines)
    var blocks: [MarkdownBlock] = []
    var index = 0

    while index < lines.count {
      let line = lines[index]
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty {
        index += 1
        continue
      }

      if trimmed.hasPrefix("```") {
        let languageText = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        index += 1
        var codeLines: [String] = []
        while index < lines.count,
          !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```")
        {
          codeLines.append(lines[index])
          index += 1
        }
        if index < lines.count { index += 1 }
        blocks.append(
          .code(
            language: languageText.isEmpty ? nil : languageText,
            text: codeLines.joined(separator: "\n")
          )
        )
        continue
      }

      if let heading = heading(from: trimmed) {
        blocks.append(heading)
        index += 1
        continue
      }

      if isDivider(trimmed) {
        blocks.append(.divider)
        index += 1
        continue
      }

      if unorderedItem(from: trimmed) != nil {
        var items: [String] = []
        while index < lines.count,
          let item = unorderedItem(
            from: lines[index].trimmingCharacters(in: .whitespaces)
          )
        {
          items.append(item)
          index += 1
        }
        blocks.append(.unorderedList(items))
        continue
      }

      if orderedItem(from: trimmed) != nil {
        var items: [String] = []
        while index < lines.count,
          let item = orderedItem(from: lines[index].trimmingCharacters(in: .whitespaces))
        {
          items.append(item)
          index += 1
        }
        blocks.append(.orderedList(items))
        continue
      }

      if trimmed.hasPrefix(">") {
        var quoteLines: [String] = []
        while index < lines.count {
          let quoteLine = lines[index].trimmingCharacters(in: .whitespaces)
          guard quoteLine.hasPrefix(">") else { break }
          quoteLines.append(String(quoteLine.dropFirst()).trimmingCharacters(in: .whitespaces))
          index += 1
        }
        blocks.append(.blockquote(quoteLines.joined(separator: "\n")))
        continue
      }

      var paragraphLines: [String] = []
      while index < lines.count {
        let paragraphLine = lines[index].trimmingCharacters(in: .whitespaces)
        guard !paragraphLine.isEmpty else { break }
        if !paragraphLines.isEmpty, isBlockStart(paragraphLine) { break }
        paragraphLines.append(paragraphLine)
        index += 1
      }
      blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
    }
    return blocks
  }

  private static func heading(from line: String) -> MarkdownBlock? {
    let prefixCount = line.prefix(while: { $0 == "#" }).count
    guard (1...6).contains(prefixCount), line.dropFirst(prefixCount).hasPrefix(" ") else {
      return nil
    }
    return .heading(
      level: prefixCount,
      text: String(line.dropFirst(prefixCount + 1))
    )
  }

  private static func unorderedItem(from line: String) -> String? {
    for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
      return String(line.dropFirst(prefix.count))
    }
    return nil
  }

  private static func orderedItem(from line: String) -> String? {
    guard let separator = line.firstIndex(of: "."), separator != line.startIndex else { return nil }
    let number = line[..<separator]
    let contentStart = line.index(after: separator)
    guard number.allSatisfy(\.isNumber), contentStart < line.endIndex,
      line[contentStart] == " "
    else { return nil }
    return String(line[line.index(after: contentStart)...])
  }

  private static func isDivider(_ line: String) -> Bool {
    ["---", "***", "___"].contains(line)
  }

  private static func isBlockStart(_ line: String) -> Bool {
    line.hasPrefix("```") || heading(from: line) != nil || isDivider(line)
      || unorderedItem(from: line) != nil || orderedItem(from: line) != nil
      || line.hasPrefix(">")
  }
}

public enum TextPreviewError: LocalizedError, Equatable, Sendable {
  case fileTooLarge
  case binaryContent
  case invalidEncoding

  public var errorDescription: String? {
    switch self {
    case .fileTooLarge:
      "This file is too large for MiniExplorer's text preview."
    case .binaryContent:
      "This file contains binary data and cannot be shown as text."
    case .invalidEncoding:
      "This file is not valid UTF-8 text."
    }
  }
}

public protocol TextFileServing: Sendable {
  func load(_ url: URL) async throws -> String
  func save(_ text: String, to url: URL) async throws
}

public actor LocalTextFileService: TextFileServing {
  public let maximumBytes: Int

  public init(maximumBytes: Int = 10 * 1_024 * 1_024) {
    self.maximumBytes = maximumBytes
  }

  public func load(_ url: URL) async throws -> String {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
    if let size = values.fileSize, size > maximumBytes {
      throw TextPreviewError.fileTooLarge
    }
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    guard data.count <= maximumBytes else { throw TextPreviewError.fileTooLarge }
    guard !data.contains(0) else { throw TextPreviewError.binaryContent }
    guard let text = String(data: data, encoding: .utf8) else {
      throw TextPreviewError.invalidEncoding
    }
    return text
  }

  public func save(_ text: String, to url: URL) async throws {
    try Data(text.utf8).write(to: url, options: .atomic)
  }
}

@MainActor
public final class TextPreviewSession: ObservableObject {
  public let url: URL
  @Published public var text = ""
  @Published public private(set) var isLoading = false
  @Published public private(set) var isSaving = false
  @Published public private(set) var lastSavedAt: Date?
  @Published public private(set) var errorMessage: String?
  @Published public private(set) var saveErrorMessage: String?

  private let service: any TextFileServing
  private var savedText = ""
  private var autosaveTask: Task<Void, Never>?

  public init(url: URL, service: any TextFileServing = LocalTextFileService()) {
    self.url = url
    self.service = service
  }

  public var isDirty: Bool { text != savedText }

  public func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let loadedText = try await service.load(url)
      text = loadedText
      savedText = loadedText
      errorMessage = nil
      saveErrorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func save() async {
    autosaveTask?.cancel()
    autosaveTask = nil
    await performSave()
  }

  public func scheduleAutosave(after delay: Duration = .milliseconds(700)) {
    autosaveTask?.cancel()
    autosaveTask = Task { [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      await self?.performSave()
    }
  }

  private func performSave() async {
    guard isDirty else { return }
    let textToSave = text
    isSaving = true
    defer { isSaving = false }
    do {
      try await service.save(textToSave, to: url)
      savedText = textToSave
      lastSavedAt = Date()
      saveErrorMessage = nil
    } catch {
      saveErrorMessage = error.localizedDescription
    }
  }
}

public struct ApplicationChoice: Identifiable, Hashable, Sendable {
  public let url: URL
  public let displayName: String
  public let isCompatible: Bool

  public var id: URL { url.standardizedFileURL }

  public init(url: URL, displayName: String, isCompatible: Bool) {
    self.url = url.standardizedFileURL
    self.displayName = displayName
    self.isCompatible = isCompatible
  }

  public static func filtered(_ applications: [ApplicationChoice], query: String)
    -> [ApplicationChoice]
  {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return
      applications
      .filter {
        trimmedQuery.isEmpty || $0.displayName.localizedCaseInsensitiveContains(trimmedQuery)
      }
      .sorted { lhs, rhs in
        if lhs.isCompatible != rhs.isCompatible { return lhs.isCompatible }
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
      }
  }
}
