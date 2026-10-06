public enum BrowserViewMode: String, CaseIterable, Identifiable, Sendable {
  case list
  case largeIcons

  public var id: Self { self }
}
