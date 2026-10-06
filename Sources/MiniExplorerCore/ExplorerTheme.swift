import Combine
import Foundation

public enum ExplorerThemeID: String, CaseIterable, Identifiable, Sendable {
  case classic
  case murmurFlat
  case tokyoNight
  case retroCraft

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .classic:
      "Classic Explorer"
    case .murmurFlat:
      "Murmur Flat"
    case .tokyoNight:
      "Tokyo Night"
    case .retroCraft:
      "Retro Craft"
    }
  }
}

public protocol ThemeStoring: AnyObject {
  func loadThemeIdentifier() -> String?
  func saveThemeIdentifier(_ identifier: String)
}

public final class UserDefaultsThemeStore: ThemeStoring {
  public static let key = "MiniExplorer.selectedTheme"

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func loadThemeIdentifier() -> String? {
    defaults.string(forKey: Self.key)
  }

  public func saveThemeIdentifier(_ identifier: String) {
    defaults.set(identifier, forKey: Self.key)
  }
}

@MainActor
public final class ExplorerThemeController: ObservableObject {
  @Published public private(set) var selection: ExplorerThemeID

  private let store: ThemeStoring

  public init(store: ThemeStoring = UserDefaultsThemeStore()) {
    self.store = store
    selection = store.loadThemeIdentifier()
      .flatMap(ExplorerThemeID.init(rawValue:)) ?? .murmurFlat
  }

  public func select(_ theme: ExplorerThemeID) {
    selection = theme
    store.saveThemeIdentifier(theme.rawValue)
  }
}
