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
/// translucent with a check once it is at target, and translucent with a double chevron past it.
/// Nothing else marks a track. The groups the headline names are always the leftmost bars, in the
/// headline's own colours, and every bar carries its group's letters — a ring around the named bars
/// was tried and pulled the whole Summary toward that corner.
///
/// Draws the entries in the order given — `MuscleBalanceCalculator.rankedEntries`, the one order
/// every balance surface shares, which puts the groups furthest behind first.
struct MuscleBalanceTrackChart: View {
    /// Already narrowed and ordered by the caller (`MuscleBalanceCalculator.rankedEntries`).
    let entries: [MuscleBalanceEntry]
    var spacing: CGFloat = 5
    var badgeDiameter: CGFloat = 13
    /// Each group's letters under its track, in its colour. The point size follows the track width:
    /// the Summary tile's bars are about 20 pt wide, the Muscle Groups chart's nearly twice that.
    var labelSize: CGFloat = 12

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(entries) { entry in
                VStack(spacing: labelSize * 0.5) {
                    MuscleBalanceTrack(entry: entry, badgeDiameter: badgeDiameter)
                    Text(entry.muscleGroup.abbreviation)
                        .font(.system(size: labelSize, weight: .bold, design: .rounded))
                        .foregroundStyle(entry.muscleGroup.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Every group in reading order with its weekly sets against its target — the chart said aloud.
    private var accessibilityLabel: Text {
        Text(
            entries
                .map { entry in
                    entry.muscleGroup.description + ", "
                        + String(
                            format: NSLocalizedString("muscleBalanceSetsOfTarget", comment: ""),
                            entry.setsPerWeek, entry.target
                        )
                }
                .joined(separator: "; ")
        )
    }
}

/// One muscle group's filling track, normalised to its own target — the bar behind every balance
/// chart, so the tile and the Muscle Groups screen can never draw a group differently.
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
                    MuscleBalanceGoalBadge(state: entry.goalState, color: color, diameter: badgeDiameter)
                }
            }
        }
    }
}

/// A verdict as a glyph in a filled circle — a check at target, a double chevron past it, a chevron
/// down short of it. Solid on a translucent fill so it reads as a badge rather than part of a bar, and
/// the same mark heads each section of the Muscle Groups list, so a section and its bars share a sign.
struct MuscleBalanceGoalBadge: View {
    let systemImage: String
    /// The disc. `nil` draws the neutral one the section headers use.
    var color: Color? = nil
    var diameter: CGFloat = 13

    init(systemImage: String, color: Color? = nil, diameter: CGFloat = 13) {
        self.systemImage = systemImage
        self.color = color
        self.diameter = diameter
    }

    init(state: MuscleBalanceGoalState, color: Color? = nil, diameter: CGFloat = 13) {
        self.init(systemImage: Self.symbol(for: state), color: color, diameter: diameter)
    }

    static func symbol(for state: MuscleBalanceGoalState) -> String {
        switch state {
        case .under: return "chevron.down"
        case .met: return "checkmark"
        case .over: return "chevron.up.2"
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(color ?? Color.fill)
            Image(systemName: systemImage)
                // A check fills its box; chevrons and a minus read heavier, so they draw smaller.
                .font(.system(size: diameter * (systemImage == "checkmark" ? 0.56 : 0.48), weight: .black))
                .foregroundStyle(color == nil ? Color.label : Color.background)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

#Preview {
    FetchRequestWrapper(Workout.self) { workouts in
        let calculator = MuscleBalanceCalculator(workouts: workouts, focus: .default, weeks: 4)
        VStack(spacing: 24) {
            MuscleBalanceTrackChart(entries: calculator.rankedEntries, labelSize: 8.5)
                .frame(height: 90)
            MuscleBalanceTrackChart(entries: calculator.rankedEntries, spacing: 10, badgeDiameter: 22)
                .frame(height: 160)
        }
        .padding()
    }
    .previewEnvironmentObjects()
}
