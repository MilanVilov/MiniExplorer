import Foundation

@MainActor
public struct FileBrowserModelFactory {
  private let build: @MainActor () -> FileBrowserModel

  public init(_ build: @escaping @MainActor () -> FileBrowserModel) {
    self.build = build
  }

  public func makeModel() -> FileBrowserModel {
    build()
  }
}
