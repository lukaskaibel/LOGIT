//
//  MetricTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 25.06.26.
//

import SwiftUI

// MARK: - Metric Tile

/// The shared metric tile behind every stat on the exercise-detail and workout-detail screens: a
/// title row with an optional navigation chevron, an optional gray subtitle, and the large label-
/// colored value; beneath them a full-width chart supplied by the caller — a line sparkline bleeding to
/// the tile's bottom and side edges, or a bar chart inset just enough (`chartBleeds: false`) that its
/// rounded bars sit inside the corners — with the trend pill overlaid on the chart's bottom-leading
/// corner (the line fades in from the left so it doesn't collide with the pill).
///
/// The accent (a flat muscle color, or a workout's multi-muscle gradient) tints only the trend pill
/// and, through the caller's chart, the highlighted bar/line; the number itself always stays neutral
/// so the color reads as "progress", never decoration. Every tile is one fixed height so a grid row
/// stays even — the chart fills the height the value block leaves, never growing the tile.
struct MetricTile<ChartContent: View>: View {
    enum Label {
        case currentBest
        case plain(String)
        /// A plain label with an info button explaining the value — the workout stat tiles explain
        /// their comparison basis this way.
        case info(String, explanation: String)
        /// A quiet, understated qualifier under the title — smaller and lighter than `.plain`, so it
        /// reads as a soft annotation on the value ("per workout") rather than a second heading.
        case caption(String)
        /// No subtitle line at all — the title and value carry the whole tile.
        case none
    }

    let title: String
    /// The trailing navigation chevron, on by default since every tile taps into a detail screen.
    /// Pass `false` for a tile that isn't a button.
    var showsChevron: Bool = true
    let label: Label
    /// Nil renders the "––" placeholder.
    let value: String?
    let unit: String
    /// Tints the trend pill (and, through the caller's chart, the highlighted bar/line). A flat
    /// `Color` or a multi-muscle gradient, type-erased so both fit. The value and unit stay neutral
    /// regardless — the accent only ever marks progress.
    let accent: AnyShapeStyle
    /// The flat-color form of the accent, for the two consumers that need a `Color` rather than a
    /// style: the trend pill's non-gradient fallback and the empty state's ghost dot.
    let accentColor: Color
    let percentChange: Double?
    var isRecord: Bool = false
    /// Gates the tile's data — pill, subtitle, value, and chart — behind Pro (blur + compact crown).
    /// The title and chevron stay readable so a locked tile still says what it is.
    var requiresPro: Bool = false
    /// Last session this tile's metric has a value from, when that session predates the metric's
    /// window — renders the gray "time since" capsule in the trend pill's slot.
    var lapsedSince: Date? = nil
    /// The date of the "last best" entry — the most recent session's best, shown when a metric's
    /// current-best window is empty. Renders an absolute-date capsule in the trend pill's slot, the
    /// dated companion to the value above. Distinct from `lapsedSince`, which shows a *relative*
    /// "time since" for the weekly tiles; this stamps the exact day the value was last reached.
    var lastBestDate: Date? = nil
    /// Swaps subtitle, value, and chart for the centered ghost placeholder — for tiles whose metric
    /// has no usable data at all (the weight tiles of a bodyweight exercise). The content keeps
    /// rendering hidden underneath so the tile stays exactly as tall as its row neighbor.
    var showsEmptyPlaceholder: Bool = false
    /// Whether the chart bleeds to the tile's bottom and side edges. The default — the line sparklines
    /// run edge to edge. Bar charts pass `false`: their outermost bars would be sliced by the tile's
    /// rounded corners, so they take a small inset and sit just inside the corner instead.
    var chartBleeds: Bool = true
    @ViewBuilder let chart: () -> ChartContent

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Every tile is pinned to one height so a grid row stays even, and a value too long to share a
    /// line with the trend pill pushes the pill onto its own line by stealing height from the chart
    /// rather than growing the tile. Dropped at accessibility sizes, where the tiles stack in one
    /// column and size to their content.
    private static var fixedHeight: CGFloat { 172 }
    /// The chart's height once the tile is no longer fixed-height (accessibility sizes): the footer
    /// can't fill the leftover space, so it takes a flat height instead of collapsing.
    private static var accessibilityChartHeight: CGFloat { 64 }

