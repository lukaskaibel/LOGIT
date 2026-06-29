//
//  MuscleBalanceTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// The Summary screen's period-scoped Muscle Balance tile — the free, actionable hook (same pattern as
/// Records: tile free, detail Pro). It leads with a one-line, period-aware insight, shows the couple
/// of groups furthest from target as diverging `MuscleBalanceBar` rows, and footers "N of 8 on
/// target". Non-nagging: the insight only ever flags a major/compound group under target, never an
/// "over" and never a deliberately-light abs/cardio. Taps into the Muscle Groups overview.
struct MuscleBalanceTile: View {
    /// Workouts already filtered to the Summary's selected period.
    let workouts: [Workout]
    let period: StatPeriod

    @EnvironmentObject private var targetSplitStore: MuscleTargetSplitStore
    @EnvironmentObject private var muscleGroupService: MuscleGroupService

    private var calculator: MuscleBalanceCalculator {
        MuscleBalanceCalculator(
            workouts: workouts,
            target: targetSplitStore.split,
            muscleGroupService: muscleGroupService
        )
    }

    var body: some View {
        let calculator = self.calculator
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(NSLocalizedString("muscleBalance", comment: ""))
                    .tileHeaderStyle()
                Spacer()
                NavigationChevron()
                    .foregroundStyle(.secondary)
            }
            if calculator.totalSets > 0 {
                Text(insightText(calculator.insight(for: period)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 11) {
                    ForEach(topEntries(calculator)) { entry in
                        MuscleBalanceBar(entry: entry, showsName: true, showsDelta: true)
                    }
                }
                Text(String(format: NSLocalizedString("muscleBalanceOnTarget", comment: ""), calculator.onTargetCount()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                emptyState
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
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

    /// The two groups furthest from target — the most informative rows for a compact tile.
    private func topEntries(_ calculator: MuscleBalanceCalculator) -> [MuscleBalanceEntry] {
        Array(calculator.entries.sorted { abs($0.deviation) > abs($1.deviation) }.prefix(2))
    }

    private func insightText(_ insight: MuscleBalanceInsight) -> String {
        switch insight {
        case .empty:
            return NSLocalizedString("muscleBalanceEmpty", comment: "")
        case .balanced:
            return NSLocalizedString("muscleBalanceBalanced", comment: "")
        case let .mostTrained(group):
            return String(format: NSLocalizedString("muscleBalanceMostTrained", comment: ""), group.description)
        case let .behind(group, setsToGo):
            switch period {
            case .week:
                return String(format: NSLocalizedString("muscleBalanceSetsToGo", comment: ""), group.description, setsToGo)
            case .month:
                return String(format: NSLocalizedString("muscleBalanceLightMonth", comment: ""), group.description)
            case .year:
                return String(format: NSLocalizedString("muscleBalanceLightYear", comment: ""), group.description)
            }
        }
    }
}

#Preview {
    FetchRequestWrapper(Workout.self) { workouts in
        MuscleBalanceTile(workouts: workouts, period: .month)
            .previewEnvironmentObjects()
            .padding()
    }
}
