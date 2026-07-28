//
//  StrengthScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 27.07.26.
//

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

    /// Nil is the whole training; a group narrows the hero, and the composition, to it.
    @State private var selectedGroup: MuscleGroup?
    @State private var window: StrengthWindow = .default
    @State private var progress: StrengthProgress = .empty
    @State private var showsAllExercises = false

    /// Movers shown before the list collapses. Below about five the shortest bar is a stub and the
    /// ranking stops reading, so the cap sits where the shape is still legible rather than at a
    /// rounder number.
    private static let collapsedExerciseCount = 5

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
                    groupGrid
                    composition
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
            showsAllExercises = false
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

    private var composition: some View {
        let all = progress.exerciseChanges(in: selectedGroup)
        let shown = showsAllExercises ? all : Array(all.prefix(Self.collapsedExerciseCount))
        return VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("strengthBiggestMovers", comment: ""))
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(NSLocalizedString("strengthMoversCaption", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            StrengthCompositionChart(changes: shown, scale: all)
            if all.count > Self.collapsedExerciseCount {
                Button {
                    withAnimation(.snappy) { showsAllExercises.toggle() }
                } label: {
                    HStack {
                        Text(
                            showsAllExercises
                                ? NSLocalizedString("showLess", comment: "")
                                : String(format: NSLocalizedString("strengthShowAllExercises", comment: ""), all.count)
                        )
                        .foregroundStyle(Color.label)
                        Spacer()
                        Image(systemName: showsAllExercises ? "chevron.up" : "chevron.down")
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

// MARK: - Composition chart

/// Every exercise's change on **one shared zero axis** — the weighted mean pulled apart. The shared
/// axis is the whole point: it is what lets the rows be compared to each other at a glance, and it is
/// what a per-row centred tick (the muscle-balance chart's earlier, rejected shape) destroys.
///
/// Gains grow right of the axis in the muscle colour, declines grow left in neutral grey — never a
/// warning colour. The axis sits wherever the deepest decline needs it, so both directions share one
/// scale rather than each getting its own.
struct StrengthCompositionChart: View {
    let changes: [StrengthProgress.ExerciseChange]
    /// The full (uncapped) set the axis is scaled against, so collapsing the list doesn't rescale
    /// the bars underneath the user.
    let scale: [StrengthProgress.ExerciseChange]

    private let rowHeight: CGFloat = 34
    private let barHeight: CGFloat = 14
    private let nameWidth: CGFloat = 104
    /// Room kept at the trailing edge for the value label that follows the longest bar.
    private static let labelGutter: CGFloat = 46

    /// Largest gain and largest decline in the scale set — one unit serves both sides.
    private var extremes: (up: Double, down: Double) {
        let up = scale.map(\.percentChange).filter { $0 > 0 }.max() ?? 0
        let down = abs(scale.map(\.percentChange).filter { $0 < 0 }.min() ?? 0)
        return (max(up, 0.001), down)
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(changes) { change in
                row(change)
            }
        }
    }

    private func row(_ change: StrengthProgress.ExerciseChange) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(change.exercise.displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(String(format: NSLocalizedString("nSets", comment: ""), change.setCount))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: nameWidth, alignment: .trailing)
            .padding(.trailing, 12)

            GeometryReader { geometry in
                let width = geometry.size.width
                let (up, down) = extremes
                // The value label sits past the end of its bar, so the bars are scaled against the
                // width *minus* a gutter wide enough to hold it. Without this the longest bar — the
                // one that sets the scale — always pushes its own label off the edge.
                let unit = max(width - Self.labelGutter, 1) / CGFloat(up + down)
                let zeroX = CGFloat(down) * unit
                let isGain = change.percentChange > 0
                let length = max(CGFloat(abs(change.percentChange)) * unit, 2)
                let color = isGain ? change.muscleGroup.color : Color.secondaryLabel

                ZStack(alignment: .topLeading) {
                    // The shared axis.
                    Rectangle()
                        .fill(Color.separator)
                        .frame(width: 1, height: rowHeight)
                        .offset(x: zeroX)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isGain ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.4)))
                        .frame(width: length, height: barHeight)
                        .offset(x: isGain ? zeroX : zeroX - length, y: (rowHeight - barHeight) / 2)
                    // The value sits on the far side of the axis from its bar, so the two can never
                    // collide however long the bar gets.
                    Text(signedPercentText(change.percentChange))
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(isGain ? color : Color.secondaryLabel)
                        .monospacedDigit()
                        .fixedSize()
                        .offset(x: isGain ? zeroX + length + 6 : zeroX + 6, y: (rowHeight - 14) / 2)
                }
            }
            .frame(height: rowHeight)
        }
        .frame(height: rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(change.exercise.displayName), \(signedPercentText(change.percentChange)), "
                + String(format: NSLocalizedString("nSets", comment: ""), change.setCount)
        )
    }

    private func signedPercentText(_ percent: Double) -> String {
        String(format: "%+.0f%%", percent)
    }
}
