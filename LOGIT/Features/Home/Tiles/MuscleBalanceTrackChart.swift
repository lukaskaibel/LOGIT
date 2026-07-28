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

/// One muscle group as a compact cell for the overview's two-column grid: the name and its verdict
/// on one line, the same filling track beneath, and the actual-of-target numbers under that.
///
/// A full-width row could carry all of that on a single line, but two columns halve the scrolling on
/// a screen whose whole job is comparing eight groups — and the grouping into below / at / above
/// target is what makes the columns readable, because everything in a section shares a verdict.
struct MuscleBalanceGoalCell: View {
    let entry: MuscleBalanceEntry

    var body: some View {
        let color = entry.muscleGroup.color
        // Capped at target exactly like the vertical track, so "full" means the same thing on both
        // surfaces. Overshoot is carried by the chevron rather than by extra bar length.
        let fraction = min(entry.goalFraction ?? 0, 1)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text(entry.muscleGroup.description)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 2)
                mark
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // The unfilled remainder stays visible, the same way it does in the tile.
                    Capsule().fill(Color.label.opacity(0.07))
                    Capsule()
                        .fill(color.opacity(entry.goalState == .under ? 1 : 0.35))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 10)
            Text(
                String(
                    format: NSLocalizedString("muscleBalanceActualOfTarget", comment: ""),
                    entry.actualPercent, entry.targetPercent
                )
            )
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .secondaryTileStyle()
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
                .font(.caption2.weight(.black))
                .foregroundStyle(entry.muscleGroup.color)
        case .over:
            Image(systemName: "chevron.up.2")
                .font(.caption2.weight(.black))
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
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(calculator.goalEntries) { MuscleBalanceGoalCell(entry: $0) }
            }
        }
        .padding()
    }
    .previewEnvironmentObjects()
}
