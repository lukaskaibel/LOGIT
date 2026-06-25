//
//  WorkoutProgressSection.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 11.06.26.
//

import CoreData
import SwiftUI

// MARK: - Progress report

/// Everything the workout detail's progress section shows, computed once per appearance.
///
/// All comparisons are judged *as of the workout's date*: a personal record here means a value
/// beat everything recorded before this workout — even if a later workout has since surpassed
/// it — so a workout's detail screen keeps telling the story of that day. First-ever entries are
/// not records (there is nothing to beat); they read as a first session in the trends instead.
struct WorkoutProgressReport {

    struct PRRecord: Identifiable {
        let exercise: Exercise
        let metric: ExercisePrimaryMetric
        /// Base units: grams for weight and estimated 1RM, plain count for repetitions.
        let value: Int
        /// The exercise's best for this metric *before* this workout — the value the record beat.
        /// Base units like `value`; the records screen shows the gain over it.
        let previousBest: Int
        /// When that previous best was first set — the earliest prior session to reach it — so the
        /// card can date it beside the new record. Nil if no dated prior session carried it.
        let previousBestDate: Date?
        var id: String { "\(exercise.objectID.uriRepresentation())-\(metric.rawValue)" }
    }

    struct ExerciseTrend: Identifiable {
        let exercise: Exercise
        /// The exercise's chosen progress metric — except when it has no usable value in this
        /// workout (e.g. bodyweight exercises on a weight metric), which falls back to repetitions.
        let metric: ExercisePrimaryMetric
        let current: Int
        /// Mirrors the baseline of the exercise badge in the list below: the exercise's best in
        /// the month before this workout (excluding it), falling back to the all-time best before
        /// it. Nil when this workout is the exercise's first session.
        let baseline: Int?

        var percentChange: Double? {
            guard let baseline, baseline > 0, current > 0 else { return nil }
            return (Double(current) - Double(baseline)) / Double(baseline) * 100
        }

        /// Matches `TrendIndicatorView`'s rounding so the "n of m improved" headline can never
        /// disagree with the pills below it: a change only counts once it displays as at least 1%.
        var isImprovement: Bool {
            guard let change = percentChange else { return false }
            return change > 0 && Int(min(abs(change), 999).rounded()) > 0
        }

        var id: NSManagedObjectID { exercise.objectID }
    }

    let prRecords: [PRRecord]
    let trends: [ExerciseTrend]

    var comparableTrendCount: Int { trends.filter { $0.percentChange != nil }.count }
    var improvedTrendCount: Int { trends.filter { $0.isImprovement }.count }

    static let empty = WorkoutProgressReport(prRecords: [], trends: [])

    // MARK: Computation

    static func compute(for workout: Workout, database: Database) -> WorkoutProgressReport {
        guard let workoutDate = workout.date, workout.hasEntries else { return .empty }

        var prRecords = [PRRecord]()
        var trends = [ExerciseTrend]()

        for exercise in uniqueExercises(in: workout) {
            // All of the exercise's sets before this workout, by timestamp (strictly earlier, so
            // a twin at the same instant can't be its own baseline) — computed once and shared by
            // record detection and the trend baseline.
            let priorSets = exercise.sets.filter {
                guard $0.workout != workout, let date = $0.workout?.date else { return false }
                return date < workoutDate
            }

            func value(_ workoutSet: WorkoutSet, _ metric: ExercisePrimaryMetric) -> Int {
                switch metric {
                case .estimatedOneRepMax: return workoutSet.estimatedOneRepMax(for: exercise)
                case .weight: return workoutSet.maximum(.weight, for: exercise)
                case .repetitions: return workoutSet.maximum(.repetitions, for: exercise)
                }
            }

            func sessionBest(_ metric: ExercisePrimaryMetric) -> Int {
                workout.sets.map { value($0, metric) }.max() ?? 0
            }

            for metric in ExercisePrimaryMetric.allCases {
                let current = sessionBest(metric)
                let priorBest = priorSets.map { value($0, metric) }.max() ?? 0
                // Ties don't count, and neither do first-ever entries — with no earlier value
                // there is no record to beat.
                if current > 0, priorBest > 0, current > priorBest {
                    // When the beaten record was first set: the earliest prior session that reached
                    // it, so the card can date the previous best beside the new one.
                    let previousBestDate = priorSets
                        .filter { value($0, metric) == priorBest }
                        .compactMap { $0.workout?.date }
                        .min()
                    prRecords.append(
                        PRRecord(
                            exercise: exercise,
                            metric: metric,
                            value: current,
                            previousBest: priorBest,
                            previousBestDate: previousBestDate
                        )
                    )
                }
            }

            var trendMetric = exercise.primaryMetric
            if sessionBest(trendMetric) == 0 {
                trendMetric = .repetitions
            }
            let current = sessionBest(trendMetric)
            // Same baseline as the exercise badge: best of the month before this workout, falling
            // back to the all-time best before it — so the "n improved" pill beside the exercises
            // title can never disagree with the badges it summarizes.
            let windowStart = Exercise.currentBestWindowStart(endingAt: workoutDate)
            let windowBest = priorSets
                .filter { ($0.workout?.date ?? .distantPast) >= windowStart }
                .map { value($0, trendMetric) }
                .max() ?? 0
            let priorBestForTrend = priorSets.map { value($0, trendMetric) }.max() ?? 0
            let baseline = windowBest > 0 ? windowBest : priorBestForTrend
            if current > 0 {
                trends.append(ExerciseTrend(
                    exercise: exercise,
                    metric: trendMetric,
                    current: current,
                    baseline: baseline > 0 ? baseline : nil
                ))
            }
        }

        return WorkoutProgressReport(prRecords: prRecords, trends: trends)
    }

