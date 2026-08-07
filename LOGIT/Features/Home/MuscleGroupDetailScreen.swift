//
//  MuscleGroupDetailScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import CoreData
import SwiftUI

/// The single-muscle detail: a target-share tile (the diverging `MuscleBalanceBar` showing how the
/// group's share sits against target, with a "↓ Below target / ↑ Above target / ✓ On target" pill),
/// a 2×2 stat grid, a sets-history chart following the selected window, and the top exercises that
/// train it. Opens scoped to the window the caller was showing — the Summary's picker carries all the
/// way down here through Muscle Groups. Pro — the full per-muscle breakdown is the analytics behind
/// the wall.
///
/// It used to carry a calendar Week / Month / Year picker, which made it the one screen in the chain
/// that changed vocabulary: Summary on four rolling weeks → Muscle Groups on four rolling weeks →
/// this screen on a calendar month, with the switch never mentioned. The route now hands over a
/// `TrendWindow` unchanged.
struct MuscleGroupDetailScreen: View {
    let muscleGroup: MuscleGroup

    @State private var window: TrendWindow

    init(muscleGroup: MuscleGroup, initialWindow: TrendWindow = .default) {
        self.muscleGroup = muscleGroup
        _window = State(initialValue: initialWindow)
    }

    @EnvironmentObject private var muscleGroupService: MuscleGroupService
    @EnvironmentObject private var targetSplitStore: MuscleTargetSplitStore
    @EnvironmentObject private var homeNavigationCoordinator: HomeNavigationCoordinator

    private var color: Color { muscleGroup.color }

    var body: some View {
        FetchRequestWrapper(
            Workout.self,
            sortDescriptors: [SortDescriptor(\.date, order: .reverse)],
            predicate: WorkoutPredicateFactory.getWorkouts()
        ) { allWorkouts in
            content(allWorkouts: allWorkouts)
        }
    }

    private func content(allWorkouts: [Workout]) -> some View {
        // `TrendWindow.contains` rather than a range check, so the boundary instant two windows share
        // falls on the same side here as it does in every other rolling-window surface.
        let periodWorkouts = allWorkouts.filter { ($0.date).map { window.contains($0) } ?? false }
        let occurrences = muscleGroupService.getMuscleGroupOccurances(in: periodWorkouts)
        let total = occurrences.reduce(0) { $0 + $1.1 }
        let groupSetCount = occurrences.first { $0.0 == muscleGroup }?.1 ?? 0
        let percent = total > 0 ? Int((Double(groupSetCount) / Double(total) * 100).rounded()) : 0
        let rank = (occurrences.firstIndex { $0.0 == muscleGroup }).map { $0 + 1 } ?? MuscleGroup.allCases.count
        let setGroups = setGroupsTraining(in: periodWorkouts)
        let sessions = Set(setGroups.compactMap { $0.workout?.objectID }).count
        let volume = getVolume(of: setGroups.flatMap { $0.sets })
        let calculator = MuscleBalanceCalculator(workouts: periodWorkouts, target: targetSplitStore.split, muscleGroupService: muscleGroupService)
        let entry = calculator.entries.first { $0.muscleGroup == muscleGroup }
            ?? MuscleBalanceEntry(muscleGroup: muscleGroup, setCount: 0, actualPercent: 0, targetPercent: targetSplitStore.target(for: muscleGroup))

        return ScrollView {
            VStack(spacing: SECTION_SPACING) {
                TrendWindowPicker(selection: $window)
                if groupSetCount > 0 {
                    targetShare(entry: entry, percent: percent)
                    statGrid(setCount: groupSetCount, volume: volume, sessions: sessions, rank: rank)
                    setsHistoryChart(allWorkouts: allWorkouts)
                    topExercises(in: periodWorkouts)
                } else {
                    emptyState
                        .containerRelativeFrame(.vertical, alignment: .center) { height, _ in
                            max(height - 96, 320)
                        }
                }
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // Muscle names carry their colour themselves — bold, rounded, no identity dot.
                Text(muscleGroup.description)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(color)
            }
        }
    }

    // MARK: - Hero

