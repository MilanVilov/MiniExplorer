import Foundation

public enum MarkdownWritingStyle {
  public enum Kind: Equatable, Sendable {
    case heading(level: Int)
    case bold
    case italic
    case link
    case inlineCode
    case codeBlock
    case listMarker
    case quoteMarker
    case syntax
  }

  public struct Span: Equatable {
    public let range: NSRange
    public let kind: Kind

    public init(range: NSRange, kind: Kind) {
      self.range = range
      self.kind = kind
    }
  }

  public static func spans(in source: String) -> [Span] {
    let fullRange = NSRange(location: 0, length: (source as NSString).length)
    var spans: [Span] = []
    let codeRanges = matches(
      pattern: "^```[^\\n]*\\n.*?^```[ \\t]*$",
      in: source,
      options: [.anchorsMatchLines, .dotMatchesLineSeparators]
    ).map(\.range)
    spans.append(contentsOf: codeRanges.map { Span(range: $0, kind: .codeBlock) })

    for match in matches(pattern: "^(#{1,6})[ \\t]+.*$", in: source, options: .anchorsMatchLines)
    where !intersectsCode(match.range, codeRanges: codeRanges) {
      let markerRange = match.range(at: 1)
      spans.append(Span(range: match.range, kind: .heading(level: markerRange.length)))
      spans.append(Span(range: markerRange, kind: .syntax))
    }

    appendCapturedStyles(
      pattern: "\\*\\*([^\\n*]+)\\*\\*|__([^\\n_]+)__",
      kind: .bold,
      source: source,
      codeRanges: codeRanges,
      spans: &spans
    )
    appendCapturedStyles(
      pattern: "(?<!\\*)\\*([^\\n*]+)\\*(?!\\*)|(?<!_)_([^\\n_]+)_(?!_)",
      kind: .italic,
      source: source,
      codeRanges: codeRanges,
      spans: &spans
    )
    appendCapturedStyles(
      pattern: "`([^`\\n]+)`",
      kind: .inlineCode,
      source: source,
      codeRanges: codeRanges,
      spans: &spans
    )

    for match in matches(pattern: "\\[([^]\\n]+)\\]\\(([^)\\n]+)\\)", in: source)
    where !intersectsCode(match.range, codeRanges: codeRanges) {
      spans.append(Span(range: match.range(at: 1), kind: .link))
      let labelRange = match.range(at: 1)
      let destinationRange = match.range(at: 2)
      spans.append(Span(range: NSRange(location: match.range.location, length: 1), kind: .syntax))
      spans.append(
        Span(
          range: NSRange(location: NSMaxRange(labelRange), length: 2),
          kind: .syntax
        )
      )
      spans.append(Span(range: destinationRange, kind: .syntax))
      spans.append(
        Span(range: NSRange(location: NSMaxRange(destinationRange), length: 1), kind: .syntax)
      )
    }

    for match in matches(
      pattern: "^[ \\t]*(?:[-+*]|\\d+[.)])(?=[ \\t])",
      in: source,
      options: .anchorsMatchLines
    ) where !intersectsCode(match.range, codeRanges: codeRanges) {
      spans.append(Span(range: match.range, kind: .listMarker))
    }
    for match in matches(
      pattern: "^[ \\t]*>+[ \\t]?",
      in: source,
      options: .anchorsMatchLines
    ) where !intersectsCode(match.range, codeRanges: codeRanges) {
      spans.append(Span(range: match.range, kind: .quoteMarker))
    }

    for codeRange in codeRanges {
      let code = (source as NSString).substring(with: codeRange) as NSString
      let firstLineEnd = code.range(of: "\n").location
      let openingLength = firstLineEnd == NSNotFound ? code.length : firstLineEnd
      spans.append(
        Span(
          range: NSRange(location: codeRange.location, length: openingLength),
          kind: .syntax
        )
      )
      let closingRange = code.range(of: "```", options: .backwards)
      if closingRange.location != NSNotFound {
        spans.append(
          Span(
            range: NSRange(
              location: codeRange.location + closingRange.location,
              length: closingRange.length
            ),
            kind: .syntax
          )
        )
      }
    }

    return spans.filter { NSMaxRange($0.range) <= NSMaxRange(fullRange) }
  }

  private static func appendCapturedStyles(
    pattern: String,
    kind: Kind,
    source: String,
    codeRanges: [NSRange],
    spans: inout [Span]
  ) {
    for match in matches(pattern: pattern, in: source)
    where !intersectsCode(match.range, codeRanges: codeRanges) {
      let contentRange =
        (1..<match.numberOfRanges)
        .map { match.range(at: $0) }
        .first { $0.location != NSNotFound } ?? match.range
      spans.append(Span(range: contentRange, kind: kind))
      if contentRange.location > match.range.location {
        spans.append(
          Span(
            range: NSRange(
              location: match.range.location,
              length: contentRange.location - match.range.location
            ),
            kind: .syntax
          )
        )
      }
      if NSMaxRange(contentRange) < NSMaxRange(match.range) {
        spans.append(
          Span(
            range: NSRange(
              location: NSMaxRange(contentRange),
              length: NSMaxRange(match.range) - NSMaxRange(contentRange)
            ),
            kind: .syntax
          )
        )
      }
    }
  }

  private static func matches(
    pattern: String,
    in source: String,
    options: NSRegularExpression.Options = []
  ) -> [NSTextCheckingResult] {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
      return []
    }
    return expression.matches(
      in: source,
      range: NSRange(location: 0, length: (source as NSString).length)
    )
  }

  private static func intersectsCode(_ range: NSRange, codeRanges: [NSRange]) -> Bool {
    codeRanges.contains { NSIntersectionRange(range, $0).length > 0 }
  }
}

public struct MarkdownEditResult: Equatable, Sendable {
  public let text: String
  public let selection: NSRange

  public init(text: String, selection: NSRange) {
    self.text = text
    self.selection = selection
  }
}

public enum MarkdownEditing {
  public static func bold(_ text: String, selection: NSRange) -> MarkdownEditResult {
    wrap(text, selection: selection, prefix: "**", suffix: "**")
  }

  public static func italic(_ text: String, selection: NSRange) -> MarkdownEditResult {
    wrap(text, selection: selection, prefix: "*", suffix: "*")
  }

  public static func link(_ text: String, selection: NSRange) -> MarkdownEditResult {
    let source = text as NSString
    let safeRange = NSIntersectionRange(selection, NSRange(location: 0, length: source.length))
    let selectedText = source.substring(with: safeRange)
    let label = selectedText.isEmpty ? "link text" : selectedText
    let replacement = "[\(label)](https://)"
    let mutableText = NSMutableString(string: text)
    mutableText.replaceCharacters(in: safeRange, with: replacement)
    let destinationLocation = safeRange.location + (label as NSString).length + 3
    return MarkdownEditResult(
      text: mutableText as String,
      selection: NSRange(location: destinationLocation, length: 8)
    )
  }

  private static func wrap(
    _ text: String,
    selection: NSRange,
    prefix: String,
    suffix: String
  ) -> MarkdownEditResult {
    let source = text as NSString
    let safeRange = NSIntersectionRange(selection, NSRange(location: 0, length: source.length))
    let selectedText = source.substring(with: safeRange)
    let replacement = prefix + selectedText + suffix
    let mutableText = NSMutableString(string: text)
    mutableText.replaceCharacters(in: safeRange, with: replacement)
    return MarkdownEditResult(
      text: mutableText as String,
      selection: NSRange(
        location: safeRange.location + (prefix as NSString).length,
        length: safeRange.length
      )
    )
  }
}
