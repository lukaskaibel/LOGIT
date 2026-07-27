//
//  ProgressHighlights.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.07.26.
//

import Foundation

// MARK: - Highlight items

/// One card in the Progress tab's Highlights carousel — a recent improvement the user would
/// otherwise have to dig out of the detail charts. Ordered by `ProgressHighlights.compute`:
/// milestones, then records, then the year crossing, then whole-training trends, then scoped
/// (muscle-group / exercise) trends.
enum ProgressHighlight: Identifiable {
    /// An all-time best that crossed a ladder step ("first time past 160 kg"). Replaces the plain
    /// record card for its exercise — it is the same event, dressed up. `subject` is the record that
    /// did the crossing, which need not be the exercise's lead metric.
    case milestone(
        records: WorkoutProgressReport.ExerciseRecords,
        subject: WorkoutProgressReport.PRRecord,
        stepBaseValue: Int
    )
    /// One exercise's recent records (the existing `SummaryRecords` feed, grouped per exercise so an
    /// exercise that set two records at once is one card rather than two).
    case record(WorkoutProgressReport.ExerciseRecords)
    /// This year's running volume total passed last year's full total.
    case yearCrossing(ProgressYearCrossing)
    /// A now-vs-before comparison over rolling 4-week windows.
    case trend(ProgressTrend)

    var id: String {
        switch self {
        case let .milestone(_, subject, step): return "milestone-\(subject.id)-\(step)"
        case let .record(records): return "record-\(records.lead.id)"
        case let .yearCrossing(crossing): return "year-\(crossing.year)"
        case let .trend(trend): return "trend-\(trend.id)"
        }
    }
}

/// A rolling-window trend: the last 4 weeks against the 4 before, for one scope + metric family.
/// Values are in base units (grams for volume, plain counts otherwise); the displayed percent is
/// already rounded the way `TrendIndicatorView` rounds, so thresholds and the pill can't disagree.
struct ProgressTrend: Identifiable {
    enum Kind: String {
        /// Whole-training volume.
        case volume
        /// Whole-training set count.
        case sets
        /// Whole-training workout count.
        case workouts
        /// One muscle group's set count.
        case muscleGroupSets
        /// One exercise's volume.
        case exerciseVolume
    }

    let kind: Kind
    /// Set for `muscleGroupSets` only.
    var muscleGroup: MuscleGroup? = nil
    /// Set for `exerciseVolume` only.
    var exercise: Exercise? = nil
    /// Base-unit totals of the recent and prior windows.
    let currentValue: Int
    let previousValue: Int

    /// Rounded display percent (`TrendIndicatorView`'s rounding), guaranteed > 0 by construction.
    var displayedPercent: Int {
        guard previousValue > 0 else { return 0 }
        let raw = (Double(currentValue) - Double(previousValue)) / Double(previousValue) * 100
        return Int(min(abs(raw), 999).rounded()) * (raw < 0 ? -1 : 1)
    }

    var id: String {
        "\(kind.rawValue)-\(muscleGroup?.rawValue ?? "")-\(exercise?.id?.uuidString ?? "")"
    }
}

/// The one-time "this year already beat last year" event, in total volume. Only reported while its
/// crossing date is recent (the highlights window), so it celebrates once and then retires without
/// any persisted state.
struct ProgressYearCrossing {
    let year: Int
    let previousYear: Int
    /// Base-unit (gram) totals: this year to date, last year in full.
    let currentVolume: Int
    let previousVolume: Int
    /// The date of the workout whose volume tipped the running total past last year.
    let crossingDate: Date
    /// Full calendar months left in the year after the crossing — "with 5 months to spare".
    let monthsToSpare: Int
}

// MARK: - Milestone ladder

/// The fixed ladder steps behind milestone detection, in the metric's base units. Weight ladders
/// follow the *display* unit — a kg lifter crosses 100 kg, an lbs lifter crosses plate numbers like
/// 225 lb — because thresholds are only meaningful in the unit you think in.
enum MilestoneLadder {
    /// Weight / e1RM steps in display units: kg every 10 to 100, then 20s to 200, then 25s;
    /// lbs plate math, then 50s.
    private static let kgSteps: [Int] = Array(stride(from: 10, through: 100, by: 10))
        + Array(stride(from: 120, through: 200, by: 20))
        + Array(stride(from: 225, through: 500, by: 25))
    private static let lbsSteps: [Int] = [45, 95, 135, 185, 225, 275, 315, 365, 405, 455, 495]
        + Array(stride(from: 545, through: 1000, by: 50))

    private static let repsSteps = [10, 15, 20, 25, 30, 40, 50, 75, 100]
    /// Seconds.
    private static let durationSteps = [30, 60, 120, 180, 300, 600]
    /// Meters — 1 k, 2.5 k, 5 k, 10 k, 15 k, half and full marathon.
    private static let distanceSteps = [1000, 2500, 5000, 10000, 15000, 21098, 42195]