    /// The target-share tile: the group's standing (↓ Below target / ↑ Above target / ✓ On target) +
    /// its share of sets, over the diverging `MuscleBalanceBar` — the fill grows out of the centred
    /// target tick, left when under, right when over.
    private func targetShare(entry: MuscleBalanceEntry, percent: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString("targetShare", comment: ""))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.label)
                    Text(String(format: NSLocalizedString("muscleDetailPercentOfSets", comment: ""), percent))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                stateBadge(entry.state)
            }
            MuscleBalanceBar(entry: entry, showsName: false, showsDelta: true)
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }

    private func stateBadge(_ state: MuscleBalanceState) -> some View {
        let word: String
        let icon: String
        let isGood: Bool
        switch state {
        case .under: word = "muscleBalanceBelowTarget"; icon = "arrow.down"; isGood = false
        case .over: word = "muscleBalanceAboveTarget"; icon = "arrow.up"; isGood = false
        // `muscleBalanceAtTargetSection` — the key the overview's section header uses. This read
        // `…OnTargetSection`, which has never existed in any locale, so the badge printed the raw
        // key on screen.
        case .onTarget: word = "muscleBalanceAtTargetSection"; icon = "checkmark"; isGood = true
        }
        return HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(NSLocalizedString(word, comment: ""))
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(isGood ? Color.accentColor : Color.secondaryLabel)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(isGood ? Color.accentColor.opacity(0.16) : Color.secondaryFill))
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.16))
                    .frame(width: 76, height: 76)
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(color.gradient)
            }
            VStack(spacing: 6) {
                Text(NSLocalizedString("muscleBalanceEmpty", comment: ""))
                    .font(.headline)
                Text(NSLocalizedString("muscleDetailEmptySubtitle", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }

    // MARK: - Stat grid

    private func statGrid(setCount: Int, volume: Int, sessions: Int, rank: Int) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
            statTile(title: NSLocalizedString("sets", comment: ""), value: "\(setCount)", unit: NSLocalizedString("sets", comment: ""), caption: periodCaption)
            statTile(title: NSLocalizedString("volume", comment: ""), value: formatWeightForDisplay(volume), unit: WeightUnit.used.rawValue, caption: periodCaption)
            statTile(title: NSLocalizedString("sessions", comment: ""), value: "\(sessions)", unit: "", caption: periodCaption)
            statTile(title: NSLocalizedString("rank", comment: ""), value: "#\(rank)", unit: "", caption: NSLocalizedString("muscleDetailRankCaption", comment: ""))
        }
    }

    private func statTile(title: String, value: String, unit: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.label)
            UnitView(value: value, unit: unit, configuration: .large, unitColor: .secondaryLabel)
                .foregroundStyle(color.gradient)
                .padding(.top, 10)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CELL_PADDING)
        .tileStyle()
    }

    // MARK: - Sets history chart

    /// Sets per window over recent history, one bar per `TrendWindow` back from now, current window
    /// highlighted. Titled "Sets over time" like the overview's "Balance over time" one level up
    /// rather than "Sets per month": a rolling window has no name to put after "per", and the caption
    /// beside it already says how far the strip reaches.
    private func setsHistoryChart(allWorkouts: [Workout]) -> some View {
        let sets = setsTraining(in: allWorkouts)
        let buckets = TrendWindowBucket.history(
            for: window,
            raw: { range in
                Double(sets.filter { set in
                    guard let date = set.workout?.date else { return false }
                    return date > range.lowerBound && date <= range.upperBound
                }.count)
            },
            display: { $0 },
            formatted: { String(Int($0.rounded())) }
        )
        return VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
            HStack {
                Text(NSLocalizedString("setsOverTime", comment: ""))
                    .sectionHeaderStyle2()
                Spacer()
                Text(window.historySpanCaption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            // The shared rolling-window chart in a compact tile — the same bars as the stat detail
            // screens, so tapping to inspect a window works here too, at the tile's height.
            TrendWindowHistoryChart(
                buckets: buckets,
                valueLabel: NSLocalizedString("sets", comment: ""),
                currentBarStyle: AnyShapeStyle(color),
                unit: NSLocalizedString("sets", comment: ""),
                height: 120
            )
            .padding(CELL_PADDING)
            .tileStyle()
        }
    }

    // MARK: - Top exercises

    private func topExercises(in workouts: [Workout]) -> some View {
        var byExercise: [NSManagedObjectID: (exercise: Exercise, count: Int)] = [:]
        for setGroup in setGroupsTraining(in: workouts) {
            let count = setGroup.sets.count
            if setGroup.exercise?.muscleGroup == muscleGroup, let exercise = setGroup.exercise {
                byExercise[exercise.objectID, default: (exercise, 0)].count += count
            }
            if setGroup.secondaryExercise?.muscleGroup == muscleGroup, let exercise = setGroup.secondaryExercise {
                byExercise[exercise.objectID, default: (exercise, 0)].count += count
            }
        }
        let top = byExercise.values.sorted { $0.count > $1.count }.prefix(5)
        return VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
            Text(NSLocalizedString("topExercises", comment: ""))
                .sectionHeaderStyle2()
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 0) {
                let items = Array(top)
                ForEach(Array(items.enumerated()), id: \.element.exercise.objectID) { index, item in
                    Button {
                        homeNavigationCoordinator.path.append(.exercise(item.exercise))
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "dumbbell.fill")
                                .font(.subheadline)
                                .foregroundStyle(color.gradient)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 9).fill(Color.fill))
                            Text(item.exercise.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.label)
                                .lineLimit(1)
                            Spacer()
                            UnitView(value: "\(item.count)", unit: NSLocalizedString("sets", comment: ""), unitColor: .secondaryLabel)
                                .foregroundStyle(.secondary)
                            NavigationChevron()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < items.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, CELL_PADDING)
            .tileStyle()
            .emptyPlaceholder(Array(top)) {
                Text(NSLocalizedString("noData", comment: ""))
            }
        }
    }

    // MARK: - Helpers

    private var periodCaption: String {
        window.currentWindowLabel
    }

    private func setGroupsTraining(in workouts: [Workout]) -> [WorkoutSetGroup] {
        workouts.flatMap { $0.setGroups }.filter {
            $0.exercise?.muscleGroup == muscleGroup || $0.secondaryExercise?.muscleGroup == muscleGroup
        }
    }

    private func setsTraining(in workouts: [Workout]) -> [WorkoutSet] {
        setGroupsTraining(in: workouts).flatMap { $0.sets }
    }
}
