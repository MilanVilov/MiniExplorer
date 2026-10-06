import Foundation

public enum PDFPreviewSizing {
  public static func fitWidthScale(
    viewWidth: Double,
    pageWidth: Double,
    horizontalInset: Double,
    minimumScale: Double,
    maximumScale: Double
  ) -> Double {
    guard pageWidth > 0 else { return minimumScale }
    let availableWidth = max(viewWidth - horizontalInset, 1)
    return min(max(availableWidth / pageWidth, minimumScale), maximumScale)
  }
}
