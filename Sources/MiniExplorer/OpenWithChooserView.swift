import AppKit
import MiniExplorerCore
import SwiftUI

struct OpenWithChooserView: View {
  let item: FileItem
  @Environment(\.dismiss) private var dismiss
  @Environment(\.explorerPalette) private var palette
  @State private var applications: [ApplicationChoice] = []
  @State private var searchText = ""
  @State private var isLoading = true
  @State private var errorMessage: String?

  private var filteredApplications: [ApplicationChoice] {
    ApplicationChoice.filtered(applications, query: searchText)
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        ExplorerItemIcon(item: item, size: 30)
        VStack(alignment: .leading, spacing: 2) {
          Text("Open With")
            .font(.system(size: 17, weight: .semibold))
          Text(item.displayName)
            .font(.system(size: 12))
            .foregroundStyle(palette.secondaryText)
            .lineLimit(1)
        }
        Spacer()
      }
      .padding(16)

      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(palette.secondaryText)
        TextField("Search installed applications", text: $searchText)
          .focusedValue(\.fileActionsDisabled, true)
          .textFieldStyle(.plain)
      }
      .padding(.horizontal, 11)
      .frame(height: 34)
      .explorerInputSurface()
      .padding(.horizontal, 16)
      .padding(.bottom, 12)

      Divider()

      Group {
        if isLoading {
          ProgressView("Finding applications…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
          ContentUnavailableView(
            "Cannot Find Applications",
            systemImage: "app.dashed",
            description: Text(errorMessage)
          )
        } else if filteredApplications.isEmpty {
          ContentUnavailableView.search(text: searchText)
        } else {
          List(filteredApplications) { application in
            Button {
              open(with: application)
            } label: {
              HStack(spacing: 11) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                  .resizable()
                  .scaledToFit()
                  .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                  Text(application.displayName)
                    .foregroundStyle(palette.primaryText)
                  Text(application.isCompatible ? "Recommended for this file" : "Application")
                    .font(.system(size: 10.5))
                    .foregroundStyle(application.isCompatible ? palette.accent : palette.secondaryText)
                }
                Spacer()
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
          .listStyle(.inset)
          .scrollContentBackground(.hidden)
          .background(palette.contentBackground)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      Divider()
      HStack {
        Text("Compatible applications are listed first.")
          .font(.system(size: 11))
          .foregroundStyle(palette.secondaryText)
        Spacer()
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
      }
      .padding(12)
    }
    .frame(width: 560, height: 520)
    .foregroundStyle(palette.primaryText)
    .background(palette.contentBackground)
    .task {
      applications = await ApplicationDiscovery.applications(for: item.url)
      isLoading = false
    }
    .accessibilityIdentifier("open-with-chooser")
  }

  private func open(with application: ApplicationChoice) {
    let configuration = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.open(
      [item.url],
      withApplicationAt: application.url,
      configuration: configuration
    ) { _, error in
      Task { @MainActor in
        if let error {
          errorMessage = error.localizedDescription
        } else {
          dismiss()
        }
      }
    }
  }
}

@MainActor
private enum ApplicationDiscovery {
  static func applications(for fileURL: URL) async -> [ApplicationChoice] {
    let compatibleURLs = Set(
      NSWorkspace.shared.urlsForApplications(toOpen: fileURL).map(\.standardizedFileURL)
    )
    let installedURLs = await Task.detached(priority: .userInitiated) {
      discoverInstalledApplicationURLs()
    }.value
    let allURLs = Set(installedURLs).union(compatibleURLs)
    return allURLs.map { url in
      ApplicationChoice(
        url: url,
        displayName: FileManager.default.displayName(atPath: url.path),
        isCompatible: compatibleURLs.contains(url.standardizedFileURL)
      )
    }
  }

  nonisolated private static func discoverInstalledApplicationURLs() -> [URL] {
    let fileManager = FileManager.default
    var roots = fileManager.urls(for: .applicationDirectory, in: .allDomainsMask)
    roots.append(URL(fileURLWithPath: "/System/Applications", isDirectory: true))
    roots.append(
      FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications", isDirectory: true)
    )
    var applications = Set<URL>()

    for root in Set(roots.map(\.standardizedFileURL)) {
      guard
        let enumerator = fileManager.enumerator(
          at: root,
          includingPropertiesForKeys: [.isApplicationKey],
          options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
      else { continue }

      while let url = enumerator.nextObject() as? URL {
        guard url.pathExtension.lowercased() == "app" else { continue }
        applications.insert(url.standardizedFileURL)
        enumerator.skipDescendants()
      }
    }
    return Array(applications)
  }
}
