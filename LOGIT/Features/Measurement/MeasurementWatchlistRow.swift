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
        let entries = self.entries
        let latest = entries.first
        let previous = entries.dropFirst().first
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
            sparkline(entries)
                .frame(width: 52, height: 24)
            HStack(spacing: 8) {
                if let latest {
                    UnitView(
                        value: formatDecimal(latest.decimalValue),
                        unit: measurementType.unit,
                        unitColor: .secondaryLabel
                    )
                    .foregroundStyle(Color.label)
                } else {
                    Text("––").foregroundStyle(.secondary)
                }
                if let latest, let previous {
                    changePill(latest: latest.decimalValue, previous: previous.decimalValue)
                }
            }
        }
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private func sparkline(_ entries: [MeasurementEntry]) -> some View {
        let points = Array(entries.prefix(12)).reversed().map {
            TileSparklinePoint(date: $0.date ?? .now, value: $0.decimalValue)
        }
        Chart {
            tileSparklineMarks(points: points, color: .secondary)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
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
