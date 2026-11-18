import SpreekCore
import SwiftData
import SwiftUI

/// List footer: "listened" / "saved" pills, a Little Snitch-style mirrored column chart (one
/// column per day across the full width, plays up pink, saves down blue) and the `‹ Last 30 days ›` control.
/// The window is independent of the list's 7d / 30d / All filter. Collapsed (Xcode's "Hide the
/// Debug Area"), only the bottom row stays, showing the page's sentence count; the toggle sits at
/// its trailing edge in both states.
struct ActivityFooter: View {
    /// Sentences the list shows (scope plus search, language, range and note filters).
    let sentenceCount: Int

    @Environment(AppModel.self) private var model
    /// Bumped when the library saves (new plays, deletions), so the chart re-renders. A query over
    /// every `PlayEvent` would do the same but keeps them all in memory (25k plays: ~15 MB).
    @State private var revision = 0
    @Query(filter: #Predicate<Sentence> { $0.isFavorite }) private var favorites: [Sentence]

    var body: some View {
        let dashboard = model.dashboard
        let summary = dashboard.showsChart ? activity(revision: revision + favorites.count) : nil

        VStack(spacing: 0) {
            if let summary {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        StatPill(tint: .pink, label: "listened", value: "\(summary.totalPlays)")
                        StatPill(tint: .blue, label: "saved", value: "\(summary.totalSaves)")
                    }
                    ActivityColumns(summary: summary)
                        .frame(height: 84)
                }
                .padding(EdgeInsets(top: 10, leading: 12, bottom: 8, trailing: 12))
                // Slides out from behind the bottom row while the footer grows, like the inspector.
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            // The same row in both states, so the toggle never moves.
            ZStack {
                if let summary { rangeControl(summary.window) } else { sentenceCountLabel }
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .overlay(alignment: .trailing) { toggle }
            .padding(EdgeInsets(top: summary == nil ? 10 : 0, leading: 12, bottom: 10, trailing: 12))
            .background(Color.windowBG)
            .zIndex(1)
        }
        .clipped()
        .overlay(alignment: .top) {
            Rectangle().fill(Color.separator).frame(height: Metrics.hairline)
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave, object: model.library.context)) { _ in
            revision += 1
        }
    }

