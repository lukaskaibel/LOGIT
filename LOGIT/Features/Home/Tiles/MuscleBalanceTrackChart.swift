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
    /// Fullest last, so the gaps read first — matching the Strength chart beside it.
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
                Capsule(style: .continuous)
                    .fill(entry.setCount == 0 ? color.opacity(0.12) : Color.label.opacity(0.07))
                // The fill keeps the track's original near-flat top; the capsule clip below rounds
                // its bottom (and its top once full). A capsule-shaped fill instead shrinks into a
                // circle whenever it is shorter than the track is wide — every low weekly count.
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color.opacity(isMet ? 0.25 : 1))
                    .frame(height: geo.size.height * fraction)
            }
            // Capsule ends to sit with the rounded tiles they stand in.
            .clipShape(Capsule(style: .continuous))
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

/// One muscle group as a compact cell for the Muscle Groups grid: the name at the top, the group's
/// weekly sets over its weekly target ("7/10") at the bottom-leading corner, and its filling track
/// standing full height on the trailing edge.
///
/// The track is literally `MuscleBalanceTrack`, the same bar the hero chart above draws, badge and
/// all: a cell and its bar in the hero say the same thing in the same shape, and the verdict glyph
/// lives in one place instead of being repeated beside the name.
///
/// A reading only: the cell opens nothing, so it wears no chevron.
struct MuscleBalanceGoalCell: View {
    let entry: MuscleBalanceEntry
    /// A group the user turned off. It keeps its place in the grid — the editor keeps it in place as
    /// "Off" too, so nothing shifts between the two screens — but has no share to read against a
    /// target: its name gives up its colour, the value says Off, and the track stands empty.
    var isExcluded: Bool = false

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
                    .foregroundStyle(isExcluded ? Color.secondaryLabel : entry.muscleGroup.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 10)
                if isExcluded {
                    Text(NSLocalizedString("musclePriorityOff", comment: ""))
                        .font(.title.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.secondaryLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    share
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            if isExcluded {
                Capsule(style: .continuous)
                    .fill(Color.label.opacity(0.07))
                    .frame(width: Self.trackWidth)
                    .frame(maxHeight: usesFixedHeight ? .infinity : Self.accessibilityTrackHeight)
            } else {
                track
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: usesFixedHeight ? Self.height : nil)
        .secondaryTileStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(
                isExcluded
                    ? entry.muscleGroup.description + ", " + NSLocalizedString("musclePriorityOff", comment: "")
                    : entry.muscleGroup.description + ", "
                        + String(format: NSLocalizedString("muscleBalanceSetsOfTarget", comment: ""), entry.setsPerWeek, entry.target)
            )
        )
    }

    /// "7/10" over "sets per week": the group's weekly sets over its weekly target, in the goal shape
    /// every other count on these screens uses — 4/8 groups above it. Neutral like every other value in
    /// the app: the name and the track already carry the group's colour, and a coloured number would
    /// read as a verdict of its own.
    private var share: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text("\(entry.setsPerWeek)")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Color.label)
                Text("/\(entry.target)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.secondaryLabel)
            }
            .fontDesign(.rounded)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(NSLocalizedString("setsPerWeekCaption", comment: ""))
                .font(.caption2)
                .foregroundStyle(Color.secondaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
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
        let calculator = MuscleBalanceCalculator(workouts: workouts, focus: .default, weeks: 4)
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
