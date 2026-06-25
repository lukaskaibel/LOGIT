//
//  ExerciseMetricTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.06.26.
//

import Charts
import SwiftUI

// MARK: - Trend

/// The numbers behind a metric tile's trend pill: the exercise's current best (the value the tile
/// shows), the last execution's change versus the execution before it (the pill's percent), and
/// whether that current best stands at the exercise's all-time best (the pill's trophy).
///
/// Sets of the workout currently being recorded must be filtered out by the caller — the tiles
/// tell the standing *before* this session (the in-workout badge tells the live story), and a
/// baseline that moved with every entered set couldn't be a baseline.
struct ExerciseTileTrend {
    /// Best value within the current-best window (see `Exercise.currentBestWindowStart`) — the
    /// value the tile displays. Nil when no set in the window has a usable value.
    let currentBest: Int?
    /// Percent change of the current best over the *previous* current best — the best value in the
    /// four weeks before the day the current best was reached (sliding back to the most recent
    /// earlier window with data after a gap). "How much better your peak is than it used to be."
    /// Nil only while the exercise is lapsed, or the current best is a first-ever execution with
    /// nothing before it to compare; the pill is hidden then.
    let percentChange: Double?
    /// True while the current best *is* the all-time best — "you're at your peak right now".
    /// Requires a usable value from before the window: with no older history there is no record
    /// to be at, and every first-month value would wear a trophy on day one.
    let isAtAllTimeBest: Bool
    /// Best value across the exercise's whole history — the tile's fallback when the window is
    /// empty (untrained for over a month). Nil when no set has a usable value for this metric.
    let allTimeBest: Int?

    init(sets: [WorkoutSet], value: (WorkoutSet) -> Int) {
        let windowStart = Exercise.currentBestWindowStart
        let calendar = Calendar.current

        var currentMax = 0
        var allTimeMax = 0
        var hasValueBeforeWindow = false
        // The day the current best was first reached — the anchor the previous-best window sits
        // before. Tracked as the earliest day at the peak so a later equal day can't hide the climb.
        var currentBestDate: Date?
        for workoutSet in sets {
            let setValue = value(workoutSet)
            guard setValue > 0 else { continue }
            allTimeMax = max(allTimeMax, setValue)
            let date = workoutSet.workout?.date ?? .distantPast
            if date >= windowStart {
                let day = calendar.startOfDay(for: date)
                if setValue > currentMax {
                    currentMax = setValue
                    currentBestDate = day
                } else if setValue == currentMax, let best = currentBestDate, day < best {
                    currentBestDate = day
                }
            } else {
                hasValueBeforeWindow = true
            }
        }

        currentBest = currentMax > 0 ? currentMax : nil
        allTimeBest = allTimeMax > 0 ? allTimeMax : nil
        isAtAllTimeBest = currentMax > 0 && hasValueBeforeWindow && currentMax == allTimeMax

        // Trend pill: the current best versus the previous current best — the best in the four weeks
        // before it was reached. A lapsed exercise (no current best) keeps its "time since" pill
        // instead; a first-ever best with nothing before it has nothing to compare and shows none.
        if currentMax > 0, let anchor = currentBestDate,
           let previousBest = Self.previousBest(before: anchor, sets: sets, value: value) {
            percentChange = (Double(currentMax) - Double(previousBest)) / Double(previousBest) * 100
        } else {
            percentChange = nil
        }
    }

