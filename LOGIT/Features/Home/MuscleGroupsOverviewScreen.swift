//
//  MuscleGroupsOverviewScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// The Muscle Groups overview: the goal hero leads — how many groups reached their target share, over
/// the same filling tracks the Balance tile draws — then the groups themselves, split by standing
/// (⌄ Below target · ✓ At target · ⌃⌃ Above target) as a two-column grid of tiles. The 4 weeks /
/// 3 months / 1 year picker sets the window. Tiles tap through to the muscle's own page. Pro; the
/// Summary's Balance tile is the free hook into it.
///
/// It opens on `TrendWindow.default` — the same rolling four weeks the tile reports — and it only ever
/// describes the window the picker names, which the header states outright. It used to open on the
/// newest window that had sets, which meant a tile saying "keep training" could open onto a fully drawn
/// split from months ago, with nothing on screen naming the period.
struct MuscleGroupsOverviewScreen: View {
    @State private var window: TrendWindow

    /// Opens on the window the Summary was showing, so the screen states the same measurement as the
    /// Balance tile that opened it.
    init(initialWindow: TrendWindow = .default) {
        _window = State(initialValue: initialWindow)
    }

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
        let range = window.range(windowsAgo: 0)
        let windowWorkouts = allWorkouts.filter { ($0.date).map { range.contains($0) } ?? false }
        let calculator = MuscleBalanceCalculator(
            workouts: windowWorkouts,
            target: targetSplitStore.split,
            muscleGroupService: muscleGroupService
        )

        return ScrollView {
            VStack(spacing: SECTION_SPACING) {
                TrendWindowPicker(selection: $window)
                if calculator.totalSets > 0 {
                    goalHero(calculator)
                    goalSections(calculator)
                } else {
                    emptyState
                }
                adjustRow
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        // Switching the window re-splits the sections and morphs the tracks.
        .animation(.snappy(duration: 0.3), value: window)
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(NSLocalizedString("muscleGroups", comment: ""))
                    .font(.headline)
            }
        }
    }

    // MARK: - Goal hero

    /// The Balance tile's own chart at full size, over the count it reports. Same component, same
    /// rule (a group counts once it is at least its target), same window on arrival — the detail
    /// screen is the tile with room, not a second opinion.
    ///
    /// The window name sits above the count, because every other number on the screen is a share
    /// *of that window*: four weeks and a year produce very different splits from the same training.
    ///
    /// No axis labels under the tracks: the tiles immediately below name every group in reading
    /// order, and eight labels at track width would be abbreviations of the words already there.
    private func goalHero(_ calculator: MuscleBalanceCalculator) -> some View {
        let entries = calculator.goalEntries
        return VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(window.currentWindowLabel)
                    .font(.caption.weight(.bold))
                    .tracking(0.3)
                    .foregroundStyle(.tertiary)
                    .contentTransition(.identity)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(calculator.atLeastTargetCount())")
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
                        calculator.totalSets
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
    private func goalSections(_ calculator: MuscleBalanceCalculator) -> some View {
        let entries = calculator.goalEntries
        let under = entries.filter { $0.goalState == .under }
            .sorted { ($0.goalFraction ?? 0) < ($1.goalFraction ?? 0) }
        let met = entries.filter { $0.goalState == .met }
            .sorted { $0.actualPercent > $1.actualPercent }
        let over = entries.filter { $0.goalState == .over }
            .sorted { $0.deviation > $1.deviation }
        VStack(spacing: SECTION_SPACING) {
            goalSection("muscleBalanceBelowTargetSection", systemImage: "chevron.down", entries: under)
            goalSection("muscleBalanceAtTargetSection", systemImage: "checkmark", entries: met, isGood: true)
            goalSection("muscleBalanceAboveTargetSection", systemImage: "chevron.up.2", entries: over)
        }
    }

    /// The header glyphs are the ones the tracks already use: a group short of target has no badge and
    /// gets the plain chevron down, at target is the check the badge wears, and overshoot is the same
    /// double chevron the badge wears — each in the circle the badges are drawn in.
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
                            Circle()
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
                                .muscleGroupDetail(entry.muscleGroup, window)
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
