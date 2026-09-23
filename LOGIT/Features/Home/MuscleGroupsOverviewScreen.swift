//
//  MuscleGroupsOverviewScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// Muscle Groups: which groups to train next, the Balance tile's chart at full size with every bar
/// lettered, and all eight groups as rows filed under Below / At / Above target. The 4 weeks / 3 months
/// / 1 year picker sets the window. Pro; the Summary's Balance tile is the free hook into it.
///
/// **There is no default focus.** Until one is chosen the screen holds no readings at all — a short
/// explanation of what a focus is and one button to choose one — because "behind on" only means
/// something against targets the user endorsed. After that, **the focus every number is measured
/// against** is the navigation subtitle ("Full Body", "Custom"), and the toolbar button beside it
/// opens the focus picker — the one setting that
/// changes what everything on the screen means, stated where a screen states what it shows. It used
/// to be a menu row at the top of the page, and before that the last row, a screen below the numbers
/// it explained.
///
/// **The chart and the rows share one order** (`MuscleBalanceCalculator.rankedEntries`): short groups
/// first, furthest behind leading, then at target, then past it. The headline names the first two,
/// they are the leftmost bars, and their rows open the list. Each bar's letters are the lead of its row.
///
/// **A row or a bar opens a popover** with the group's weekly target and the exercises behind its
/// sets. Bar and row are the same group, so both open the same popover, hanging off whichever was
/// tapped. Opened from a bar, the popover hangs under it, so the bar changes above the target control
/// while you edit it. While a popover is up the chart keeps its order and every row its section — one
/// of them is the popover's anchor, and a bar sliding away from under its arrow would take the popover
/// with it. Only the numbers stay live. On close, bars and rows move to their new places together.
///
/// It opens on the window the Summary was showing, so the screen states the same measurement as the
/// Balance tile that opened it.
struct MuscleGroupsOverviewScreen: View {
    @State private var window: TrendWindow

    init(initialWindow: TrendWindow = .default) {
        _window = State(initialValue: initialWindow)
    }

    @EnvironmentObject private var muscleGroupService: MuscleGroupService
    @EnvironmentObject private var focusStore: MuscleFocusStore

    @State private var isShowingFocusPicker = false
    /// The open target popover, and what it hangs off.
    @State private var popoverAnchor: PopoverAnchor?
    /// The chart and the rows as they stood when the popover opened. While it is set, bar order and
    /// sections come from here and only the numbers are live.
    @State private var frozenArrangement: Arrangement?

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
        let arrangement = frozenArrangement ?? Arrangement(calculator)
        let byGroup = Dictionary(uniqueKeysWithValues: calculator.entries.map { ($0.muscleGroup, $0) })

