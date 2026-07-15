//
//  ExerciseWeightScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.11.24.
//

import Charts
import SwiftUI

/// Max weight per day for a single exercise — the detail screen behind the Weight tile. All the
/// scrolling, inspecting and header math lives in the shared `CapabilityChartView`; this screen just
/// reduces the sets to plotted `Point`s and the fixed scoreboard anchor once, up front.
struct ExerciseWeightScreen: View {
    private static let yAxisMaxValuesKG = [10, 25, 50, 100, 150, 200, 300, 400, 500, 600, 700, 800, 900, 1000]
    private static let yAxisMaxValuesLBS = [25, 55, 110, 225, 335, 445, 665, 885, 1105, 1325, 1545, 1765, 1985, 2205]

    let exercise: Exercise
    let workoutSets: [WorkoutSet]

    /// The plotted history — one daily-max point, reduced to plain values, built once at init so
    /// scrolling and inspecting never regroup sets or convert units per frame.
    private let points: [CapabilityChartView.Point]
    /// Earliest day with a recorded weight — the left end of the scrollable domain.
    private let firstDataDate: Date?
    /// The fixed right-hand scoreboard anchor (current or last best), computed once rather than
    /// re-scanning every set on each render.
    private let bestAnchor: (value: Int, date: Date?, isLapsed: Bool)?
    /// The y-axis cap in display units — the next weight ladder step above the all-time PR.
    private let yScaleMax: Int

    init(exercise: Exercise, workoutSets: [WorkoutSet]) {
        self.exercise = exercise
        self.workoutSets = workoutSets
        let daily = Self.dailyMaxWeightSets(in: workoutSets, for: exercise)
        self.firstDataDate = daily.first?.workout?.date
        self.points = daily.enumerated().map { index, set in
            let raw = set.maximum(.weight, for: exercise)
            return CapabilityChartView.Point(
                id: index,
                date: set.workout?.date ?? .now,
                value: convertWeightForDisplayingDecimal(raw),
                raw: raw,
                formatted: formatWeightForDisplay(raw)
            )
        }
        let pr = convertWeightForDisplaying(daily.map { $0.maximum(.weight, for: exercise) }.max() ?? 0)
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
                    valueLabel: NSLocalizedString("weight", comment: ""),
                    formatValue: { formatWeightForDisplay($0) }
                )

                // MARK: - About Section
                AboutSection(
                    metricTitle: NSLocalizedString("weight", comment: ""),
                    text: NSLocalizedString("weightInfo", comment: "")
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
                    Text("\(NSLocalizedString("weight", comment: ""))")
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

    /// One max-weight set per day, oldest first, days with no recorded weight dropped.
    private static func dailyMaxWeightSets(in workoutSets: [WorkoutSet], for exercise: Exercise) -> [WorkoutSet] {
        let groupedSets = Dictionary(grouping: workoutSets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }.sorted { $0.key < $1.key }
            .map { $0.1 }
        return groupedSets
            .compactMap { setsPerDay -> WorkoutSet? in
                setsPerDay.max(by: { $0.maximum(.weight, for: exercise) < $1.maximum(.weight, for: exercise) })
            }
            .filter { $0.maximum(.weight, for: exercise) > 0 }
    }

    private static func chartYScaleMax(maxYValue: Int) -> Int {
        let values = WeightUnit.used == .kg ? yAxisMaxValuesKG : yAxisMaxValuesLBS
        let nextBiggerYAxisMaxValue = values.filter { $0 > maxYValue }.min()
        return nextBiggerYAxisMaxValue ?? maxYValue
    }

    /// The fixed right-hand anchor of the header scoreboard, independent of scroll: the current best
    /// (highest max-weight in the last four weeks) and the day it was reached. When the current-best
    /// window is empty (untrained for over a month) it falls back to the "last best" — the best on the
    /// most recent session — which flips the label to "Last Best" and drops the comparison pill.
    private static func bestAnchor(for exercise: Exercise, in workoutSets: [WorkoutSet]) -> (value: Int, date: Date?, isLapsed: Bool)? {
        if let best = exercise.currentBestSet(for: .weight, in: workoutSets) {
            return (best.maximum(.weight, for: exercise), best.workout?.date, false)
        }
        if let last = exercise.lastBestSet(for: .weight, in: workoutSets) {
            return (last.maximum(.weight, for: exercise), last.workout?.date, true)
        }
        return nil
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        let exercise = database.getExercises().first!
        NavigationView {
            ExerciseWeightScreen(exercise: exercise, workoutSets: exercise.sets)
        }
    }
}

struct PersonalBestScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
