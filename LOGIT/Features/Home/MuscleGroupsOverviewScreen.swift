//
//  MuscleGroupsOverviewScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// The Muscle Groups overview (`muscle-group-screens.html` screen 1): a period-scoped set-distribution
/// donut, a neutral "on target" insight banner (no alarm colour — muscle hues are identity, not
/// warning), the full eight-group balance-vs-target list (worst gap first) built from the shared
/// `MuscleBalanceBar`, and a row into the target-split editor. The full breakdown is Pro; the
/// Summary's Muscle Balance tile is the free hook into it. Replaces the 2022 `MuscleGroupSplitScreen`.
struct MuscleGroupsOverviewScreen: View {
    @State private var period: StatPeriod = .month

    @EnvironmentObject private var muscleGroupService: MuscleGroupService
    @EnvironmentObject private var targetSplitStore: MuscleTargetSplitStore
    @EnvironmentObject private var homeNavigationCoordinator: HomeNavigationCoordinator

    var body: some View {
        FetchRequestWrapper(
            Workout.self,
            sortDescriptors: [SortDescriptor(\.date, order: .reverse)],
            predicate: WorkoutPredicateFactory.getWorkouts()
        ) { allWorkouts in
            let range = period.currentRange()
            content(workouts: allWorkouts.filter { ($0.date).map { range.contains($0) } ?? false })
        }
    }

    private func content(workouts: [Workout]) -> some View {
        let occurrences = muscleGroupService.getMuscleGroupOccurances(in: workouts)
        let totalSets = occurrences.reduce(0) { $0 + $1.1 }
        let calculator = MuscleBalanceCalculator(
            workouts: workouts,
            target: targetSplitStore.split,
            muscleGroupService: muscleGroupService
        )
        return ScrollView {
            VStack(spacing: SECTION_SPACING) {
                VStack(spacing: 16) {
                    PeriodPicker(selection: $period)
                    donut(occurrences: occurrences, totalSets: totalSets)
                    insightBanner(calculator)
                }
                balanceList(calculator)
                adjustRow
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(NSLocalizedString("muscleGroups", comment: ""))
                    .font(.headline)
            }
        }
    }

    private func donut(occurrences: [(MuscleGroup, Int)], totalSets: Int) -> some View {
        ZStack {
            MuscleGroupOccurancesChart(muscleGroupOccurances: occurrences)
                .frame(width: 170, height: 170)
            VStack(spacing: 2) {
                Text("\(totalSets)")
                    .font(.system(size: 34, weight: .bold))
                    .fontDesign(.rounded)
                Text(NSLocalizedString("sets", comment: ""))
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func insightBanner(_ calculator: MuscleBalanceCalculator) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.pie.fill")
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(bannerTitle(calculator))
                    .font(.subheadline.weight(.bold))
                Text(String(format: NSLocalizedString("muscleBalanceOnTarget", comment: ""), calculator.onTargetCount()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }

    private func bannerTitle(_ calculator: MuscleBalanceCalculator) -> String {
        if calculator.totalSets == 0 { return NSLocalizedString("muscleBalanceEmpty", comment: "") }
        return calculator.onTargetCount() >= 6
            ? NSLocalizedString("muscleBalanceOnTrack", comment: "")
            : NSLocalizedString("muscleBalanceRoomToBalance", comment: "")
    }

    private func balanceList(_ calculator: MuscleBalanceCalculator) -> some View {
        VStack(spacing: SECTION_HEADER_SPACING) {
            Text(NSLocalizedString("balanceVsTarget", comment: ""))
                .sectionHeaderStyle2()
                .frame(maxWidth: .infinity, alignment: .leading)
            let entries = calculator.worstGapSorted()
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        homeNavigationCoordinator.path.append(.muscleGroupDetail(entry.muscleGroup))
                    } label: {
                        HStack(spacing: 8) {
                            MuscleBalanceBar(entry: entry, showsName: true, showsDelta: true)
                            NavigationChevron()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < entries.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, CELL_PADDING)
            .tileStyle()
        }
    }

    private var adjustRow: some View {
        Button {
            homeNavigationCoordinator.path.append(.muscleTargetSplit)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                Text(NSLocalizedString("adjustTargetSplit", comment: ""))
                    .foregroundStyle(Color.label)
                Spacer()
                NavigationChevron()
                    .foregroundStyle(.secondary)
            }
            .padding(CELL_PADDING)
            .tileStyle()
        }
        .buttonStyle(TileButtonStyle())
    }
}

private struct PreviewWrapperView: View {
    var body: some View {
        NavigationStack {
            MuscleGroupsOverviewScreen()
        }
    }
}

struct MuscleGroupsOverviewScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