    private static func uniqueExercises(in workout: Workout) -> [Exercise] {
        var result = [Exercise]()
        for exercise in workout.exercises where !result.contains(where: { $0.objectID == exercise.objectID }) {
            result.append(exercise)
        }
        return result
    }
}

// MARK: - Shared record rendering

/// "Personal record" for one, "%d Personal Records" otherwise — shared by the records tile and the
/// records screen so their headlines can never disagree.
private func personalRecordsHeadline(count: Int) -> String {
    count == 1
        ? NSLocalizedString("personalRecord", comment: "")
        : String(format: NSLocalizedString("personalRecordsCount", comment: ""), count)
}

/// A record's base value as a display string and its unit, in the metric's units. The tile and the
/// card both render it through `UnitView`, which uppercases the unit, so the casing can't drift.
private func personalRecordDisplay(_ base: Int, metric: ExercisePrimaryMetric) -> (value: String, unit: String) {
    switch metric {
    case .estimatedOneRepMax: return (formatEstimatedOneRepMax(base), WeightUnit.used.rawValue)
    case .weight: return (formatWeightForDisplay(base), WeightUnit.used.rawValue)
    case .repetitions: return (String(base), NSLocalizedString("reps", comment: ""))
    }
}

/// The metric's base value of a single set for `exercise` — the per-day series behind the records
/// screen's sparkline, matching the detection in `WorkoutProgressReport.compute`.
private func personalRecordSetValue(_ workoutSet: WorkoutSet, exercise: Exercise, metric: ExercisePrimaryMetric) -> Int {
    switch metric {
    case .estimatedOneRepMax: return workoutSet.estimatedOneRepMax(for: exercise)
    case .weight: return workoutSet.maximum(.weight, for: exercise)
    case .repetitions: return workoutSet.maximum(.repetitions, for: exercise)
    }
}

/// A record's value as `UnitView` — the caller tints it in the exercise's muscle-group gradient.
private func personalRecordValueView(
    for record: WorkoutProgressReport.PRRecord,
    configuration: UnitViewConfiguration = .normal
) -> some View {
    let display = personalRecordDisplay(record.value, metric: record.metric)
    return UnitView(value: display.value, unit: display.unit, configuration: configuration)
}

// MARK: - Records tile

/// The compact personal records tile on the workout detail: the first few of this workout's records,
/// each value in its exercise's muscle-group gradient, with a count of any extras. The whole tile is
/// a button into `WorkoutPersonalRecordsScreen` — the chevron stands in for the navigation
/// affordance, and the records' explanation and the value each one beat live on that screen, so the
/// tile next to the volume tile stays a quick glance rather than a wall of numbers.
struct WorkoutPersonalBestsTile: View {
    let workout: Workout
    let report: WorkoutProgressReport
    /// How many records the tile lists before deferring the rest to "+n more".
    var maxShown: Int = 3

