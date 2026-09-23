//
//  WorkoutRecap.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 21.09.26.
//

import CoreData
import Foundation

/// Everything the finish panel says about the session, gathered in one pass when the panel opens.
///
/// The panel answers four questions, in the order a lifter asks them:
/// 1. **Did it count?** The week's goal moves by one with every finished workout — the one reward
///    that happens every single time, so it leads.
/// 2. **What was the best of it?** Personal records, then the exercises that beat their recent best.
/// 3. **How did it feel?** Effort and the note — the user's own answers, not ours.
/// 4. **What was it?** The exercises and the totals — read off the workout itself, not from here.
///
/// Everything here is computed once, on the view context's queue, when the panel opens — never on a
/// redraw. The goal itself is *not* baked in: it is derived per target (`goal(target:)`), so setting a
/// goal from the panel's nudge updates the hero without walking the history again.
struct WorkoutRecap {
    // MARK: The week

    /// The date the workout is filed under — its start. Every other surface counts the workout in
    /// this date's week once it is saved (the Summary pill, the goal screen, History), so the panel
    /// does too, even for a session that ran past midnight into a new week.
    let workoutDate: Date
    /// Finished, non-empty workouts in the workout's week, this one excluded. The strip's day rings.
    let weekWorkouts: [Workout]

    var weekCountBefore: Int { weekWorkouts.count }
    var weekCountAfter: Int { weekWorkouts.count + 1 }

    // MARK: Progress

    let report: WorkoutProgressReport
    /// The session's personal records, without the Strength estimate. A one-rep max nobody lifted
    /// is not a personal best — it is the estimate moving, which is an improvement, and it reads as
    /// one under the improvements, as a percentage. An exercise whose only "record" was the
    /// estimate is therefore listed there, not here. The report's own records (which the workout
    /// detail and the Summary count) are untouched.
    let records: [WorkoutProgressReport.ExerciseRecords]
    /// Exercises that beat their recent best without setting a record, and the exercises whose
    /// only record was Strength (see `compute`) — the records come first in the highlights, so no
    /// exercise is listed twice. Biggest gain first.
    let improvements: [WorkoutProgressReport.ExerciseTrend]
    /// Exercises trained for the first time: nothing to beat yet, but next time there will be.
    let firstSessionCount: Int

    /// The week's goal, before and after this workout, for one target. Nil without a goal.
    struct Goal: Equatable {
        let target: Int
        let countBefore: Int
        let countAfter: Int

        var isReachedByThisWorkout: Bool { countBefore < target && countAfter >= target }
        var wasAlreadyMet: Bool { countBefore >= target }
        var remaining: Int { max(target - countAfter, 0) }
        /// Workouts past the goal, once it is met.
        var beyond: Int { max(countAfter - target, 0) }

        /// Clamped, so an over-delivered week can't wrap the arc round and read as a fresh one.
        var progressBefore: Double { min(Double(countBefore) / Double(target), 1) }
        var progressAfter: Double { min(Double(countAfter) / Double(target), 1) }
    }

    // MARK: Highlights

    /// One row of the finish panel's highlights: a personal record or a beaten recent best, told in
    /// the metric it happened in.
    struct Highlight: Identifiable {
        enum Kind { case record, improvement }
        let kind: Kind
        let exercise: Exercise
        let metric: ExercisePrimaryMetric
        let previous: Int
        let current: Int

        var id: NSManagedObjectID { exercise.objectID }
        var isRecord: Bool { kind == .record }

        /// "Weight PR" / "Strength improved" — the row's eyebrow. Strength is never a PR here
        /// (`WorkoutRecap.records` drops it), so it only ever reads as improved.
        var label: String {
            String(
                format: NSLocalizedString(isRecord ? "highlightRecordLabel" : "highlightImprovedLabel", comment: ""),
                metric.title
            )
        }
    }

    /// The records first, each on its lead metric, then the improvements biggest gain first — each
    /// exercise once, on the comparison it shows (`displayedTrend`).
    var highlights: [Highlight] {
        records.map { group in
            let lead = group.lead
            return Highlight(kind: .record, exercise: group.exercise, metric: lead.metric, previous: lead.previousBest, current: lead.value)
        } + improvements.map { trend in
            let shown = displayedTrend(for: trend)
            return Highlight(kind: .improvement, exercise: shown.exercise, metric: shown.metric, previous: shown.baseline ?? 0, current: shown.current)
        }
    }

    // MARK: Derived

    func goal(target: Int) -> Goal? {
        guard target > 0 else { return nil }
        return Goal(target: target, countBefore: weekCountBefore, countAfter: weekCountAfter)
    }

    /// The comparison an improvement row shows. An exercise scored on Strength whose lifted weight
    /// also went up shows the weight — the number that was on the bar is the more tangible win than
    /// the estimate derived from it. Otherwise the trend as scored.
    func displayedTrend(for trend: WorkoutProgressReport.ExerciseTrend) -> WorkoutProgressReport.ExerciseTrend {
        Self.displayedTrend(for: trend, in: report)
    }

