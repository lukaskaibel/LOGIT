//
//  MeasurementWatchlistRow.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Charts
import SwiftUI

/// The compact Summary measurements watchlist — replaces the 120pt `MeasurementTile` stack with one
/// `tileStyle` card whose rows each show a type icon, the latest value, a mini sparkline and a change
/// pill versus the previous entry. Pinned measurements only; "See all" reaches the full screen.
struct MeasurementWatchlist: View {
    let types: [MeasurementEntryType]
    let onTap: (MeasurementEntryType) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(types.enumerated()), id: \.element) { index, type in
                Button {
                    onTap(type)
                } label: {
                    MeasurementWatchlistRow(measurementType: type)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < types.count - 1 {
                    Divider()
                }
            }
        }
        .padding(.horizontal, CELL_PADDING)
        .tileStyle()
    }
}

struct MeasurementWatchlistRow: View {
    @EnvironmentObject private var measurementController: MeasurementEntryController

    let measurementType: MeasurementEntryType

    /// Newest-first.
    private var entries: [MeasurementEntry] {
        measurementController.getMeasurementEntries(ofType: measurementType)
    }

    var body: some View {
        MeasurementWatchlistRowContent(
            measurementType: measurementType,
            points: Array(entries.prefix(12)).reversed().map {
                TileSparklinePoint(date: $0.date ?? .now, value: $0.decimalValue)
            }
        )
    }
}

/// The row itself, driven by plain sparkline points instead of the measurement store — the latest
/// value, change pill, and sparkline all derive from `points`, so a row can never show a number its
/// line doesn't end on. `MeasurementWatchlistRow` feeds it real entries; the Summary's measurements
/// empty state feeds it made-up values so its dimmed samples are this exact view, not a replica.
struct MeasurementWatchlistRowContent: View {
    let measurementType: MeasurementEntryType
    /// Oldest → newest, at most the 12 most recent entries.
    let points: [TileSparklinePoint]

    var body: some View {
        let latest = points.last
        let previous = points.dropLast().last
        HStack(spacing: 11) {
            Image(systemName: measurementType.systemImage)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(measurementType.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.label)
                    .lineLimit(1)
                Text(NSLocalizedString("current", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            sparkline
                .frame(width: 52, height: 24)
            HStack(spacing: 8) {
                if let latest {
                    UnitView(
                        value: formatDecimal(latest.value),
                        unit: measurementType.unit,
                        unitColor: .secondaryLabel
                    )
                    .foregroundStyle(Color.label)
                } else {
                    Text("––").foregroundStyle(.secondary)
                }
                if let latest, let previous {
                    changePill(latest: latest.value, previous: previous.value)
                }
            }
            // The value must never wrap mid-number ("21." / "2 %") when a long title squeezes the
            // row — scale it down a touch instead, like the watchlist's stock-app ancestors.
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 11)
    }

    private var sparkline: some View {
        Chart {
            tileSparklineMarks(points: points, color: .secondary)
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .clipped()
        .tileSparklineFadeMask()
    }

    /// First entry to just past today, like the exercise tiles' windows: the trailing margin keeps
    /// the newest dot from being sliced by the edge, and the domain clips the style's
    /// `Date.distantPast` lead-in so the line enters from the left edge.
    private var xDomain: ClosedRange<Date> {
        let anchor = points.first?.date ?? .now
        let lead = Calendar.current.date(byAdding: .day, value: -2, to: anchor) ?? anchor
        let trail = Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now
        return lead ... max(trail, anchor)
    }

    /// Banded to the shown entries, not zero-anchored like the exercise tiles: measurements move a
    /// percent or two around a large baseline, so against zero every series is a flat line at the
    /// top of the frame. The band makes the 24pt line show the trend the change pill summarizes.
    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        guard let min = values.min(), let max = values.max() else { return 0 ... 1 }
        let padding = Swift.max((max - min) * 0.15, 0.1)
        return (min - padding) ... (max + padding)
    }

    private func changePill(latest: Double, previous: Double) -> some View {
        let delta = latest - previous
        return ProgressIndicatorPill(
            symbol: delta >= 0 ? "arrow.up" : "arrow.down",
            color: .secondary,
            size: .compact
        ) {
            Text(formatDecimal(abs(delta)))
                .font(.system(.caption2, design: .rounded, weight: .bold))
        }
    }

    private func formatDecimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.decimalSeparator = "."
        formatter.groupingSeparator = ""
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
}

#Preview {
    MeasurementWatchlist(types: [.bodyweight, .bodyFatPercentage, .length(.waist)]) { _ in }
        .previewEnvironmentObjects()
        .padding()
}
