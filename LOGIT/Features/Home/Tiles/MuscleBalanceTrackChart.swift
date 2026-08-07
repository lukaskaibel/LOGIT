//
//  MuscleBalanceTrackChart.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 28.07.26.
//

import SwiftUI

/// One filling track per muscle group, each normalised to **its own** target.
///
/// That normalisation is the whole design. Because every track's top is the same statement — "this
/// group is at its target" — the tracks are comparable to each other at a glance, which is exactly
/// what a per-group centred tick destroys (the reason the earlier diverging version read as a
/// puzzle). What differs between groups is how full they are, and nothing else.
///
/// A track's state is `MuscleBalanceEntry.goalState`: partly filled and unbadged while short, then
/// translucent with a check once it is at target, and translucent with a double chevron when it is
/// well past it. Overshoot still counts — the chevron admits it rather than hiding it.
struct MuscleBalanceTrackChart: View {
    /// Already narrowed to targeted groups by the caller (`MuscleBalanceCalculator.goalEntries`).
    let entries: [MuscleBalanceEntry]
    var spacing: CGFloat = 5
    var badgeDiameter: CGFloat = 13
    /// Fullest last, so the gaps read first — matching the Strength chart beside it. Off for the
    /// detail screen's fixed-order variants.
    var sortsByFill: Bool = true

    private var ordered: [MuscleBalanceEntry] {
        guard sortsByFill else { return entries }
        return entries.sorted { ($0.goalFraction ?? 0) < ($1.goalFraction ?? 0) }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(ordered) { entry in
                MuscleBalanceTrack(entry: entry, badgeDiameter: badgeDiameter)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: Text {
        let met = entries.filter { $0.goalState != .under }.count
        let base = String(
            format: NSLocalizedString("muscleBalanceGoalAccessibility", comment: ""),
            met, entries.count
        )
        let short = entries.filter { $0.goalState == .under }
            .sorted { ($0.goalFraction ?? 0) < ($1.goalFraction ?? 0) }
            .prefix(2)
            .map(\.muscleGroup.description)
        guard !short.isEmpty else { return Text(base) }
        return Text(base + ", " + short.joined(separator: ", "))
    }
}

/// One muscle group's filling track, normalised to its own target — the shared bar behind both the
/// chart above and the overview's cells, so the two can never drift apart.
struct MuscleBalanceTrack: View {
    let entry: MuscleBalanceEntry
    var badgeDiameter: CGFloat = 13

    var body: some View {
        let color = entry.muscleGroup.color
        let fraction = min(entry.goalFraction ?? 0, 1)
        let isMet = entry.goalState != .under
        return GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // The unfilled remainder stays visible on every track, so "not there yet" is a
                // shape rather than something you infer from the absence of a badge. An untrained
                // group keeps its colour at low alpha: identity without inventing a single set.
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(entry.setCount == 0 ? color.opacity(0.12) : Color.label.opacity(0.07))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color.opacity(isMet ? 0.25 : 1))
                    .frame(height: geo.size.height * fraction)
            }
            // Centred on the track rather than laid out by the fill's bottom-aligned stack, which
            // parked every badge on the floor.
            .overlay {
                if isMet {
                    badge(for: entry.goalState, color: color)
                }
            }
        }
    }

    /// The verdict, centred on the filled track. Solid on a translucent fill so it reads as a badge
    /// rather than part of the bar.
    private func badge(for state: MuscleBalanceGoalState, color: Color) -> some View {
        ZStack {
            Circle().fill(color)
            Image(systemName: state == .over ? "chevron.up.2" : "checkmark")
                .font(.system(size: badgeDiameter * (state == .over ? 0.48 : 0.56), weight: .black))
                .foregroundStyle(Color.background)
        }
        .frame(width: badgeDiameter, height: badgeDiameter)
    }
}

/// One muscle group as a compact cell for the overview's two-column grid: the name at the top, the
/// group's share of the period large at the bottom-leading corner over the target it is measured
/// against, and its filling track standing full height on the trailing edge.
///
/// That is the app's tile anatomy — title, big value, caption, chart — so the grid reads as tiles
/// rather than as a second kind of row. The track is literally `MuscleBalanceTrack`, the same bar the
/// hero chart above draws, badge and all: a cell and its bar in the hero say the same thing in the
/// same shape, and the verdict glyph lives in one place instead of being repeated beside the name.
///
/// A full-width row could carry all of that on a single line, but two columns halve the scrolling on
/// a screen whose whole job is comparing eight groups — and the grouping into below / at / above
/// target is what makes the columns readable, because everything in a section shares a verdict.
struct MuscleBalanceGoalCell: View {
    let entry: MuscleBalanceEntry

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// One height for every cell, so a grid row stays even and every track is measured against the
    /// same span. Dropped at accessibility sizes, where the text has to be free to grow.
    private static let height: CGFloat = 104
    /// The track's height once the cell is no longer fixed-height: it can't fill the leftover space,
    /// so it takes a flat height rather than collapsing.
    private static let accessibilityTrackHeight: CGFloat = 72
    /// Roughly the hero chart's own width-to-height ratio at this cell's height (its tracks run about
    /// 37×130), so the tile's bar reads as one of those bars rather than a thinner cousin.
    private static let trackWidth: CGFloat = 24
    /// Narrower than the track, like the hero's badges — the bar has to stay visible around it.
    private static let badgeDiameter: CGFloat = 16

    private var usesFixedHeight: Bool { !dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.muscleGroup.description)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(entry.muscleGroup.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 10)
                // Neutral, like every other value in the app: the name and the track already carry
                // the group's colour, and a coloured number would read as a verdict of its own.
                UnitView(
                    value: "\(entry.actualPercent)",
                    unit: "%",
                    configuration: .large,
                    unitColor: .secondaryLabel
                )
                .foregroundStyle(Color.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Text(
                    String(
                        format: NSLocalizedString("muscleBalanceOfTarget", comment: ""),
                        entry.targetPercent
                    )
                )
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            track
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: usesFixedHeight ? Self.height : nil)
        .secondaryTileStyle()
        .accessibilityElement(children: .combine)
    }

    /// Fills the cell's height at normal sizes; at accessibility sizes the cell grows with its text,
    /// so the track takes a fixed height instead (a `GeometryReader` given no height to work with
    /// would have nothing to divide).
    @ViewBuilder
    private var track: some View {
        if usesFixedHeight {
            MuscleBalanceTrack(entry: entry, badgeDiameter: Self.badgeDiameter)
                .frame(width: Self.trackWidth)
                .frame(maxHeight: .infinity)
        } else {
            MuscleBalanceTrack(entry: entry, badgeDiameter: Self.badgeDiameter)
                .frame(width: Self.trackWidth, height: Self.accessibilityTrackHeight)
        }
    }
}

#Preview {
    FetchRequestWrapper(Workout.self) { workouts in
        let calculator = MuscleBalanceCalculator(workouts: workouts, target: .default)
        VStack(spacing: 24) {
            MuscleBalanceTrackChart(entries: calculator.goalEntries)
                .frame(height: 90)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(calculator.goalEntries) { MuscleBalanceGoalCell(entry: $0) }
            }
        }
        .padding()
    }
    .previewEnvironmentObjects()
}
