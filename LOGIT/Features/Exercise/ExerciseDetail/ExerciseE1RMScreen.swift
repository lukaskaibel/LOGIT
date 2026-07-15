//
//  ExerciseE1RMScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 04.06.26.
//

import Charts
import SwiftUI

/// Estimated one-rep max per day for a single exercise — the detail screen behind the e1RM tile.
/// Structurally the twin of `ExerciseWeightScreen`; only the per-set metric and its formatting differ.
/// The chart, scrolling, selection and header all live in the shared `CapabilityChartView`.
struct ExerciseE1RMScreen: View {
    private static let yAxisMaxValuesKG = [10, 25, 50, 100, 150, 200, 300, 400, 500, 600, 700, 800, 900, 1000]
    private static let yAxisMaxValuesLBS = [25, 55, 110, 225, 335, 445, 665, 885, 1105, 1325, 1545, 1765, 1985, 2205]

    let exercise: Exercise
    let workoutSets: [WorkoutSet]

    private let points: [CapabilityChartView.Point]
    private let firstDataDate: Date?
    private let bestAnchor: (value: Int, date: Date?, isLapsed: Bool)?
    private let yScaleMax: Int

    init(exercise: Exercise, workoutSets: [WorkoutSet]) {
        self.exercise = exercise
        self.workoutSets = workoutSets
        let daily = Self.dailyMaxE1RMSets(in: workoutSets, for: exercise)
        self.firstDataDate = daily.first?.workout?.date
        self.points = daily.enumerated().map { index, set in
            let raw = set.estimatedOneRepMax(for: exercise)
            return CapabilityChartView.Point(
                id: index,
                date: set.workout?.date ?? .now,
                value: convertWeightForDisplayingDecimal(raw),
                raw: raw,
                formatted: formatEstimatedOneRepMax(raw)
            )
        }
        let pr = convertWeightForDisplaying(daily.map { $0.estimatedOneRepMax(for: exercise) }.max() ?? 0)
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
                    valueLabel: NSLocalizedString("estimatedOneRepMax", comment: ""),
                    formatValue: { formatEstimatedOneRepMax($0) }
                )

                // MARK: - About Section
                AboutSection(
                    metricTitle: NSLocalizedString("estimatedOneRepMax", comment: ""),
                    text: NSLocalizedString("e1RMInfo", comment: "")
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
                    Text("\(NSLocalizedString("estimatedOneRepMax", comment: ""))")
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

    private static func dailyMaxE1RMSets(in workoutSets: [WorkoutSet], for exercise: Exercise) -> [WorkoutSet] {
        let groupedSets = Dictionary(grouping: workoutSets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }.sorted { $0.key < $1.key }
            .map { $0.1 }
        return groupedSets
            .compactMap { setsPerDay -> WorkoutSet? in
                setsPerDay.max(by: { $0.estimatedOneRepMax(for: exercise) < $1.estimatedOneRepMax(for: exercise) })
            }
            .filter { $0.estimatedOneRepMax(for: exercise) > 0 }
    }

    private static func chartYScaleMax(maxYValue: Int) -> Int {
        let values = WeightUnit.used == .kg ? yAxisMaxValuesKG : yAxisMaxValuesLBS
        let nextBiggerYAxisMaxValue = values.filter { $0 > maxYValue }.min()
        return nextBiggerYAxisMaxValue ?? maxYValue
    }

    /// The fixed right-hand anchor of the header scoreboard, independent of scroll: the current best
    /// (highest e1RM in the last four weeks) and the day it was reached. When the current-best window
    /// is empty (untrained for over a month) it falls back to the "last best" — the best on the most
    /// recent session — which flips the label to "Last Best" and drops the comparison pill.
    private static func bestAnchor(for exercise: Exercise, in workoutSets: [WorkoutSet]) -> (value: Int, date: Date?, isLapsed: Bool)? {
        if let best = exercise.currentBestSet(for: .estimatedOneRepMax, in: workoutSets) {
            return (best.estimatedOneRepMax(for: exercise), best.workout?.date, false)
        }
        if let last = exercise.lastBestSet(for: .estimatedOneRepMax, in: workoutSets) {
            return (last.estimatedOneRepMax(for: exercise), last.workout?.date, true)
        }
        return nil
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        let exercise = database.getExercises().first!
        NavigationView {
            ExerciseE1RMScreen(exercise: exercise, workoutSets: exercise.sets)
        }
    }
}

struct ExerciseE1RMScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
