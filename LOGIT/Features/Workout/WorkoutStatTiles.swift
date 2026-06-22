//
//  WorkoutStatTiles.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.06.26.
//

import Charts
import SwiftUI

// MARK: - Stat Metric

/// The four session stats on the workout detail — total volume, duration, set count, and total
/// repetitions — shared by the stat tiles and their detail screens so values, formatting, and
/// Pro gating can never drift apart between the two.
enum WorkoutStatMetric: Int, CaseIterable, Identifiable {
    case volume, duration, sets, repetitions

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .volume: return NSLocalizedString("volume", comment: "")
        case .duration: return NSLocalizedString("duration", comment: "")
        case .sets: return NSLocalizedString("sets", comment: "")
        case .repetitions: return NSLocalizedString("repetitions", comment: "")
        }
    }

    /// Unit beside the value. Duration formats its units into the value itself ("1h 12m").
    var unit: String {
        switch self {
        case .volume: return WeightUnit.used.rawValue
        case .duration: return ""
        case .sets: return NSLocalizedString("sets", comment: "")
        case .repetitions: return NSLocalizedString("rps", comment: "")
        }
    }

    /// Only volume is Pro — exactly the data the workout detail gated before the stat grid
    /// (total volume tile and volume-vs-last-time comparison); nothing new moves behind the wall.
    var requiresPro: Bool { self == .volume }

    /// Raw value for a workout: grams for volume, minutes for duration, plain counts otherwise.
    /// Raw units are what histories are compared in; they only convert for display.
    func rawValue(of workout: Workout) -> Int {
        switch self {
        case .volume:
            return getVolume(of: workout.sets)
        case .duration:
            guard let start = workout.date, let end = workout.endDate else { return 0 }
            return max(Calendar.current.dateComponents([.minute], from: start, to: end).minute ?? 0, 0)
        case .sets:
            return workout.numberOfSets
        case .repetitions:
            return workout.sets.reduce(0) { $0 + totalRepetitions(of: $1) }
        }
    }

    func displayValue(fromRaw raw: Int) -> Double {
        switch self {
        case .volume: return convertWeightForDisplayingDecimal(raw)
        case .duration, .sets, .repetitions: return Double(raw)
        }
    }

    func formattedValue(fromRaw raw: Int) -> String {
        switch self {
        case .volume: return formatWeightForDisplay(raw)
        case .duration: return formattedWorkoutDuration(minutes: raw)
        case .sets, .repetitions: return String(raw)
        }
    }

    /// Average per workout for the detail screens' header, formatted like the tile values so the
    /// two read as the same quantity. Volume rounds to whole display units like the estimated
    /// 1RM does — it's a calculated value, and fractional kilograms on a four-digit average are
    /// noise. Counts keep a decimal instead: a rounded "19" would claim a precision the average
    /// doesn't have.
    func formattedAverage(rawAverage: Double) -> String {
        switch self {
        case .volume: return String(Int(convertWeightForDisplayingDecimal(Int(rawAverage.rounded())).rounded()))
        case .duration: return formattedWorkoutDuration(minutes: Int(rawAverage.rounded()))
        case .sets, .repetitions: return HighlightView.formatNumber(rawAverage)
        }
    }

    // MARK: Detail screen texts

    var aboutText: String {
        switch self {
        case .volume: return NSLocalizedString("workoutVolumeAboutInfo", comment: "")
        case .duration: return NSLocalizedString("workoutDurationAboutInfo", comment: "")
        case .sets: return NSLocalizedString("workoutSetsAboutInfo", comment: "")
        case .repetitions: return NSLocalizedString("workoutRepsAboutInfo", comment: "")
        }
    }

    func highlightHeadline(isMore: Bool, isYearGranularity: Bool) -> String {
        let key: String
        switch self {
        case .volume:
            key = isYearGranularity
                ? (isMore ? "avgMoreWorkoutVolumeThisYearThanLastYear" : "avgLessWorkoutVolumeThisYearThanLastYear")
                : (isMore ? "avgMoreWorkoutVolumeThisMonthThanLastMonth" : "avgLessWorkoutVolumeThisMonthThanLastMonth")
        case .duration:
            key = isYearGranularity
                ? (isMore ? "avgLongerWorkoutsThisYearThanLastYear" : "avgShorterWorkoutsThisYearThanLastYear")
                : (isMore ? "avgLongerWorkoutsThisMonthThanLastMonth" : "avgShorterWorkoutsThisMonthThanLastMonth")
        case .sets:
            key = isYearGranularity
                ? (isMore ? "avgMoreSetsPerWorkoutThisYearThanLastYear" : "avgLessSetsPerWorkoutThisYearThanLastYear")
                : (isMore ? "avgMoreSetsPerWorkoutThisMonthThanLastMonth" : "avgLessSetsPerWorkoutThisMonthThanLastMonth")
        case .repetitions:
            key = isYearGranularity
                ? (isMore ? "avgMoreRepsPerWorkoutThisYearThanLastYear" : "avgLessRepsPerWorkoutThisYearThanLastYear")
                : (isMore ? "avgMoreRepsPerWorkoutThisMonthThanLastMonth" : "avgLessRepsPerWorkoutThisMonthThanLastMonth")
        }
        return NSLocalizedString(key, comment: "")
    }

    /// "kg/Workout"-style unit for the highlight tile.
    var highlightUnit: String {
        let perWorkout = "/\(NSLocalizedString("workout", comment: ""))"
        switch self {
        case .volume: return WeightUnit.used.rawValue + perWorkout
        case .duration: return NSLocalizedString("min", comment: "") + perWorkout
        case .sets: return NSLocalizedString("sets", comment: "") + perWorkout
        case .repetitions: return NSLocalizedString("rps", comment: "") + perWorkout
        }
    }

    /// Highlight tile value — duration shows plain minutes there ("69"), since its formatted
    /// form ("1h 9m") can't sit in front of the "min/Workout" unit.
    func highlightValue(rawAverage: Double) -> String {
        self == .duration ? HighlightView.formatNumber(rawAverage) : formattedAverage(rawAverage: rawAverage)
    }
}

