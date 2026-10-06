import AppKit
import MiniExplorerCore
import SwiftUI

struct ContentView: View {
  @ObservedObject var model: FileBrowserModel
  private let volumeMonitor = WorkspaceVolumeMonitor()
  @Environment(\.explorerPalette) private var palette
  @FocusedValue(\.previewFindActions) private var previewFindActions

  var body: some View {
    NavigationSplitView {
      SidebarView(model: model)
        .navigationSplitViewColumnWidth(min: 190, ideal: 245, max: 360)
    } detail: {
      VStack(spacing: 0) {
        AddressBarView(model: model)
        Divider()
        if !model.searchText.isEmpty && model.items.isEmpty {
          ContentUnavailableView(
            "No Matching Files",
            systemImage: "magnifyingglass",
            description: Text("No names in this folder contain “\(model.searchText)”.")
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.isPreviewVisible {
          if model.previewKind == .image {
            ImagePreviewView(model: model)
          } else if let item = model.previewItem, let kind = model.previewKind {
            if kind == .pdf {
              PDFPreviewView(item: item, model: model)
                .id(item.id)
            } else {
              TextPreviewView(item: item, kind: kind, model: model)
                .id(item.id)
            }
          }
        } else {
          switch model.viewMode {
          case .list:
            FileTableView(model: model)
          case .largeIcons:
            LargeIconGridView(model: model)
          }
        }
      }
      .overlay {
        if model.isLoading {
          ProgressView()
            .padding(14)
            .background(palette.selectionBackground)
            .overlay { Rectangle().stroke(palette.accent, lineWidth: palette.borderWidth) }
        }
      }
    }
    .navigationSplitViewStyle(.balanced)
    .tint(palette.isFlat ? palette.primaryText : palette.accent)
    .foregroundStyle(palette.primaryText)
    .font(
      palette.isFlat
        ? .system(
          size: 13,
          weight: palette.isRetro ? .bold : .regular,
          design: .monospaced
        )
        : .body
    )
    .background(palette.contentBackground)
    .overlay {
      if palette.id == .tokyoNight {
        Rectangle()
          .stroke(palette.accent, lineWidth: 2)
          .allowsHitTesting(false)
      }
    }
    .task {
      await model.start()
    }
    .onReceive(volumeMonitor.events) { _ in
      Task { await model.refreshVolumes() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .miniExplorerEscapePressed)) { _ in
      if model.isPreviewVisible {
        if previewFindActions?.dismissIfPresented() != true {
          model.closePreview()
        }
      }
    }
    .onChange(of: model.searchActivationRequest) { _, _ in
      activatePrimaryItem()
    }
    .onChange(of: model.primaryItemActivationRequest) { _, _ in
      activatePrimaryItem()
    }
    .alert(item: $model.alert) { alert in
      Alert(
        title: Text(alert.title),
        message: Text(alert.message),
        dismissButton: .default(Text("OK"))
      )
    }
    .sheet(isPresented: $model.isClipboardHistoryPresented) {
      ClipboardHistoryView(model: model)
    }
    .sheet(isPresented: $model.isRenamePresented) {
      RenameItemView(model: model)
    }
    .sheet(isPresented: $model.isFileInfoPresented) {
      FileInfoView(model: model)
    }
    .alert("Move to Trash?", isPresented: $model.isTrashConfirmationPresented) {
      Button("Cancel", role: .cancel) {}
      Button("Move to Trash", role: .destructive) {
        Task { await model.trashSelection() }
      }
    } message: {
      Text(
        model.trashConfirmationItemCount == 1
          ? "Move \(model.trashConfirmationDisplayName ?? "this item") to macOS Trash?"
          : "Move \(model.trashConfirmationItemCount) selected items to macOS Trash?"
      )
    }
  }

  private func activatePrimaryItem() {
    guard let item = model.primaryItem else { return }
    if item.isDirectory && !item.isPackage {
      Task { await model.navigate(to: item.url) }
    } else if model.previewFileIfSupported(item) {
      return
    } else if !NSWorkspace.shared.open(item.url) {
      model.alert = BrowserAlert(
        title: "Cannot Open Item",
        message: "macOS could not find an application to open \(item.displayName)."
      )
    }
  }
}

extension Notification.Name {
  static let miniExplorerEscapePressed = Notification.Name("MiniExplorerEscapePressed")
}
