//
//  StrengthScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 27.07.26.
//

import CoreData
import SwiftUI

// MARK: - Screen

/// The detail behind the Strength tile. Deliberately has no time axis: the headline is a set-weighted
/// mean of every exercise's e1RM change, so the honest detail of it is its *components* — which
/// exercises moved, how far, and how heavily each counted — not a history of the percentage. (A chart
/// of a rate is a second-order quantity, and consecutive rolling windows overlap so heavily that the
/// line barely moves.)
///
/// Three sections: the hero for the selected scope, a muscle-group grid that *is* the scope selector,
/// and the composition — every exercise on one shared zero axis.
struct StrengthScreen: View {
    let workouts: [Workout]

    @EnvironmentObject private var homeNavigationCoordinator: HomeNavigationCoordinator

    /// Nil is the whole training; a group narrows the hero, and the composition, to it.
    @State private var selectedGroup: MuscleGroup?
    @State private var window: StrengthWindow = .default
    @State private var progress: StrengthProgress = .empty
    /// The scrubbed exercise, by object ID. Nil until a finger lands on the chart.
    @State private var selectedExerciseID: NSManagedObjectID?
    @State private var showsAllBests = false

    /// Below this many bars the chart stops being a ranking and becomes a handful of columns, so it
    /// widens them and labels each one instead of asking for a scrub it doesn't need.
    private static let labelledChartThreshold = 8
    /// Every group cell stands this tall, with or without a trend pill inside it.
    private static let groupCellHeight: CGFloat = 44
    /// Strongest lifts shown before the list collapses.
    private static let collapsedBestsCount = 5

