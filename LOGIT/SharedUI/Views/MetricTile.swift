//
//  MetricTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 25.06.26.
//

import SwiftUI

// MARK: - Metric Tile

/// The shared metric tile behind every stat on the exercise-detail and workout-detail screens: a
/// title row ending in the navigation chevron at the trailing edge, an optional gray subtitle, and
/// the large label-colored value; beneath them the caller's chart, running the tile's **full
/// width** — a line sparkline bleeding to the bottom and side edges, or a bar chart inset just
/// enough (`chartBleeds: false`) that its rounded bars sit inside the corners.
///
/// **The title row carries no percentage.** A trend pill sat in its trailing corner until 2026-09,
/// and it went because one identical badge stood for six different comparisons across the app — a
/// timeframe against the one before it, a workout against the average of the last eight, a week
/// against the previous week, a 4-week best against the best before it — with nothing on the tile
/// saying which, so a perfectly normal arm day read as four grey declines and five of one
/// exercise's six tiles wore a trophy. Every tile already draws its own history underneath with the
/// current value highlighted, which is the honest version of the same story. The percentage still
/// lives wherever both of its numbers are on screen beside it: the chart-detail header a tile taps
/// into (`MetricComparisonView`), the Highlights cards, the Strength figure, and the in-workout set
/// badges. The slot the pill vacated still holds the last-best date capsule (`TileDatePill`).
///
/// The tile's own text is entirely neutral; the accent (a flat muscle color, or a workout's
/// multi-muscle gradient) reaches it only through the caller's chart — the highlighted bar or line
/// — so the color reads as "progress", never decoration. Every tile is one fixed height so a grid
/// row stays even — the chart fills the height the value block leaves, never growing the tile.
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
    /// The tile's muscle color — the empty state's ghost dot, and nothing else. The caller tints its
    /// own chart; the tile's text is neutral throughout.
    let accentColor: Color
    /// Gates the tile's data — date capsule, subtitle, value, and chart — behind Pro (blur +
    /// compact crown). The title and chevron stay readable so a locked tile still says what it is.
    var requiresPro: Bool = false
    /// The date of the "last best" entry — the most recent session's best, shown when a metric's
    /// current-best window is empty. Renders an absolute-date capsule between the title and the
    /// chevron, the dated companion to the value above: the exact day the value was last reached.
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

    /// Every tile is pinned to one height so a grid row stays even; the chart takes whatever height
    /// the text block above it leaves rather than growing the tile. Dropped at accessibility sizes,
    /// where the tiles stack in one column and size to their content.
    private static var fixedHeight: CGFloat { 172 }
    /// The chart's height once the tile is no longer fixed-height (accessibility sizes): the footer
    /// can't fill the leftover space, so it takes a flat height instead of collapsing.
    private static var accessibilityChartHeight: CGFloat { 64 }
    /// How far the title may shrink before it truncates instead. Every metric name now fits at full
    /// size, but a state capsule can still share the row, and a pinned tile leads with the
    /// *exercise* name rather than a metric name — those scale down a step rather than losing their
    /// tail, which is what makes a name still readable. Past this point they truncate: shrinking
    /// stops buying legibility.
    private static var titleMinimumScale: CGFloat { 0.75 }

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

    /// Title, the last-best date capsule where there is one, then the navigation chevron pinned to
    /// the trailing edge — the same order and the same trailing anchor as `TileHeader`, the shared
    /// row every other navigable tile uses, so a screen mixing the two reads as one system. (The
    /// chevron used to travel with the title, to keep it away from the trend pill in the corner;
    /// with the pill gone the corner is the chevron's again.)
    private var header: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.label)
                .lineLimit(1)
                // A long title ("Satzvolumen") gets shrunk rather than ellipsized.
                .minimumScaleFactor(Self.titleMinimumScale)
            Spacer(minLength: 4)
            if let lastBestDate {
                TileDatePill(date: lastBestDate)
                    // The capsule never compresses to make room — the title shrinks instead.
                    .fixedSize()
                    // The capsule annotates data the tile may be gating; the title row deliberately
                    // stays legible on a locked tile, so it has to be blurred on its own.
                    .proBlurred(requiresPro)
            }
            if showsChevron {
                NavigationChevron()
                    .foregroundStyle(Color.secondaryLabel)
            }
        }
    }

    /// The padded subtitle + value block sitting above the full-bleed chart footer. The text keeps
    /// the tile's `CELL_PADDING` inset; the chart carries none and bleeds to the rounded bottom and
    /// side edges, the way the personal-record card's all-time line does.
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

    /// The chart, across the tile's whole width — nothing shares the row, so its geometry is the same
    /// on every tile whatever state it's in. A line bleeds to the leading, trailing and bottom edges;
    /// a bar chart takes `CELL_PADDING` on all three so its rounded bars clear the corners.
    private var chartFooter: some View {
        chartContent
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
    /// now. A bar chart sits inside the tile's normal `CELL_PADDING`, like the header and value above
    /// it, on all three sides.
    private var chartFooterInsets: EdgeInsets {
        guard !chartBleeds else { return EdgeInsets() }
        return EdgeInsets(top: 0, leading: CELL_PADDING, bottom: CELL_PADDING, trailing: CELL_PADDING)
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

// MARK: - Date Pill

/// The only capsule the title row still carries: an exact date on a tile showing its "last best"
/// (the most recent session's best, when the current-best window is empty). The app's pill anatomy
/// — calendar glyph + rounded bold text on a 0.15 gray fill — stamping the value above with when it
/// was last reached. Gray and compact deliberately: it's quiet metadata, not a score.
///
/// It used to have a sibling, `TileLapsedPill`, showing a *relative* "time since" for the weekly
/// tiles. No tile ever passed it a date, so it went with the trend pill.
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