    /// The previous current best: the highest value in the month before `anchor` (the day the
    /// current best was reached), excluding that day. When that month holds no training, slides back
    /// to the most recent earlier session and takes the month ending at it, so a gap before the
    /// current best doesn't erase the comparison — the tiles' sibling of the chart screens'
    /// `exerciseWindowTrendPercentage` slide-back. Nil only with no earlier history at all.
    private static func previousBest(before anchor: Date, sets: [WorkoutSet], value: (WorkoutSet) -> Int) -> Int? {
        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .month, value: -1, to: anchor) ?? anchor
        let inWindow = sets.filter {
            let date = $0.workout?.date ?? .distantPast
            return date >= windowStart && date < anchor
        }
        if let best = inWindow.map(value).filter({ $0 > 0 }).max() { return best }
        // The month before the current best was empty: slide back to the most recent earlier
        // session and take the month ending at it.
        guard let lastPrior = sets.compactMap({ $0.workout?.date }).filter({ $0 < windowStart }).max() else {
            return nil
        }
        let slideStart = calendar.date(byAdding: .month, value: -1, to: lastPrior) ?? lastPrior
        let slid = sets.filter {
            let date = $0.workout?.date ?? .distantPast
            return date >= slideStart && date <= lastPrior
        }
        return slid.map(value).filter { $0 > 0 }.max()
    }
}

// MARK: - Detail-screen Trend

/// Percent change of a metric across the visible chart window versus a comparable window before it
/// — the trend pill in the exercise stat screens' headers. When the window immediately before the
/// visible one holds no training, the baseline slides back to the most recent equally-long window
/// that does, so the pill stays present whenever there's any earlier history instead of vanishing
/// after a gap. A sibling of the tiles' previous-month → earlier-history fallback (and the workout
/// detail's previous-runs → recent fallback). `aggregate(start, end)` reduces the metric over
/// `[start, end]` to one comparable number — a best for "max" metrics, a total for weekly sums —
/// returning nil when that span has nothing to compare.
///
/// `emptyCurrentMeansDecline` decides what an empty *current* window means. For a "max" metric an
/// empty window has simply nothing to plot — leave it off and the pill hides. For a cumulative
/// metric (volume, sets) an empty window genuinely did zero work, so turn it on: once there's a
/// baseline to fall from, that's a real "down 100%" reported rather than hidden.
func exerciseWindowTrendPercentage(
    sets: [WorkoutSet],
    windowStart: Date,
    windowSeconds: Int,
    emptyCurrentMeansDecline: Bool = false,
    aggregate: (_ start: Date, _ end: Date) -> Double?
) -> Double? {
    let calendar = Calendar.current
    let windowEnd = calendar.date(byAdding: .second, value: windowSeconds, to: windowStart) ?? windowStart
    let current = aggregate(windowStart, windowEnd) ?? 0
    if current <= 0 && !emptyCurrentMeansDecline { return nil }
    let priorStart = calendar.date(byAdding: .second, value: -windowSeconds, to: windowStart) ?? windowStart
    var baseline = aggregate(priorStart, windowStart)
    if baseline == nil || baseline == 0 {
        // Nothing in the immediately-preceding window: slide back to the last window that has any
        // training, so a gap before the visible range doesn't hide the trend.
        if let lastPriorDate = sets.compactMap({ $0.workout?.date }).filter({ $0 < windowStart }).max() {
            let slideStart = calendar.date(byAdding: .second, value: -windowSeconds, to: lastPriorDate) ?? lastPriorDate
            baseline = aggregate(slideStart, lastPriorDate)
        }
    }
    guard let baseline, baseline > 0 else { return nil }
    return (current - baseline) / baseline * 100
}

/// The exercise chart headers' comparison baseline: the best value in the visible window *other than*
/// the current best, so the header pill measures the current best against the rest of the shown
/// period instead of against itself when the peak is on screen. `currentBestDay` — the day the
/// current best was reached — is excluded from the window. When the window holds no other value, the
/// baseline falls back to the most recent day's best before it; nil only when there's nothing earlier
/// to compare against either. `value` extracts the per-set metric (a max for these screens).
func exerciseOtherBestBaseline(
    sets: [WorkoutSet],
    windowStart: Date,
    windowEnd: Date,
    currentBestDay: Date?,
    value: (WorkoutSet) -> Int
) -> Int? {
    let calendar = Calendar.current
    let otherInWindow = sets.filter { set in
        guard let date = set.workout?.date, date >= windowStart, date <= windowEnd else { return false }
        if let currentBestDay, calendar.isDate(date, inSameDayAs: currentBestDay) { return false }
        return value(set) > 0
    }
    if let best = otherInWindow.map(value).max(), best > 0 { return best }
    // No other value in the shown window: the most recent day's best before it.
    let prior = sets.filter { set in
        guard let date = set.workout?.date, date < windowStart else { return false }
        return value(set) > 0
    }
    guard let lastDate = prior.compactMap({ $0.workout?.date }).max() else { return nil }
    return prior
        .filter { calendar.isDate($0.workout?.date ?? .distantPast, inSameDayAs: lastDate) }
        .map(value)
        .max()
}

