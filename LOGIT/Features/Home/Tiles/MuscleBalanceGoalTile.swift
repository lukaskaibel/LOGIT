//
//  MuscleBalanceGoalTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 28.07.26.
//

import SwiftUI

/// The Summary's Balance half: how many muscle groups reached their target share, over one filling
/// track each. Half width, paired with `StrengthTile`.
///
/// The headline counts groups that are **at least** their target, which is the rule the tracks
/// already draw — a bar visibly full while the count says otherwise is a tile arguing with itself.
/// That is a deliberate departure from `MuscleBalanceEntry.state`, whose tolerance is symmetric and
/// still governs the older diverging surfaces.
///
/// Untrained groups stay in the chart as empty tracks. A group with a real target and no sets is the
/// most out-of-balance state there is, and hiding it would make the tile look *better* the worse the
/// month went. Only a group the user has zeroed out drops away — that one can never fill, so it
/// leaves the denominator too.
///
/// It draws from the **first set on**, matching `MuscleGroupsOverviewScreen`, which is what the tile
/// taps through to. There used to be a 20-set floor here on the grounds that one session hits two or
/// three groups and so reports them "at or above target" purely because everything else is absent —
/// which is true, and the tile does read optimistically early on. But the detail screen never had
/// that floor, so the pair contradicted each other: a placeholder tile opening onto a fully drawn
/// split. One rule across both surfaces beats a defensible rule applied to only one of them.
struct MuscleBalanceGoalTile: View {
    /// Workouts already narrowed to the window the tile reports.
    let workouts: [Workout]

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
        let entries = calculator.goalEntries
        return VStack(alignment: .leading, spacing: 0) {
            header
            subtitle
                .padding(.top, 8)
            if calculator.totalSets > 0, !entries.isEmpty {
                count(met: calculator.atLeastTargetCount(), total: entries.count)
                    .padding(.top, 2)
                MuscleBalanceTrackChart(entries: entries)
                    .frame(maxHeight: .infinity)
                    .padding(.top, 12)
            } else {
                emptyState
                    .padding(.top, 12)
            }
        }
        .padding(CELL_PADDING)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileStyle()
        // The whole card is the target. Without this the tile is only tappable where its own
        // subviews are, so the gaps between the figure and the chart did nothing.
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(NSLocalizedString("balance", comment: ""))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            NavigationChevron()
                .foregroundStyle(Color.secondaryLabel)
        }
    }

    private var subtitle: some View {
        Text(NSLocalizedString("muscleBalanceGoalBasis", comment: ""))
            .font(.caption.weight(.medium))
            .tracking(0.3)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// Deliberately not accent-coloured: Strength's figure carries the accent on the other half of
    /// the pair, and two competing accents at the top of the screen is one too many. The denominator
    /// stays secondary so the pair reads as a goal rather than a score.
    private func count(met: Int, total: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(met)")
                .foregroundStyle(Color.label)
            Text("/\(total)")
                .foregroundStyle(Color.secondaryLabel)
        }
        .font(.system(size: 30, weight: .bold, design: .rounded))
        .monospacedDigit()
        .minimumScaleFactor(0.7)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(
                String(
                    format: NSLocalizedString("muscleBalanceGoalAccessibility", comment: ""),
                    met, total
                )
            )
        )
    }

    /// The same gray ring the Strength half and the core-stat tiles wear while they wait.
    ///
    /// The arc stays at zero — it renders as `TrendPlaceholder`'s minimum "begun" fill. It used to
    /// track progress toward the old set floor, but the tile now draws from the first set on, so
    /// this state means the window is genuinely empty and there is no progress to report.
    ///
    /// Greedy without a `Spacer` beside it, because `TrendPlaceholder` bottom-anchors itself: it
    /// stands in for the chart, which runs to the tile's bottom edge.
    private var emptyState: some View {
        TrendPlaceholder(
            progress: 0,
            text: NSLocalizedString("muscleBalanceEmpty", comment: ""),
            systemImage: "chart.pie.fill"
        )
    }
}

#Preview {
    FetchRequestWrapper(Workout.self) { workouts in
        HStack(alignment: .top, spacing: 10) {
            MuscleBalanceGoalTile(workouts: workouts)
            MuscleBalanceGoalTile(workouts: [])
        }
        .frame(height: 190)
        .padding()
    }
    .previewEnvironmentObjects()
}
