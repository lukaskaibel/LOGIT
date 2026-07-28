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

    /// Below this many bars the chart stops being a ranking and becomes a handful of columns, so it
    /// widens them and labels each one instead of asking for a scrub it doesn't need.
    private static let labelledChartThreshold = 8

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

    /// The figure, left-aligned like the tile's, with whichever exercise the screen is currently
    /// talking about beside it.
    ///
    /// It has three states and they share one shape. With nothing selected it shows the scope's
    /// change and names its **best mover** — the single most useful thing the number can't say.
    /// Hold a bar and it becomes that exercise: its own change, in its muscle group's colour, with
    /// its name on the right. Selecting a group swaps the scope. The caption underneath is gone;
    /// the window picker directly above already states the period, and saying it twice was noise.
    private var hero: some View {
        HStack(alignment: .center, spacing: 14) {
            if let percent = heroPercent {
                figure(percent, color: heroColor)
                Spacer(minLength: 8)
                if let subject = heroSubject {
                    subjectLabel(subject)
                }
            } else {
                // Same gray ring the tile and the core-stat tiles wear while they wait for data.
                TrendPlaceholder(
                    progress: progress.historyFraction,
                    text: NSLocalizedString("strengthEmpty", comment: ""),
                    systemImage: "chart.line.uptrend.xyaxis",
                    alignment: .leading,
                    diameter: 40
                )
                .padding(.vertical, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy, value: selectedGroup)
        .animation(.snappy, value: selectedExerciseID)
    }

    /// Selected exercise wins, then the selected group, then the whole training.
    private var heroPercent: Double? {
        selectedChange?.percentChange ?? progress.percentChange(in: selectedGroup)
    }

    private var heroColor: Color {
        selectedChange?.muscleGroup.color ?? selectedGroup?.color ?? .accentColor
    }

    /// The exercise the hero is naming: the selected one, or the scope's biggest gainer.
    private var heroSubject: StrengthProgress.ExerciseChange? {
        selectedChange ?? progress.exerciseChanges(in: selectedGroup)
            .max { $0.percentChange < $1.percentChange }
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

    /// The exercise beside the figure. Tapping it opens that exercise, which is why the whole label
    /// is a button rather than the separate readout row it replaces.
    private func subjectLabel(_ change: StrengthProgress.ExerciseChange) -> some View {
        Button {
            homeNavigationCoordinator.path.append(.exercise(change.exercise))
        } label: {
            VStack(alignment: .trailing, spacing: 2) {
                Text(
                    selectedExerciseID == nil
                        ? NSLocalizedString("strengthBestMover", comment: "")
                        : String(format: NSLocalizedString("nSets", comment: ""), change.setCount)
                )
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
                HStack(spacing: 4) {
                    Text(change.exercise.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(change.muscleGroup.color)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .minimumScaleFactor(0.8)
                    NavigationChevron()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 165, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(TileButtonStyle())
    }

    // MARK: Group grid

    /// The scope selector: "All" plus every muscle group. Groups without data stay in the grid,
    /// dimmed and disabled, so the grid keeps a stable shape instead of reshuffling as the window
    /// changes.
    private var groupGrid: some View {
        VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
            Text(NSLocalizedString("strengthTapGroup", comment: ""))
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                cell(for: nil, percent: progress.overallPercentChange)
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    cell(for: group, percent: progress.percentChange(in: group))
                }
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
            .frame(maxWidth: .infinity, alignment: .leading)
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
    private var composition: some View {
        let all = progress.changes
        let ranked = all.sorted { $0.percentChange < $1.percentChange }
        return VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("strengthBiggestMovers", comment: ""))
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(NSLocalizedString("strengthHoldHint", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            StrengthBarChart(
                changes: all,
                spacing: ranked.count < Self.labelledChartThreshold ? 8 : 2,
                selection: $selectedExerciseID,
                highlightedGroup: selectedGroup
            )
            .frame(height: 150)
            .animation(.snappy(duration: 0.2), value: selectedExerciseID)
            .animation(.snappy(duration: 0.2), value: selectedGroup)
            .sensoryFeedback(.selection, trigger: selectedExerciseID)
            if ranked.count < Self.labelledChartThreshold {
                axisLabels(ranked)
            }
        }
    }

    /// Under about eight bars there is room to name each column, so the chart stops depending on a
    /// gesture to be readable at all.
    private func axisLabels(_ ranked: [StrengthProgress.ExerciseChange]) -> some View {
        HStack(spacing: 8) {
            ForEach(ranked) { change in
                Text(change.exercise.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
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