    /// All ladder steps for a metric, converted to the metric's base units (grams for weights).
    static func steps(for metric: ExercisePrimaryMetric) -> [Int] {
        switch metric {
        case .weight, .estimatedOneRepMax:
            // `convertWeightForStoring` converts a display-unit value to grams using the same
            // active unit that picked the step list.
            let displaySteps = WeightUnit.used == .kg ? kgSteps : lbsSteps
            return displaySteps.map { Int(convertWeightForStoring(Double($0))) }
        case .repetitions: return repsSteps
        case .duration: return durationSteps
        case .distance: return distanceSteps
        }
    }

    /// The highest ladder step a record crossed — `previousBest < step ≤ value` — or nil when none.
    /// Because `previousBest` is the all-time best the record beat, a crossing can only happen once:
    /// afterwards the all-time best sits at or above the step.
    static func highestStep(crossedFrom previousBest: Int, to value: Int, metric: ExercisePrimaryMetric) -> Int? {
        steps(for: metric).filter { previousBest < $0 && $0 <= value }.max()
    }
}

// MARK: - Computation

/// Assembles the Highlights feed from the already-fetched workouts — no new Core Data fetches, the
/// same deal as the rest of the Progress tab. All windows anchor to the start of today so the feed
/// is stable within a day.
enum ProgressHighlights {

    /// Rolling window length used by all trends: 4 weeks, the app's standard recent window.
    private static let windowDays = 28

    /// Noise floors: a trend must clear its relative threshold AND its absolute delta, with enough
    /// training in both windows, so "up 50%" can never come from 2 sets becoming 3.
    private static let wholePercentFloor = 10
    private static let scopedPercentFloor = 15
    private static let volumeDeltaFloorGrams = 500_000 // 500 kg
    private static let setsDeltaFloor = 5
    private static let workoutsDeltaFloor = 2
    private static let wholeMinWorkoutsPerWindow = 3
    private static let muscleMinSetsPerWindow = 6
    private static let exerciseMinSessionsPerWindow = 2
    /// A year crossing is only impressive against a real year of training.
    private static let yearCrossingMinPreviousWorkouts = 20

    /// How many cards the carousel shows; the See-All screen lists everything.
    static let carouselLimit = 5