// MARK: - Ghost Sparkline

/// The empty states' placeholder artwork: a dashed, muted curve rising toward a single
/// muscle-tinted point — the chart that isn't there yet. Shared by the per-metric placeholder
/// inside a tile and the whole-screen empty tile.
struct GhostSparkline: View {
    let color: Color

    /// Fraction of the height where the curve (and its end dot) tops out.
    private static let endHeightFraction: CGFloat = 0.16
    /// Inset keeping the end dot's symbol inside the frame.
    private static let endInset: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let end = CGPoint(
                x: size.width - Self.endInset,
                y: size.height * Self.endHeightFraction + 3
            )
            GhostCurve(end: end)
                .stroke(Color.fill, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 7]))
            Circle()
                .frame(width: 6, height: 6)
                .foregroundStyle(color.gradient)
                .overlay {
                    Circle()
                        .frame(width: 2, height: 2)
                        .foregroundStyle(Color.black)
                }
                .position(end)
        }
        .accessibilityHidden(true)
    }

    private struct GhostCurve: Shape {
        let end: CGPoint

        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.72))
            path.addCurve(
                to: CGPoint(x: rect.width * 0.48, y: rect.height * 0.52),
                control1: CGPoint(x: rect.width * 0.18, y: rect.height * 0.80),
                control2: CGPoint(x: rect.width * 0.32, y: rect.height * 0.40)
            )
            path.addCurve(
                to: end,
                control1: CGPoint(x: rect.width * 0.66, y: rect.height * 0.68),
                control2: CGPoint(x: rect.width * 0.84, y: rect.height * 0.24)
            )
            return path
        }
    }
}

// MARK: - Sparkline

/// The compact progression chart under a tile's value — the popover's recipe (line + area in the
/// muscle-group color, daily-best points, dashed carry-forward since the last session, faded
/// leading edge, hidden axes) over the current-best window, so the chart shows exactly the
/// history the value above it comes from.
struct ExerciseTileSparkline: View {
    /// One daily-best point — the shared tile-sparkline point type, kept under this name so the
    /// metric tiles and the personal-record card can go on building `ExerciseTileSparkline.Point`.
    typealias Point = TileSparklinePoint

    enum Window {
        /// The current-best month, dashed carry-forward to today — the default while the window
        /// has data.
        case currentBest
        /// The last few trained sessions, however long ago — the fallback when the month is
        /// empty. An empty month would render as nothing but the dashed carry-forward line;
        /// showing the sessions the personal best comes from tells a story instead.
        case recentHistory
        /// The exercise's entire history, first session to last, as a single clean line — no
        /// per-session dots and no crest marker, just the smooth arc. It spans the full width edge
        /// to edge and skips the leading fade, so the curve reads end to end. Used on the
        /// personal-records cards, where it bleeds to the card's borders beneath the scoreboard.
        case allTime
    }

    /// Daily-best points, oldest → newest. May extend past the window: the domain clips, and the
    /// surplus lets the line enter from the left edge instead of starting mid-chart.
    let points: [Point]
    let color: Color
    var window: Window = .currentBest
    /// Chart height. Taller suits the all-time window, where the full history needs room to read.
    var height: CGFloat = 56

    /// How many sessions the recent-history window shows.
    private static let recentHistoryCount = 6

