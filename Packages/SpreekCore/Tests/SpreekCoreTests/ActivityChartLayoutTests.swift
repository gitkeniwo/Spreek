import Foundation
import Testing
@testable import SpreekCore

@Suite struct ActivityChartLayoutTests {
    @Test(arguments: [30, 90])
    func columnsFillTheWidth(days: Int) {
        let layout = ActivityChartLayout(dayCount: days, width: 406, halfHeight: 41, scale: 10)
        let total = layout.columnWidth * Double(days) + ActivityChartLayout.gap * Double(days - 1)
        #expect(abs(total - 406) < 0.0001)
        #expect(layout.columnWidth > 0)
        #expect(abs(layout.columnX(days - 1) + layout.columnWidth - 406) < 0.0001)
    }

    @Test func thirtyDaysAreWiderThanTheOldFixedStrip() {
        let layout = ActivityChartLayout(dayCount: 30, width: 406, halfHeight: 41, scale: 1)
        #expect(layout.columnWidth > 4.5)
        #expect(ActivityChartLayout(dayCount: 30, width: 600, halfHeight: 41, scale: 1).columnWidth > layout.columnWidth)
    }

    @Test func barsScaleToTheBusiestDay() {
        let layout = ActivityChartLayout(dayCount: 30, width: 406, halfHeight: 40, scale: 20)
        #expect(layout.barHeight(20) == 40)
        #expect(layout.barHeight(10) == 20)
        #expect(layout.barHeight(5) == 10)
    }

    @Test func smallNonZeroDaysGetTheMinimumHeight() {
        // 1 save next to a 200-play day would be 0.2 pt proportionally.
        let layout = ActivityChartLayout(dayCount: 90, width: 406, halfHeight: 41, scale: 200)
        #expect(layout.barHeight(1) == ActivityChartLayout.minimumBarHeight)
        #expect(layout.barHeight(14) == ActivityChartLayout.minimumBarHeight)
        #expect(layout.barHeight(15) > ActivityChartLayout.minimumBarHeight)
        #expect(layout.barHeight(0) == 0)
    }

    @Test func barsNeverExceedTheHalf() {
        let tiny = ActivityChartLayout(dayCount: 30, width: 406, halfHeight: 2, scale: 5)
        #expect(tiny.barHeight(1) == 2)
        #expect(ActivityChartLayout(dayCount: 30, width: 406, halfHeight: 40, scale: 5).barHeight(9) == 40)
    }

    @Test func columnUnderPointer() {
        let layout = ActivityChartLayout(dayCount: 30, width: 418, halfHeight: 41, scale: 1)  // 12 pt columns
        #expect(layout.columnWidth == 12)
        #expect(layout.columnIndex(at: 0) == 0)
        #expect(layout.columnIndex(at: 12.5) == 0)  // gap
        #expect(layout.columnIndex(at: 14) == 1)
        #expect(layout.columnIndex(at: 417.9) == 29)
        #expect(layout.columnIndex(at: -1) == nil)
        #expect(layout.columnIndex(at: 418) == nil)
        #expect(ActivityChartLayout(dayCount: 0, width: 418, halfHeight: 41, scale: 1).columnIndex(at: 5) == nil)
    }
}
