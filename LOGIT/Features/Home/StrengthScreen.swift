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

    private var hero: some View {
        VStack(spacing: 10) {
            if let percent = progress.percentChange(in: selectedGroup) {
                StrengthHeroPill(percentChange: percent)
                Text("\(scopeName) · \(window.comparisonCaption)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: selectedGroup)
    }

    private var scopeName: String {
        selectedGroup?.description ?? NSLocalizedString("allExercises", comment: "")
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
            selectedGroup = group
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

    /// Every exercise in scope as one ranked bar, worst to best. Replaces the horizontal
    /// `StrengthCompositionChart`: all of them fit at once, which is what retired that chart's
    /// five-row cap and its "Show all" button.
    ///
    /// The readout sits **above** the plot rather than below it, so a scrubbing finger never covers
    /// the thing it is selecting.
    private var composition: some View {
        let changes = progress.exerciseChanges(in: selectedGroup)
        let ranked = changes.sorted { $0.percentChange < $1.percentChange }
        let selected = ranked.first { $0.id == selectedExerciseID } ?? ranked.last
        return VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("strengthBiggestMovers", comment: ""))
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(NSLocalizedString("strengthScrubHint", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let selected {
                readout(selected)
            }
            StrengthBarChart(
                changes: changes,
                spacing: ranked.count < Self.labelledChartThreshold ? 8 : 2,
                selection: $selectedExerciseID
            )
            .frame(height: 150)
            .animation(.snappy(duration: 0.2), value: selectedExerciseID)
            .sensoryFeedback(.selection, trigger: selectedExerciseID)
            if ranked.count < Self.labelledChartThreshold {
                axisLabels(ranked)
            }
        }
    }

    /// The scrubbed exercise, as a row that taps through to its detail screen.
    private func readout(_ change: StrengthProgress.ExerciseChange) -> some View {
        Button {
            homeNavigationCoordinator.path.append(.exercise(change.exercise))
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(change.muscleGroup.color)
                    .frame(width: 9, height: 9)
                Text(change.exercise.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.label)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(String(format: NSLocalizedString("nSets", comment: ""), change.setCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TrendIndicatorView(percentChange: change.percentChange)
                NavigationChevron()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .secondaryTileStyle(insetShadow: true)
        }
        .buttonStyle(TileButtonStyle())
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