    /// The chart's x-domain. Windowed sparklines push the trailing edge ~2 days past the last shown
    /// moment so the latest point's symbol clears the right edge (they are `.clipped()` with no
    /// trailing fade, and a point on the edge would be sliced in half). The all-time line carries no
    /// symbols to protect, so it fills the width exactly — first session to last, edge to edge.
    private func xDomain() -> ClosedRange<Date> {
        let margin: (Date) -> Date = { Calendar.current.date(byAdding: .day, value: 2, to: $0) ?? $0 }
        switch window {
        case .currentBest:
            return Exercise.currentBestWindowStart ... margin(.now)
        case .recentHistory:
            let shown = points.suffix(Self.recentHistoryCount)
            guard let first = shown.first?.date, let last = shown.last?.date else {
                return Exercise.currentBestWindowStart ... margin(.now)
            }
            let lead = Calendar.current.date(byAdding: .day, value: -2, to: first) ?? first
            return lead ... margin(last)
        case .allTime:
            guard let first = points.first?.date, let last = points.last?.date, first < last else {
                // A single session: center it on a one-day window so the line has somewhere to sit.
                let anchor = points.first?.date ?? .now
                let lead = Calendar.current.date(byAdding: .day, value: -1, to: anchor) ?? anchor
                let trail = Calendar.current.date(byAdding: .day, value: 1, to: anchor) ?? anchor
                return lead ... trail
            }
            return first ... last
        }
    }

    var body: some View {
        let maxValue = points.map(\.value).max() ?? 1
        // Over a long span catmullRom waggles between sessions; monotone keeps the all-time line a
        // clean trend that never overshoots its own crest.
        let interpolation: InterpolationMethod = window == .allTime ? .monotone : .catmullRom
        let base = Chart {
            tileSparklineMarks(
                points: points,
                color: color,
                interpolation: interpolation,
                // The all-time line is a single clean curve — no per-session dots, no crest marker.
                // The windowed sparklines keep a dot per session.
                showsSymbols: window != .allTime,
                showsCarryForward: window == .currentBest
            )
        }
        .chartXScale(domain: xDomain())
        .chartYScale(domain: 0 ... max(maxValue * 1.15, 1))
        .chartXAxis {}
        .chartYAxis {}
        .frame(maxWidth: .infinity)
        .frame(height: height)
        // The all-time window spans the full width and skips `.clipped()` and the leading fade — its
        // whole point is to show where the history begins and ends — but it still fades its area out
        // at the bottom so the full-bleed fill melts into the card border instead of being clipped
        // while still tinted. The windowed sparklines clip and fade in from the left (and bottom).
        if window == .allTime {
            base.tileSparklineBottomFadeMask()
        } else {
            base.clipped().tileSparklineFadeMask()
        }
    }
}

// MARK: - Current Best Tile

/// One of the four "current best" tiles (weight, e1RM, repetitions, set volume) on the exercise
/// detail screen. Sets of the workout currently being recorded are excluded from everything —
/// value, pill, and chart — so the whole tile tells one consistent story: where you stood going
/// into this session.
struct ExerciseBestMetricTile: View {
    let exercise: Exercise
    let workoutSets: [WorkoutSet]
    let title: String
    let unit: String
    /// Pro-gates the tile's data (see `MetricTile.requiresPro`).
    var requiresPro: Bool = false
    /// The metric's base value of a single set, in raw storage units (grams for weights).
    let metricValue: (WorkoutSet) -> Int
    /// Display string for a base value (handles unit conversion).
    let formattedValue: (Int) -> String
    /// Chart y-value for a base value (handles unit conversion).
    let chartValue: (Int) -> Double

