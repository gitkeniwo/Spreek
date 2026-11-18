import CoreGraphics
import Testing
@testable import SpreekCore

@Suite struct FloatingBarPlacementTests {
    /// A 1440×900 screen with a 25 pt menu bar and a 70 pt Dock.
    private let visible = CGRect(x: 0, y: 70, width: 1440, height: 805)
    private let bar = CGSize(width: 560, height: 56)
    private let card = CGSize(width: 560, height: 240)

    @Test func fixedSpotsSitTheGapInsideTheVisibleFrame() {
        let gap = FloatingBarPlacement.screenGap
        func frame(_ position: FloatingBarPosition) -> CGRect {
            FloatingBarPlacement.anchor(for: position, in: visible).frame(for: bar, in: visible)
        }
        #expect(frame(.bottomCenter) == CGRect(x: 440, y: 70 + gap, width: 560, height: 56))
        #expect(frame(.topCenter) == CGRect(x: 440, y: 875 - gap - 56, width: 560, height: 56))
        #expect(frame(.topLeft).origin == CGPoint(x: gap, y: 875 - gap - 56))
        #expect(frame(.topRight).maxX == 1440 - gap)
        #expect(frame(.bottomLeft).origin == CGPoint(x: gap, y: 70 + gap))
        #expect(frame(.bottomRight).maxX == 1440 - gap)
        #expect(frame(.bottomRight).minY == 70 + gap)
    }

    @Test func topSpotsGrowDownAndBottomSpotsGrowUp() {
        let top = FloatingBarPlacement.anchor(for: .topRight, in: visible)
        #expect(top.frame(for: card, in: visible).maxY == top.frame(for: bar, in: visible).maxY)
        let bottom = FloatingBarPlacement.anchor(for: .bottomLeft, in: visible)
        #expect(bottom.frame(for: card, in: visible).minY == bottom.frame(for: bar, in: visible).minY)
    }

    @Test func nearSelectionGoesBelowAndCentersOnIt() {
        let selection = CGRect(x: 600, y: 500, width: 200, height: 18)
        let anchor = FloatingBarPlacement.anchor(nextTo: selection, size: bar, in: visible)
        let frame = anchor.frame(for: bar, in: visible)
        #expect(frame.maxY == selection.minY - FloatingBarPlacement.selectionGap)
        #expect(frame.midX == selection.midX)
        // Pinning grows the card downward, away from the text.
        #expect(anchor.frame(for: card, in: visible).maxY == frame.maxY)
    }

    @Test func nearSelectionFlipsAboveWhenThereIsNoRoomBelow() {
        let selection = CGRect(x: 600, y: 100, width: 200, height: 18)
        let anchor = FloatingBarPlacement.anchor(nextTo: selection, size: bar, in: visible)
        let frame = anchor.frame(for: bar, in: visible)
        #expect(frame.minY == selection.maxY + FloatingBarPlacement.selectionGap)
        #expect(anchor.frame(for: card, in: visible).minY == frame.minY)
    }

    @Test func aSelectionTallerThanTheRoomEitherWayPicksTheBiggerSide() {
        let paragraph = CGRect(x: 100, y: 200, width: 900, height: 620)
        let anchor = FloatingBarPlacement.anchor(nextTo: paragraph, size: card, in: visible)
        // 120 pt below, 45 pt above: below, clamped onto the screen.
        #expect(anchor.vertical == .top)
        #expect(visible.contains(anchor.frame(for: card, in: visible)))
    }

    @Test func nearTheEdgesTheBarStaysOnScreen() {
        let selection = CGRect(x: 1400, y: 600, width: 30, height: 18)
        let frame = FloatingBarPlacement.anchor(nextTo: selection, size: bar, in: visible).frame(for: bar, in: visible)
        #expect(frame.maxX == visible.maxX)
        #expect(visible.contains(frame))
    }

    @Test func pointerFallbackClearsTheArrow() {
        let pointer = CGPoint(x: 700, y: 600)
        let frame = FloatingBarPlacement.anchor(nearPointer: pointer, size: bar, in: visible).frame(for: bar, in: visible)
        #expect(frame.maxY == pointer.y - FloatingBarPlacement.pointerHeight - FloatingBarPlacement.selectionGap)
        #expect(frame.midX == pointer.x)
    }

    @Test func dragPositionIsRelativeToTheNearestCorner() {
        let glass = CGRect(x: 1000, y: 700, width: 560, height: 56).offsetBy(dx: -200, dy: 0)
        let drag = FloatingBarPlacement.dragPosition(for: glass, in: visible, screenID: "S")
        #expect(drag.horizontal == .right && drag.horizontalInset == 1440 - glass.maxX)
        #expect(drag.vertical == .top && drag.verticalInset == 875 - glass.maxY)
        // Same screen: same frame.
        #expect(FloatingBarPlacement.anchor(for: drag, in: visible).frame(for: bar, in: visible) == glass)
        // A bigger screen: same distance from its top-right corner.
        let big = CGRect(x: 0, y: 0, width: 2560, height: 1415)
        let moved = FloatingBarPlacement.anchor(for: drag, in: big).frame(for: bar, in: big)
        #expect(big.maxX - moved.maxX == drag.horizontalInset)
        #expect(big.maxY - moved.maxY == drag.verticalInset)
    }

    @Test func aDraggedBarInTheLowerHalfGrowsUp() {
        let glass = CGRect(x: 100, y: 200, width: 560, height: 56)
        let drag = FloatingBarPlacement.dragPosition(for: glass, in: visible, screenID: nil)
        #expect(drag.horizontal == .left && drag.vertical == .bottom)
        let anchor = FloatingBarPlacement.anchor(for: drag, in: visible)
        #expect(anchor.frame(for: card, in: visible).minY == glass.minY)
    }

    @Test func aRememberedPositionOffASmallerScreenIsPulledBackOn() {
        let drag = FloatingBarDragPosition(screenID: nil, horizontal: .left, horizontalInset: 2000, vertical: .bottom, verticalInset: 1200)
        let frame = FloatingBarPlacement.anchor(for: drag, in: visible).frame(for: bar, in: visible)
        #expect(visible.contains(frame))
        #expect(frame.maxX == visible.maxX && frame.maxY == visible.maxY)
    }
}
