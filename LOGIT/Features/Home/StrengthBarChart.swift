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
    /// Set by `StrengthScreen` to drive selection; nil on the tile, which isn't interactive.
    var selection: Binding<NSManagedObjectID?>?
    /// When set, that group's bars keep their colour and every other bar drops to neutral grey —
    /// the chart stays whole instead of filtering down, so a group is read *against* the rest.
    var highlightedGroup: MuscleGroup?

    /// Below this the bars stop reading as bars, so the gap gives way first and then the bar itself
    /// is floored — past that point the chart is a texture, which is an acceptable thing for a tile
    /// graphic to be.
    private static let minimumBarWidth: CGFloat = 1.5
    /// Six steps, matching the validated ordinal ramp: one hue, monotone lightness, and the dimmest
    /// step still visible on the tile surface.
    private static let rampSteps = 6
    private static let rampFloor: Double = 0.35
    /// Declines keep the hue and lose the solidity — dimmer than the ramp's own floor so they read
    /// as below the line rather than as a very small gain.
    private static let declineOpacity: Double = 0.22
    /// Shortest a bar can be drawn. Every exercise in the ranking keeps one: a flat lift is part of
    /// the ranking and should hold its column, and columns that render nothing leave the movers
    /// crowded into a corner of an otherwise empty chart.
    private static let minimumBarHeight: CGFloat = 2.5

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
            // Fraction of the height above the axis. Never clamped: with nothing declining the axis
            // belongs on the bottom edge, and pinning it inboard made the tallest bar overshoot it
            // and hang below the line.
            let upShare = up / span
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
                        // Nudged inboard only for drawing: with every lift up, the axis is the
                        // bottom edge and an unclamped offset would put the line outside the frame.
                        .offset(y: min(zeroY, geo.size.height - 1))
                }
            }
            .contentShape(Rectangle())
            .gesture(selectGesture(ranked: ranked, width: geo.size.width))
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
        let magnitude = max(CGFloat(abs(change.percentChange) / span) * height, Self.minimumBarHeight)
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
                .fill(color(for: change, maxGain: maxGain))
                .frame(height: max(magnitude, Self.minimumBarHeight))
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

    /// Colour carries two things at once: identity and direction.
    ///
    /// Identity is the base hue — the accent normally, the muscle group's own colour once a group is
    /// highlighted, and neutral grey for every bar outside that group. Direction is opacity: gains
    /// step through the six-step ramp by rank, declines are drawn translucent in the same hue rather
    /// than recoloured, so a decline reads as "less of this" instead of as a different category.
    private func color(for change: StrengthProgress.ExerciseChange, maxGain: Double) -> Color {
        let base: Color
        if let highlightedGroup {
            guard change.muscleGroup == highlightedGroup else {
                return Color.secondaryLabel.opacity(change.percentChange > 0 ? 0.5 : 0.25)
            }
            base = highlightedGroup.color
        } else {
            base = .accentColor
        }
        guard change.percentChange > 0 else { return base.opacity(Self.declineOpacity) }
        guard maxGain > 0 else { return base }
        let step = min(Int(change.percentChange / maxGain * Double(Self.rampSteps)), Self.rampSteps - 1)
        let t = Double(step) / Double(Self.rampSteps - 1)
        return base.opacity(Self.rampFloor + (1 - Self.rampFloor) * t)
    }

    /// Keeps the 2 pt gap while the bars can afford it, then closes it rather than letting the bars
    /// vanish — a 40-lift month should still read as a chart.
    private func resolvedSpacing(count: Int, width: CGFloat) -> CGFloat {
        guard count > 1 else { return 0 }
        let widthAtFullGap = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
        if widthAtFullGap >= Self.minimumBarWidth * 2 { return spacing }
        return max((width - Self.minimumBarWidth * CGFloat(count)) / CGFloat(count - 1), 0)
    }

    /// Press and hold to select, then keep scrubbing while the finger is down.
    ///
    /// Not a plain drag: the chart lives inside a ScrollView, and a zero-distance drag claims every
    /// touch that starts on the plot — so scrolling the screen from the chart became impossible and
    /// a stray flick reassigned the selection. Requiring the hold first leaves the scroll gesture
    /// untouched, and it makes selection deliberate rather than something a passing finger does.
    /// The muscle-group grid below is the other way in, and it needs no gesture at all.
    private func selectGesture(ranked: [StrengthProgress.ExerciseChange], width: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case let .second(_, drag?) = value else { return }
                select(at: drag.location.x, ranked: ranked, width: width)
            }
    }

    /// Individual bars are far under a tappable size at any realistic exercise count, so the whole
    /// plot is the target and the finger picks the closest column.
    private func select(at x: CGFloat, ranked: [StrengthProgress.ExerciseChange], width: CGFloat) {
        guard let selection, !ranked.isEmpty, width > 0 else { return }
        let fraction = min(max(x / width, 0), 0.9999)
        let id = ranked[min(Int(fraction * CGFloat(ranked.count)), ranked.count - 1)].id
        if selection.wrappedValue != id { selection.wrappedValue = id }
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
