//
//  StrengthBarChart.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 28.07.26.
//

import CoreData
import SwiftUI

/// Every trained exercise as one bar, ranked worst to best — the weighted mean pulled apart into the
/// numbers it is made of. Shared by the Summary's Strength tile and `StrengthScreen`, at two sizes.
///
/// Three decisions worth keeping:
///
/// **Sorted, so the ramp is legal.** Colouring bars darker-where-taller is normally redundant — the
/// height already says it. Sorting turns the exercises into an *ordered* category, which is the one
/// case where a value ramp encodes something the reader can use: it makes the ranking itself visible,
/// so a strong period reads as a wall of bright accent and a flat one as a washed-out slope. The ramp
/// is one hue at six steps rather than a continuous gradient, so neighbouring bars stay distinct.
///
/// **Declines are neutral grey and never ramp.** Same rule as `TrendIndicatorView` and the muscle
/// balance surfaces: a decline is reported, not scolded.
///
/// **The axis sits where the data puts it.** The deepest decline claims its share of the frame and
/// gains take the rest, so both directions share one scale. On a good period the zero line rides low
/// and the chart is mostly accent; on a bad one it climbs and the grey grows.
struct StrengthBarChart: View {
    let changes: [StrengthProgress.ExerciseChange]
    /// Gap between bars. Shrinks automatically once the bars would be thinner than `minimumBarWidth`.
    var spacing: CGFloat = 2
    /// Drawn unless the caller is showing a chart small enough that a hairline would be noise.
    var showsZeroLine: Bool = true
    /// Set by `StrengthScreen` to drive scrub selection; nil on the tile, which isn't interactive.
    var selection: Binding<NSManagedObjectID?>?

    /// Below this the bars stop reading as bars, so the gap gives way first and then the bar itself
    /// is floored — past that point the chart is a texture, which is an acceptable thing for a tile
    /// graphic to be.
    private static let minimumBarWidth: CGFloat = 1.5
    /// Six steps, matching the validated ordinal ramp: one hue, monotone lightness, and the dimmest
    /// step still visible on the tile surface.
    private static let rampSteps = 6
    private static let rampFloor: Double = 0.35
    /// Below this a change is reported as no bar at all rather than a stub.
    private static let flatThreshold: Double = 0.5

    /// Worst first, so the ramp climbs left to right.
    private var ranked: [StrengthProgress.ExerciseChange] {
        changes.sorted { $0.percentChange < $1.percentChange }
    }

    /// Largest gain and largest decline, so one unit serves both sides of the axis.
    private var extremes: (up: Double, down: Double) {
        let up = changes.map(\.percentChange).filter { $0 > 0 }.max() ?? 0
        let down = abs(changes.map(\.percentChange).filter { $0 < 0 }.min() ?? 0)
        return (up, down)
    }

