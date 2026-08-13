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
    /// doesn't have. `compact` (the tiles, where width is tight) additionally drops a count's decimal
    /// once it reaches 1000 — a fractional part is noise at that scale and would overflow the tile.
    func formattedAverage(rawAverage: Double, compact: Bool = false) -> String {
        switch self {
        case .volume: return String(Int(convertWeightForDisplayingDecimal(Int(rawAverage.rounded())).rounded()))
        case .duration: return formattedWorkoutDuration(minutes: Int(rawAverage.rounded()))
        case .sets, .repetitions: return Self.formatAverageNumber(rawAverage, compact: compact)
        }
    }

    /// "18.5"-style average formatting — at most one decimal, none when whole. `compact` drops the
    /// decimal entirely at 1000+, where it's noise and the extra glyphs overflow a tile ("1,234" not
    /// "1,234.5").
    private static func formatAverageNumber(_ value: Double, compact: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = (compact && value >= 1000) ? 0 : 1
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
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
    workoutSet.entryValues.reduce(0) { $0 + Int($1.repetitions) }
}

// MARK: - Run History

/// The comparison basis behind a stat tile's bars: a run of sessions, oldest → newest, with the
/// session the tile is about last. One basis for a whole grid, so its four tiles can never disagree
/// about what "vs. last time" means.
///
/// The workout detail's grid takes the *last eight workouts of any kind* ending with this one —
/// the same eight its detail screens draw on their run axis, so tapping a tile never changes which
/// sessions you are being compared against. The template detail builds its own history from that
/// template's sessions instead, where a like-for-like previous run genuinely exists.
struct WorkoutRunHistory {
    enum Basis {
        /// Previous runs of this same workout — the pill compares against the immediately
        /// previous run, a precise like-for-like. The template detail's grid.
        case sameWorkout
        /// Consecutive workouts of any kind — the pill compares against the *average* of the runs
        /// shown, this session included, which is exactly the number the detail screen's scoreboard
        /// carries for the same window. A single unrelated session (push vs. legs) can't swing it
        /// the way a like-for-like comparison against one workout would.
        case recentWorkouts
    }

    /// Workouts in a workout-detail comparison — the tile's bars and the window its detail screen
    /// opens on are the same eight sessions. `WorkoutStatScreen` scrolls back through more of them;
    /// the tile just shows the window.
    static let windowCount = 8

    let basis: Basis
    /// Oldest → newest with the workout itself last; at most the chart's slot count.
    let runs: [Workout]

    func percentChange(for metric: WorkoutStatMetric) -> Double? {
        guard let current = runs.last.map({ metric.rawValue(of: $0) }), current > 0 else { return nil }
        // Sessions with no value for this metric (a workout with no recorded end, on duration)
        // don't count — the same rule the detail screen's axis applies by not giving them a bar.
        let priorValues = runs.dropLast().map { metric.rawValue(of: $0) }.filter { $0 > 0 }
        guard !priorValues.isEmpty else { return nil }
        let baseline: Double
        switch basis {
        case .sameWorkout:
            guard let previous = runs.dropLast().last.map({ metric.rawValue(of: $0) }),
                  previous > 0 else { return nil }
            baseline = Double(previous)
        case .recentWorkouts:
            baseline = Double(priorValues.reduce(0, +) + current) / Double(priorValues.count + 1)
        }
        return (Double(current) - baseline) / baseline * 100
    }

