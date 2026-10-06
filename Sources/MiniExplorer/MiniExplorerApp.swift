import AppKit
import MiniExplorerCore
import SwiftUI

@main
struct MiniExplorerApp: App {
  @NSApplicationDelegateAdaptor(MiniExplorerAppDelegate.self) private var appDelegate
  @StateObject private var themeController: ExplorerThemeController
  @StateObject private var terminalController: TerminalLauncherController
  private let modelFactory: FileBrowserModelFactory

  init() {
    modelFactory = FileBrowserModelFactory {
      FileBrowserModel(
        service: LocalFileSystemService(),
        systemClipboard: SystemPasteboardService()
      )
    }
    _themeController = StateObject(wrappedValue: ExplorerThemeController())
    _terminalController = StateObject(wrappedValue: TerminalLauncherController())
  }

  var body: some Scene {
    WindowGroup("MiniExplorer") {
      MiniExplorerWindow(modelFactory: modelFactory)
        .environment(
          \.explorerPalette,
          ExplorerPalette.palette(for: themeController.selection)
        )
        .preferredColorScheme(themeController.selection == .classic ? nil : .dark)
        .environmentObject(terminalController)
        .frame(minWidth: 780, minHeight: 480)
    }
    .defaultSize(width: 1_040, height: 680)
    .windowStyle(.hiddenTitleBar)
    .commands {
      FileActionCommands(
        themeController: themeController,
        terminalController: terminalController
      )
    }
  }
}

private struct MiniExplorerWindow: View {
  @StateObject private var model: FileBrowserModel

  init(modelFactory: FileBrowserModelFactory) {
    _model = StateObject(wrappedValue: modelFactory.makeModel())
  }

  var body: some View {
    ContentView(model: model)
      .focusedSceneObject(model)
  }
}

final class MiniExplorerAppDelegate: NSObject, NSApplicationDelegate {
  private var escapeMonitor: Any?

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
      let icon = NSImage(contentsOf: iconURL)
    else { return }
    NSApplication.shared.applicationIconImage = icon
    escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if event.keyCode == 53 {
        NotificationCenter.default.post(name: .miniExplorerEscapePressed, object: nil)
      }
      return event
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    if let escapeMonitor {
      NSEvent.removeMonitor(escapeMonitor)
    }
  }
}
