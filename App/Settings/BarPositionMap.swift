import AppKit
import SpreekCore
import SwiftUI

/// Settings › Floating Bar › Position: a small screen with the six spots a bar can sit in
/// Click a spot, or focus the map and use the arrow keys.
/// `dragged` draws a dashed bar where the user last dragged one.
struct BarPositionMap: View {
    @Binding var selection: FloatingBarPosition
    /// Gray instead of accent: in "Where I left it" the spot is only the starting point.
    var isStartingPoint = false
    var dragged: FloatingBarDragPosition?

    static let size = CGSize(width: 176, height: 110)
    private static let spot = CGSize(width: 44, height: 12)
    private static let menuBarHeight: CGFloat = 9
    private static let inset: CGFloat = 10

    @FocusState private var isFocused: Bool

    var body: some View {
        let screen = RoundedRectangle(cornerRadius: 9, style: .continuous)
        ZStack(alignment: .topLeading) {
            screen.fill(Color.windowBG)
            UnevenRoundedRectangle(topLeadingRadius: 9, topTrailingRadius: 9, style: .continuous)
                .fill(Color.separator)
                .frame(height: Self.menuBarHeight)
            ForEach(FloatingBarPosition.allCases, id: \.self) { position in
                let selected = position == selection
                Capsule()
                    .fill(selected ? (isStartingPoint ? Color.fg3 : Color.accentColor) : Color.control)
                    .overlay(Capsule().strokeBorder(Color.separator, lineWidth: selected ? 0 : Metrics.hairline))
                    .frame(width: Self.spot.width, height: Self.spot.height)
                    .contentShape(Capsule().inset(by: -6))
                    .onTapGesture { selection = position }
                    .offset(Self.origin(of: position))
                    .help(position.title)
            }
            if let ghost = draggedOrigin {
                Capsule()
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                    .frame(width: Self.spot.width, height: Self.spot.height)
                    .offset(ghost)
                    .allowsHitTesting(false)
                    .help("Where you last dragged the bar")
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .overlay(screen.strokeBorder(isFocused ? Color.accentColor : Color.separator, lineWidth: isFocused ? 2 : Metrics.hairline))
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            selection = selection.moved(press.key)
            return .handled
        }
        .accessibilityRepresentation {
            Picker("Bar position", selection: $selection) {
                ForEach(FloatingBarPosition.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        }
    }

    private static func origin(of position: FloatingBarPosition) -> CGSize {
        let x: CGFloat = switch position {
        case .topLeft, .bottomLeft: inset
        case .topCenter, .bottomCenter: (size.width - spot.width) / 2
        case .topRight, .bottomRight: size.width - inset - spot.width
        }
        let y: CGFloat = switch position {
        case .topLeft, .topCenter, .topRight: menuBarHeight + 8
        case .bottomLeft, .bottomCenter, .bottomRight: size.height - 10 - spot.height
        }
        return CGSize(width: x, height: y)
    }

    /// The dragged bar's center, scaled from its screen (or the main one) onto the map.
    private var draggedOrigin: CGSize? {
        guard let dragged,
              let screen = dragged.screenID.flatMap(NSScreen.screen(withDisplayUUID:)) ?? NSScreen.main
        else { return nil }
        let frame = screen.frame
        let bar = CGSize(width: FloatingBarLayout.width, height: Metrics.floatingBarHeight)
        let glass = FloatingBarPlacement.anchor(for: dragged, in: screen.visibleFrame).frame(for: bar, in: screen.visibleFrame)
        let centerX = (glass.midX - frame.minX) / frame.width * Self.size.width
        let centerY = (frame.maxY - glass.midY) / frame.height * Self.size.height
        return CGSize(
            width: min(max(centerX - Self.spot.width / 2, 2), Self.size.width - Self.spot.width - 2),
            height: min(max(centerY - Self.spot.height / 2, Self.menuBarHeight + 2), Self.size.height - Self.spot.height - 2)
        )
    }
}

extension FloatingBarPosition {
    var title: String {
        switch self {
        case .topLeft: "Top left"
        case .topCenter: "Top center"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomCenter: "Bottom center"
        case .bottomRight: "Bottom right"
        }
    }

    /// The neighbor in the 3×2 grid; stays put at the edges.
    func moved(_ key: KeyEquivalent) -> FloatingBarPosition {
        let grid: [[FloatingBarPosition]] = [[.topLeft, .topCenter, .topRight], [.bottomLeft, .bottomCenter, .bottomRight]]
        let row = grid.firstIndex { $0.contains(self) } ?? 1
        var column = grid[row].firstIndex(of: self) ?? 1
        var newRow = row
        switch key {
        case .leftArrow: column = max(column - 1, 0)
        case .rightArrow: column = min(column + 1, 2)
        case .upArrow: newRow = 0
        case .downArrow: newRow = 1
        default: break
        }
        return grid[newRow][column]
    }
}
