import Foundation

/// Geometry of the dashboard footer's mirrored activity chart: columns fill the available width
/// with fixed gaps, and every non-zero day gets a visible bar.
public struct ActivityChartLayout: Sendable, Hashable {
    /// Gap between day columns.
    public static let gap = 2.0
    /// A day with at least one listen (or save) never draws a shorter bar than this.
    public static let minimumBarHeight = 3.0

    public let dayCount: Int
    public let width: Double
    /// Height of one half (plays above the center line, saves below).
    public let halfHeight: Double
    /// The busiest day's count; both halves scale to it.
    public let scale: Int

    public init(dayCount: Int, width: Double, halfHeight: Double, scale: Int) {
        self.dayCount = max(dayCount, 0)
        self.width = max(width, 0)
        self.halfHeight = max(halfHeight, 0)
        self.scale = max(scale, 1)
    }

    /// Flexible column width so `dayCount` columns and their gaps span `width`.
    public var columnWidth: Double {
        guard dayCount > 0 else { return 0 }
        return max((width - Self.gap * Double(dayCount - 1)) / Double(dayCount), 0)
    }

    /// Left edge of column `index`.
    public func columnX(_ index: Int) -> Double {
        Double(index) * (columnWidth + Self.gap)
    }

    /// The column under `x` (gaps belong to the column on their left); `nil` outside the chart.
    public func columnIndex(at x: Double) -> Int? {
        guard dayCount > 0, x >= 0, x < width else { return nil }
        return min(Int(x / (columnWidth + Self.gap)), dayCount - 1)
    }

    /// Bar height for `count`: 0 for none, otherwise proportional to `scale` but at least
    /// `minimumBarHeight` (capped by the half height).
    public func barHeight(_ count: Int) -> Double {
        guard count > 0, halfHeight > 0 else { return 0 }
        let proportional = halfHeight * Double(min(count, scale)) / Double(scale)
        return min(max(proportional, Self.minimumBarHeight), halfHeight)
    }
}
