//
//  ExerciseDurationScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 16.07.26.
//

import Charts
import SwiftUI

/// Max hold/work duration per day for a single exercise — the detail screen behind the Duration
/// tile. Structurally the twin of `ExerciseRepetitionsScreen`; durations are plain seconds (no
/// unit conversion), and the screen stays free like repetitions — for a duration-only exercise
/// this is its basic capability metric. The chart, scrolling, selection and header live in
/// `CapabilityChartView`.
struct ExerciseDurationScreen: View {
    private static let yAxisMaxValues = [30, 60, 120, 300, 600, 1200]

    let exercise: Exercise
    let workoutSets: [WorkoutSet]

    private let points: [CapabilityChartView.Point]
    private let firstDataDate: Date?
    private let bestAnchor: (value: Int, date: Date?, isLapsed: Bool)?
    private let yScaleMax: Int

    init(exercise: Exercise, workoutSets: [WorkoutSet]) {
        self.exercise = exercise
        self.workoutSets = workoutSets
        let daily = Self.dailyMaxDurationSets(in: workoutSets, for: exercise)
        self.firstDataDate = daily.first?.workout?.date
        self.points = daily.enumerated().map { index, set in
            let raw = set.maximum(.duration, for: exercise)
            return CapabilityChartView.Point(
                id: index,
                date: set.workout?.date ?? .now,
                value: Double(raw),
                raw: raw,
                formatted: String(raw)
            )
        }
        let pr = daily.map { $0.maximum(.duration, for: exercise) }.max() ?? 0
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
                    unit: NSLocalizedString("sec", comment: ""),
                    valueLabel: NSLocalizedString("measurementType.duration", comment: ""),
                    formatValue: { String($0) }
                )
            }
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text("\(NSLocalizedString("measurementType.duration", comment: ""))")
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

    private static func dailyMaxDurationSets(in workoutSets: [WorkoutSet], for exercise: Exercise) -> [WorkoutSet] {
        let groupedSets = Dictionary(grouping: workoutSets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }.sorted { $0.key < $1.key }
            .map { $0.1 }
        return groupedSets
            .compactMap { setsPerDay -> WorkoutSet? in
                setsPerDay.max(by: { $0.maximum(.duration, for: exercise) < $1.maximum(.duration, for: exercise) })
            }
            .filter { $0.maximum(.duration, for: exercise) > 0 }
    }

    private static func chartYScaleMax(maxYValue: Int) -> Int {
        let nextBiggerYAxisMaxValue = yAxisMaxValues.filter { $0 > maxYValue }.min()
        return nextBiggerYAxisMaxValue ?? maxYValue
    }

    /// The fixed right-hand anchor of the header scoreboard, independent of scroll: the current best
    /// (longest duration in the last four weeks) and the day it was reached. When the current-best
    /// window is empty (untrained for over a month) it falls back to the "last best" — the best on the
    /// most recent session — which flips the label to "Last Best" and drops the comparison pill.
    private static func bestAnchor(for exercise: Exercise, in workoutSets: [WorkoutSet]) -> (value: Int, date: Date?, isLapsed: Bool)? {
        if let best = exercise.currentBestSet(for: .duration, in: workoutSets) {
            return (best.maximum(.duration, for: exercise), best.workout?.date, false)
        }
        if let last = exercise.lastBestSet(for: .duration, in: workoutSets) {
            return (last.maximum(.duration, for: exercise), last.workout?.date, true)
        }
        return nil
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        let exercise = database.getExercises().first!
        NavigationView {
            ExerciseDurationScreen(exercise: exercise, workoutSets: exercise.sets)
        }
    }
}

struct ExerciseDurationScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
