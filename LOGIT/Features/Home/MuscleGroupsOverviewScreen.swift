//
//  MuscleGroupsOverviewScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// The Muscle Groups overview: the goal hero leads — how many groups reached their target share, over
/// the same filling tracks the Balance tile draws — then the groups split by standing (↓ Below target ·
/// ↑ Above target · ✓ On target) as a two-column grid. Below, the slim segmented "Balance over time"
/// chart: the 4 weeks / 3 months / 1 year picker sets the window and tapping a bar rebinds the hero and
/// sections to it. Rows tap through to the muscle's own page. Pro; the Summary's Balance tile is the
/// free hook into it.
///
/// It opens on `TrendWindow.default` — the same rolling four weeks the tile reports — and the hero
/// stays on the *current* window until a bar is tapped. It used to open on the newest window that had
/// sets, which meant a tile saying "keep training" could open onto a fully drawn split from months ago,
/// with nothing on screen naming the period. The header now always names the window it is showing.
struct MuscleGroupsOverviewScreen: View {
    @State private var window: TrendWindow = .default
    /// The bar the gesture last selected (a bucket id), or nil for "none tapped yet" → the current window.
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
            window: window,
            target: target,
            muscleGroupService: muscleGroupService
        )
        let orderedGroups = orderedGroups(for: target)
        let hasData = buckets.contains { $0.totalSets > 0 }
        let selected = resolveSelected(in: buckets)

        return ScrollView {
            VStack(spacing: SECTION_SPACING) {
                TrendWindowPicker(selection: $window)
                if hasData {
                    if selected.totalSets > 0 {
                        goalHero(selected)
                        goalSections(selected)
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
        .onChange(of: window) { rawSelection = nil }
    }

    // MARK: - Goal hero

    /// The Balance tile's own chart at full size, over the count it reports. Same component, same
    /// rule (a group counts once it is at least its target), same window on arrival — the detail
    /// screen is the tile with room, not a second opinion.
    ///
    /// The window name sits above the count. It is the one line that makes every other number on the
    /// screen readable: the same hero can describe "Last 4 weeks" or a four-week block from last
    /// autumn depending on which bar is selected, and without it the two are indistinguishable.
    ///
    /// No axis labels under the tracks: the rows immediately below name every group in reading
    /// order, and eight labels at track width would be abbreviations of the words already there.
    private func goalHero(_ bucket: MuscleBalanceBucket) -> some View {
        let entries = bucket.calculator.goalEntries
        return VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(bucket.title)
                    .font(.caption.weight(.bold))
                    .tracking(0.3)
                    .foregroundStyle(.tertiary)
                    .contentTransition(.identity)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(bucket.calculator.atLeastTargetCount())")
                        .foregroundStyle(Color.label)
                    Text("/\(entries.count)")
                        .foregroundStyle(Color.secondaryLabel)
                }
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                Text(
                    String(
                        format: NSLocalizedString("muscleBalanceGoalHeroCaption", comment: ""),
                        bucket.totalSets
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            }
            MuscleBalanceTrackChart(entries: entries, spacing: 10, badgeDiameter: 22)
                .frame(height: 130)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    /// The eight groups as a two-column grid, split by verdict: what needs work, what is done, what
    /// overshot. The grouping is what makes two columns readable — within a section every cell shares
    /// a state, so scanning a column is comparing magnitudes rather than decoding badges.
    ///
    /// Below-target leads: it is the only section you can act on, and the other two are its cause.
    @ViewBuilder
    private func goalSections(_ bucket: MuscleBalanceBucket) -> some View {
        let entries = bucket.calculator.goalEntries
        let under = entries.filter { $0.goalState == .under }
            .sorted { ($0.goalFraction ?? 0) < ($1.goalFraction ?? 0) }
        let met = entries.filter { $0.goalState == .met }
            .sorted { $0.actualPercent > $1.actualPercent }
        let over = entries.filter { $0.goalState == .over }
            .sorted { $0.deviation > $1.deviation }
        VStack(spacing: SECTION_SPACING) {
            goalSection("muscleBalanceBelowTargetSection", systemImage: "arrow.down", entries: under)
            goalSection("muscleBalanceAtTargetSection", systemImage: "checkmark", entries: met, isGood: true)
            goalSection("muscleBalanceAboveTargetSection", systemImage: "chevron.up.2", entries: over)
        }
    }

    @ViewBuilder
    private func goalSection(
        _ titleKey: String,
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
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(entries) { entry in
                        Button {
                            homeNavigationCoordinator.path.append(
                                .muscleGroupDetail(entry.muscleGroup, window.nearestStatPeriod)
                            )
                        } label: {
                            MuscleBalanceGoalCell(entry: entry)
                        }
                        .buttonStyle(TileButtonStyle())
                    }
                }
            }
        }
    }

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

    /// The bar currently selected, or — before any tap, or after a window switch — the **current**
    /// window, so the screen opens on exactly what the Balance tile reported.
    ///
    /// It deliberately does not reach back to the newest window that has sets. That fallback made an
    /// empty current window silently show old data, which is how a placeholder tile could open onto a
    /// populated screen; an empty window now says so via `emptyBucketNote` and the reader can tap
    /// back through the strip themselves.
    private func resolveSelected(in buckets: [MuscleBalanceBucket]) -> MuscleBalanceBucket {
        if let rawSelection, let match = buckets.first(where: { $0.id == rawSelection }) {
            return match
        }
        return buckets[buckets.count - 1]
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