    static func compute(
        workouts: [Workout],
        database: Database,
        reference: Date = .now
    ) -> [ProgressHighlight] {
        let calendar = Calendar.current
        // Exclude the workout currently being recorded everywhere — highlights tell the standing
        // before this session, the way the exercise tiles do.
        let finished = workouts.filter { !$0.isEmpty && !$0.isCurrentWorkout }

        // Bests: the existing records feed over the recent window, split into milestones + records.
        let windowStart = Exercise.currentBestWindowStart
        let recentWorkouts = finished.filter { ($0.date ?? .distantPast) >= windowStart }
        let records = SummaryRecords.records(in: recentWorkouts, database: database)
        var milestones: [ProgressHighlight] = []
        var plainRecords: [ProgressHighlight] = []
        for group in records {
            // A milestone can sit on any of the exercise's records, not only the lead one: crossing
            // 100 kg on the estimated 1RM is the story even when the lifted weight leads the card.
            // `records` is already in lead priority, so the first crossing found is the most
            // tangible one.
            let crossing = group.records.lazy.compactMap { record in
                MilestoneLadder
                    .highestStep(crossedFrom: record.previousBest, to: record.value, metric: record.metric)
                    .map { (record, $0) }
            }.first
            if let (subject, step) = crossing {
                milestones.append(.milestone(records: group, subject: subject, stepBaseValue: step))
            } else {
                plainRecords.append(.record(group))
            }
        }

        // Rolling windows: [end-28d, end) vs [end-56d, end-28d), end = start of tomorrow so today
        // counts fully.
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: reference)) ?? reference
        guard
            let currentStart = calendar.date(byAdding: .day, value: -windowDays, to: end),
            let priorStart = calendar.date(byAdding: .day, value: -2 * windowDays, to: end)
        else { return milestones + plainRecords }

        let currentWorkouts = finished.filter { ($0.date ?? .distantPast) >= currentStart && ($0.date ?? .distantPast) < end }
        let priorWorkouts = finished.filter { ($0.date ?? .distantPast) >= priorStart && ($0.date ?? .distantPast) < currentStart }
        let currentSets = currentWorkouts.flatMap { $0.sets }
        let priorSets = priorWorkouts.flatMap { $0.sets }

        var wholeTrends: [ProgressTrend] = []
        var scopedTrends: [ProgressTrend] = []

        let enoughWorkouts = currentWorkouts.count >= wholeMinWorkoutsPerWindow
            && priorWorkouts.count >= wholeMinWorkoutsPerWindow

        // Whole-training volume.
        let currentVolume = getVolume(of: currentSets)
        let priorVolume = getVolume(of: priorSets)
        let volumeTrend = ProgressTrend(kind: .volume, currentValue: currentVolume, previousValue: priorVolume)
        let volumeFires = enoughWorkouts
            && volumeTrend.displayedPercent >= wholePercentFloor
            && currentVolume - priorVolume >= volumeDeltaFloorGrams
        if volumeFires { wholeTrends.append(volumeTrend) }

        // Whole-training sets.
        let setsTrend = ProgressTrend(kind: .sets, currentValue: currentSets.count, previousValue: priorSets.count)
        let setsFire = enoughWorkouts
            && setsTrend.displayedPercent >= wholePercentFloor
            && currentSets.count - priorSets.count >= setsDeltaFloor
        if setsFire { wholeTrends.append(setsTrend) }

        // Workout count.
        let workoutsTrend = ProgressTrend(
            kind: .workouts, currentValue: currentWorkouts.count, previousValue: priorWorkouts.count
        )
        if priorWorkouts.count >= wholeMinWorkoutsPerWindow,
           workoutsTrend.displayedPercent >= wholePercentFloor,
           currentWorkouts.count - priorWorkouts.count >= workoutsDeltaFloor {
            wholeTrends.append(workoutsTrend)
        }

        // Muscle-group set trends — suppressed as a family when the whole-training sets card fires
        // (one card per metric family per scope: the strongest single story wins).
        if !setsFire {
            let service = MuscleGroupService()
            let currentByGroup = Dictionary(uniqueKeysWithValues: service.getMuscleGroupOccurances(in: currentSets))
            let priorByGroup = Dictionary(uniqueKeysWithValues: service.getMuscleGroupOccurances(in: priorSets))
            for group in MuscleGroup.allCases {
                let current = currentByGroup[group] ?? 0
                let prior = priorByGroup[group] ?? 0
                guard current >= muscleMinSetsPerWindow, prior >= muscleMinSetsPerWindow else { continue }
                let trend = ProgressTrend(kind: .muscleGroupSets, muscleGroup: group, currentValue: current, previousValue: prior)
                guard trend.displayedPercent >= scopedPercentFloor,
                      current - prior >= setsDeltaFloor else { continue }
                scopedTrends.append(trend)
            }
        }

        // Exercise volume trends — same family rule against the whole-training volume card.
        if !volumeFires {
            var exercises: [Exercise] = []
            var seen = Set<Exercise>()
            for workout in currentWorkouts {
                for exercise in workout.exercises where !seen.contains(exercise) {
                    seen.insert(exercise)
                    exercises.append(exercise)
                }
            }
            for exercise in exercises {
                let currentSessions = currentWorkouts.filter { $0.exercises.contains(exercise) }
                let priorSessions = priorWorkouts.filter { $0.exercises.contains(exercise) }
                guard currentSessions.count >= exerciseMinSessionsPerWindow,
                      priorSessions.count >= exerciseMinSessionsPerWindow else { continue }
                let current = getVolume(of: currentSessions.flatMap { $0.sets }, for: exercise)
                let prior = getVolume(of: priorSessions.flatMap { $0.sets }, for: exercise)
                guard prior > 0 else { continue }
                let trend = ProgressTrend(kind: .exerciseVolume, exercise: exercise, currentValue: current, previousValue: prior)
                guard trend.displayedPercent >= scopedPercentFloor else { continue }
                scopedTrends.append(trend)
            }
        }

        wholeTrends.sort { $0.displayedPercent > $1.displayedPercent }
        scopedTrends.sort { $0.displayedPercent > $1.displayedPercent }

        // Year crossing — computed from full history, shown only while the crossing is recent.
        var yearItems: [ProgressHighlight] = []
        if let crossing = yearCrossing(in: finished, reference: reference, calendar: calendar),
           crossing.crossingDate >= currentStart {
            yearItems.append(.yearCrossing(crossing))
        }

        return milestones
            + plainRecords
            + yearItems
            + wholeTrends.map { .trend($0) }
            + scopedTrends.map { .trend($0) }
    }

    /// The day this year's running volume total passed last year's full total, or nil if it hasn't
    /// (or last year holds too little training to make the comparison meaningful).
    private static func yearCrossing(
        in workouts: [Workout], reference: Date, calendar: Calendar
    ) -> ProgressYearCrossing? {
        let year = calendar.component(.year, from: reference)
        let previousYear = year - 1
        let previousYearWorkouts = workouts.filter {
            guard let date = $0.date else { return false }
            return calendar.component(.year, from: date) == previousYear
        }
        guard previousYearWorkouts.count >= yearCrossingMinPreviousWorkouts else { return nil }
        let previousTotal = getVolume(of: previousYearWorkouts.flatMap { $0.sets })
        guard previousTotal > 0 else { return nil }

        let thisYearWorkouts = workouts
            .filter {
                guard let date = $0.date else { return false }
                return calendar.component(.year, from: date) == year && date <= reference
            }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }

        var runningTotal = 0
        var crossingDate: Date?
        for workout in thisYearWorkouts {
            runningTotal += getVolume(of: workout.sets)
            if crossingDate == nil, runningTotal > previousTotal {
                crossingDate = workout.date
            }
        }
        guard let crossingDate else { return nil }
        return ProgressYearCrossing(
            year: year,
            previousYear: previousYear,
            // The card shows the full year-to-date total, not the total at the moment of crossing.
            currentVolume: runningTotal,
            previousVolume: previousTotal,
            crossingDate: crossingDate,
            monthsToSpare: 12 - calendar.component(.month, from: crossingDate)
        )
    }
}