/// "45 min" / "1h 12m" — the workout header's duration format, shared by the duration tile and
/// its detail screen.
func formattedWorkoutDuration(minutes: Int) -> String {
    if minutes < 60 {
        return "\(minutes) \(NSLocalizedString("min", comment: ""))"
    }
    let hours = minutes / 60
    let remainder = minutes % 60
    return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
}

/// All repetitions recorded in a set — across drops of a drop set and both sides of a super set —
/// as opposed to `maximum(.repetitions,for:)`, which is the best single entry for one exercise.
private func totalRepetitions(of workoutSet: WorkoutSet) -> Int {
    if let standardSet = workoutSet as? StandardSet {
        return Int(standardSet.repetitions)
    }
    if let dropSet = workoutSet as? DropSet {
        return Int(dropSet.repetitions?.reduce(0, +) ?? 0)
    }
    if let superSet = workoutSet as? SuperSet {
        return Int(superSet.repetitionsFirstExercise + superSet.repetitionsSecondExercise)
    }
    return 0
}

// MARK: - Run History

/// The comparison basis behind the workout stat tiles: the last few previous runs of the same
/// workout (same template, else same name) — or, when this workout has no previous runs, the
/// latest workouts of any kind, so first-run and unnamed workouts still get a comparison instead
/// of empty tiles. One basis for the whole grid; the four tiles can never disagree about what
/// "vs. last time" means.
struct WorkoutRunHistory {
    enum Basis {
        /// Previous runs of this same workout — the pill compares against the immediately
        /// previous run, a precise like-for-like.
        case sameWorkout
        /// Recent workouts of any kind — the pill compares against their *average*, since a
        /// single unrelated workout (push vs. legs) would swing the percent for reasons that
        /// have nothing to do with progress.
        case recentWorkouts
    }

    let basis: Basis
    /// Oldest → newest with the workout itself last; at most `WorkoutRunsBarChart.slotCount`.
    let runs: [Workout]

    func percentChange(for metric: WorkoutStatMetric) -> Double? {
        guard let current = runs.last.map({ metric.rawValue(of: $0) }), current > 0 else { return nil }
        let priorValues = runs.dropLast().map { metric.rawValue(of: $0) }.filter { $0 > 0 }
        guard !priorValues.isEmpty else { return nil }
        let baseline: Double
        switch basis {
        case .sameWorkout:
            guard let previous = runs.dropLast().last.map({ metric.rawValue(of: $0) }),
                  previous > 0 else { return nil }
            baseline = Double(previous)
        case .recentWorkouts:
            baseline = Double(priorValues.reduce(0, +)) / Double(priorValues.count)
        }
        return (Double(current) - baseline) / baseline * 100
    }