    /// `displayedTrend(for:)` before the recap exists — `compute` needs it to decide which row an
    /// exercise keeps.
    private static func displayedTrend(
        for trend: WorkoutProgressReport.ExerciseTrend,
        in report: WorkoutProgressReport
    ) -> WorkoutProgressReport.ExerciseTrend {
        guard trend.metric == .estimatedOneRepMax,
              let weight = report.weightTrend(for: trend.exercise),
              weight.isImprovement
        else { return trend }
        return weight
    }

    /// Whether this finish has earned the confetti: a personal record — a number nobody had lifted
    /// before. The week being won gets the arc's own moment (it closes, swells, the verdict springs
    /// in) and nothing louder, so that the confetti keeps meaning one thing. Rewards that arrive
    /// every time stop meaning anything; rewards for something real keep meaning it.
    func celebrates(target: Int) -> Bool {
        !records.isEmpty
    }

    /// Identifies what a celebration was for, so reopening an unchanged panel (Continue, then Finish
    /// again) shows its final state at once instead of replaying the whole show.
    func celebrationKey(target: Int) -> String {
        let records = records
            .flatMap { group in group.records.map { "\($0.id):\($0.value)" } }
            .sorted()
            .joined(separator: ",")
        return "\(records)|\(weekCountAfter)|\(target)"
    }

    // MARK: Computation

    /// One pass on the view context's queue. `WorkoutProgressReport.compute` is the expensive part —
    /// every exercise's whole history, ~50 ms on two years of dense training — which is why the panel
    /// runs this after its opening animation has landed rather than into it.
    static func compute(for workout: Workout, database: Database) -> WorkoutRecap {
        let workoutDate = workout.date ?? .now
        let weekStart = workoutDate.startOfWeek
        let weekEnd = workoutDate.endOfWeek

        let finished = (database.fetch(
            Workout.self,
            predicate: NSPredicate(format: "isCurrentWorkout == nil OR isCurrentWorkout == NO")
        ) as? [Workout]) ?? []
        var weekWorkouts = [Workout]()
        for other in finished where other != workout && !other.isEmpty {
            guard let date = other.date else { continue }
            if date >= weekStart && date <= weekEnd { weekWorkouts.append(other) }
        }

        let report = WorkoutProgressReport.compute(for: workout, database: database)
        // Strength records fall away; a group that was only the estimate is no record group at all.
        let records = report.exerciseRecords.compactMap { group -> WorkoutProgressReport.ExerciseRecords? in
            let lifted = group.records.filter { $0.metric != .estimatedOneRepMax }
            return lifted.isEmpty ? nil : WorkoutProgressReport.ExerciseRecords(exercise: group.exercise, records: lifted)
        }
        let recordIDs = Set(records.map(\.id))

        var improvements = report.trends.filter { $0.isImprovement && !recordIDs.contains($0.id) }
        // A group whose only record was Strength still has to show — the workout detail counts it
        // as a record, and a best-ever estimate is news. Waiting for the exercise's scored trend to
        // carry it lost it whenever that trend hadn't beaten the month's best: more reps at the
        // same weight, on an exercise scored on repetitions (the free default), set a Strength
        // record and no highlight at all. So it becomes a "Strength improved" row of its own, the
        // percent it beat the previous best by — an improvement, so no confetti.
        for group in report.exerciseRecords where !recordIDs.contains(group.id) {
            guard let estimate = group.records.first(where: { $0.metric == .estimatedOneRepMax }) else { continue }
            let strength = WorkoutProgressReport.ExerciseTrend(
                exercise: group.exercise,
                metric: .estimatedOneRepMax,
                current: estimate.value,
                baseline: estimate.previousBest
            )
            // A gain too small to read as 1% would show as "0%"; the detail keeps it, the panel
            // doesn't, like every other improvement.
            guard strength.isImprovement else { continue }
            if let index = improvements.firstIndex(where: { $0.id == group.id }) {
                // The exercise already has its row — once is enough. It stays when it already says
                // weight (weight wins over the estimate whenever both moved) or Strength (the same
                // news, against the recent best like every other row). A rep, time or distance gain
                // over the month gives way: a best-ever Strength outranks it, the order records
                // lead in (`ExerciseRecords.leadPriority`).
                let shown = Self.displayedTrend(for: improvements[index], in: report)
                if shown.metric == .weight || shown.metric == .estimatedOneRepMax { continue }
                improvements[index] = strength
            } else {
                improvements.append(strength)
            }
        }
        improvements.sort { abs($0.percentChange ?? 0) > abs($1.percentChange ?? 0) }

        return WorkoutRecap(
            workoutDate: workoutDate,
            weekWorkouts: weekWorkouts,
            report: report,
            records: records,
            improvements: improvements,
            firstSessionCount: report.trends.filter { $0.baseline == nil }.count
        )
    }
}
