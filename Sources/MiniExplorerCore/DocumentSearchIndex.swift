import Foundation

public struct DocumentSearchIndex: Equatable, Sendable {
  public let ranges: [NSRange]

  public init(text: String, query: String) {
    guard !query.isEmpty else {
      ranges = []
      return
    }

    let content = text as NSString
    var foundRanges: [NSRange] = []
    var searchLocation = 0
    while searchLocation < content.length {
      let searchRange = NSRange(
        location: searchLocation,
        length: content.length - searchLocation
      )
      let match = content.range(
        of: query,
        options: [.caseInsensitive, .diacriticInsensitive],
        range: searchRange
      )
      guard match.location != NSNotFound else { break }
      foundRanges.append(match)
      searchLocation = NSMaxRange(match)
    }
    ranges = foundRanges
  }

  public static func nextMatch(after current: Int?, count: Int) -> Int? {
    guard count > 0 else { return nil }
    guard let current else { return 0 }
    return (current + 1) % count
  }

  public static func previousMatch(before current: Int?, count: Int) -> Int? {
    guard count > 0 else { return nil }
    guard let current else { return count - 1 }
    return (current - 1 + count) % count
  }
}

public struct DocumentFindState: Equatable, Sendable {
  public private(set) var isPresented = false
  public private(set) var matchCount = 0
  public private(set) var currentMatchIndex: Int?

  public init() {}

  public mutating func present() {
    isPresented = true
  }

  @discardableResult
  public mutating func dismissIfPresented() -> Bool {
    guard isPresented else { return false }
    isPresented = false
    return true
  }

  public mutating func updateMatchCount(_ count: Int) {
    matchCount = max(0, count)
    currentMatchIndex = matchCount > 0 ? 0 : nil
  }

  public mutating func selectNextMatch() {
    currentMatchIndex = DocumentSearchIndex.nextMatch(
      after: currentMatchIndex,
      count: matchCount
    )
  }

  public mutating func selectPreviousMatch() {
    currentMatchIndex = DocumentSearchIndex.previousMatch(
      before: currentMatchIndex,
      count: matchCount
    )
  }
}