    static func compute(for workout: Workout, database: Database) -> WorkoutRunHistory {
        let maxPriorRuns = WorkoutRunsBarChart.slotCount - 1
        guard let workoutDate = workout.date else {
            return WorkoutRunHistory(basis: .recentWorkouts, runs: [workout])
        }
        let lineage = previousRuns(of: workout, before: workoutDate, database: database, limit: maxPriorRuns)
        if !lineage.isEmpty {
            return WorkoutRunHistory(basis: .sameWorkout, runs: lineage.reversed() + [workout])
        }
        let recents = recentWorkouts(before: workoutDate, excluding: workout, database: database, limit: maxPriorRuns)
        return WorkoutRunHistory(basis: .recentWorkouts, runs: recents.reversed() + [workout])
    }

    /// Previous runs of the same workout, newest first: from the same template when there is
    /// one, else earlier workouts with the same name. The single-run version of this lived in
    /// the progress section's volume comparison before the stat tiles absorbed it.
    private static func previousRuns(
        of workout: Workout,
        before workoutDate: Date,
        database: Database,
        limit: Int
    ) -> [Workout] {
        if let template = workout.template {
            return Array(
                template.workouts
                    .filter {
                        $0 != workout && !$0.isCurrentWorkout && !$0.isEmpty
                            && ($0.date ?? .distantFuture) < workoutDate
                    }
                    .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                    .prefix(limit)
            )
        }
        guard let name = workout.name, !name.isEmpty else { return [] }
        let sameName = (database.fetch(
            Workout.self,
            sortingKey: "date",
            ascending: false,
            predicate: NSPredicate(
                format: "name ==[c] %@ AND date < %@ AND (isCurrentWorkout == nil OR isCurrentWorkout == NO)",
                name,
                workoutDate as NSDate
            )
        ) as? [Workout]) ?? []
        return Array(sameName.filter { $0 != workout && !$0.isEmpty }.prefix(limit))
    }

    private static func recentWorkouts(
        before workoutDate: Date,
        excluding workout: Workout,
        database: Database,
        limit: Int
    ) -> [Workout] {
        let all = (database.fetch(
            Workout.self,
            sortingKey: "date",
            ascending: false,
            predicate: NSPredicate(
                format: "date < %@ AND (isCurrentWorkout == nil OR isCurrentWorkout == NO)",
                workoutDate as NSDate
            )
        ) as? [Workout]) ?? []
        return Array(all.filter { $0 != workout && !$0.isEmpty }.prefix(limit))
    }
}

// MARK: - Run History Chart

/// The mini bar chart under a stat tile's value: this workout against its previous runs, one bar
/// per run in a fixed five-slot frame (bars keep the same width however little history there is,
/// and the newest run is always rightmost). Only the current workout's bar is drawn in
/// `currentStyle` — the label color, matching the tile's value — every previous run stays quiet
/// gray, whichever comparison basis is behind it (the label's info button spells the basis out).
/// Short, wide, softly-rounded bars.
struct WorkoutRunsBarChart: View {
    struct Bar: Identifiable {
        let slot: Int
        let value: Double
        /// The current workout's bar — drawn with `currentStyle`; previous runs stay gray.
        let isCurrent: Bool
        var id: Int { slot }
    }

    static let slotCount = 5

    let bars: [Bar]
    let currentStyle: AnyShapeStyle