    /// One record per exercise for the compact tile, so three records of the same exercise (its
    /// weight, estimated 1RM, and reps all at once) don't crowd the others out — the most tangible
    /// metric wins (weight, then estimated 1RM, then reps). Every record still lives on the records
    /// screen; "+n more" counts them all.
    private var tileRecords: [WorkoutProgressReport.PRRecord] {
        func priority(_ metric: ExercisePrimaryMetric) -> Int {
            switch metric {
            case .weight: return 0
            case .estimatedOneRepMax: return 1
            case .repetitions: return 2
            }
        }
        var best: [NSManagedObjectID: WorkoutProgressReport.PRRecord] = [:]
        var order: [NSManagedObjectID] = []
        for record in report.prRecords {
            let id = record.exercise.objectID
            if let existing = best[id] {
                if priority(record.metric) < priority(existing.metric) { best[id] = record }
            } else {
                best[id] = record
                order.append(id)
            }
        }
        return order.compactMap { best[$0] }
    }

    var body: some View {
        let shown = Array(tileRecords.prefix(maxShown))
        let remaining = report.prRecords.count - shown.count
        VStack(alignment: .leading, spacing: 0) {
            TileHeader(NSLocalizedString("personalRecords", comment: "")) {
                if remaining > 0 {
                    Text(String(format: NSLocalizedString("personalRecordsMoreCount", comment: ""), remaining))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 8) {
                ForEach(shown) { record in
                    row(for: record)
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One record on its own secondary tile: a muscle-tinted trophy badge leads the exercise and
    /// metric, with the new best in its muscle-group gradient on the right. The tile stays neutral
    /// (`tertiaryBackground`, recessed with the same inset shadow as the set cells) so the muscle
    /// colour reads from the badge and value; the gain over the value it beat lives on the records
    /// screen behind the tile rather than crowding the glance here.
    private func row(for record: WorkoutProgressReport.PRRecord) -> some View {
        let color = record.exercise.muscleGroup?.color ?? .accentColor
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: "trophy.fill")
                    .font(.caption)
                    .foregroundStyle(color.gradient)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(record.exercise.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.label)
                    .lineLimit(1)
                Text(record.metric.title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            personalRecordValueView(for: record, configuration: .normal)
                .foregroundStyle(color.gradient)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .secondaryTileStyle(insetShadow: true)
    }
}

// MARK: - Records screen

/// The full personal records screen behind the workout detail's records tile: every record set in
/// this workout, each with the value it beat and a line chart of the exercise's entire history for
/// that metric cresting at the new best. The tile shows only the first few and the count; this is
/// where they all live, with the basis spelled out at the bottom.
///
/// Pro-gated (blur + crown, like the other metric detail screens): the records *tile* on the workout
/// detail stays free — the PR celebration is the teaser that sells Pro — but the full per-record
/// history charts here are the analytics behind the wall.
struct WorkoutPersonalRecordsScreen: View {
    @ObservedObject var workout: Workout
    let report: WorkoutProgressReport

    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                header
                VStack(spacing: 10) {
                    ForEach(report.prRecords) { record in
                        WorkoutPersonalRecordCard(workout: workout, record: record)
                    }
                }
                footnote
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text(NSLocalizedString("personalRecords", comment: ""))
                        .font(.headline)
                    Text(workout.name ?? "")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(workout.sets.muscleGroupGradient(startPoint: .bottomLeading, endPoint: .topTrailing).opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(workout.sets.muscleGroupGradientStyle(startPoint: .bottomLeading, endPoint: .topTrailing))
            }
            Text(personalRecordsHeadline(count: report.prRecords.count))
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.label)
            if let date = workout.date {
                Text(date.formatted(.dateTime.day().month().year()))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top)
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
            Text(NSLocalizedString("workoutPRInfo", comment: ""))
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

/// One record on `WorkoutPersonalRecordsScreen`: a trophy badge leading the exercise and metric, then
/// a comparison scoreboard of the previous best (dated) against the new record (dated, muscle-tinted)
/// with the gain as a percent pill between them, over a clean line chart of the exercise's entire
/// history for this metric that bleeds to the card's edges. The top-right corner is intentionally left
/// free now that the gain reads from the scoreboard rather than a pill up there.
struct WorkoutPersonalRecordCard: View {
    let workout: Workout
    let record: WorkoutProgressReport.PRRecord

    var body: some View {
        let color = record.exercise.muscleGroup?.color ?? .accentColor
        // Spacing 0 so the chart can sit flush against the card's bottom and side edges: the header
        // and scoreboard carry their own `CELL_PADDING` inset, the chart carries none and bleeds out
        // to the `tileStyle` rounded border (which clips its bottom corners).
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                header(color: color)
                comparison(color: color)
            }
            .padding(CELL_PADDING)
            ExerciseTileSparkline(points: sparklinePoints, color: color, window: .allTime, height: 108)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileStyle()
    }

    private func header(color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: "trophy.fill")
                    .font(.subheadline)
                    .foregroundStyle(color.gradient)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(record.exercise.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.label)
                    .lineLimit(1)
                Text(record.metric.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            // Top-right corner intentionally free — the gain now reads from the scoreboard below.
        }
    }

    /// The scoreboard: the dated previous best on the left, the dated new record (muscle-tinted) on
    /// the right, and the percent gain of one over the other in the pill between them — the shared
    /// `MetricComparisonView` the chart-detail headers wear, so this PR jump reads the same way.
    private func comparison(color: Color) -> some View {
        let previous = personalRecordDisplay(record.previousBest, metric: record.metric)
        let current = personalRecordDisplay(record.value, metric: record.metric)
        let percentChange = record.previousBest > 0
            ? (Double(record.value) - Double(record.previousBest)) / Double(record.previousBest) * 100
            : nil
        return MetricComparisonView(
            leading: .init(
                label: NSLocalizedString("previousBest", comment: ""),
                value: previous.value,
                unit: previous.unit,
                caption: recordDateCaption(record.previousBestDate)
            ),
            trailing: .init(
                label: NSLocalizedString("newRecord", comment: ""),
                value: current.value,
                unit: current.unit,
                caption: recordDateCaption(workout.date)
            ),
            trailingValueStyle: AnyShapeStyle(color.gradient),
            percentChange: percentChange,
            positiveColor: color,
            positiveStyle: AnyShapeStyle(color.gradient)
        )
    }

    /// A scoreboard caption date — day and month, with the year only when it isn't the current one,
    /// matching the chart headers' date captions.
    private func recordDateCaption(_ date: Date?) -> String? {
        guard let date else { return nil }
        return date.isInCurrentYear
            ? date.formatted(.dateTime.day().month())
            : date.formatted(.dateTime.day().month().year())
    }

    /// The exercise's daily best for this metric up to and including this workout — the same
    /// daily-best series the exercise detail tiles chart, ending at the record.
    private var sparklinePoints: [ExerciseTileSparkline.Point] {
        let cutoff = workout.date ?? .now
        let sets = record.exercise.sets.filter { ($0.workout?.date ?? .distantFuture) <= cutoff }
        let grouped = Dictionary(grouping: sets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }
        return grouped.compactMap { day, daySets -> ExerciseTileSparkline.Point? in
            let best = daySets
                .map { personalRecordSetValue($0, exercise: record.exercise, metric: record.metric) }
                .max() ?? 0
            guard best > 0 else { return nil }
            let value: Double
            switch record.metric {
            case .estimatedOneRepMax, .weight: value = convertWeightForDisplayingDecimal(best)
            case .repetitions: value = Double(best)
            }
            return ExerciseTileSparkline.Point(date: day, value: value)
        }
        .sorted { $0.date < $1.date }
    }
}

// MARK: - Info panel

/// Explains what the workout detail's progress numbers mean — shown from the records tile's
/// info button. The stat tiles' comparison basis is explained on the tiles themselves.
struct WorkoutProgressInfoPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            infoBlock(
                icon: "trophy.fill",
                title: NSLocalizedString("personalRecords", comment: ""),
                text: NSLocalizedString("workoutPRInfo", comment: "")
            )
            infoBlock(
                icon: "chart.line.uptrend.xyaxis",
                title: NSLocalizedString("exerciseProgress", comment: ""),
                text: NSLocalizedString("workoutTrendInfo", comment: "")
            )
        }
    }

    private func infoBlock(icon: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.footnote)
                .fontWeight(.semibold)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Preview

private struct PreviewWrapperView: View {
    @EnvironmentObject var database: Database

    var body: some View {
        let workout = database.testWorkout
        return NavigationStack {
            WorkoutPersonalRecordsScreen(
                workout: workout,
                report: .compute(for: workout, database: database)
            )
        }
    }
}

struct WorkoutPersonalRecords_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
