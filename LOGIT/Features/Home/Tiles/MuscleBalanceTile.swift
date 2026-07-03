//
//  MuscleBalanceTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// The Summary screen's period-scoped Muscle Balance tile — the free, actionable hook (same pattern as
/// Records: tile free, detail Pro). It leads with the groups that are below their target (then the
/// ones above), three at a time — each row the diverging `MuscleBalanceBar` growing out of the target
/// tick, the same language as the overview's sections — with a "+N more" hint by the chevron, and
/// rolls the rest into one encouraging line ("N of 8 on target"). Taps into the Muscle Groups
/// overview.
struct MuscleBalanceTile: View {
    /// Workouts already filtered to the Summary's selected period.
    let workouts: [Workout]
    let period: StatPeriod

    @EnvironmentObject private var targetSplitStore: MuscleTargetSplitStore
    @EnvironmentObject private var muscleGroupService: MuscleGroupService

    /// How many off-target rows the tile shows before collapsing the rest into "+N more".
    private static let maxRows = 3

    private var calculator: MuscleBalanceCalculator {
        MuscleBalanceCalculator(
            workouts: workouts,
            target: targetSplitStore.split,
            muscleGroupService: muscleGroupService
        )
    }

    var body: some View {
        let calculator = self.calculator
        // Below-target first — the under-target groups are the actionable ones; the above ones trail.
        let offTarget = calculator.totalSets > 0
            ? calculator.underTargets() + calculator.overTargets()
            : []
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(NSLocalizedString("muscleBalance", comment: ""))
                    .tileHeaderStyle()
                Spacer()
                if offTarget.count > Self.maxRows {
                    Text(String(format: NSLocalizedString("muscleBalanceMore", comment: ""), offTarget.count - Self.maxRows))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                NavigationChevron()
                    .foregroundStyle(.secondary)
            }
            if calculator.totalSets > 0 {
                balance(calculator, offTarget: offTarget)
            } else {
                emptyState
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }

    @ViewBuilder
    private func balance(_ calculator: MuscleBalanceCalculator, offTarget: [MuscleBalanceEntry]) -> some View {
        if offTarget.isEmpty {
            // Everything's in range — a calm, positive read.
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text(NSLocalizedString("muscleBalanceBalanced", comment: ""))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.label)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } else {
            VStack(spacing: 7) {
                ForEach(offTarget.prefix(Self.maxRows)) { entry in
                    row(entry)
                }
            }
            Text(String(format: NSLocalizedString("muscleBalanceOnTarget", comment: ""), calculator.onTargetCount()))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// One off-target group: the diverging bar with its coloured name and signed delta — the same
    /// language the overview's sections use, so tile and detail read as one.
    private func row(_ entry: MuscleBalanceEntry) -> some View {
        MuscleBalanceBar(entry: entry, showsName: true, showsDelta: true)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.tertiaryBackground))
    }

    /// A muted body silhouette + message when the period has no sets — themed to the muscle split
    /// rather than a bare one-line "no data".
    private var emptyState: some View {
        VStack(spacing: 10) {
            BodyMapFigure(highlighted: nil)
                .frame(width: 34, height: 70)
                .opacity(0.7)
            Text(NSLocalizedString("muscleBalanceEmpty", comment: ""))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("muscleBalanceEmptySubtitle", comment: ""))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}

#Preview {
    FetchRequestWrapper(Workout.self) { workouts in
        MuscleBalanceTile(workouts: workouts, period: .month)
            .previewEnvironmentObjects()
            .padding()
    }
}