    private func rangeControl(_ window: DateInterval) -> some View {
        let dashboard = model.dashboard
        return HStack(spacing: 6) {
            Button { dashboard.chartOffset += 1 } label: {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(RangeStepStyle())
            .help("Earlier")
            .accessibilityLabel("Earlier")
            rangeMenu(window)
            Button { dashboard.chartOffset = max(dashboard.chartOffset - 1, 0) } label: {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(RangeStepStyle())
            .disabled(dashboard.chartOffset == 0)
            .help("Later")
            .accessibilityLabel("Later")
        }
        .transition(.opacity)
    }

    private var sentenceCountLabel: some View {
        Text(sentenceCount == 1 ? "1 sentence" : "\(sentenceCount) sentences")
            .font(.system(size: 12))
            .foregroundStyle(Color.fg3)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
    }

    /// Xcode-style bottom-panel glyph in the list toolbar's icon style, accent while expanded.
    private var toggle: some View {
        let dashboard = model.dashboard
        let label = dashboard.showsChart ? "Hide Activity" : "Show Activity"
        return Button {
            withAnimation(.snappy(duration: 0.2)) { dashboard.showsChart.toggle() }
        } label: {
            Image(systemName: "rectangle.bottomthird.inset.filled")
        }
        .buttonStyle(.toolbarIcon(isOn: dashboard.showsChart))
        .help(label)
        .accessibilityLabel(label)
    }

    /// `revision` only ties the result to the queries above so new plays and saves re-render.
    private func activity(revision: Int) -> ActivitySummary {
        model.library.activity(model.dashboard.chartRange, offset: model.dashboard.chartOffset)
    }

    private func rangeMenu(_ window: DateInterval) -> some View {
        let dashboard = model.dashboard
        return Menu {
            ForEach(ChartRange.allCases, id: \.self) { range in
                Button {
                    dashboard.chartRange = range
                    dashboard.chartOffset = 0
                } label: {
                    let title = "\(range.days) days"
                    if dashboard.chartRange == range { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(title(window))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.fg2)
            }
            .font(.spreekRounded(size: 12.5, weight: .bold))
            .foregroundStyle(Color.fg)
            .padding(.horizontal, 16)
            .frame(minWidth: 140)
            .frame(height: 28)
            .background(Color.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .plainMenu()
        .help("Chart range")
    }

    private func title(_ window: DateInterval) -> String {
        if model.dashboard.chartOffset == 0 { return model.dashboard.chartRange.title }
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return "\(window.start.formatted(style)) – \(window.end.formatted(style))"
    }
}

/// One rounded column per day on a `chartTrack` background, mirrored around a center line;
/// columns stretch to fill the footer (`ActivityChartLayout`) and both halves scale to the
/// busiest day, with a minimum height for small non-zero days. Hovering shows the counts.
struct ActivityColumns: View {
    let summary: ActivitySummary

    @State private var hovered: Int?

    var body: some View {
        let days = summary.days
        GeometryReader { proxy in
            let layout = ActivityChartLayout(
                dayCount: days.count, width: Double(proxy.size.width),
                halfHeight: Double(proxy.size.height - 1) / 2, scale: summary.scale
            )
            let half = CGFloat(layout.halfHeight)
            // Read out of the proxy before the closures below: `GeometryProxy` is not `Sendable`.
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                HStack(spacing: ActivityChartLayout.gap) {
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        column(day, layout: layout, highlighted: hovered == index)
                    }
                }
                .frame(width: width, height: proxy.size.height, alignment: .leading)
                Rectangle()
                    .fill(Color.fg3.opacity(0.35))
                    .frame(width: width, height: 1)
                    .offset(y: half)
                if let hovered, days.indices.contains(hovered) {
                    tooltip(days[hovered])
                        .fixedSize()
                        .alignmentGuide(.leading) { dimensions in
                            let center = CGFloat(layout.columnX(hovered) + layout.columnWidth / 2)
                            let x = min(max(center - dimensions.width / 2, 0), width - dimensions.width)
                            return -x
                        }
                        .offset(y: -26)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hovered = layout.columnIndex(at: Double(point.x))
                case .ended: hovered = nil
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Listened and saved per day")
        .accessibilityValue("\(summary.totalPlays) listened, \(summary.totalSaves) saved in \(summary.days.count) days")
    }

    private func column(_ day: DailyActivity, layout: ActivityChartLayout, highlighted: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(min(1.5, layout.columnWidth / 2)), style: .continuous)
        let half = CGFloat(layout.halfHeight)
        return VStack(spacing: 1) {
            ZStack(alignment: .bottom) {
                shape.fill(Color.chartTrack)
                shape.fill(Color.chartPink).frame(height: CGFloat(layout.barHeight(day.plays)))
            }
            .frame(height: half)
            ZStack(alignment: .top) {
                shape.fill(Color.chartTrack)
                shape.fill(Color.chartBlue).frame(height: CGFloat(layout.barHeight(day.saves)))
            }
            .frame(height: half)
        }
        .frame(width: CGFloat(layout.columnWidth))
        .opacity(hovered == nil || highlighted ? 1 : 0.55)
    }

    private func tooltip(_ day: DailyActivity) -> some View {
        Text("\(day.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(day.plays) listened · \(day.saves) saved")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.fg)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Color.field, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.separator, lineWidth: Metrics.hairline))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
    }
}

private struct RangeStepStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StepBody(configuration: configuration)
    }

    private struct StepBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(Color.fg2)
                .frame(width: 30, height: 28)
                .background(Color.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
                .contentShape(Rectangle())
        }
    }
}
