//
//  SummaryRecords.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Foundation

/// Aggregates the personal records set across a window of workouts — the feed behind the Highlights
/// carousel's record and milestone cards. Reuses `WorkoutProgressReport`'s verified "is this a record
/// as of that date" detection per workout, then unions the results — the highest value per
/// exercise+metric, grouped into one entry per exercise (newest record first, the same per-exercise
/// unit every other record surface counts) — instead of re-deriving prior-best math.
enum SummaryRecords {
    static func records(in workouts: [Workout], database: Database) -> [WorkoutProgressReport.ExerciseRecords] {
        var best: [String: WorkoutProgressReport.PRRecord] = [:]
        for workout in workouts {
            let report = WorkoutProgressReport.compute(for: workout, database: database)
            for record in report.exerciseRecords.flatMap(\.records) {
                if let existing = best[record.id] {
                    if record.value > existing.value { best[record.id] = record }
                } else {
                    best[record.id] = record
                }
            }
        }
        let newestFirst = best.values.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return WorkoutProgressReport.ExerciseRecords.grouped(newestFirst)
    }
}
