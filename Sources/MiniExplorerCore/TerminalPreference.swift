import Foundation

public protocol TerminalPreferenceStoring: AnyObject {
  func loadTerminalBundleIdentifier() -> String?
  func saveTerminalBundleIdentifier(_ bundleIdentifier: String)
}

public final class UserDefaultsTerminalPreferenceStore: TerminalPreferenceStoring {
  public static let key = "MiniExplorer.selectedTerminalBundleIdentifier"

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func loadTerminalBundleIdentifier() -> String? {
    defaults.string(forKey: Self.key)
  }

  public func saveTerminalBundleIdentifier(_ bundleIdentifier: String) {
    defaults.set(bundleIdentifier, forKey: Self.key)
  }
}

public enum TerminalPreferenceResolver {
  public static let ghosttyBundleIdentifier = "com.mitchellh.ghostty"
  public static let appleTerminalBundleIdentifier = "com.apple.Terminal"

  public static func resolve<Identifiers: Collection>(
    savedBundleIdentifier: String?,
    availableBundleIdentifiers: Identifiers
  ) -> String? where Identifiers.Element == String {
    let available = Set(availableBundleIdentifiers)
    if let savedBundleIdentifier, available.contains(savedBundleIdentifier) {
      return savedBundleIdentifier
    }
    if available.contains(ghosttyBundleIdentifier) {
      return ghosttyBundleIdentifier
    }
    if available.contains(appleTerminalBundleIdentifier) {
      return appleTerminalBundleIdentifier
    }
    return nil
  }
}
