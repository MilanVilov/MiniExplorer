import CoreGraphics

public enum MarqueeSelection {
  public static func rectangle(from start: CGPoint, to end: CGPoint) -> CGRect {
    CGRect(
      x: min(start.x, end.x),
      y: min(start.y, end.y),
      width: abs(end.x - start.x),
      height: abs(end.y - start.y)
    )
  }

  public static func intersectingIDs<ID: Hashable>(
    visibleIDs: [ID],
    frames: [ID: CGRect],
    rectangle: CGRect
  ) -> [ID] {
    visibleIDs.filter { id in
      frames[id]?.intersects(rectangle) == true
    }
  }

  public static func resolvedIDs<ID: Hashable>(
    baseline: [ID],
    hits: [ID],
    togglesBaseline: Bool,
    visibleIDs: [ID]
  ) -> [ID] {
    let selected: Set<ID>
    if togglesBaseline {
      selected = Set(baseline).symmetricDifference(Set(hits))
    } else {
      selected = Set(hits)
    }
    return visibleIDs.filter(selected.contains)
  }
}