    private var usesFixedHeight: Bool { !dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, CELL_PADDING)
                .padding(.top, CELL_PADDING)
            if showsEmptyPlaceholder {
                placeholderFooter
            } else {
                content
                    .isBlockedWithoutPro(requiresPro, style: .compact)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: usesFixedHeight ? Self.fixedHeight : nil, alignment: .top)
        .tileStyle()
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.label)
                .lineLimit(1)
                // A long title ("Satzvolumen") gets shrunk rather than ellipsized.
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            if showsChevron {
                NavigationChevron()
                    .foregroundStyle(Color.secondaryLabel)
            }
        }
    }

    /// The padded subtitle + value/pill block sitting above the full-bleed chart footer. The text
    /// keeps the tile's `CELL_PADDING` inset; the chart carries none and bleeds to the rounded bottom
    /// and side edges, the way the personal-record card's all-time line does.
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                subtitle
                    .padding(.top, 8)
                valueView
                    .padding(.top, 2)
            }
            .padding(.horizontal, CELL_PADDING)
            chartFooter
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var valueView: some View {
        UnitView(value: value ?? "––", unit: unit, configuration: .large, unitColor: .secondaryLabel)
            .foregroundStyle(Color.label)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// The chart and its trend pill, side by side: the pill sits at the bottom-leading corner and the
    /// chart fills the space to its RIGHT, so the two never overlap and the gap between them stays
    /// constant. The line bleeds to the trailing + bottom edges; a bar chart takes a small inset there
    /// so its rounded bars clear the corners.
    private var chartFooter: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if hasPill {
                pill
                    .padding(.leading, CELL_PADDING)
                    .padding(.bottom, CELL_PADDING)
            }
            chartContent
        }
    }

    /// The chart itself: on a fixed-height tile it fills whatever the value block leaves above it; at
    /// accessibility sizes (no fixed height) it takes a flat height so the footer can't collapse.
    @ViewBuilder
    private var chartContent: some View {
        if usesFixedHeight {
            chart()
                .padding(chartFooterInsets)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            chart()
                .padding(chartFooterInsets)
                .frame(maxWidth: .infinity)
                .frame(height: Self.accessibilityChartHeight)
        }
    }

    /// Zero for a bleeding (line) chart — it runs to the edges, the only chart with reduced padding for
    /// now. A bar chart sits inside the tile's normal `CELL_PADDING`, like the header and value above it:
    /// full trailing + bottom padding, and full leading too unless a pill sits beside it (then the pill
    /// + HStack spacing already hold the bars in).
    private var chartFooterInsets: EdgeInsets {
        guard !chartBleeds else { return EdgeInsets() }
        return EdgeInsets(
            top: 0,
            leading: hasPill ? 0 : CELL_PADDING,
            bottom: CELL_PADDING,
            trailing: CELL_PADDING
        )
    }

    @ViewBuilder
    private var subtitle: some View {
        switch label {
        case .currentBest:
            CurrentBestLabel()
        case let .plain(text):
            Text(text)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        case let .info(text, explanation):
            MetricTileInfoLabel(text: text, explanation: explanation)
        case let .caption(text):
            Text(text)
                .font(.caption.weight(.medium))
                .tracking(0.3)
                .foregroundStyle(.tertiary)
        case .none:
            // Reserve one subtitle line's height so the value keeps the same fixed vertical position
            // as tiles that do have a subtitle. Without it the value floats up into the empty slot and
            // the chart below — which fills the leftover height — grows too tall (the Summary bars).
            Text(" ")
                .font(.footnote)
                .fontWeight(.semibold)
                .hidden()
                .accessibilityHidden(true)
        }
    }

    /// The empty-state body: the ghost sparkline + "no data" centered in the space below the header,
    /// filling the same footer the chart would so an empty tile is exactly as tall as its neighbours.
    @ViewBuilder
    private var placeholderFooter: some View {
        if usesFixedHeight {
            placeholder
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(CELL_PADDING)
        } else {
            placeholder
                .frame(maxWidth: .infinity)
                .frame(height: Self.accessibilityChartHeight + 40)
                .padding(CELL_PADDING)
        }
    }

    @ViewBuilder
    private var pill: some View {
        if let percentChange {
            TrendIndicatorView(
                percentChange: percentChange,
                positiveColor: accentColor,
                positiveStyle: accent,
                isRecord: isRecord
            )
        } else if let lapsedSince {
            TileLapsedPill(date: lapsedSince)
        } else if let lastBestDate {
            TileDatePill(date: lastBestDate)
        }
    }

    /// Whether any pill applies — drives whether the bleeding line reserves the space to its left.
    private var hasPill: Bool {
        percentChange != nil || lapsedSince != nil || lastBestDate != nil
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            GhostSparkline(color: accentColor)
                .frame(width: 90, height: 30)
            Text(NSLocalizedString("noData", comment: ""))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Lapsed Pill

/// The gray "time since the last session" capsule in the trend pill's slot on lapsed tiles — the
/// trend pill's anatomy (icon + rounded bold text on a 0.15 fill) with the history icon and a
/// relative date, so the stale state is visible right where the trend usually lives. A size softer
/// than the trend pill: it's quiet metadata, not a score.
private struct TileLapsedPill: View {
    let date: Date

    var body: some View {
        ProgressIndicatorPill(symbol: "clock.arrow.circlepath", color: .secondary, size: .compact) {
            Text(date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                .font(.system(.caption2, design: .rounded, weight: .bold))
        }
        // The pill never compresses or wraps — the title next to it shrinks instead.
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date, format: .relative(presentation: .named)))
    }
}

// MARK: - Date Pill

/// The absolute-date companion to `TileLapsedPill`, in the trend pill's slot on a tile showing its
/// "last best" (the most recent session's best, when the current-best window is empty). Same compact
/// capsule anatomy as the lapsed pill, but a calendar glyph and an exact date — the dated stamp on
/// the value above, "when this was last done" — rather than a relative "time since".
private struct TileDatePill: View {
    let date: Date

    var body: some View {
        ProgressIndicatorPill(symbol: "calendar", color: .secondary, size: .compact) {
            Text(dateText)
                .font(.system(.caption2, design: .rounded, weight: .bold))
        }
        // The pill never compresses or wraps — the title next to it shrinks instead.
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date, format: .dateTime.day().month().year()))
    }

    /// Day and month, with the year only when it isn't the current one — a stale metric is often
    /// from an earlier year, where the year is the point.
    private var dateText: String {
        date.isInCurrentYear
            ? date.formatted(.dateTime.day().month())
            : date.formatted(.dateTime.day().month().year())
    }
}

// MARK: - Info Label

/// Backs `MetricTile.Label.info` — `CurrentBestLabel`'s text + info-dot anatomy with the texts
/// supplied by the tile (the workout stat tiles explain their comparison basis here).
private struct MetricTileInfoLabel: View {
    let text: String
    let explanation: String
    @State private var isShowingInfo = false

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .fontWeight(.semibold)
            Button {
                isShowingInfo = true
            } label: {
                Image(systemName: "info.circle")
            }
            .popover(isPresented: $isShowingInfo) {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding()
                    .frame(width: 300)
                    .presentationCompactAdaptation(.popover)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
