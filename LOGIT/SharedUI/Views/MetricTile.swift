//
//  MetricTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 25.06.26.
//

import SwiftUI

// MARK: - Compact Chart Frame

/// The fixed size of a metric tile's bottom-right chart slot — small enough to sit beside the trend
/// pill on one row, and shared by every tile so a line chart and a bar chart line up across a grid.
/// The chart pins to the tile's trailing edge and gives up its leading edge first when a wide pill
/// crowds the row, so the newest (rightmost) bar always stays visible.
enum CompactChartFrame {
    static let width: CGFloat = 72
    static let height: CGFloat = 40
}

// MARK: - Metric Tile

/// The shared metric tile behind every stat on the exercise-detail and workout-detail screens: a
/// title row with an optional navigation chevron, an optional gray subtitle over the large
/// label-colored value, and a bottom row carrying the trend pill on the left and a compact chart —
/// a sparkline or a bar chart, supplied by the caller — in the bottom-right corner.
///
/// The accent (a flat muscle color, or a workout's multi-muscle gradient) tints only the trend pill
/// and, through the caller's chart, the highlighted bar/line; the number itself always stays neutral
/// so the color reads as "progress", never decoration. One skeleton for every tile so tiles sharing
/// a grid row always come out the same height — the chart's fixed height anchors the bottom row, and
/// the empty state renders the real content hidden underneath to match its row neighbor.
struct MetricTile<ChartContent: View>: View {
    enum Label {
        case currentBest
        case plain(String)
        /// A plain label with an info button explaining the value — the workout stat tiles explain
        /// their comparison basis this way.
        case info(String, explanation: String)
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
    /// Swaps subtitle, value, and chart for the centered ghost placeholder — for tiles whose metric
    /// has no usable data at all (the weight tiles of a bodyweight exercise). The content keeps
    /// rendering hidden underneath so the tile stays exactly as tall as its row neighbor.
    var showsEmptyPlaceholder: Bool = false
    @ViewBuilder let chart: () -> ChartContent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if showsEmptyPlaceholder {
                ZStack {
                    content.hidden()
                    placeholder
                }
            } else {
                content
                    .isBlockedWithoutPro(requiresPro, style: .compact)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CELL_PADDING)
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

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            subtitle
                .padding(.top, 8)
            UnitView(value: value ?? "––", unit: unit, configuration: .large, unitColor: .secondaryLabel)
                .foregroundStyle(Color.label)
                .padding(.top, 2)
            // The bottom row sits a fixed gap below the value, the same on every tile, so tiles in a
            // grid row keep their pills and charts on one line.
            bottomRow
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        case .none:
            EmptyView()
        }
    }

    /// Trend pill on the left, compact chart pinned to the trailing edge on the right. The chart's
    /// fixed height anchors the row, so a tile with no pill (or the shorter lapsed pill) is exactly as
    /// tall as one with a full trend pill — no height ruler needed. The chart frame is greedy and
    /// trailing-aligned, so it keeps the chart in the corner and clips its leading edge first if a
    /// wide pill ever crowds the row.
    private var bottomRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            pill
            chart()
                .frame(width: CompactChartFrame.width, height: CompactChartFrame.height)
                .frame(maxWidth: .infinity, alignment: .trailing)
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
