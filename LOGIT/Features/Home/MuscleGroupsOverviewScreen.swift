//
//  MuscleGroupsOverviewScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// The Muscle Groups overview: the training focus every number here is measured against, the goal
/// hero — how many groups reached their target share, over the same filling tracks the Balance tile
/// draws — then the eight groups as a two-column grid of tiles. The 4 weeks / 3 months / 1 year picker
/// sets the window. Pro; the Summary's Balance tile is the free hook into it.
///
/// It is the focus editor's twin. The editor sets priorities in a fixed two-column grid; this screen
/// reads results in the identical grid, in the same order, so a group sits in the same place on both
/// and "set there, read here" needs no explaining. It used to file the groups under Below / At / Above
/// target sections instead, which re-sorted the whole grid every time the window changed and said
/// again what each tile's badge already says.
///
/// It opens on `TrendWindow.default` — the same rolling four weeks the tile reports — and it only ever
/// describes the window the picker at its top names.
struct MuscleGroupsOverviewScreen: View {
    @State private var window: TrendWindow

    /// Opens on the window the Summary was showing, so the screen states the same measurement as the
    /// Balance tile that opened it.
    init(initialWindow: TrendWindow = .default) {
        _window = State(initialValue: initialWindow)
    }

    @EnvironmentObject private var muscleGroupService: MuscleGroupService
    @EnvironmentObject private var focusStore: MuscleFocusStore
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
        let range = window.range(windowsAgo: 0)
        let windowWorkouts = allWorkouts.filter { ($0.date).map { range.contains($0) } ?? false }
        let calculator = MuscleBalanceCalculator(
            workouts: windowWorkouts,
            focus: focusStore.focus,
            weeks: window.weeksCovered(firstDataDate: allWorkouts.compactMap(\.date).min()),
            muscleGroupService: muscleGroupService
        )

        return ScrollView {
            VStack(spacing: SECTION_SPACING) {
                TrendWindowPicker(selection: $window)
                focusHeader
                if calculator.totalSets > 0 {
                    goalHero(calculator)
                    groupGrid(calculator)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        // Switching the window morphs the tracks; changing the focus re-targets every tile.
        .animation(.snappy(duration: 0.3), value: window)
        .animation(.snappy(duration: 0.3), value: focusStore.focus)
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(NSLocalizedString("muscleGroups", comment: ""))
                    .font(.headline)
            }
        }
    }

    // MARK: - Focus

    /// The basis of every number below, as the control that changes it: the same menu the editor's
    /// title is, plus a way into the editor itself. It sits above the hero because it is what the
    /// hero's "at or above target" is *relative to*; it used to be the last row of the page, a full
    /// screen below the numbers it explained.
    ///
    /// Until the user has chosen a focus, one quiet caption says the targets are the default. It is
    /// a statement rather than a request — the default is a perfectly good focus — and it goes the
    /// first time anything is chosen.
    private var focusHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            MuscleFocusMenu(onEditTargets: {
                homeNavigationCoordinator.path.append(.muscleFocus)
            })
            if !focusStore.hasChosenFocus {
                Text(NSLocalizedString("muscleFocusDefaultCaption", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryLabel)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .animation(.snappy, value: focusStore.hasChosenFocus)
    }

    // MARK: - Goal hero

    /// The Balance tile's own chart at full size, over the count it reports. Same component, same
    /// rule (a group counts once it is at least its target), same window on arrival — the detail
    /// screen is the tile with room, not a second opinion.
    ///
    /// Just the count and what it counts. The window used to be named above it and the period's set
    /// total beside the caption; the picker at the top of the screen already names the window, and
    /// the set total isn't what the count is about. The caption is tertiary, like the Balance tile's
    /// own "at or above target", so the count reads first.
    ///
    /// No axis labels under the tracks: the tiles immediately below name every group, and eight labels
    /// at track width would be abbreviations of the words already there.
    private func goalHero(_ calculator: MuscleBalanceCalculator) -> some View {
        let entries = calculator.goalEntries
        return VStack(spacing: 14) {
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(calculator.atLeastTargetCount())")
                        .foregroundStyle(Color.label)
                    Text("/\(entries.count)")
                        .foregroundStyle(Color.secondaryLabel)
                }
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                Text(NSLocalizedString("muscleBalanceGoalHeroCaption", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            MuscleBalanceTrackChart(entries: entries, spacing: 10, badgeDiameter: 22)
                .frame(height: 130)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Grid

    /// All eight groups, two across, in the editor's order. A group the user turned off keeps its
    /// place as an Off tile, the way it does on the editor — dropping it would slide every later
    /// group into a different slot and break the one promise the shared order makes. It stays out of
    /// the hero and the count, where there is no target for it to be read against.
    ///
    /// The tiles don't open anything. Each used to push the muscle's own page, which repeated the
    /// tile's reading at a larger size over a weekly chart.
    private func groupGrid(_ calculator: MuscleBalanceCalculator) -> some View {
        let byGroup = Dictionary(uniqueKeysWithValues: calculator.goalEntries.map { ($0.muscleGroup, $0) })
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
            spacing: 8
        ) {
            ForEach(MuscleFocus.displayOrder, id: \.self) { group in
                Group {
                    // The goal entries are exactly the groups with a target, so a group missing
                    // from them is one the user set to 0.
                    if let entry = byGroup[group] {
                        MuscleBalanceGoalCell(entry: entry)
                    } else {
                        MuscleBalanceGoalCell(
                            entry: MuscleBalanceEntry(muscleGroup: group, setCount: 0, setsPerWeek: 0, target: 0),
                            isExcluded: true
                        )
                    }
                }
                .accessibilityIdentifier("muscleBalanceCell_\(group.rawValue)")
            }
        }
    }

    // MARK: - Empty state

    /// No sets in the window the picker names — nothing to split.
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
