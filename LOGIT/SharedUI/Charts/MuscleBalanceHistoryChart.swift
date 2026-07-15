//
//  MuscleBalanceHistoryChart.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 01.07.26.
//

import Charts
import SwiftUI

/// The Muscle Groups overview's history chart: one slim, normalized (0–100 %) candle per period, each
/// a continuous stack of the muscle-group colours — segments fused with no gaps and no inner rounding,
/// the whole candle capped once at its top and bottom. Tapping a candle selects that period — the
/// parent's donut and sections rebind to it — and the selected candle shows in full colour with an
/// accent-underlined label while the rest dim. The x-categories are the buckets' stable ids (not their
/// labels, which needn't be unique across a window).
struct MuscleBalanceHistoryChart: View {
    let buckets: [MuscleBalanceBucket]
    /// Bottom→top stack order — biggest target share first, stable across periods.
    let orderedGroups: [MuscleGroup]
    /// The resolved selection (falls back to the newest bucket with sets when nothing is tapped yet).
    let selectedID: String
    @Binding var rawSelection: String?

    private static let barWidth: CGFloat = 10
    private static let capRadius: CGFloat = 5

    var body: some View {
        Chart {
            ForEach(buckets) { bucket in
                let stacked = stackedGroups(in: bucket)
                ForEach(Array(stacked.enumerated()), id: \.element.group) { index, item in
                    candleSegment(bucket: bucket, item: item, index: index, count: stacked.count)
                }
            }
        }
        .chartXScale(domain: buckets.map(\.id))
        .chartYScale(domain: 0 ... 100)
        .chartXSelection(value: $rawSelection)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: buckets.map(\.id)) { value in
                if let id = value.as(String.self), let bucket = buckets.first(where: { $0.id == id }) {
                    AxisValueLabel {
                        VStack(spacing: 3) {
                            Text(bucket.axisLabel)
                                .font(.system(size: 10, weight: id == selectedID ? .bold : .semibold, design: .rounded))
                                .foregroundStyle(id == selectedID ? Color.label : Color.secondaryLabel)
                                .fixedSize()
                            Capsule()
                                .fill(id == selectedID ? Color.accentColor : Color.clear)
                                .frame(width: 14, height: 2.5)
                        }
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.3), value: selectedID)
        .frame(height: 150)
    }

    /// One stacked segment of a bucket's candle. Extracted from the `Chart` builder (with an
    /// explicit `ChartContent` return type) so the compiler doesn't have to type-check the whole
    /// nested mark-plus-rounded-rect expression at once — inline it timed out on CI.
    @ChartContentBuilder
    private func candleSegment(
        bucket: MuscleBalanceBucket,
        item: (group: MuscleGroup, percent: Int),
        index: Int,
        count: Int
    ) -> some ChartContent {
        let isBottom = index == 0
        let isTop = index == count - 1
        // Segments fuse into one candle: square inner edges, the candle's own ends capped.
        let clip = UnevenRoundedRectangle(
            topLeadingRadius: isTop ? Self.capRadius : 0,
            bottomLeadingRadius: isBottom ? Self.capRadius : 0,
            bottomTrailingRadius: isBottom ? Self.capRadius : 0,
            topTrailingRadius: isTop ? Self.capRadius : 0
        )
        BarMark(
            x: .value("Period", bucket.id),
            y: .value("Share", item.percent),
            width: .fixed(Self.barWidth)
        )
        .foregroundStyle(item.group.color)
        .opacity(bucket.id == selectedID ? 1 : 0.32)
        .clipShape(clip)
    }

    /// The bucket's trained groups in stack order (bottom first) — Charts stacks marks in declaration
    /// order, and knowing the first/last lets the candle's outer ends carry the only rounding.
    private func stackedGroups(in bucket: MuscleBalanceBucket) -> [(group: MuscleGroup, percent: Int)] {
        orderedGroups.compactMap { group in
            guard let entry = bucket.calculator.entries.first(where: { $0.muscleGroup == group }),
                  entry.actualPercent > 0 else { return nil }
            return (group, entry.actualPercent)
        }
    }
}
