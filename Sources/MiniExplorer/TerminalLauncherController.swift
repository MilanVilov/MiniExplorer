import AppKit
import MiniExplorerCore
import SwiftUI
import UniformTypeIdentifiers

struct TerminalApplication: Identifiable, Hashable {
  let bundleIdentifier: String
  let displayName: String
  let url: URL

  var id: String { bundleIdentifier }
}

@MainActor
final class TerminalLauncherController: ObservableObject {
  @Published private(set) var availableApplications: [TerminalApplication] = []
  @Published private(set) var selection: TerminalApplication?

  private let store: any TerminalPreferenceStoring
  private let workspace: NSWorkspace

  private static let knownBundleIdentifiers = [
    TerminalPreferenceResolver.ghosttyBundleIdentifier,
    TerminalPreferenceResolver.appleTerminalBundleIdentifier,
    "com.googlecode.iterm2",
    "dev.warp.Warp-Stable",
    "net.kovidgoyal.kitty",
    "com.github.wez.wezterm",
    "org.alacritty",
  ]

  init(
    store: any TerminalPreferenceStoring = UserDefaultsTerminalPreferenceStore(),
    workspace: NSWorkspace = .shared
  ) {
    self.store = store
    self.workspace = workspace
    refreshApplications()
  }

  var actionTitle: String {
    "Open in \(selection?.displayName ?? "Terminal")"
  }

  func refreshApplications() {
    let savedIdentifier = store.loadTerminalBundleIdentifier()
    var identifiers = Self.knownBundleIdentifiers
    if let savedIdentifier, !identifiers.contains(savedIdentifier) {
      identifiers.append(savedIdentifier)
    }

    availableApplications = identifiers.compactMap(application(for:))
    let resolvedIdentifier = TerminalPreferenceResolver.resolve(
      savedBundleIdentifier: savedIdentifier,
      availableBundleIdentifiers: availableApplications.map(\.bundleIdentifier)
    )
    selection = availableApplications.first { $0.bundleIdentifier == resolvedIdentifier }
    if let resolvedIdentifier, resolvedIdentifier != savedIdentifier {
      store.saveTerminalBundleIdentifier(resolvedIdentifier)
    }
  }

  func select(_ application: TerminalApplication) {
    selection = application
    store.saveTerminalBundleIdentifier(application.bundleIdentifier)
  }

  func chooseOtherApplication(model: FileBrowserModel) {
    let panel = NSOpenPanel()
    panel.title = "Choose Terminal Application"
    panel.prompt = "Choose"
    panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.application]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard let bundleIdentifier = Bundle(url: url)?.bundleIdentifier else {
      model.alert = BrowserAlert(
        title: "Cannot Select Terminal",
        message: "The selected application does not have a macOS bundle identifier."
      )
      return
    }
    let application = TerminalApplication(
      bundleIdentifier: bundleIdentifier,
      displayName: applicationDisplayName(at: url),
      url: url
    )
    if !availableApplications.contains(where: { $0.bundleIdentifier == bundleIdentifier }) {
      availableApplications.append(application)
      availableApplications.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
    select(application)
  }

  func open(directory: URL, model: FileBrowserModel) {
    refreshApplications()
    guard let selection else {
      model.alert = BrowserAlert(
        title: "No Terminal Selected",
        message: "Install a terminal or choose an application from the terminal menu."
      )
      return
    }

    Task {
      do {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        _ = try await workspace.open(
          [directory.standardizedFileURL],
          withApplicationAt: selection.url,
          configuration: configuration
        )
      } catch {
        model.alert = BrowserAlert(
          title: "Cannot Open Terminal",
          message: "\(selection.displayName) could not open \(directory.path): \(error.localizedDescription)"
        )
      }
    }
  }

  private func application(for bundleIdentifier: String) -> TerminalApplication? {
    guard let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
      return nil
    }
    return TerminalApplication(
      bundleIdentifier: bundleIdentifier,
      displayName: applicationDisplayName(at: url),
      url: url
    )
  }

  private func applicationDisplayName(at url: URL) -> String {
    let bundleName = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
    let fallbackName = url.deletingPathExtension().lastPathComponent
    return bundleName ?? fallbackName
  }
}

struct TerminalToolbarControl: View {
  @ObservedObject var model: FileBrowserModel
  @EnvironmentObject private var terminalController: TerminalLauncherController

  var body: some View {
    HStack(spacing: 2) {
      Button {
        terminalController.open(directory: model.currentURL, model: model)
      } label: {
        Label(terminalController.actionTitle, systemImage: "terminal")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(ExplorerToolbarButtonStyle())
      .help("\(terminalController.actionTitle) (⌥⌘T)")
      .accessibilityIdentifier("open-terminal")

      Menu {
        ForEach(terminalController.availableApplications) { application in
          Button {
            terminalController.select(application)
          } label: {
            if terminalController.selection?.id == application.id {
              Label(application.displayName, systemImage: "checkmark")
            } else {
              Text(application.displayName)
            }
          }
        }
        Divider()
        Button("Choose Other Application…") {
          terminalController.chooseOtherApplication(model: model)
        }
      } label: {
        Label("Choose Terminal", systemImage: "chevron.down")
          .labelStyle(.iconOnly)
      }
      .menuStyle(.borderlessButton)
      .frame(width: 18, height: 24)
      .help("Choose Terminal Application")
    }
    .onAppear { terminalController.refreshApplications() }
  }
}
