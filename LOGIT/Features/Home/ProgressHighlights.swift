//
//  ProgressHighlights.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.07.26.
//

import Foundation

// MARK: - Highlight items

/// One card in the Summary's Highlights carousel — a recent improvement the user would
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

/// A rolling-window trend: one window against the equally long one before it, for one scope + metric
/// family. Values are in base units (grams for volume, plain counts otherwise); the displayed percent
/// is already rounded the way `TrendIndicatorView` rounds, so thresholds and the pill can't disagree.
struct ProgressTrend: Identifiable {
    enum Kind: String {
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
    /// The window the two values were measured over — the card labels its bars from this, so a
    /// widened highlights screen can't go on saying "4 weeks before".
    var window: TrendWindow = ProgressHighlights.recentWindow

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
/// same deal as the rest of the Summary.
///
/// Everything is scoped to one `TrendWindow` and compared against the window before it: which
/// records count as recent, which trends are measured, and how recent a year crossing has to be to
/// still be worth celebrating. The Summary's carousel always passes `recentWindow`, whatever the
/// screen's picker says — see `SummaryHighlightsSection` — while `ProgressHighlightsScreen` lets a
/// reader widen it.
enum ProgressHighlights {

    /// The window the Summary's carousel is fixed to, and what the highlights screen opens on: four
    /// weeks, the app's standard recent window. A highlight is an *event*, and an event stops being a
    /// highlight once it stops being recent, so the carousel keeps this clock even when the rest of
    /// the Summary is reading a year.
    static let recentWindow = TrendWindow.fourWeeks

    /// Noise floors: a trend must clear its relative threshold AND its absolute delta, with enough
    /// training in both windows, so "up 50%" can never come from 2 sets becoming 3. The counting
    /// floors are quoted per four weeks and scaled by `floorScale` — three workouts is a real month
    /// of training and a rounding error in a year.
    private static let scopedPercentFloor = 15
    private static let setsDeltaFloor = 5
    private static let minWorkoutsPerWindow = 3
    private static let muscleMinSetsPerWindow = 6
    private static let exerciseMinSessionsPerWindow = 2

    /// How many four-week blocks a window holds — the multiplier on every count-based noise floor, so
    /// widening the window raises the bar for a trend instead of letting a year's worth of slack
    /// through.
    private static func floorScale(for window: TrendWindow) -> Int {
        switch window {
        case .fourWeeks: return 1
        case .threeMonths: return 3
        case .oneYear: return 13
        }
    }
    /// A year crossing is only impressive against a real year of training.
    private static let yearCrossingMinPreviousWorkouts = 20

    /// How many cards the carousel shows; the See-All screen lists everything.
    static let carouselLimit = 5

    static func compute(
        workouts: [Workout],
        database: Database,
        window: TrendWindow = ProgressHighlights.recentWindow,
        reference: Date = .now
    ) -> [ProgressHighlight] {
        let calendar = Calendar.current
        // Exclude the workout currently being recorded everywhere — highlights tell the standing
        // before this session, the way the exercise tiles do.
        let finished = workouts.filter { !$0.isEmpty && !$0.isCurrentWorkout }

        // Every window anchors to the start of tomorrow rather than to this instant, so today counts
        // in full and the feed doesn't reshuffle as the day goes on.
        let anchor = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: reference)) ?? reference
        let currentRange = window.range(windowsAgo: 0, from: anchor)
        let priorRange = window.range(windowsAgo: 1, from: anchor)

        // Bests: the existing records feed over the window, split into milestones + records.
        let recentWorkouts = finished.filter { ($0.date ?? .distantPast) > currentRange.lowerBound }
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

        // The window against the equally long one before it. Half-open at the lower edge, so a
        // workout on the shared boundary instant counts in the newer window only.
        let currentWorkouts = finished.filter { workout in
            guard let date = workout.date else { return false }
            return date > currentRange.lowerBound && date <= currentRange.upperBound
        }
        let priorWorkouts = finished.filter { workout in
            guard let date = workout.date else { return false }
            return date > priorRange.lowerBound && date <= priorRange.upperBound
        }
        let currentSets = currentWorkouts.flatMap { $0.sets }
        let priorSets = priorWorkouts.flatMap { $0.sets }
        let scale = floorScale(for: window)

        var scopedTrends: [ProgressTrend] = []

        // Whole-training volume / sets / workout-count trends deliberately have no card: the core
        // stat grid on the same scroll already reports those three numbers with their own trend
        // pills. Highlights earns its space by saying what the grid can't — which muscle group and
        // which lift moved.
        let enoughWorkouts = currentWorkouts.count >= minWorkoutsPerWindow * scale
            && priorWorkouts.count >= minWorkoutsPerWindow * scale

        // Muscle-group set trends.
        if enoughWorkouts {
            let service = MuscleGroupService()
            let currentByGroup = Dictionary(uniqueKeysWithValues: service.getMuscleGroupOccurances(in: currentSets))
            let priorByGroup = Dictionary(uniqueKeysWithValues: service.getMuscleGroupOccurances(in: priorSets))
            for group in MuscleGroup.allCases {
                let current = currentByGroup[group] ?? 0
                let prior = priorByGroup[group] ?? 0
                guard current >= muscleMinSetsPerWindow * scale, prior >= muscleMinSetsPerWindow * scale else { continue }
                let trend = ProgressTrend(
                    kind: .muscleGroupSets, muscleGroup: group,
                    currentValue: current, previousValue: prior, window: window
                )
                guard trend.displayedPercent >= scopedPercentFloor,
                      current - prior >= setsDeltaFloor * scale else { continue }
                scopedTrends.append(trend)
            }
        }

        // Exercise volume trends.
        if enoughWorkouts {
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
                guard currentSessions.count >= exerciseMinSessionsPerWindow * scale,
                      priorSessions.count >= exerciseMinSessionsPerWindow * scale else { continue }
                let current = getVolume(of: currentSessions.flatMap { $0.sets }, for: exercise)
                let prior = getVolume(of: priorSessions.flatMap { $0.sets }, for: exercise)
                guard prior > 0 else { continue }
                let trend = ProgressTrend(
                    kind: .exerciseVolume, exercise: exercise,
                    currentValue: current, previousValue: prior, window: window
                )
                guard trend.displayedPercent >= scopedPercentFloor else { continue }
                scopedTrends.append(trend)
            }
        }

        scopedTrends.sort { $0.displayedPercent > $1.displayedPercent }

        // Year crossing — computed from full history, shown only while the crossing is recent.
        var yearItems: [ProgressHighlight] = []
        if let crossing = yearCrossing(in: finished, reference: reference, calendar: calendar),
           crossing.crossingDate > currentRange.lowerBound {
            yearItems.append(.yearCrossing(crossing))
        }

        return milestones
            + plainRecords
            + yearItems
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
