import MiniExplorerCore
import SwiftUI

struct AddressBarView: View {
  @ObservedObject var model: FileBrowserModel
  @Environment(\.explorerPalette) private var palette
  @FocusState private var isAddressFocused: Bool
  @FocusState private var isSearchFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Button {
          Task { await model.navigateBack() }
        } label: {
          Label("Back", systemImage: "chevron.left")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(ExplorerToolbarButtonStyle())
        .disabled(!model.canNavigateBack)
        .help("Back")
        .accessibilityIdentifier("navigate-back")

        Button {
          Task { await model.navigate(to: model.homeDirectory) }
        } label: {
          Label("Home", systemImage: "house")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(ExplorerToolbarButtonStyle())
        .help("Home")

        Text("Location:")
          .font(.system(size: 12))
          .foregroundStyle(palette.secondaryText)

        TextField("/path/to/folder", text: $model.addressText)
          .textFieldStyle(.plain)
          .font(.system(size: 12.5, design: .monospaced))
          .padding(.horizontal, 6)
          .frame(height: 23)
          .explorerInputSurface()
          .focused($isAddressFocused)
          .focusedValue(\.fileActionsDisabled, true)
          .onSubmit {
            Task { await model.navigateFromAddress() }
          }
          .accessibilityIdentifier("address-bar")

        Button {
          Task { await model.navigateFromAddress() }
        } label: {
          Label("Go", systemImage: "arrow.right.circle.fill")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(ExplorerToolbarButtonStyle())
        .help("Open Path")

        Button {
          Task { await model.refreshCurrentDirectory() }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(ExplorerToolbarButtonStyle())
        .help("Refresh")

        TerminalToolbarControl(model: model)
      }

      HStack(spacing: 8) {
        Button {
          model.viewMode = .list
          model.closePreview()
        } label: {
          Label("List", systemImage: "list.bullet").labelStyle(.iconOnly)
        }
        .buttonStyle(ExplorerToolbarButtonStyle(isSelected: model.viewMode == .list))
        .help("List View")

        Button {
          model.viewMode = .largeIcons
          model.closePreview()
        } label: {
          Label("Large Icons", systemImage: "square.grid.2x2").labelStyle(.iconOnly)
        }
        .buttonStyle(ExplorerToolbarButtonStyle(isSelected: model.viewMode == .largeIcons))
        .help("Large Icons")

        Button {
          model.togglePreview()
        } label: {
          Label(
            model.isPreviewVisible ? "Close Preview" : "Preview",
            systemImage: model.isPreviewVisible ? "eye.fill" : "eye"
          )
          .labelStyle(.iconOnly)
        }
        .buttonStyle(ExplorerToolbarButtonStyle(isSelected: model.isPreviewVisible))
        .help(model.isPreviewVisible ? "Close Preview" : "Preview Selected File")
        .accessibilityIdentifier("preview-toggle")

        Spacer()

        HStack(spacing: 5) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 11))
            .foregroundStyle(palette.secondaryText)

          TextField("Search", text: $model.searchText)
            .textFieldStyle(.plain)
            .focused($isSearchFocused)
            .focusedValue(\.fileActionsDisabled, true)
            .onKeyPress(.downArrow) {
              model.selectNextSearchResult()
              return .handled
            }
            .onKeyPress(.upArrow) {
              model.selectPreviousSearchResult()
              return .handled
            }
            .onSubmit {
              model.requestSearchResultActivation()
            }

          if !model.searchText.isEmpty {
            Button {
              model.searchText = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(palette.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Clear Search")
          }
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 6)
        .frame(width: 180, height: 23)
        .explorerInputSurface()
        .accessibilityIdentifier("folder-search")
      }

      if let addressError = model.addressError {
        Text(addressError)
          .font(.caption)
          .foregroundStyle(palette.error)
          .padding(.leading, 30)
          .accessibilityIdentifier("address-error")
      }
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 7)
    .background(palette.toolbarBackground)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(palette.accent)
        .frame(height: 1)
    }
    .onChange(of: model.searchFocusRequest) { _, _ in
      isSearchFocused = true
    }
    .onChange(of: model.fileInteractionFocusRequest) { _, _ in
      isAddressFocused = false
      isSearchFocused = false
    }
  }
}
