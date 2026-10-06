import AppKit
import MiniExplorerCore

@MainActor
final class SystemPasteboardService: SystemClipboardServing {
  private let pasteboard: NSPasteboard

  init(pasteboard: NSPasteboard = .general) {
    self.pasteboard = pasteboard
  }

  var changeCount: Int { pasteboard.changeCount }

  func readSnapshot() -> SystemClipboardSnapshot? {
    let content: SystemClipboardContent?
    let options: [NSPasteboard.ReadingOptionKey: Any] = [
      .urlReadingFileURLsOnly: true
    ]
    if let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options),
      !objects.isEmpty
    {
      let urls = objects.compactMap { ($0 as? NSURL) as URL? }
        .map(\.standardizedFileURL)
      content = urls.isEmpty ? nil : .files(urls)
    } else if let png = pasteboard.data(forType: .png) {
      content = .binary(data: png, preferredFilename: "Clipboard.png")
    } else if let tiff = pasteboard.data(forType: .tiff),
      let representation = NSBitmapImageRep(data: tiff),
      let png = representation.representation(using: .png, properties: [:])
    {
      content = .binary(data: png, preferredFilename: "Clipboard.png")
    } else if let string = pasteboard.string(forType: .string) {
      content = .text(string)
    } else {
      content = nil
    }

    return content.map {
      SystemClipboardSnapshot(changeCount: pasteboard.changeCount, content: $0)
    }
  }

  func writeFileURLs(_ urls: [URL]) -> Int {
    pasteboard.clearContents()
    pasteboard.writeObjects(urls.map { $0.standardizedFileURL as NSURL })
    return pasteboard.changeCount
  }
}
