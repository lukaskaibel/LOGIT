//
//  ExerciseSetVolumeScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 11.06.26.
//

import Charts
import SwiftUI

/// Best single-set volume (weight × reps) per day for a single exercise — the detail screen behind the
/// Set Volume tile. Structurally the twin of `ExerciseWeightScreen`; the chart, scrolling, selection
/// and header all live in the shared `CapabilityChartView`.
struct ExerciseSetVolumeScreen: View {
    let exercise: Exercise
    let workoutSets: [WorkoutSet]

    private let points: [CapabilityChartView.Point]
    private let firstDataDate: Date?
    private let bestAnchor: (value: Int, date: Date?, isLapsed: Bool)?
    private let yScaleMax: Int

    init(exercise: Exercise, workoutSets: [WorkoutSet]) {
        self.exercise = exercise
        self.workoutSets = workoutSets
        let daily = Self.dailyMaxSetVolumeSets(in: workoutSets, for: exercise)
        self.firstDataDate = daily.first?.workout?.date
        self.points = daily.enumerated().map { index, set in
            let raw = set.volume(for: exercise)
            return CapabilityChartView.Point(
                id: index,
                date: set.workout?.date ?? .now,
                value: convertWeightForDisplayingDecimal(raw),
                raw: raw,
                formatted: formatWeightForDisplay(raw)
            )
        }
        let pr = convertWeightForDisplaying(daily.map { $0.volume(for: exercise) }.max() ?? 0)
        self.yScaleMax = Self.chartYScaleMax(maxYValue: pr)
        self.bestAnchor = Self.bestAnchor(for: exercise, in: workoutSets)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                CapabilityChartView(
                    points: points,
                    firstDataDate: firstDataDate,
                    bestAnchor: bestAnchor,
                    yScaleMax: yScaleMax,
                    color: exerciseMuscleGroupColor,
                    unit: WeightUnit.used.rawValue,
                    valueLabel: NSLocalizedString("setVolume", comment: ""),
                    formatValue: { formatWeightForDisplay($0) }
                )

                // MARK: - About Section
                AboutSection(
                    metricTitle: NSLocalizedString("setVolume", comment: ""),
                    text: NSLocalizedString("setVolumeInfo", comment: "")
                )
                .padding(.horizontal)
            }
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text("\(NSLocalizedString("setVolume", comment: ""))")
                        .font(.headline)
                    Text(exercise.displayName)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
        }
    }

    // MARK: - Data

    private var exerciseMuscleGroupColor: Color {
        exercise.muscleGroup?.color ?? Color.accentColor
    }

    private static func dailyMaxSetVolumeSets(in workoutSets: [WorkoutSet], for exercise: Exercise) -> [WorkoutSet] {
        let groupedSets = Dictionary(grouping: workoutSets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }.sorted { $0.key < $1.key }
            .map { $0.1 }
        return groupedSets
            .compactMap { setsPerDay -> WorkoutSet? in
                setsPerDay.max(by: { $0.volume(for: exercise) < $1.volume(for: exercise) })
            }
            .filter { $0.volume(for: exercise) > 0 }
    }

    /// Set volume has no practical upper bound, so unlike the weight and e1RM screens (which pick from a
    /// fixed list of axis caps) the cap is the PR rounded up to a clean half-magnitude step — keeping
    /// the mid axis mark (cap / 2) a round number too.
    private static func chartYScaleMax(maxYValue: Int) -> Int {
        guard maxYValue > 0 else { return 10 }
        let magnitude = pow(10.0, floor(log10(Double(maxYValue))))
        let step = magnitude / 2
        return Int((Double(maxYValue) / step).rounded(.up) * step)
    }

    /// The fixed right-hand anchor of the header scoreboard, independent of scroll: the current best
    /// (highest single-set volume in the last four weeks) and the day it was reached. When the
    /// current-best window is empty (untrained for over a month) it falls back to the "last best" — the
    /// best on the most recent session — which flips the label to "Last Best" and drops the pill.
    private static func bestAnchor(for exercise: Exercise, in workoutSets: [WorkoutSet]) -> (value: Int, date: Date?, isLapsed: Bool)? {
        if let best = exercise.currentBestSetVolumeSet(in: workoutSets) {
            return (best.volume(for: exercise), best.workout?.date, false)
        }
        if let last = exercise.lastBestSetVolumeSet(in: workoutSets) {
            return (last.volume(for: exercise), last.workout?.date, true)
        }
        return nil
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        let exercise = database.getExercises().first!
        NavigationView {
            ExerciseSetVolumeScreen(exercise: exercise, workoutSets: exercise.sets)
        }
    }
}

struct ExerciseSetVolumeScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