    var body: some View {
        let sets = workoutSets.filter { $0.workout?.isCurrentWorkout != true }
        let trend = ExerciseTileTrend(sets: sets, value: metricValue)
        let color = exercise.muscleGroup?.color ?? .accentColor
        let points = dailyBestPoints(in: sets)
        // Untrained for over a month: the window has nothing to show, but the history does —
        // fall back to the all-time personal best over the last sessions' chart (with the
        // "time since" capsule in the pill slot) instead of a "––" floating above an empty month.
        let isLapsed = trend.currentBest == nil && trend.allTimeBest != nil
        MetricTile(
            title: title,
            label: isLapsed ? .plain(NSLocalizedString("personalBest", comment: "")) : .currentBest,
            value: (trend.currentBest ?? trend.allTimeBest).map(formattedValue),
            unit: unit,
            accent: AnyShapeStyle(color),
            accentColor: color,
            percentChange: trend.percentChange,
            isRecord: trend.isAtAllTimeBest,
            requiresPro: requiresPro,
            lapsedSince: isLapsed ? points.last?.date : nil,
            showsEmptyPlaceholder: trend.allTimeBest == nil
        ) {
            ExerciseTileSparkline(
                points: points,
                color: color,
                window: isLapsed ? .recentHistory : .currentBest,
                height: CompactChartFrame.height
            )
        }
    }

    private func dailyBestPoints(in sets: [WorkoutSet]) -> [ExerciseTileSparkline.Point] {
        let grouped = Dictionary(grouping: sets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }
        return grouped.compactMap { day, daySets -> ExerciseTileSparkline.Point? in
            let best = daySets.map(metricValue).max() ?? 0
            guard best > 0 else { return nil }
            return ExerciseTileSparkline.Point(date: day, value: chartValue(best))
        }
        .sorted { $0.date < $1.date }
    }
}

// MARK: - Empty State

/// Full-width placeholder that replaces the whole metric-tile grid while an exercise has no
/// logged sets — five identical "––" skeletons would say "no data" five times; one friendly tile
/// says it once and tells the user how to change it. Not a button: there is nothing to navigate
/// to yet. The ghost sparkline sketches the chart that will appear, its single tinted point the
/// first entry that isn't logged yet.
struct ExerciseMetricsEmptyTile: View {
    let color: Color

    var body: some View {
        VStack(spacing: 18) {
            GhostSparkline(color: color)
                .frame(width: 200, height: 52)
                .padding(.top, 6)
            VStack(spacing: 3) {
                Text(NSLocalizedString("noExerciseDataTitle", comment: ""))
                    .font(.headline)
                    .foregroundStyle(Color.label)
                Text(NSLocalizedString("noExerciseDataMessage", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(CELL_PADDING)
        .tileStyle()
    }
}

// MARK: - Current Best Label

/// The "Current Best" stat label on the exercise-detail metric tiles, with a small info button
/// that explains how the value is calculated (best of the last month). Shared by
/// the e1RM, weight, and repetitions tiles, and — in its uppercased variant, which matches their
/// "BEST" header style — by the metric chart screens while they show the current-best window.
struct CurrentBestLabel: View {
    /// Chart-screen header style (uppercase, medium) instead of the tiles' semibold style.
    var uppercased: Bool = false
    @State private var isShowingInfo = false

    var body: some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString("currentBest", comment: ""))
                .fontWeight(uppercased ? .medium : .semibold)
                .textCase(uppercased ? .uppercase : nil)
            Button {
                isShowingInfo = true
            } label: {
                Image(systemName: "info.circle")
            }
            .popover(isPresented: $isShowingInfo) {
                Text(NSLocalizedString("currentBestInfo", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding()
                    .frame(width: 300)
                    .presentationCompactAdaptation(.popover)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        let exercise = database.getExercises().first!
        HStack(alignment: .top, spacing: 10) {
            ExerciseBestMetricTile(
                exercise: exercise,
                workoutSets: exercise.sets,
                title: NSLocalizedString("weight", comment: ""),
                unit: WeightUnit.used.rawValue,
                metricValue: { $0.maximum(.weight, for: exercise) },
                formattedValue: { formatWeightForDisplay($0) },
                chartValue: { convertWeightForDisplayingDecimal($0) }
            )
            ExerciseBestMetricTile(
                exercise: exercise,
                workoutSets: exercise.sets,
                title: NSLocalizedString("repetitions", comment: ""),
                unit: NSLocalizedString("rps", comment: ""),
                metricValue: { $0.maximum(.repetitions, for: exercise) },
                formattedValue: { String($0) },
                chartValue: { Double($0) }
            )
        }
        .padding()
    }
}

struct ExerciseMetricTile_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
