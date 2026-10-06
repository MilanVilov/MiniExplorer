import AppKit
import Combine

@MainActor
protocol VolumeMonitoring {
  var events: AnyPublisher<Void, Never> { get }
}

@MainActor
final class WorkspaceVolumeMonitor: VolumeMonitoring {
  let events: AnyPublisher<Void, Never>

  init(workspace: NSWorkspace = .shared) {
    let center = workspace.notificationCenter
    events = Publishers.Merge3(
      center.publisher(for: NSWorkspace.didMountNotification),
      center.publisher(for: NSWorkspace.didUnmountNotification),
      center.publisher(for: NSWorkspace.didRenameVolumeNotification)
    )
    .map { _ in () }
    .eraseToAnyPublisher()
  }
}
