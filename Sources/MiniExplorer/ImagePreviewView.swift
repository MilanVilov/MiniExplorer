import AppKit
import MiniExplorerCore
import SwiftUI

struct ImagePreviewView: View {
  @ObservedObject var model: FileBrowserModel
  @State private var image: NSImage?
  @State private var zoom: CGFloat = 1
  @State private var gestureStartZoom: CGFloat = 1
  @State private var panOffset: CGSize = .zero
  @State private var panStartOffset: CGSize = .zero
  @State private var isPanning = false
  @Environment(\.explorerPalette) private var palette

  var body: some View {
    ZStack {
      palette.contentBackground

      if let item = model.previewItem {
        if let image {
          GeometryReader { geometry in
            let viewport = geometry.size
            let baseSize = fittedImageSize(image: image, in: viewport)
            let scaledSize = CGSize(width: baseSize.width * zoom, height: baseSize.height * zoom)

            ZStack {
              Image(nsImage: image)
                .resizable()
                .frame(width: scaledSize.width, height: scaledSize.height)
                .shadow(color: palette.isFlat ? .clear : .black.opacity(0.18), radius: 10, y: 3)
                .position(
                  x: viewport.width / 2 + panOffset.width,
                  y: viewport.height / 2 + panOffset.height
                )
            }
            .frame(width: viewport.width, height: viewport.height)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(magnificationGesture(baseSize: baseSize, viewport: viewport))
            .simultaneousGesture(panGesture(baseSize: baseSize, viewport: viewport))
            .onChange(of: zoom) { _, _ in
              panOffset = clampedPan(panOffset, baseSize: baseSize, viewport: viewport)
            }
            .onChange(of: geometry.size) { _, _ in
              panOffset = clampedPan(panOffset, baseSize: baseSize, viewport: viewport)
            }
            .contextMenu {
              Button("Copy Image") { copyImage(image) }
              Divider()
              Button("Move to Trash…", role: .destructive) {
                model.requestPreviewTrashConfirmation()
              }
            }
          }
        } else {
          ProgressView("Loading \(item.displayName)…")
        }

        HStack {
          previewButton(systemImage: "chevron.left", label: "Previous Image") {
            model.selectPreviousPreviewImage()
          }
          Spacer()
          previewButton(systemImage: "chevron.right", label: "Next Image") {
            model.selectNextPreviewImage()
          }
        }
        .padding(.horizontal, 18)

        VStack {
          HStack(spacing: 6) {
            PreviewTrashButton(isEnabled: model.previewItem != nil) {
              model.requestPreviewTrashConfirmation()
            }
            Divider().frame(height: 20)
            zoomButton(systemImage: "minus.magnifyingglass", label: "Zoom Out") {
              setZoom(zoom / 1.25)
            }
            Text("\(Int((zoom * 100).rounded()))%")
              .font(.system(size: 12, weight: .medium, design: .monospaced))
              .frame(minWidth: 48)
            zoomButton(systemImage: "plus.magnifyingglass", label: "Zoom In") {
              setZoom(zoom * 1.25)
            }
            zoomButton(systemImage: "arrow.down.right.and.arrow.up.left", label: "Fit Image") {
              setZoom(1)
              panOffset = .zero
            }
          }
          .padding(7)
          .background(palette.selectionBackground)
          .overlay { Rectangle().stroke(palette.border, lineWidth: palette.borderWidth) }
          .padding(.top, 12)

          Spacer()
          Text(item.displayName)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(palette.selectionBackground)
            .overlay { Rectangle().stroke(palette.border, lineWidth: palette.borderWidth) }
            .padding(.bottom, 12)
        }
      } else {
        ContentUnavailableView(
          "No Image Selected",
          systemImage: "photo",
          description: Text("Close Preview and select an image to view it here.")
        )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task(id: model.previewItem?.id) {
      image = nil
      setZoom(1)
      panOffset = .zero
      guard let url = model.previewItem?.url else { return }
      image = NSImage(contentsOf: url)
      if image == nil {
        model.alert = BrowserAlert(
          title: "Cannot Preview Image",
          message: "MiniExplorer could not decode \(url.lastPathComponent)."
        )
      }
    }
    .accessibilityIdentifier("image-preview")
    .focusedSceneValue(
      \.previewTrashAction,
      PreviewTrashAction(isEnabled: model.previewItem != nil) {
        model.requestPreviewTrashConfirmation()
      }
    )
  }

  private func magnificationGesture(baseSize: CGSize, viewport: CGSize) -> some Gesture {
    MagnifyGesture()
      .onChanged { value in
        zoom = min(max(gestureStartZoom * value.magnification, 0.25), 8)
        panOffset = clampedPan(panOffset, baseSize: baseSize, viewport: viewport)
      }
      .onEnded { _ in
        gestureStartZoom = zoom
        panOffset = clampedPan(panOffset, baseSize: baseSize, viewport: viewport)
      }
  }

  private func panGesture(baseSize: CGSize, viewport: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        guard zoom > 1 else { return }
        if !isPanning {
          panStartOffset = panOffset
          isPanning = true
        }
        panOffset = clampedPan(
          CGSize(
            width: panStartOffset.width + value.translation.width,
            height: panStartOffset.height + value.translation.height
          ),
          baseSize: baseSize,
          viewport: viewport
        )
      }
      .onEnded { _ in
        isPanning = false
        panOffset = clampedPan(panOffset, baseSize: baseSize, viewport: viewport)
      }
  }

  private func fittedImageSize(image: NSImage, in viewport: CGSize) -> CGSize {
    let available = CGSize(
      width: max(1, viewport.width - 140),
      height: max(1, viewport.height - 108)
    )
    let imageSize = image.size
    let scale = min(
      available.width / max(1, imageSize.width),
      available.height / max(1, imageSize.height)
    )
    return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
  }

  private func clampedPan(_ proposed: CGSize, baseSize: CGSize, viewport: CGSize) -> CGSize {
    let maximumX = max(0, (baseSize.width * zoom - viewport.width) / 2)
    let maximumY = max(0, (baseSize.height * zoom - viewport.height) / 2)
    return CGSize(
      width: min(max(proposed.width, -maximumX), maximumX),
      height: min(max(proposed.height, -maximumY), maximumY)
    )
  }

  private func copyImage(_ image: NSImage) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects([image])
  }

  private func previewButton(
    systemImage: String,
    label: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 24, weight: .semibold))
        .frame(width: 46, height: 64)
        .background(palette.selectionBackground)
        .overlay { Rectangle().stroke(palette.accent, lineWidth: palette.borderWidth) }
    }
    .buttonStyle(.plain)
    .help(label)
  }

  private func zoomButton(
    systemImage: String,
    label: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .frame(width: 26, height: 24)
    }
    .buttonStyle(.plain)
    .help(label)
  }

  private func setZoom(_ value: CGFloat) {
    zoom = min(max(value, 0.25), 8)
    gestureStartZoom = zoom
  }
}