    /// The window behind the workout detail's grid: this workout and the seven logged before it,
    /// whatever they were. Opening an older workout takes the seven before *it*, so the tile always
    /// shows the same eight bars its detail screen opens on.
    static func compute(for workout: Workout, database: Database) -> WorkoutRunHistory {
        guard let workoutDate = workout.date else {
            return WorkoutRunHistory(basis: .recentWorkouts, runs: [workout])
        }
        let previous = recentWorkouts(
            before: workoutDate,
            excluding: workout,
            database: database,
            limit: windowCount - 1
        )
        return WorkoutRunHistory(basis: .recentWorkouts, runs: previous.reversed() + [workout])
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

/// The mini bar chart under a stat tile's value: this session against the ones before it, one bar
/// per run in a fixed frame (bars keep the same width however little history there is, and the
/// newest run is always rightmost). Only the current run's bar is drawn in `currentStyle` — the
/// tile's accent — every earlier one stays quiet gray, whichever comparison basis is behind it (the
/// label's info button spells the basis out). Short, wide, softly-rounded bars.
struct WorkoutRunsBarChart: View {
    struct Bar: Identifiable {
        let slot: Int
        let value: Double
        /// The current workout's bar — drawn with `currentStyle`; previous runs stay gray.
        let isCurrent: Bool
        var id: Int { slot }
    }

    /// Slots for the strips that show five things: the Summary's period buckets and the template
    /// detail's recent sessions. The workout detail's tiles pass `WorkoutRunHistory.windowCount`
    /// instead — their bars are the same eight workouts their detail screens open on.
    static let defaultSlotCount = 5

    let bars: [Bar]
    let currentStyle: AnyShapeStyle
    /// Slots in the frame, however many bars arrive — what keeps the bar width fixed and lets a
    /// short history right-align instead of stretching across the tile.
    var slotCount: Int = defaultSlotCount

    var body: some View {
        let maxValue = bars.map(\.value).max() ?? 0
        Chart {
            ForEach(bars) { bar in
                if bar.value > 0 {
                    BarMark(
                        x: .value("Run", String(bar.slot)),
                        y: .value("Value", bar.value),
                        width: TileBarChartStyle.footerBarWidth
                    )
                    .foregroundStyle(bar.isCurrent ? currentStyle : AnyShapeStyle(Color.fill))
                    .tileBarStyle()
                }
            }
        }
        .chartXScale(domain: (0 ..< slotCount).map(String.init))
        .chartYScale(domain: 0 ... max(maxValue, 1))
        .chartXAxis {}
        .chartYAxis {}
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

/// One compact session stat on the workout detail — the shared metric tile with the workout
/// vocabulary: "This Workout" over a neutral value, the trend pill wearing the workout's
/// muscle-group gradient on a gain, and the run bars in the corner with this workout's bar in that
/// same gradient. The duration tile stays neutral gray in both directions — a longer workout is
/// neither better nor worse.
struct WorkoutStatTile: View {
    let metric: WorkoutStatMetric
    let workout: Workout
    let history: WorkoutRunHistory
    /// Tints the trend pill — the workout's muscle-group gradient on a diagonal (text reads
    /// diagonally), or neutral gray on the duration tile.
    let accent: AnyShapeStyle
    /// Tints the current workout's run bar — the same muscle-group gradient as `accent` but running
    /// vertically (bars read bottom-to-top), or neutral gray on the duration tile.
    let barStyle: AnyShapeStyle
    /// The flat-color form of `accent`, for the pill's non-gradient fallback and the ghost dot.
    let accentColor: Color

    var body: some View {
        let raw = metric.rawValue(of: workout)
        MetricTile(
            title: metric.title,
            label: .info(
                NSLocalizedString("thisWorkout", comment: ""),
                // The copy names the window's size, so it takes the count rather than spelling
                // "eight" out in eight languages that would then quietly go stale.
                explanation: String(
                    format: NSLocalizedString("workoutStatCompareRecentInfo", comment: ""),
                    WorkoutRunHistory.windowCount
                )
            ),
            value: raw > 0 ? metric.formattedValue(fromRaw: raw) : nil,
            unit: metric.unit,
            accent: accent,
            accentColor: accentColor,
            percentChange: history.percentChange(for: metric),
            isRecord: false,
            requiresPro: metric.requiresPro,
            chartBleeds: false
        ) {
            WorkoutRunsBarChart(bars: runBars, currentStyle: barStyle, slotCount: WorkoutRunHistory.windowCount)
        }
    }

    /// Right-aligned into the chart's fixed slots: the newest run sits in the last slot however
    /// few runs there are. Runs without a usable value keep their slot as a gap.
    private var runBars: [WorkoutRunsBarChart.Bar] {
        let offset = WorkoutRunHistory.windowCount - history.runs.count
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
        let isDuration = metric == .duration
        let sets = workout.sets
        return Button {
            onOpenDetail(metric)
        } label: {
            WorkoutStatTile(
                metric: metric,
                workout: workout,
                history: history,
                accent: isDuration ? AnyShapeStyle(Color.secondary) : sets.muscleGroupGradientStyle(startPoint: .bottomLeading, endPoint: .topTrailing),
                barStyle: isDuration ? AnyShapeStyle(Color.secondary) : sets.muscleGroupGradientStyle(startPoint: .bottom, endPoint: .top),
                accentColor: isDuration ? .secondary : dominantMuscleGroupColor
            )
        }
        .buttonStyle(TileButtonStyle())
    }

    /// The workout's most-trained muscle group — the single-color tint passed to the shared tile
    /// layout as the trend pill's fallback behind its muscle-group gradient.
    private var dominantMuscleGroupColor: Color {
        muscleGroupService.getMuscleGroupOccurances(in: workout).first?.0.color ?? .accentColor
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