    var body: some View {
        GeometryReader { geo in
            let ranked = self.ranked
            let (up, down) = extremes
            let span = max(up + down, 0.001)
            // Fraction of the height above the axis. Clamped so an all-gains or all-declines period
            // still leaves the axis on screen rather than flush against an edge.
            let upShare = min(max(up / span, 0.08), 0.92)
            let zeroY = geo.size.height * upShare
            let gap = resolvedSpacing(count: ranked.count, width: geo.size.width)
            let barWidth = max(
                (geo.size.width - gap * CGFloat(max(ranked.count - 1, 0))) / CGFloat(max(ranked.count, 1)),
                Self.minimumBarWidth
            )

            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(ranked) { change in
                        bar(change, zeroY: zeroY, height: geo.size.height, span: span, maxGain: up)
                            .frame(width: barWidth)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)

                if showsZeroLine {
                    Rectangle()
                        .fill(Color.label.opacity(0.2))
                        .frame(height: 1)
                        .offset(y: zeroY)
                }
            }
            .contentShape(Rectangle())
            .gesture(scrubGesture(ranked: ranked, width: geo.size.width))
        }
    }

    /// One bar, grown from the axis. Positive up, negative down — the column is the full height so
    /// the scrub layer has a target even where the bar is a stub.
    private func bar(
        _ change: StrengthProgress.ExerciseChange,
        zeroY: CGFloat,
        height: CGFloat,
        span: Double,
        maxGain: Double
    ) -> some View {
        let magnitude = CGFloat(abs(change.percentChange) / span) * height
        let isSelected = selection?.wrappedValue == change.id
        return ZStack(alignment: .top) {
            if isSelected {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.label.opacity(0.08))
            }
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                    .frame(height: max(zeroY - (change.percentChange > 0 ? magnitude : 0), 0))
                UnevenRoundedRectangle(
                    topLeadingRadius: change.percentChange > 0 ? 2 : 0,
                    bottomLeadingRadius: change.percentChange > 0 ? 0 : 2,
                    bottomTrailingRadius: change.percentChange > 0 ? 0 : 2,
                    topTrailingRadius: change.percentChange > 0 ? 2 : 0,
                    style: .continuous
                )
                // No forced minimum: a change that rounds to nothing gets no bar, and the zero
                // line stands in for it. Stubs at every flat exercise read as a dashed axis, which
                // looks like a rendering fault rather than a row of unchanged lifts.
                .fill(color(for: change.percentChange, maxGain: maxGain))
                .frame(height: abs(change.percentChange) < Self.flatThreshold ? 0 : max(magnitude, 1.5))
                .overlay {
                    if isSelected {
                        UnevenRoundedRectangle(
                            topLeadingRadius: change.percentChange > 0 ? 2 : 0,
                            bottomLeadingRadius: change.percentChange > 0 ? 0 : 2,
                            bottomTrailingRadius: change.percentChange > 0 ? 0 : 2,
                            topTrailingRadius: change.percentChange > 0 ? 2 : 0,
                            style: .continuous
                        )
                        .strokeBorder(Color.label, lineWidth: 1.5)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: height, alignment: .top)
        }
        .frame(height: height)
    }

    /// Gains step through the accent ramp by rank; declines are flat neutral grey.
    private func color(for percent: Double, maxGain: Double) -> Color {
        guard percent > 0 else { return Color.secondaryLabel.opacity(0.55) }
        guard maxGain > 0 else { return Color.accentColor }
        let step = min(Int(percent / maxGain * Double(Self.rampSteps)), Self.rampSteps - 1)
        let t = Double(step) / Double(Self.rampSteps - 1)
        return Color.accentColor.opacity(Self.rampFloor + (1 - Self.rampFloor) * t)
    }

    /// Keeps the 2 pt gap while the bars can afford it, then closes it rather than letting the bars
    /// vanish — a 40-lift month should still read as a chart.
    private func resolvedSpacing(count: Int, width: CGFloat) -> CGFloat {
        guard count > 1 else { return 0 }
        let widthAtFullGap = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
        if widthAtFullGap >= Self.minimumBarWidth * 2 { return spacing }
        return max((width - Self.minimumBarWidth * CGFloat(count)) / CGFloat(count - 1), 0)
    }

    /// Nearest-column scrubbing. Individual bars are far under a tappable size at any realistic
    /// exercise count, so the whole plot is the target and the finger picks the closest column.
    private func scrubGesture(ranked: [StrengthProgress.ExerciseChange], width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let selection, !ranked.isEmpty, width > 0 else { return }
                let fraction = min(max(value.location.x / width, 0), 0.9999)
                let index = Int(fraction * CGFloat(ranked.count))
                let id = ranked[min(index, ranked.count - 1)].id
                if selection.wrappedValue != id { selection.wrappedValue = id }
            }
    }
}

#Preview {
    FetchRequestWrapper(Workout.self) { workouts in
        StrengthBarChart(changes: StrengthProgress.compute(workouts: workouts).changes)
            .frame(height: 120)
            .padding()
    }
    .previewEnvironmentObjects()
}