    init(workouts: [Workout], initialGroup: MuscleGroup? = nil) {
        self.workouts = workouts
        _selectedGroup = State(initialValue: initialGroup)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                windowPicker
                hero
                if progress.hasData {
                    composition
                    groupGrid
                    strongest
                }
                footnote
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .sensoryFeedback(.selection, trigger: selectedGroup)
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(NSLocalizedString("strength", comment: ""))
                    .font(.headline)
            }
        }
        .task(id: "\(window.rawValue)-\(workouts.count)") {
            progress = StrengthProgress.compute(workouts: workouts, window: window)
            // A group that lost its data under a narrower window can't stay selected.
            if let selectedGroup, progress.percentChange(in: selectedGroup) == nil {
                self.selectedGroup = nil
            }
            // Nor can an exercise that dropped out of the recomputed scope.
            if let id = selectedExerciseID,
               !progress.exerciseChanges(in: selectedGroup).contains(where: { $0.id == id }) {
                selectedExerciseID = nil
            }
        }
    }

    // MARK: Window

    private var windowPicker: some View {
        Picker(NSLocalizedString("strength", comment: ""), selection: $window) {
            ForEach(StrengthWindow.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: Hero

    /// A caption over the figure, matching the tile's anatomy. The caption is the only thing that
    /// changes with selection: normally it names the basis ("Estimated 1RM"), and while a bar is held
    /// it names that exercise in its muscle colour, with the figure below switching to that lift's
    /// own change.
    ///
    /// Nothing sits to the right any more. A second figure beside the headline was read as one
    /// statement about it — "best mover Squat" next to a falling percentage parsed as a verdict on
    /// Squat — and no label above it could win that fight. The chart's own axis ends now carry which
    /// end is which, which is where that belongs.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 2) {
            caption
            if let percent = heroPercent {
                figure(percent, color: heroColor)
            } else {
                // Same gray ring the tile and the core-stat tiles wear while they wait for data.
                TrendPlaceholder(
                    progress: progress.historyFraction,
                    text: NSLocalizedString("strengthEmpty", comment: ""),
                    systemImage: "chart.line.uptrend.xyaxis",
                    alignment: .leading,
                    diameter: 40
                )
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy, value: selectedGroup)
        .animation(.snappy, value: selectedExerciseID)
    }

    @ViewBuilder
    private var caption: some View {
        if let selected = selectedChange {
            Text(selected.exercise.displayName)
                .font(.caption.weight(.bold))
                .tracking(0.3)
                .foregroundStyle(selected.muscleGroup.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            Text(NSLocalizedString("strengthBasis", comment: ""))
                .font(.caption.weight(.medium))
                .tracking(0.3)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    /// Selected exercise wins, then the selected group, then the whole training.
    private var heroPercent: Double? {
        selectedChange?.percentChange ?? progress.percentChange(in: selectedGroup)
    }

    private var heroColor: Color {
        selectedChange?.muscleGroup.color ?? selectedGroup?.color ?? .accentColor
    }

    private var selectedChange: StrengthProgress.ExerciseChange? {
        guard let selectedExerciseID else { return nil }
        return progress.changes.first { $0.id == selectedExerciseID }
    }

    private func figure(_ percent: Double, color: Color) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Image(systemName: strengthTrendSymbol(percent))
                .font(.system(size: 22, weight: .black))
            Text(String(format: "%.1f%%", abs(percent)))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .foregroundStyle(strengthTrendIsDown(percent) ? Color.secondaryLabel : color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(figureAccessibilityLabel(percent))
    }

    private func figureAccessibilityLabel(_ percent: Double) -> Text {
        let value = (abs(percent) / 100).formatted(.percent.precision(.fractionLength(1)))
        if strengthTrendIsUp(percent) {
            return Text(String(format: NSLocalizedString("trendUp", comment: ""), value))
        }
        if strengthTrendIsDown(percent) {
            return Text(String(format: NSLocalizedString("trendDown", comment: ""), value))
        }
        return Text(NSLocalizedString("trendFlat", comment: ""))
    }

    // MARK: Group grid

    /// The scope selector: "All" plus every muscle group, **groups with data first**. A cell you
    /// can't tap has no claim on a position near the top, and sinking them keeps the live options
    /// together instead of interleaved with dead ones.
    ///
    /// No section heading. "Tap a group to focus" is an instruction, and a grid of tappable pills
    /// doesn't need to be told it is tappable.
    private var groupGrid: some View {
        let cells: [(group: MuscleGroup?, percent: Double?)] =
            [(nil, progress.overallPercentChange)]
            + MuscleGroup.allCases
                .map { (Optional($0), progress.percentChange(in: $0)) }
                // Stable within each half: canonical order, data first.
                .sorted { ($0.1 != nil ? 0 : 1) < ($1.1 != nil ? 0 : 1) }
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
            spacing: 8
        ) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, item in
                cell(for: item.group, percent: item.percent)
            }
        }
    }

    @ViewBuilder
    private func cell(for group: MuscleGroup?, percent: Double?) -> some View {
        let color = group?.color ?? .accentColor
        let isSelected = selectedGroup == group
        Button {
            selectedGroup = selectedGroup == group ? nil : group
            selectedExerciseID = nil
            showsAllBests = false
        } label: {
            HStack(spacing: 6) {
                Text(group?.description ?? NSLocalizedString("all", comment: ""))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(percent == nil ? Color.secondaryLabel : color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 2)
                if let percent {
                    TrendIndicatorView(percentChange: percent, positiveColor: color)
                } else {
                    Text(NSLocalizedString("noData", comment: ""))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            // A no-data cell has no pill in it, so it would otherwise stand shorter than its
            // neighbours and break the grid's rhythm. Matching the pill's height keeps every cell
            // the same size whatever it contains.
            .frame(maxWidth: .infinity, minHeight: Self.groupCellHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? color.opacity(0.15) : Color.secondaryBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? color.opacity(0.45) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(TileButtonStyle())
        .disabled(percent == nil)
        .opacity(percent == nil ? 0.45 : 1)
    }

    // MARK: Composition

    /// Every exercise as one ranked bar, worst to best — and *always* every exercise. Selecting a
    /// group no longer filters the chart down to it; the group's bars simply keep their colour while
    /// the rest drop to grey. Filtering answered "how did chest do"; highlighting answers "how did
    /// chest do *compared with everything else*", which is the question a balance-minded screen is
    /// actually for, and it stops the chart's shape changing under the finger on every tap.
    ///
    /// No section header and no per-bar names. The hero above already says what this is, and eight
    /// rotated exercise labels were the densest thing on the screen while telling you the least —
    /// the two ends of the ranking are what the axis actually needs to say.
    private var composition: some View {
        let ranked = progress.changes.sorted { $0.percentChange < $1.percentChange }
        return VStack(alignment: .leading, spacing: 8) {
            StrengthBarChart(
                changes: progress.changes,
                spacing: ranked.count < Self.labelledChartThreshold ? 8 : 2,
                selection: $selectedExerciseID,
                highlightedGroup: selectedGroup
            )
            .frame(height: 170)
            .animation(.snappy(duration: 0.2), value: selectedExerciseID)
            .animation(.snappy(duration: 0.2), value: selectedGroup)
            .sensoryFeedback(.selection, trigger: selectedExerciseID)
            axisEnds(ranked)
        }
    }

    /// The axis names the *ranking*, not the bars: what the left end and the right end mean. Which
    /// words depends on the data — with declines present the left end is a drop, not a small gain.
    private func axisEnds(_ ranked: [StrengthProgress.ExerciseChange]) -> some View {
        let hasDecline = (ranked.first?.percentChange ?? 0) < 0
        let hasGain = (ranked.last?.percentChange ?? 0) > 0
        return HStack {
            Text(NSLocalizedString(hasDecline ? "strengthAxisMostDeclined" : "strengthAxisLeastImproved", comment: ""))
            Spacer(minLength: 12)
            Text(NSLocalizedString(hasGain ? "strengthAxisMostImproved" : "strengthAxisLeastDeclined", comment: ""))
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    // MARK: Strongest lifts

    /// What you can actually lift, heaviest first — the question the rest of the screen never
    /// answers. Everything above is *change*: a percentage says a lift moved, not that it is heavy,
    /// and a beginner adding 20% to a light press outranks a hard-won 2% on a heavy squat all the
    /// way down the chart. This is the standing that the ranking is relative to.
    ///
    /// Unlike the chart, a lift needs no prior-window best to appear: one you only started this
    /// month still has a weight, and leaving it out of a "strongest" list would be plainly wrong.
    @ViewBuilder
    private var strongest: some View {
        let all = scopedBests
        if !all.isEmpty {
            let shown = showsAllBests ? all : Array(all.prefix(Self.collapsedBestsCount))
            VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
                Text(NSLocalizedString("strengthStrongestLifts", comment: ""))
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, best in
                        Button {
                            homeNavigationCoordinator.path.append(.exercise(best.exercise))
                        } label: {
                            bestRow(best, rank: index + 1)
                        }
                        .buttonStyle(.plain)
                        if index < shown.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .tileStyle()
                if all.count > Self.collapsedBestsCount {
                    Button {
                        withAnimation(.snappy) { showsAllBests.toggle() }
                    } label: {
                        HStack {
                            Text(
                                showsAllBests
                                    ? NSLocalizedString("showLess", comment: "")
                                    : String(format: NSLocalizedString("strengthShowAllLifts", comment: ""), all.count)
                            )
                            .foregroundStyle(Color.label)
                            Spacer()
                            Image(systemName: showsAllBests ? "chevron.up" : "chevron.down")
                                .foregroundStyle(Color.secondaryLabel)
                                .font(.footnote.weight(.bold))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity)
                        .secondaryTileStyle(insetShadow: true)
                    }
                    .buttonStyle(TileButtonStyle())
                }
            }
        }
    }

    /// Narrowed to the selected group, so the list answers the same scope the rest of the screen is
    /// showing rather than quietly reporting the whole training.
    private var scopedBests: [StrengthProgress.ExerciseBest] {
        guard let selectedGroup else { return progress.bests }
        return progress.bests.filter { $0.muscleGroup == selectedGroup }
    }

    private func bestRow(_ best: StrengthProgress.ExerciseBest, rank: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 16, alignment: .trailing)
            Circle()
                .fill(best.muscleGroup.color)
                .frame(width: 8, height: 8)
            Text(best.exercise.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.label)
                .lineLimit(1)
            Spacer(minLength: 8)
            // `formatWeightForDisplay` keeps up to three decimals so a logged weight round-trips
            // through integer grams. An e1RM is *derived*, so that precision is noise —
            // `formatEstimatedOneRepMax` rounds it, which is what every other e1RM surface shows.
            UnitView(
                value: formatEstimatedOneRepMax(best.oneRepMax),
                unit: WeightUnit.used.rawValue,
                configuration: .small
            )
        }
        .padding(.horizontal, CELL_PADDING)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
            Text(String(format: NSLocalizedString("strengthInfo", comment: ""), window.rawValue, window.rawValue))
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

