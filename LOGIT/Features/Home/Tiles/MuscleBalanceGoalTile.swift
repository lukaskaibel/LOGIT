//
//  MuscleBalanceGoalTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 28.07.26.
//

import SwiftUI

/// The Summary's Balance half: which muscle groups are behind their weekly targets, over one filling
/// track each. Half width, paired with `StrengthTile`.
///
/// **A recommendation, not a score.** It used to lead with "3/8 at or above target", which stated a
/// result without saying what to do about it — and the tracks under it already showed the same
/// thing. Now it says "Behind on" and names the two groups furthest behind, each in its own colour,
/// with a small "+4" after them for the rest; the bars below carry every group's letters, so the
/// four more are nameable right there. Ranked by sets short, not by how full: six sets behind on
/// legs matters more than one behind on cardio, whatever the fractions say.
///
/// "Behind on" rather than "Focus on": under the Summary's timeframe picker, "Focus on Abs & Legs"
/// read as what the period *did* — the opposite of what it meant. A state can only be read forward.
/// The caption is tertiary like Strength's "Last 4 weeks", so the names lead.
///
/// **No focus, no advice.** Until the user has chosen a training focus the tile only asks for one,
/// with no bars at all: "behind on legs" only means something against targets the user endorsed. The
/// Summary presents the focus picker from here in that state rather than opening Muscle Groups.
///
/// Untrained groups stay in the chart as empty tracks. A group with a real target and no sets is the
/// most out-of-balance state there is, and hiding it would make the tile look *better* the worse the
/// month went. Only a group the user has zeroed out drops away — it has no target to fall short of.
struct MuscleBalanceGoalTile: View {
    /// Workouts already narrowed to the window the tile reports.
    let workouts: [Workout]
    /// How many weeks that window covers — the divisor for weekly averages (`TrendWindow.weeksCovered`).
    let weeks: Double

    @EnvironmentObject private var focusStore: MuscleFocusStore
    @EnvironmentObject private var muscleGroupService: MuscleGroupService

    private var calculator: MuscleBalanceCalculator {
        MuscleBalanceCalculator(
            workouts: workouts,
            focus: focusStore.focus,
            weeks: weeks,
            muscleGroupService: muscleGroupService
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !focusStore.hasChosenFocus {
                focusPrompt
            } else {
                chosenContent(calculator)
            }
        }
        .padding(CELL_PADDING)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tileStyle()
        // The whole card is the target. Without this the tile is only tappable where its own
        // subviews are, so the gaps between the figure and the chart did nothing.
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.3), value: focusStore.focus)
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

    // MARK: - Before a focus

    /// The ask, bottom-anchored where the chart would stand: a target, what to do, and what it gets
    /// you. The glyph wears the accent — it is the tile's only call to action.
    private var focusPrompt: some View {
        VStack(alignment: .leading, spacing: 3) {
            Spacer(minLength: 0)
            Image(systemName: "target")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 6)
            Text(NSLocalizedString("muscleFocusPromptTileTitle", comment: ""))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.label)
                .fixedSize(horizontal: false, vertical: true)
            Text(NSLocalizedString("muscleFocusPromptTileMessage", comment: ""))
                .font(.caption)
                .foregroundStyle(Color.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    // MARK: - With a focus

    @ViewBuilder
    private func chosenContent(_ calculator: MuscleBalanceCalculator) -> some View {
        let named = calculator.namedFocusEntries.map(\.muscleGroup)
        if calculator.totalSets > 0, !calculator.goalEntries.isEmpty {
            caption(named.isEmpty ? focusName : NSLocalizedString("muscleBalanceBehindOn", comment: ""))
                .padding(.top, 8)
            headline(named, more: calculator.unnamedFocusCount)
                .padding(.top, 2)
            MuscleBalanceTrackChart(entries: calculator.rankedEntries, labelSize: 8.5)
                .frame(maxHeight: .infinity)
                .padding(.top, 8)
        } else {
            caption(focusName)
                .padding(.top, 8)
            emptyState
                .padding(.top, 12)
        }
    }

    /// The preset's name, or "Custom" — what "on target" is measured against when nothing is behind.
    private var focusName: String {
        focusStore.focus.matchingPreset?.title ?? NSLocalizedString("muscleFocusCustom", comment: "")
    }

    /// The Strength half's caption style, so the pair reads as one component.
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .tracking(0.3)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// The groups behind, or "All on target" once none is. Always one line: a long pair ("Bizeps &
    /// Trizeps") shrinks to fit instead of wrapping, because a second line comes straight out of the
    /// chart below and the tracks would change height from one month to the next.
    ///
    /// The count of further groups sits on this line, small and grey at the trailing edge, so it
    /// belongs to the names: on the caption line it read as "behind on 4 more".
    private func headline(_ named: [MuscleGroup], more: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Group {
                if named.isEmpty {
                    Text(NSLocalizedString("muscleFocusAllOnTarget", comment: ""))
                        .foregroundStyle(Color.label)
                } else {
                    MuscleFocusNames(groups: named)
                }
            }
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .lineLimit(1)
            // Down to 0.45: "Abdominais e Pernas" at half a tile's width needs it, and at 0.55 it
            // truncated to "Pern…" instead.
            .minimumScaleFactor(0.45)
            .layoutPriority(1)
            if more > 0 {
                Spacer(minLength: 0)
                Text(String(format: NSLocalizedString("muscleBalanceMoreCount", comment: ""), more))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.secondaryLabel)
                    .monospacedDigit()
                    .lineLimit(1)
                    // Never squeezed: the names shrink around the count, not the other way round.
                    .fixedSize()
                    .accessibilityLabel(Text(String(format: NSLocalizedString("muscleFocusMoreAccessibility", comment: ""), more)))
            }
        }
    }

    /// The same gray ring the Strength half and the core-stat tiles wear while they wait — here, for
    /// a window with no sets in it.
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
            MuscleBalanceGoalTile(workouts: workouts, weeks: 4)
            MuscleBalanceGoalTile(workouts: [], weeks: 4)
        }
        .frame(height: 178)
        .padding()
    }
    .previewEnvironmentObjects()
}
