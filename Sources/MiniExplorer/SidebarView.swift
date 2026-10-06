import MiniExplorerCore
import SwiftUI

struct SidebarView: View {
  @ObservedObject var model: FileBrowserModel
  @State private var isAddingShortcut = false
  @Environment(\.explorerPalette) private var palette

  var body: some View {
    List {
      Section {
        ForEach(model.shortcuts) { shortcut in
          Button {
            Task { await model.navigate(to: shortcut.url) }
          } label: {
            HStack(spacing: 6) {
              Image(systemName: "folder.fill")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(palette.folderLight)
                .frame(width: 16)
              Text(shortcut.displayName)
                .font(.system(size: 12.5))
                .lineLimit(1)
              Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .help(shortcut.url.path)
          .contextMenu {
            Button("Remove Shortcut", role: .destructive) {
              Task { await model.removeShortcut(shortcut.url) }
            }
          }
          .accessibilityIdentifier("shortcut-\(shortcut.url.path)")
        }

        Button {
          Task { await model.saveCurrentFolderShortcut() }
        } label: {
          Label("Save Current Folder", systemImage: "bookmark.badge.plus")
            .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.accent)
        .accessibilityIdentifier("save-current-shortcut")

        Button {
          isAddingShortcut = true
        } label: {
          Label("Add Address…", systemImage: "plus")
            .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.accent)
        .accessibilityIdentifier("add-shortcut")
      } header: {
        Text("Shortcuts")
      }

      Section("Computer") {
        ForEach(model.volumes) { volume in
          FolderTreeRow(item: volume, model: model, depth: 0)
            .id(volume.id)
        }
      }
    }
    .listStyle(.sidebar)
    .environment(\.defaultMinListRowHeight, 22)
    .scrollContentBackground(.hidden)
    .background(palette.sidebarBackground)
    .tint(palette.isFlat ? palette.primaryText : palette.accent)
    .accessibilityIdentifier("volume-sidebar")
    .sheet(isPresented: $isAddingShortcut) {
      AddShortcutView(model: model, isPresented: $isAddingShortcut)
    }
  }
}

private struct AddShortcutView: View {
  @ObservedObject var model: FileBrowserModel
  @Binding var isPresented: Bool
  @State private var path = ""
  @FocusState private var isPathFocused: Bool
  @Environment(\.explorerPalette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Add Folder Shortcut")
        .font(.headline)

      Text("Paste an absolute path or a path beginning with ~.")
        .font(.callout)
        .foregroundStyle(palette.secondaryText)

      TextField("~/Pictures", text: $path)
        .textFieldStyle(.plain)
        .padding(.horizontal, 9)
        .frame(height: 30)
        .explorerInputSurface()
        .focused($isPathFocused)
        .focusedValue(\.fileActionsDisabled, true)
        .onSubmit(save)
        .accessibilityIdentifier("shortcut-address")

      HStack {
        Spacer()
        Button("Cancel") {
          isPresented = false
        }
        .keyboardShortcut(.cancelAction)

        Button("Save") {
          save()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 440)
    .foregroundStyle(palette.primaryText)
    .background(palette.contentBackground)
    .onAppear {
      isPathFocused = true
    }
  }

  private func save() {
    Task {
      if await model.addShortcut(path: path) {
        isPresented = false
      }
    }
  }
}

private struct FolderTreeRow: View {
  let item: FileItem
  @ObservedObject var model: FileBrowserModel
  let depth: Int

  @State private var isExpanded = false
  @State private var children: [FileItem]?
  @State private var isLoading = false
  @State private var isDropTarget = false
  @Environment(\.explorerPalette) private var palette

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      if isLoading {
        ProgressView()
          .controlSize(.small)
          .padding(.leading, 18)
      } else if let children {
        ForEach(children) { child in
          FolderTreeRow(item: child, model: model, depth: depth + 1)
        }
      }
    } label: {
      HStack(spacing: 6) {
        ExplorerItemIcon(item: item, size: 16, isVolumeRoot: depth == 0)
        Text(item.displayName)
          .font(.system(size: 12.5))
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.vertical, 2)
      .padding(.horizontal, 3)
      .background(isDropTarget ? palette.accent.opacity(0.16) : Color.clear)
      .overlay {
        if isDropTarget {
          Rectangle()
            .stroke(palette.accent, lineWidth: max(2, palette.borderWidth))
            .allowsHitTesting(false)
        }
      }
      .contentShape(Rectangle())
      .onTapGesture {
        Task { await model.navigate(to: item.url) }
      }
    }
    .onChange(of: isExpanded) { _, expanded in
      guard expanded, children == nil else { return }
      isLoading = true
      Task {
        children = await model.sidebarChildren(of: item.url)
        isLoading = false
      }
    }
    .onChange(of: model.showsHiddenFiles) { _, _ in
      children = nil
      guard isExpanded else { return }
      isLoading = true
      Task {
        children = await model.sidebarChildren(of: item.url)
        isLoading = false
      }
    }
    .dropDestination(for: URL.self) { urls, _ in
      let internalSources = model.draggedItemURLs
      let transferredURLs = internalSources.isEmpty ? urls : internalSources
      Task {
        await model.receiveDrop(
          transferredURLs,
          into: item.url,
          internalSources: internalSources
        )
        model.endDragging()
      }
      return true
    } isTargeted: { targeted in
      isDropTarget = targeted
    }
  }
}
