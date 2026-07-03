//
//  MuscleGroupsOverviewScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// The Muscle Groups overview: the muscle-group occurrence donut leads — the same circle the app uses
/// everywhere for muscle groups, with the period's total sets in its centre — over the groups grouped
/// by standing (↓ Below target · ↑ Above target · ✓ On target), each row the diverging
/// `MuscleBalanceBar` growing out of the target tick. Below, the slim segmented "Balance over time"
/// chart: Week / Month / Year sets its grouping and tapping a bar rebinds the donut and sections to
/// that period. Rows tap through to the muscle's own page. Pro; the Summary's Muscle Balance tile is
/// the free hook into it.
struct MuscleGroupsOverviewScreen: View {
    @State private var period: StatPeriod = .month
    /// The bar the gesture last selected (a bucket id), or nil for "none tapped yet" → newest with data.
    @State private var rawSelection: String?

    @EnvironmentObject private var muscleGroupService: MuscleGroupService
    @EnvironmentObject private var targetSplitStore: MuscleTargetSplitStore
    @EnvironmentObject private var homeNavigationCoordinator: HomeNavigationCoordinator

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
        let target = targetSplitStore.split
        let buckets = MuscleBalanceHistory.buckets(
            from: allWorkouts,
            period: period,
            target: target,
            muscleGroupService: muscleGroupService
        )
        let orderedGroups = orderedGroups(for: target)
        let hasData = buckets.contains { $0.totalSets > 0 }
        let selected = resolveSelected(in: buckets)

        return ScrollView {
            VStack(spacing: SECTION_SPACING) {
                PeriodPicker(selection: $period)
                if hasData {
                    if selected.totalSets > 0 {
                        donutHero(selected)
                        section(
                            titleKey: "muscleBalanceBelowTarget",
                            systemImage: "arrow.down",
                            entries: selected.calculator.underTargets()
                        )
                        section(
                            titleKey: "muscleBalanceAboveTarget",
                            systemImage: "arrow.up",
                            entries: selected.calculator.overTargets()
                        )
                        section(
                            titleKey: "muscleBalanceOnTargetSection",
                            systemImage: "checkmark",
                            entries: selected.calculator.entries
                                .filter(\.isOnTarget)
                                .sorted { $0.actualPercent > $1.actualPercent },
                            isGood: true
                        )
                    } else {
                        emptyBucketNote
                    }
                    chartSection(buckets: buckets, orderedGroups: orderedGroups, selectedID: selected.id)
                } else {
                    emptyState
                }
                adjustRow
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        // Selecting a bar re-splits the sections, morphs the donut, and ticks a selection haptic.
        .animation(.snappy(duration: 0.3), value: selected.id)
        .sensoryFeedback(.selection, trigger: selected.id)
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(NSLocalizedString("muscleGroups", comment: ""))
                    .font(.headline)
            }
        }
        .onChange(of: period) { rawSelection = nil }
    }

    // MARK: - Donut hero

    /// The muscle-group occurrence donut with the period's total sets in the centre and the period's
    /// name beneath — the name keeps time-travel legible when a past bar is selected.
    private func donutHero(_ bucket: MuscleBalanceBucket) -> some View {
        VStack(spacing: 12) {
            ZStack {
                MuscleGroupOccurancesChart(muscleGroupOccurances: occurrences(in: bucket))
                VStack(spacing: 1) {
                    Text("\(bucket.totalSets)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Color.label)
                    Text(NSLocalizedString("sets", comment: ""))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 190, height: 190)
            Text(bucket.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    /// The donut's input: this bucket's set occurrences per group, canonical order, untrained groups
    /// omitted (the chart draws slices only for what was trained).
    private func occurrences(in bucket: MuscleBalanceBucket) -> [(MuscleGroup, Int)] {
        bucket.calculator.entries
            .filter { $0.setCount > 0 }
            .map { ($0.muscleGroup, $0.setCount) }
    }

    // MARK: - Grouped sections

    @ViewBuilder
    private func section(
        titleKey: String,
        systemImage: String,
        entries: [MuscleBalanceEntry],
        isGood: Bool = false
    ) -> some View {
        if !entries.isEmpty {
            VStack(spacing: SECTION_HEADER_SPACING) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isGood ? Color.accentColor : Color.secondaryLabel)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(isGood ? Color.accentColor.opacity(0.16) : Color.fill)
                        )
                    Text(NSLocalizedString(titleKey, comment: ""))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.label)
                    Spacer()
                    Text("\(entries.count)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            homeNavigationCoordinator.path.append(.muscleGroupDetail(entry.muscleGroup))
                        } label: {
                            barRow(entry)
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
    }

    private func barRow(_ entry: MuscleBalanceEntry) -> some View {
        HStack(spacing: 8) {
            MuscleBalanceBar(entry: entry, showsName: true, showsDelta: true)
            NavigationChevron()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Chart

    private func chartSection(
        buckets: [MuscleBalanceBucket],
        orderedGroups: [MuscleGroup],
        selectedID: String
    ) -> some View {
        VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
            Text(NSLocalizedString("muscleBalanceOverTime", comment: ""))
                .sectionHeaderStyle2()
                .frame(maxWidth: .infinity, alignment: .leading)
            MuscleBalanceHistoryChart(
                buckets: buckets,
                orderedGroups: orderedGroups,
                selectedID: selectedID,
                rawSelection: $rawSelection
            )
            .padding(CELL_PADDING)
            .tileStyle()
        }
    }

    // MARK: - Empty states

    /// The selected bucket has no sets (the user tapped an empty bar) though other periods do.
    private var emptyBucketNote: some View {
        Text(NSLocalizedString("noData", comment: ""))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .tileStyle()
    }

    /// No sets anywhere in the window — nothing to chart at all.
    private var emptyState: some View {
        VStack(spacing: 10) {
            BodyMapFigure(highlighted: nil)
                .frame(width: 44, height: 92)
                .opacity(0.7)
            Text(NSLocalizedString("muscleBalanceEmpty", comment: ""))
                .font(.headline)
            Text(NSLocalizedString("muscleBalanceEmptySubtitle", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Adjust

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

    // MARK: - Helpers

    /// The bar currently selected, or — before any tap, or after a period switch — the most recent
    /// bucket that has sets (so the donut and sections always open on real data).
    private func resolveSelected(in buckets: [MuscleBalanceBucket]) -> MuscleBalanceBucket {
        if let rawSelection, let match = buckets.first(where: { $0.id == rawSelection }) {
            return match
        }
        return buckets.last(where: { $0.totalSets > 0 }) ?? buckets[buckets.count - 1]
    }

    /// Chart stack order: biggest target share first, so the composition is stable across periods.
    private func orderedGroups(for target: MuscleTargetSplit) -> [MuscleGroup] {
        MuscleGroup.allCases.sorted {
            let lhs = target.percentage(for: $0)
            let rhs = target.percentage(for: $1)
            if lhs != rhs { return lhs > rhs }
            let li = MuscleGroup.allCases.firstIndex(of: $0) ?? 0
            let ri = MuscleGroup.allCases.firstIndex(of: $1) ?? 0
            return li < ri
        }
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
