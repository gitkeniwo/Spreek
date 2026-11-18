import CoreGraphics

/// "Position:" where a new floating bar appears. A bar that is showing can always be dragged;
/// it stays there (pinned or not) until it hides.
public enum FloatingBarPlacementMode: String, Codable, CaseIterable, Sendable {
    /// At the chosen `FloatingBarPosition`.
    case fixed
    /// Next to the selected text, or the pointer when the app doesn't say where the selection is.
    case nearSelection
    /// Where the user last dragged a bar; the chosen `FloatingBarPosition` until they have.
    case lastDragged
}

/// One of the six spots on the screen map. `bottomCenter` and `topCenter` predate the corners and
/// keep their raw values.
public enum FloatingBarPosition: String, Codable, CaseIterable, Sendable {
    case topLeft, topCenter, topRight, bottomLeft, bottomCenter, bottomRight
}

/// Where a bar was dragged to, kept relative to the nearest corner of its screen's visible frame
/// so it still makes sense after a resolution or arrangement change.
public struct FloatingBarDragPosition: Codable, Hashable, Sendable {
    public enum Horizontal: String, Codable, Sendable { case left, right }
    public enum Vertical: String, Codable, Sendable { case top, bottom }

    /// Display UUID of the screen it was on; when that screen is gone the pointer's is used.
    public var screenID: String?
    public var horizontal: Horizontal
    /// From the visible frame's `horizontal` edge to the bar's same edge.
    public var horizontalInset: CGFloat
    public var vertical: Vertical
    /// From the visible frame's `vertical` edge to the bar's same edge.
    public var verticalInset: CGFloat

    public init(screenID: String?, horizontal: Horizontal, horizontalInset: CGFloat, vertical: Vertical, verticalInset: CGFloat) {
        self.screenID = screenID
        self.horizontal = horizontal
        self.horizontalInset = horizontalInset
        self.vertical = vertical
        self.verticalInset = verticalInset
    }
}

/// Fixes one horizontal and one vertical reference of the bar's glass, so a bar that changes size
/// (pinning expands it to the card) grows away from that edge. Coordinates are Cocoa screen
/// coordinates (origin bottom-left, y up).
public struct FloatingBarAnchor: Hashable, Sendable {
    public enum Horizontal: Sendable { case left, center, right }
    /// `.top`: the top edge stays put and the bar grows downward.
    public enum Vertical: Sendable { case top, bottom }

    public var x: CGFloat
    public var horizontal: Horizontal
    public var y: CGFloat
    public var vertical: Vertical

    public init(x: CGFloat, horizontal: Horizontal, y: CGFloat, vertical: Vertical) {
        self.x = x
        self.horizontal = horizontal
        self.y = y
        self.vertical = vertical
    }

    /// The glass frame for `size`, kept inside `visible`.
    public func frame(for size: CGSize, in visible: CGRect) -> CGRect {
        let originX = switch horizontal {
        case .left: x
        case .center: x - size.width / 2
        case .right: x - size.width
        }
        let originY = vertical == .bottom ? y : y - size.height
        return FloatingBarPlacement.clamp(CGRect(origin: CGPoint(x: originX, y: originY), size: size), to: visible)
    }
}

/// Placement math for the floating bar's glass (without its shadow margins).
public enum FloatingBarPlacement {
    /// Inset from the visible frame for the six fixed spots.
    public static let screenGap: CGFloat = 34
    /// Space between the selection (or pointer) and the bar.
    public static let selectionGap: CGFloat = 10
    /// The arrow pointer's height below its hot spot, which is the area the bar keeps clear.
    public static let pointerHeight: CGFloat = 22

    /// One of the six spots; top spots grow downward, bottom spots upward.
    public static func anchor(for position: FloatingBarPosition, in visible: CGRect, gap: CGFloat = screenGap) -> FloatingBarAnchor {
        let (x, horizontal): (CGFloat, FloatingBarAnchor.Horizontal) = switch position {
        case .topLeft, .bottomLeft: (visible.minX + gap, .left)
        case .topCenter, .bottomCenter: (visible.midX, .center)
        case .topRight, .bottomRight: (visible.maxX - gap, .right)
        }
        return switch position {
        case .topLeft, .topCenter, .topRight: FloatingBarAnchor(x: x, horizontal: horizontal, y: visible.maxY - gap, vertical: .top)
        case .bottomLeft, .bottomCenter, .bottomRight: FloatingBarAnchor(x: x, horizontal: horizontal, y: visible.minY + gap, vertical: .bottom)
        }
    }

    /// Centered below `target` (the selection's bounds), growing downward; above it, growing upward,
    /// when a bar of `size` doesn't fit below. When it fits neither way, the side with more room.
    public static func anchor(nextTo target: CGRect, size: CGSize, in visible: CGRect, gap: CGFloat = selectionGap) -> FloatingBarAnchor {
        let roomBelow = target.minY - gap - visible.minY
        let roomAbove = visible.maxY - (target.maxY + gap)
        let below = roomBelow >= size.height || (roomAbove < size.height && roomBelow >= roomAbove)
        return below
            ? FloatingBarAnchor(x: target.midX, horizontal: .center, y: target.minY - gap, vertical: .top)
            : FloatingBarAnchor(x: target.midX, horizontal: .center, y: target.maxY + gap, vertical: .bottom)
    }

    /// Near the pointer at `location` (its hot spot): below the arrow, or above it.
    public static func anchor(nearPointer location: CGPoint, size: CGSize, in visible: CGRect) -> FloatingBarAnchor {
        let arrow = CGRect(x: location.x, y: location.y - pointerHeight, width: 0, height: pointerHeight)
        return anchor(nextTo: arrow, size: size, in: visible)
    }

    /// A remembered drag position on a screen whose visible frame is `visible`.
    public static func anchor(for drag: FloatingBarDragPosition, in visible: CGRect) -> FloatingBarAnchor {
        FloatingBarAnchor(
            x: drag.horizontal == .left ? visible.minX + drag.horizontalInset : visible.maxX - drag.horizontalInset,
            horizontal: drag.horizontal == .left ? .left : .right,
            y: drag.vertical == .bottom ? visible.minY + drag.verticalInset : visible.maxY - drag.verticalInset,
            vertical: drag.vertical == .bottom ? .bottom : .top
        )
    }

    /// Records a bar the user dropped at `glass`, relative to the visible frame's nearest corner.
    public static func dragPosition(for glass: CGRect, in visible: CGRect, screenID: String?) -> FloatingBarDragPosition {
        let left = glass.midX < visible.midX
        let bottom = glass.midY < visible.midY
        return FloatingBarDragPosition(
            screenID: screenID,
            horizontal: left ? .left : .right,
            horizontalInset: (left ? glass.minX - visible.minX : visible.maxX - glass.maxX).rounded(),
            vertical: bottom ? .bottom : .top,
            verticalInset: (bottom ? glass.minY - visible.minY : visible.maxY - glass.maxY).rounded()
        )
    }

    /// `rect` moved (not resized) so it lies inside `bounds`; when it is larger, its top-left wins.
    public static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        var origin = rect.origin
        origin.x = max(min(origin.x, bounds.maxX - rect.width), bounds.minX)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - rect.height)
        return CGRect(origin: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: rect.size)
    }
}