        return ScrollView {
            VStack(alignment: .leading, spacing: SECTION_SPACING) {
                if !focusStore.hasChosenFocus {
                    focusIntro
                } else {
                    TrendWindowPicker(selection: $window)
                    if let goal = focusStore.suggestedResizeGoal {
                        resizeCard(goal: goal)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                    if calculator.totalSets > 0 {
                        hero(calculator, arrangement: arrangement, byGroup: byGroup, windowWorkouts: windowWorkouts)
                        groupSections(arrangement: arrangement, byGroup: byGroup, windowWorkouts: windowWorkouts)
                    } else {
                        emptyState
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        // Switching the window morphs the tracks; changing the focus re-targets every row.
        .animation(.snappy(duration: 0.3), value: window)
        .animation(.snappy(duration: 0.3), value: focusStore.focus)
        .animation(.snappy(duration: 0.3), value: focusStore.hasChosenFocus)
        .animation(.snappy(duration: 0.3), value: frozenArrangement == nil)
        .isBlockedWithoutPro()
        .navigationTitle(NSLocalizedString("muscleGroups", comment: ""))
        .navigationSubtitle(focusSubtitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingFocusPicker = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel(Text(NSLocalizedString("trainingFocus", comment: "")))
                .accessibilityIdentifier("muscleFocusButton")
            }
        }
        .sheet(isPresented: $isShowingFocusPicker) {
            MuscleFocusPickerSheet()
                .environmentObject(focusStore)
        }
    }

    /// What every number is measured against: the preset, or "Custom". Nothing before a choice — there
    /// is no focus to name.
    private var focusSubtitle: String {
        guard focusStore.hasChosenFocus else { return "" }
        return focusStore.focus.matchingPreset?.title ?? NSLocalizedString("muscleFocusCustom", comment: "")
    }

    // MARK: - Cards

    /// The weekly goal moved since the targets were sized: offer to follow it, or keep them. Never
    /// automatic — the user may have tuned numbers they want left alone — and a "Not Now" holds until
    /// the goal changes again.
    private func resizeCard(goal: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                goal == 1
                    ? NSLocalizedString("muscleFocusResizeTitleOne", comment: "")
                    : String(format: NSLocalizedString("muscleFocusResizeTitle", comment: ""), goal)
            )
            .font(.headline)
            .foregroundStyle(Color.label)
            Text(String(format: NSLocalizedString("muscleFocusResizeMessage", comment: ""), focusStore.focus.workoutsPerWeek))
                .font(.subheadline)
                .foregroundStyle(Color.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy) { focusStore.resizeToWorkoutGoal() }
                } label: {
                    Text(NSLocalizedString("muscleFocusResizeAction", comment: ""))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.background)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor, in: Capsule())
                }
                .accessibilityIdentifier("muscleFocusResizeUpdate")
                Button {
                    withAnimation(.snappy) { focusStore.keepTargetsForWorkoutGoal() }
                } label: {
                    Text(NSLocalizedString("notNow", comment: ""))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.fill, in: Capsule())
                }
                .accessibilityIdentifier("muscleFocusResizeKeep")
            }
            .buttonStyle(TileButtonStyle())
            .padding(.top, 10)
        }
        .padding(CELL_PADDING + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileStyle()
    }

    /// The whole screen before a focus is chosen: what a focus is, in three lines, and the one thing
    /// to do. No picker, no chart, no rows — there are no targets to read anything against, and
    /// showing readings against a default the user never picked was the thing this replaces.
    private var focusIntro: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("muscleFocusIntroTitle", comment: ""))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.label)
                    .fixedSize(horizontal: false, vertical: true)
                Text(NSLocalizedString("muscleFocusIntroLead", comment: ""))
                    .font(.body)
                    .foregroundStyle(Color.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 18) {
                introPoint("target", "muscleFocusIntroTargets")
                introPoint("chart.bar.fill", "muscleFocusIntroBehind")
                introPoint("slider.horizontal.3", "muscleFocusIntroAdjust")
            }
            Button {
                isShowingFocusPicker = true
            } label: {
                Text(NSLocalizedString("muscleFocusChoose", comment: ""))
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("muscleFocusPromptButton")
        }
        .padding(.horizontal, 4)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func introPoint(_ systemImage: String, _ key: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            Text(NSLocalizedString(key, comment: ""))
                .font(.subheadline)
                .foregroundStyle(Color.label)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Hero

    /// The recommendation over the chart. "Behind on" and the groups furthest behind, at most two,
    /// in their colours, with the count of further groups small at the end of the line; "All on
    /// target" once none is short. Each bar opens its group's popover, like its row.
    private func hero(
        _ calculator: MuscleBalanceCalculator,
        arrangement: Arrangement,
        byGroup: [MuscleGroup: MuscleBalanceEntry],
        windowWorkouts: [Workout]
    ) -> some View {
        let named = calculator.namedFocusEntries.map(\.muscleGroup)
        let more = calculator.unnamedFocusCount
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                    Text(named.isEmpty ? focusSubtitle : NSLocalizedString("muscleBalanceBehindOn", comment: ""))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.secondaryLabel)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Group {
                            if named.isEmpty {
                                Text(NSLocalizedString("muscleFocusAllOnTarget", comment: ""))
                                    .foregroundStyle(Color.label)
                            } else {
                                MuscleFocusNames(groups: named)
                            }
                        }
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .accessibilityAddTraits(.isHeader)
                        if !named.isEmpty, more > 0 {
                            Text(String(format: NSLocalizedString("muscleBalanceMoreCount", comment: ""), more))
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.secondaryLabel)
                                .monospacedDigit()
                                .fixedSize()
                                .accessibilityLabel(Text(String(format: NSLocalizedString("muscleFocusMoreAccessibility", comment: ""), more)))
                        }
                    }
            }
            .padding(.horizontal, 4)
            MuscleBalanceTrackChart(
                entries: arrangement.bars.compactMap { byGroup[$0] },
                spacing: 10,
                badgeDiameter: 22
            ) { entry, bar in
                Button {
                    openPopover(.bar(entry.muscleGroup), arrangement: arrangement)
                } label: {
                    bar.contentShape(Rectangle())
                }
                .buttonStyle(MuscleBalanceBarButtonStyle())
                .targetPopover(
                    isPresented: popoverBinding(.bar(entry.muscleGroup)),
                    group: entry.muscleGroup,
                    window: window,
                    workouts: windowWorkouts,
                    focusStore: focusStore
                )
            }
            .frame(height: 160)
            .accessibilityIdentifier("muscleBalanceChart")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Popover

    /// Where a group's target popover hangs. Bar and row open the same popover, so the anchor is the
    /// only difference, and it keeps the two from both presenting.
    private enum PopoverAnchor: Hashable {
        case bar(MuscleGroup)
        case row(MuscleGroup)
    }

    /// Where every group stands on the screen: the chart's bar order and the rows' sections, both
    /// from `rankedEntries`, so they always agree — frozen together, released together.
    private struct Arrangement {
        var bars: [MuscleGroup]
        var sections: [MuscleBalanceSection: [MuscleGroup]]

        init(_ calculator: MuscleBalanceCalculator) {
            let ranked = calculator.rankedEntries
            bars = ranked.map(\.muscleGroup)
            sections = [:]
            for entry in ranked {
                sections[MuscleBalanceSection(entry.goalState), default: []].append(entry.muscleGroup)
            }
            sections[.off] = calculator.excludedEntries.map(\.muscleGroup)
        }
    }

    private func openPopover(_ anchor: PopoverAnchor, arrangement: Arrangement) {
        // Pin the chart and the list as they stand, so the bar or row under the popover stays where
        // its arrow points.
        frozenArrangement = arrangement
        popoverAnchor = anchor
    }

    private func popoverBinding(_ anchor: PopoverAnchor) -> Binding<Bool> {
        Binding(
            get: { popoverAnchor == anchor },
            set: { isPresented in
                if !isPresented, popoverAnchor == anchor {
                    popoverAnchor = nil
                    frozenArrangement = nil
                }
            }
        )
    }

    // MARK: - Sections

    /// Every group as a row, filed by verdict — short first, as in the chart — with the groups the
    /// user turned off last, so the list always holds all eight. Empty sections don't appear.
    private func groupSections(
        arrangement: Arrangement,
        byGroup: [MuscleGroup: MuscleBalanceEntry],
        windowWorkouts: [Workout]
    ) -> some View {
        let filing = arrangement.sections
        let visible = MuscleBalanceSection.allCases.filter { !(filing[$0] ?? []).isEmpty }
        return VStack(alignment: .leading, spacing: SECTION_SPACING) {
            ForEach(visible, id: \.self) { section in
                VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
                    sectionHeader(section)
                    VStack(spacing: 0) {
                        ForEach(Array((filing[section] ?? []).enumerated()), id: \.element) { index, group in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 60)
                            }
                            if let entry = byGroup[group] {
                                row(entry, windowWorkouts: windowWorkouts, arrangement: arrangement)
                            }
                        }
                    }
                    .tileStyle()
                    if section == visible.first {
                        Text(NSLocalizedString("muscleBalanceRowsFooter", comment: ""))
                            .font(.footnote)
                            .foregroundStyle(Color.secondaryLabel)
                            .padding(.horizontal, 4)
                    }
                }
            }
        }
    }

    /// The section's verdict as the same mark its bars wear, over a neutral disc, and its name.
    private func sectionHeader(_ section: MuscleBalanceSection) -> some View {
        HStack(spacing: 8) {
            MuscleBalanceGoalBadge(systemImage: section.systemImage, diameter: 20)
            Text(section.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.secondaryLabel)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// One group: its letters in its colour, its name, and its weekly sets over the target. The section
    /// says which side of the target the row is on and "3/5" says how far; a coloured "+2" used to
    /// follow it, which said the same thing a second time and read like a bonus.
    private func row(
        _ entry: MuscleBalanceEntry,
        windowWorkouts: [Workout],
        arrangement: Arrangement
    ) -> some View {
        let group = entry.muscleGroup
        let isOff = entry.target == 0
        return Button {
            openPopover(.row(group), arrangement: arrangement)
        } label: {
            HStack(spacing: 12) {
                Text(group.abbreviation)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(isOff ? Color.secondaryLabel : group.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 32, alignment: .leading)
                Text(group.description)
                    .font(.body)
                    .foregroundStyle(isOff ? Color.secondaryLabel : Color.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if isOff {
                    Text(NSLocalizedString("muscleBalanceNoTarget", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(Color.secondaryLabel)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(entry.setsPerWeek)")
                            .foregroundStyle(Color.label)
                        Text("/\(entry.target)")
                            .foregroundStyle(Color.secondaryLabel)
                    }
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(MuscleBalanceRowButtonStyle())
        .targetPopover(
            isPresented: popoverBinding(.row(group)),
            group: group,
            window: window,
            workouts: windowWorkouts,
            focusStore: focusStore
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(rowAccessibilityLabel(entry)))
        .accessibilityHint(Text(NSLocalizedString("muscleBalanceRowHint", comment: "")))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("muscleBalanceRow_\(group.rawValue)")
    }

    private func rowAccessibilityLabel(_ entry: MuscleBalanceEntry) -> String {
        guard entry.target > 0 else {
            return entry.muscleGroup.description + ", " + NSLocalizedString("muscleBalanceNoTarget", comment: "")
        }
        var label = entry.muscleGroup.description + ", "
            + String(format: NSLocalizedString("muscleBalanceSetsOfTarget", comment: ""), entry.setsPerWeek, entry.target)
        if entry.setsShort > 0 {
            label += ", " + String(format: NSLocalizedString("muscleBalanceSetsShortAccessibility", comment: ""), entry.setsShort)
        }
        return label
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

// MARK: - Sections

/// Where a group's row is filed on Muscle Groups: by its verdict, or under Off when the user took its
/// target away. Each wears the badge its bars wear.
enum MuscleBalanceSection: CaseIterable, Hashable {
    case below, at, above, off

    init(_ state: MuscleBalanceGoalState) {
        switch state {
        case .under: self = .below
        case .met: self = .at
        case .over: self = .above
        }
    }

    var title: String {
        switch self {
        case .below: return NSLocalizedString("muscleBalanceSectionBelow", comment: "")
        case .at: return NSLocalizedString("muscleBalanceSectionAt", comment: "")
        case .above: return NSLocalizedString("muscleBalanceSectionAbove", comment: "")
        case .off: return NSLocalizedString("musclePriorityOff", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .below: return MuscleBalanceGoalBadge.symbol(for: .under)
        case .at: return MuscleBalanceGoalBadge.symbol(for: .met)
        case .above: return MuscleBalanceGoalBadge.symbol(for: .over)
        case .off: return "minus"
        }
    }
}

/// A list row's press: the row greys under the finger, like a table cell, rather than shrinking like
/// a tile.
private struct MuscleBalanceRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.label.opacity(0.08) : Color.clear)
    }
}

/// A bar's press: the whole bar, letters included, dims under the finger, the way a plain button's
/// content does. A bar has no cell around it to grey.
private struct MuscleBalanceBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Target popover

private extension View {
    /// Hangs a group's `MuscleTargetPopover` below this view, arrow up — the one popover a row and a
    /// bar both open.
    func targetPopover(
        isPresented: Binding<Bool>,
        group: MuscleGroup,
        window: TrendWindow,
        workouts: [Workout],
        focusStore: MuscleFocusStore
    ) -> some View {
        popover(isPresented: isPresented, arrowEdge: .top) {
            MuscleTargetPopover(group: group, window: window, workouts: workouts)
                .environmentObject(focusStore)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// A group's popover from its Muscle Groups row or bar: the weekly target, with the editor's own
/// control, and the exercises behind the group's sets in the window. The target is the one thing worth
/// changing here, and where the sets came from is the one thing the row can't say. No chart — the
/// group's bar is right above, whichever opened it.
///
/// A change commits at once and counts as choosing a focus, like every target change: the row's
/// numbers follow live, the subtitle turns "Custom", and the row moves to its new section when the
/// popover closes.
struct MuscleTargetPopover: View {
    let group: MuscleGroup
    let window: TrendWindow
    let workouts: [Workout]

    private static let exerciseLimit = 3

    var body: some View {
        let exercises = MuscleGroupExerciseSets.top(Self.exerciseLimit, for: group, in: workouts)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.abbreviation)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(group.color)
                Text(group.description)
                    .font(.headline)
                    .foregroundStyle(Color.label)
            }
            HStack(spacing: 12) {
                Text(NSLocalizedString("muscleFocusWeeklyTarget", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(Color.label)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                MuscleTargetControl(group: group)
                    .accessibilityIdentifier("muscleTargetControl_\(group.rawValue)")
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(String(format: NSLocalizedString("muscleTargetPopoverExercises", comment: ""), window.currentWindowLabel))
                    .font(.footnote)
                    .foregroundStyle(Color.secondaryLabel)
                if exercises.isEmpty {
                    Text(NSLocalizedString("muscleTargetPopoverNoSets", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(Color.secondaryLabel)
                } else {
                    ForEach(exercises) { exercise in
                        HStack(spacing: 12) {
                            Text(exercise.name)
                                .foregroundStyle(Color.label)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(
                                exercise.sets == 1
                                    ? NSLocalizedString("oneSetLowercase", comment: "")
                                    : String(format: NSLocalizedString("nSets", comment: ""), exercise.sets)
                            )
                            .foregroundStyle(Color.secondaryLabel)
                            .monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 300, alignment: .leading)
    }
}
