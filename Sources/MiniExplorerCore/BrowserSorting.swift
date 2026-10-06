public enum BrowserSortColumn: String, CaseIterable, Sendable {
  case name
  case size
  case modified
}

public enum BrowserSortDirection: String, Sendable {
  case ascending
  case descending
}
