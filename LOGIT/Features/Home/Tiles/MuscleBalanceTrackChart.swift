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
                track(entry)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func track(_ entry: MuscleBalanceEntry) -> some View {
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

/// The same track laid on its side, for the muscle-group overview's per-group rows. Carries what the
/// vertical version has no room for: the group's name, its actual-of-target numbers, and the
/// tolerance band that explains why a slightly-over group still reads as met.
struct MuscleBalanceGoalRow: View {
    let entry: MuscleBalanceEntry

    var body: some View {
        let color = entry.muscleGroup.color
        // Capped at target exactly like the vertical track, so "full" means the same thing on both
        // surfaces. Overshoot is carried by the chevron rather than by extra bar length — a row that
        // ran to twice target made an at-target group read as half done.
        let fraction = min(entry.goalFraction ?? 0, 1)
        return HStack(spacing: 12) {
            Text(entry.muscleGroup.description)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 84, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.label.opacity(0.07))
                    Capsule()
                        .fill(color.opacity(entry.goalState == .under ? 1 : 0.35))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 12)
            Text(
                String(
                    format: NSLocalizedString("muscleBalanceActualOfTarget", comment: ""),
                    entry.actualPercent, entry.targetPercent
                )
            )
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 76, alignment: .trailing)
            mark
                .frame(width: 16)
        }
        .accessibilityElement(children: .combine)
    }

    /// Never colour alone: the state is a glyph, so it survives greyscale and colour-blindness.
    @ViewBuilder
    private var mark: some View {
        switch entry.goalState {
        case .under:
            EmptyView()
        case .met:
            Image(systemName: "checkmark")
                .font(.caption.weight(.black))
                .foregroundStyle(entry.muscleGroup.color)
        case .over:
            Image(systemName: "chevron.up.2")
                .font(.caption.weight(.black))
                .foregroundStyle(entry.muscleGroup.color)
        }
    }
}

#Preview {
    FetchRequestWrapper(Workout.self) { workouts in
        let calculator = MuscleBalanceCalculator(workouts: workouts, target: .default)
        VStack(spacing: 24) {
            MuscleBalanceTrackChart(entries: calculator.goalEntries)
                .frame(height: 90)
            VStack(spacing: 0) {
                ForEach(calculator.goalEntries) { MuscleBalanceGoalRow(entry: $0).padding(.vertical, 6) }
            }
        }
        .padding()
    }
    .previewEnvironmentObjects()
}