    var body: some View {
        let maxValue = bars.map(\.value).max() ?? 0
        Chart {
            ForEach(bars) { bar in
                if bar.value > 0 {
                    BarMark(
                        x: .value("Run", String(bar.slot)),
                        y: .value("Value", bar.value),
                        width: .ratio(0.8)
                    )
                    .foregroundStyle(bar.isCurrent ? currentStyle : AnyShapeStyle(Color.fill))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
        .chartXScale(domain: (0 ..< Self.slotCount).map(String.init))
        .chartYScale(domain: 0 ... max(maxValue, 1))
        .chartXAxis {}
        .chartYAxis {}
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .overlay {
            if maxValue <= 0 {
                Text(NSLocalizedString("noData", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Stat Tile

/// One compact session stat on the workout detail — the exercise metric tiles' skeleton with the
/// workout vocabulary: "This Workout" over a label-colored value with a muted unit, the trend pill
/// — wearing the workout's muscle-group gradient on a gain — against the run history top-right, and
/// the run bars beneath, this workout's bar drawn in the label color to match its value. The
/// duration tile's pill stays neutral gray in both directions — a longer workout is neither better
/// nor worse.
struct WorkoutStatTile: View {
    let metric: WorkoutStatMetric
    let workout: Workout
    let history: WorkoutRunHistory
    let pillColor: Color
    /// Gradient for the trend pill's positive tint; nil (the duration tile) keeps it neutral gray.
    let pillStyle: AnyShapeStyle?
    let valueStyle: AnyShapeStyle
    let currentBarStyle: AnyShapeStyle

    var body: some View {
        let raw = metric.rawValue(of: workout)
        let explanationKey = history.basis == .sameWorkout
            ? "workoutStatCompareSameInfo"
            : "workoutStatCompareRecentInfo"
        ExerciseMetricTileLayout(
            title: metric.title,
            label: .info(
                NSLocalizedString("thisWorkout", comment: ""),
                explanation: NSLocalizedString(explanationKey, comment: "")
            ),
            value: raw > 0 ? metric.formattedValue(fromRaw: raw) : nil,
            unit: metric.unit,
            color: pillColor,
            percentChange: history.percentChange(for: metric),
            isRecord: false,
            requiresPro: metric.requiresPro,
            valueStyle: valueStyle,
            unitColor: .secondaryLabel,
            trendStyle: pillStyle
        ) {
            WorkoutRunsBarChart(bars: runBars, currentStyle: currentBarStyle)
        }
    }

    /// Right-aligned into the chart's fixed slots: the newest run sits in the last slot however
    /// few runs there are. Runs without a usable value keep their slot as a gap.
    private var runBars: [WorkoutRunsBarChart.Bar] {
        let offset = WorkoutRunsBarChart.slotCount - history.runs.count
        return history.runs.enumerated().map { index, run in
            WorkoutRunsBarChart.Bar(
                slot: offset + index,
                value: metric.displayValue(fromRaw: metric.rawValue(of: run)),
                isCurrent: run.objectID == workout.objectID
            )
        }
    }
}

// MARK: - Stat Tile Grid

/// The 2×2 session stat grid under the workout header — volume and duration, then sets and
/// repetitions — each tile a button into its metric's detail screen. Collapses to a single
/// column at accessibility type sizes, like the exercise detail's grid.
struct WorkoutStatTileGrid: View {
    @EnvironmentObject private var database: Database
    @EnvironmentObject private var muscleGroupService: MuscleGroupService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ObservedObject var workout: Workout
    let onOpenDetail: (WorkoutStatMetric) -> Void

    @State private var history: WorkoutRunHistory?

    var body: some View {
        let history = history ?? WorkoutRunHistory(basis: .recentWorkouts, runs: [workout])
        let spacing: CGFloat = 10
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: spacing) {
                    ForEach(WorkoutStatMetric.allCases) { metric in
                        tile(metric, history: history)
                    }
                }
            } else {
                VStack(spacing: spacing) {
                    HStack(alignment: .top, spacing: spacing) {
                        tile(.volume, history: history)
                        tile(.duration, history: history)
                    }
                    HStack(alignment: .top, spacing: spacing) {
                        tile(.sets, history: history)
                        tile(.repetitions, history: history)
                    }
                }
            }
        }
        .onAppear {
            if self.history == nil {
                self.history = WorkoutRunHistory.compute(for: workout, database: database)
            }
        }
    }

    private func tile(_ metric: WorkoutStatMetric, history: WorkoutRunHistory) -> some View {
        Button {
            onOpenDetail(metric)
        } label: {
            WorkoutStatTile(
                metric: metric,
                workout: workout,
                history: history,
                pillColor: metric == .duration ? .secondary : dominantMuscleGroupColor,
                pillStyle: metric == .duration ? nil : muscleGroupStyle(startPoint: .leading, endPoint: .trailing),
                valueStyle: AnyShapeStyle(Color.label),
                currentBarStyle: AnyShapeStyle(Color.label)
            )
        }
        .buttonStyle(TileButtonStyle())
    }

    /// The workout's most-trained muscle group — the single-color tint passed to the shared tile
    /// layout as the trend pill's fallback behind its muscle-group gradient.
    private var dominantMuscleGroupColor: Color {
        muscleGroupService.getMuscleGroupOccurances(in: workout).first?.0.color ?? .accentColor
    }

    private func muscleGroupStyle(startPoint: UnitPoint, endPoint: UnitPoint) -> AnyShapeStyle {
        let colors = workout.muscleGroups.map(\.color)
        return AnyShapeStyle(.linearGradient(
            colors: colors.isEmpty ? [.accentColor] : colors,
            startPoint: startPoint,
            endPoint: endPoint
        ))
    }
}

// MARK: - Preview

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        ScrollView {
            WorkoutStatTileGrid(workout: database.testWorkout) { _ in }
                .padding(.horizontal)
        }
    }
}

struct WorkoutStatTiles_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
