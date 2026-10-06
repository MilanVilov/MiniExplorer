import Foundation

public struct ClipboardHistoryEntry: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let payload: ClipboardPayload
  public let capturedAt: Date

  public init(
    id: UUID = UUID(),
    payload: ClipboardPayload,
    capturedAt: Date = Date()
  ) {
    self.id = id
    self.payload = payload
    self.capturedAt = capturedAt
  }
}
