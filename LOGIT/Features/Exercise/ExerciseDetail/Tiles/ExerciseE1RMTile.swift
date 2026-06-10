//
//  ExerciseE1RMTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 04.06.26.
//

import Charts
import SwiftUI

struct ExerciseE1RMTile: View {
    let exercise: Exercise
    let workoutSets: [WorkoutSet]

    var body: some View {
        let groupedWorkoutSets = Dictionary(grouping: workoutSets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }.sorted { $0.key < $1.key }
        let maxDailySets = maxE1RMDailySets(in: groupedWorkoutSets.map { $0.1 })
        VStack(spacing: 0) {
            VStack {
                HStack {
                    Text(NSLocalizedString("estimatedOneRepMax", comment: ""))
                        .tileHeaderStyle()
                    Spacer()
                    NavigationChevron()
                        .foregroundStyle(.secondary)
                }
                if workoutSets.isEmpty {
                    Spacer()
                    HStack {
                        Text(NSLocalizedString("noData", comment: ""))
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.bottom, 8)
                } else {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading) {
                            VStack(alignment: .leading) {
                                Text(NSLocalizedString("bestLastMonth", comment: ""))
                                    .foregroundStyle(.secondary)
                                    .font(.footnote)
                                    .fontWeight(.semibold)
                                UnitView(
                                    value: bestE1RMThisMonth(workoutSets) != nil ? formatEstimatedOneRepMax(bestE1RMThisMonth(workoutSets)!) : "––",
                                    unit: WeightUnit.used.rawValue.uppercased(),
                                    configuration: .large
                                )
                                .foregroundStyle((exercise.muscleGroup?.color ?? Color.label).gradient)
                            }
                        }
                        Spacer()
                        Chart {
                            ForEach(maxDailySets) { workoutSet in
                                if maxDailySets.first == workoutSet {
                                    LineMark(
                                        x: .value("Date", Date.distantPast, unit: .day),
                                        y: .value("Max e1RM on day", convertWeightForDisplayingDecimal(Int64(workoutSet.estimatedOneRepMax(for: exercise))))
                                    )
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(exerciseMuscleGroupColor.gradient)
                                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                                }
                                LineMark(
                                    x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                                    y: .value("Max e1RM on day", convertWeightForDisplayingDecimal(Int64(workoutSet.estimatedOneRepMax(for: exercise))))
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(exerciseMuscleGroupColor.gradient)
                                .lineStyle(StrokeStyle(lineWidth: 3))
                                .symbol {
                                    Circle()
                                        .frame(width: 6, height: 6)
                                        .foregroundStyle(exerciseMuscleGroupColor.gradient)
                                        .overlay {
                                            Circle()
                                                .frame(width: 2, height: 2)
                                                .foregroundStyle(Color.black)
                                        }
                                }
                                AreaMark(
                                    x: .value("Date", workoutSet.workout?.date ?? .now, unit: .day),
                                    y: .value("Max e1RM on day", convertWeightForDisplayingDecimal(Int64(workoutSet.estimatedOneRepMax(for: exercise))))
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(Gradient(colors: [
                                    exerciseMuscleGroupColor.opacity(0.3),
                                    exerciseMuscleGroupColor.opacity(0.1),
                                    exerciseMuscleGroupColor.opacity(0),
                                ]))
                            }
                            if let lastSet = maxDailySets.last, let lastDate = lastSet.workout?.date, !Calendar.current.isDateInToday(lastDate) {
                                let e1RMDisplayed = convertWeightForDisplayingDecimal(Int64(lastSet.estimatedOneRepMax(for: exercise)))
                                RuleMark(
                                    xStart: .value("Start", lastDate),
                                    xEnd: .value("End", Date()),
                                    y: .value("Max e1RM on day", e1RMDisplayed)
                                )
                                .foregroundStyle(exerciseMuscleGroupColor.opacity(0.45))
                                .lineStyle(
                                    StrokeStyle(
                                        lineWidth: 3,
                                        lineCap: .round,
                                        dash: [3, 6]
                                    )
                                )
                            }
                        }
                        .chartXScale(domain: xDomain)
                        .chartYScale(domain: 0 ... ((Double(allTimeE1RMPREntry(in: workoutSets).0) ?? 0) * 1.1))
                        .chartXAxis {}
                        .chartYAxis {}
                        .frame(width: 120, height: 70)
                        .clipped()
                        .mask(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .black, location: 0.1),
                                    .init(color: .black, location: 1.0),
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    }
                }
            }
            .frame(minHeight: 100)
            .padding([.horizontal, .top], CELL_PADDING)
            .padding(.bottom, CELL_PADDING / 2)
            if !workoutSets.isEmpty {
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(.black)
                HStack {
                    let allTimeE1RMPREntry = allTimeE1RMPREntry(in: workoutSets)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(NSLocalizedString("personalBest", comment: ""))
                                .fontWeight(.semibold)
                            Spacer()
                            if let allTimeE1RMPRDate = allTimeE1RMPREntry.2 {
                                Text(allTimeE1RMPRDate.formatted(.dateTime.day().month().year()))
                            }
                        }
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                        UnitView(value: allTimeE1RMPREntry.0, unit: WeightUnit.used.rawValue.uppercased(), unitColor: .tertiaryLabel)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, CELL_PADDING)
                .padding(.vertical, CELL_PADDING / 2)
            }
        }
        .tileStyle()
    }

    // MARK: - Private Methods

    private var xDomain: some ScaleDomain {
        let startDate = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: .now)!.startOfWeek
        return startDate ... Date.now
    }

    private func maxE1RMDailySets(in groupedWorkoutSets: [[WorkoutSet]]) -> [WorkoutSet] {
        let maxSetsPerDay = groupedWorkoutSets.compactMap { setsPerDay -> WorkoutSet? in
            return setsPerDay.max(by: { $0.estimatedOneRepMax(for: exercise) < $1.estimatedOneRepMax(for: exercise) })
        }
        return maxSetsPerDay
    }

    private var exerciseMuscleGroupColor: Color {
        exercise.muscleGroup?.color ?? Color.accentColor
    }

    private var visibleChartDomainInSeconds: Int {
        3600 * 24 * 35
    }

    private func bestE1RMThisMonth(_ workoutSets: [WorkoutSet]) -> Int? {
        let startDate = Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: .now)!
        let setsInTimeFrame = workoutSets.filter { $0.workout?.date ?? .distantPast >= startDate }
        guard !setsInTimeFrame.isEmpty else {
            return 0
        }
        return setsInTimeFrame
            .map { $0.estimatedOneRepMax(for: exercise) }
            .max()
    }

    private func allTimeE1RMPREntry(in workoutSets: [WorkoutSet]) -> (String, Int, Date?) {
        guard let bestSet = workoutSets
            .max(by: { $0.estimatedOneRepMax(for: exercise) < $1.estimatedOneRepMax(for: exercise) })
        else {
            return ("––", 0, nil)
        }
        let entry = bestSet.estimatedOneRepMaxEntry(for: exercise)
        return (formatEstimatedOneRepMax(entry.oneRepMax), Int(entry.repetitions), bestSet.workout?.date)
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        NavigationStack {
            ExerciseE1RMTile(exercise: database.getExercises().first!, workoutSets: database.getExercises().flatMap { $0.sets })
        }
    }
}

struct ExerciseE1RMTileView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
            .padding()
    }
}
