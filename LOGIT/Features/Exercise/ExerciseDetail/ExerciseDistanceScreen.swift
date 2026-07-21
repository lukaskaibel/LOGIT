//
//  ExerciseDistanceScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 21.07.26.
//

import Charts
import SwiftUI

/// Max distance per day for a single exercise — the detail screen behind the Distance tile.
/// Structurally the twin of `ExerciseDurationScreen`; distances are stored in meters and shown
/// in the exercise's distance scale (km/mi for cardio, m/yd for carries). The chart, scrolling,
/// selection and header live in `CapabilityChartView`.
struct ExerciseDistanceScreen: View {
    /// Y-axis caps in display units: km-scale for cardio, meter-scale for carries.
    private static let longYAxisMaxValues = [1, 2, 5, 10, 20, 50, 100]
    private static let shortYAxisMaxValues = [20, 50, 100, 200, 500, 1000]

    let exercise: Exercise
    let workoutSets: [WorkoutSet]

    private let distanceStyle: SetMeasurementType.DistanceStyle
    private let points: [CapabilityChartView.Point]
    private let firstDataDate: Date?
    private let bestAnchor: (value: Int, date: Date?, isLapsed: Bool)?
    private let yScaleMax: Int

    init(exercise: Exercise, workoutSets: [WorkoutSet]) {
        self.exercise = exercise
        self.workoutSets = workoutSets
        let style = exercise.measurementType.distanceStyle ?? .long
        self.distanceStyle = style
        let daily = Self.dailyMaxDistanceSets(in: workoutSets, for: exercise)
        self.firstDataDate = daily.first?.workout?.date
        self.points = daily.enumerated().map { index, set in
            let raw = set.maximum(.distance, for: exercise)
            return CapabilityChartView.Point(
                id: index,
                date: set.workout?.date ?? .now,
                value: distanceChartValue(raw, style: style),
                raw: raw,
                formatted: formatDistanceForDisplay(Int64(raw), style: style)
            )
        }
        let pr = points.map(\.value).max() ?? 0
        self.yScaleMax = Self.chartYScaleMax(maxYValue: pr, style: style)
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
                    unit: distanceUnitTitle(for: distanceStyle),
                    valueLabel: NSLocalizedString("measurementType.distance", comment: ""),
                    formatValue: { formatDistanceForDisplay(Int64($0), style: distanceStyle) }
                )
            }
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text("\(NSLocalizedString("measurementType.distance", comment: ""))")
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

    private static func dailyMaxDistanceSets(in workoutSets: [WorkoutSet], for exercise: Exercise) -> [WorkoutSet] {
        let groupedSets = Dictionary(grouping: workoutSets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }.sorted { $0.key < $1.key }
            .map { $0.1 }
        return groupedSets
            .compactMap { setsPerDay -> WorkoutSet? in
                setsPerDay.max(by: { $0.maximum(.distance, for: exercise) < $1.maximum(.distance, for: exercise) })
            }
            .filter { $0.maximum(.distance, for: exercise) > 0 }
    }

    private static func chartYScaleMax(maxYValue: Double, style: SetMeasurementType.DistanceStyle) -> Int {
        let candidates = style == .long ? longYAxisMaxValues : shortYAxisMaxValues
        let nextBiggerYAxisMaxValue = candidates.filter { Double($0) > maxYValue }.min()
        return nextBiggerYAxisMaxValue ?? Int(maxYValue.rounded(.up))
    }

    /// The fixed right-hand anchor of the header scoreboard — see `ExerciseDurationScreen.bestAnchor`.
    private static func bestAnchor(for exercise: Exercise, in workoutSets: [WorkoutSet]) -> (value: Int, date: Date?, isLapsed: Bool)? {
        if let best = exercise.currentBestSet(for: .distance, in: workoutSets) {
            return (best.maximum(.distance, for: exercise), best.workout?.date, false)
        }
        if let last = exercise.lastBestSet(for: .distance, in: workoutSets) {
            return (last.maximum(.distance, for: exercise), last.workout?.date, true)
        }
        return nil
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        let exercise = database.getExercises().first!
        NavigationView {
            ExerciseDistanceScreen(exercise: exercise, workoutSets: exercise.sets)
        }
    }
}

struct ExerciseDistanceScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
