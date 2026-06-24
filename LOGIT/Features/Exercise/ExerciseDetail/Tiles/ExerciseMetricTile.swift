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
    /// Percent change of the last execution (the most recent training day's best) over the
    /// execution before it — "how last time went versus the time before". Nil while the exercise is
    /// lapsed or has fewer than two executions to compare; the pill is hidden then.
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
        // Best value per training day — one day is one "execution", used for the day-over-day pill.
        var bestByDay: [Date: Int] = [:]
        for workoutSet in sets {
            let setValue = value(workoutSet)
            guard setValue > 0 else { continue }
            allTimeMax = max(allTimeMax, setValue)
            let date = workoutSet.workout?.date ?? .distantPast
            if date >= windowStart {
                currentMax = max(currentMax, setValue)
            } else {
                hasValueBeforeWindow = true
            }
            let day = calendar.startOfDay(for: date)
            bestByDay[day] = max(bestByDay[day] ?? 0, setValue)
        }

        currentBest = currentMax > 0 ? currentMax : nil
        allTimeBest = allTimeMax > 0 ? allTimeMax : nil
        isAtAllTimeBest = currentMax > 0 && hasValueBeforeWindow && currentMax == allTimeMax

        // Trend pill: the last execution (most recent training day's best) versus the execution
        // before it — "how last time went versus the time before". Shown only while the exercise is
        // active (a value in the current-best window); a lapsed exercise keeps its "time since"
        // pill instead. Needs two executions to compare.
        let executions = bestByDay.keys.sorted()
        if currentMax > 0, executions.count >= 2,
           let last = bestByDay[executions[executions.count - 1]],
           let previous = bestByDay[executions[executions.count - 2]],
           previous > 0 {
            percentChange = (Double(last) - Double(previous)) / Double(previous) * 100
        } else {
            percentChange = nil
        }
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

// MARK: - Tile Skeleton

/// Shared skeleton of the exercise-detail metric tiles — the in-workout popover's column anatomy
/// at tile size: title row with the trend pill top-right (where the navigation chevron used to
/// sit; like the popover, the content itself is the invitation to tap), the metric's label over
/// its large value in the muscle-group tint, and the chart beneath running the full tile width.
/// One skeleton for every tile so tiles sharing a grid row always come out the same height.
struct ExerciseMetricTileLayout<ChartContent: View>: View {
    enum Label {
        case currentBest
        case plain(String)
        /// A plain label with an info button explaining the value — `CurrentBestLabel`'s anatomy
        /// with free-form texts; the workout stat tiles explain their comparison basis this way.
        case info(String, explanation: String)
    }

    @EnvironmentObject private var purchaseManager: PurchaseManager

    let title: String
    let label: Label
    /// Nil renders the "––" placeholder.
    let value: String?
    let unit: String
    let color: Color
    let percentChange: Double?
    let isRecord: Bool
    /// Gates the tile's data — pill, label, value, and chart — behind Pro (blur + compact crown;
    /// the full capsule doesn't fit a half-width tile). The title stays readable so a locked tile
    /// still says what it is. Mirrors the in-workout panel's gating: repetitions is the free
    /// metric, everything else is Pro data.
    var requiresPro: Bool = false
    /// Style of the value text. Defaults to `color.gradient`; the workout stat tiles pass
    /// `Color.label` for a plain label-colored value (their muscle tint moves to the trend pill).
    var valueStyle: AnyShapeStyle? = nil
    /// Color for the unit alone, overriding `valueStyle` for it — the workout stat tiles render a
    /// label-colored value with a muted unit. Nil lets the unit inherit the value style (the
    /// exercise tiles' muscle-tinted unit).
    var unitColor: Color? = nil
    /// Style for the trend pill's positive tint, overriding `color` — the workout stat tiles pass
    /// the workout's muscle-group gradient. Nil keeps the pill tinted in `color`.
    var trendStyle: AnyShapeStyle? = nil
    /// Last session this tile's metric has a value from, when that session is older than the
    /// current-best window. Renders the gray "time since" capsule in the trend pill's slot, so a
    /// paused exercise says so at a glance instead of impersonating an active one.
    var lapsedSince: Date? = nil
    /// Swaps label, value, and chart for the centered ghost placeholder — for tiles whose metric
    /// has no usable data at all (the weight tiles of a bodyweight exercise). The stats block
    /// keeps rendering hidden underneath so the tile stays exactly as tall as its row neighbor.
    var showsEmptyPlaceholder: Bool = false
    @ViewBuilder let chart: () -> ChartContent

    private var locksData: Bool { requiresPro && !purchaseManager.hasUnlockedPro }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.label)
                    .lineLimit(1)
                    // Next to a wide pill ("↓ 58 %", "vor 2 Mon.") a long title ("Satzvolumen")
                    // comes up short of its space — shrink it rather than ellipsize.
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 6)
                // The hidden trend pill is the row's height ruler in every state — with a shorter
                // lapsed pill or no pill at all, the tile would otherwise end up shorter than its
                // row neighbor.
                ZStack(alignment: .trailing) {
                    TrendIndicatorView(percentChange: 0, positiveColor: color, positiveStyle: trendStyle)
                        .hidden()
                    if let percentChange, !locksData {
                        TrendIndicatorView(
                            percentChange: percentChange,
                            positiveColor: color,
                            positiveStyle: trendStyle,
                            isRecord: isRecord
                        )
                    } else if let lapsedSince, !showsEmptyPlaceholder {
                        TileLapsedPill(date: lapsedSince)
                    }
                }
            }
            if showsEmptyPlaceholder {
                ZStack {
                    statsBlock.hidden()
                    VStack(spacing: 10) {
                        GhostSparkline(color: color)
                            .frame(width: 90, height: 30)
                        Text(NSLocalizedString("noData", comment: ""))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                statsBlock
                    .isBlockedWithoutPro(requiresPro, style: .compact)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CELL_PADDING)
        .tileStyle()
    }

    private var statsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch label {
                case .currentBest:
                    CurrentBestLabel()
                case let .plain(text):
                    Text(text)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                case let .info(text, explanation):
                    MetricTileInfoLabel(text: text, explanation: explanation)
                }
            }
            .padding(.top, 8)
            UnitView(value: value ?? "––", unit: unit, configuration: .large, unitColor: unitColor)
                .foregroundStyle(valueStyle ?? AnyShapeStyle(color.gradient))
                .padding(.top, 2)
            chart()
                .padding(.top, 8)
        }
    }
}

/// The gray "time since the last session" capsule in the trend pill's slot on lapsed tiles —
/// the trend pill's anatomy (icon + rounded bold text on a 0.15 fill) with the history icon and
/// a relative date, so the stale state is visible right where the trend usually lives. A size
/// softer than the trend pill: it's quiet metadata, not a score.
private struct TileLapsedPill: View {
    let date: Date

    var body: some View {
        ProgressIndicatorPill(symbol: "clock.arrow.circlepath", color: .secondary, size: .compact) {
            Text(date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                .font(.system(.caption2, design: .rounded, weight: .bold))
        }
        // The pill never compresses or wraps — the title next to it shrinks instead.
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date, format: .relative(presentation: .named)))
    }
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
        /// The exercise's entire history, first session to last. The line drops its per-point
        /// dots (too many to read) and marks only the highest point, so the all-time best stands
        /// out as the crest of the whole story — used on the personal-records screen.
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

    /// Trailing edge ~2 days past the last shown moment so the latest point's symbol clears the
    /// right edge — the chart is `.clipped()` with no trailing fade, and a point on the edge
    /// would be sliced in half.
    private var domain: ClosedRange<Date> {
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
            guard let first = points.first?.date, let last = points.last?.date else {
                return Exercise.currentBestWindowStart ... margin(.now)
            }
            let lead = Calendar.current.date(byAdding: .day, value: -2, to: first) ?? first
            return lead ... margin(last)
        }
    }

    var body: some View {
        let maxValue = points.map(\.value).max() ?? 1
        // Over a long span catmullRom waggles between sessions; monotone keeps the all-time line a
        // clean trend that never overshoots its own crest.
        let interpolation: InterpolationMethod = window == .allTime ? .monotone : .catmullRom
        // The all-time window dots only its crest (the rest would be a cluttered string of points);
        // the shorter windows dot every session.
        let recordPoint = window == .allTime ? points.max(by: { $0.value < $1.value }) : nil
        let chart = Chart {
            tileSparklineMarks(
                points: points,
                color: color,
                interpolation: interpolation,
                showsSymbols: window != .allTime,
                showsCarryForward: window == .currentBest,
                recordPoint: recordPoint
            )
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0 ... max(maxValue * 1.15, 1))
        .chartXAxis {}
        .chartYAxis {}
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        // The all-time window's whole point is to show the start of the history — a leading fade
        // would swallow it, so it draws edge to edge; the windowed sparklines fade in.
        if window == .allTime {
            chart
        } else {
            chart.tileSparklineFadeMask()
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
    /// Pro-gates the tile's data (see `ExerciseMetricTileLayout.requiresPro`).
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
        ExerciseMetricTileLayout(
            title: title,
            label: isLapsed ? .plain(NSLocalizedString("personalBest", comment: "")) : .currentBest,
            value: (trend.currentBest ?? trend.allTimeBest).map(formattedValue),
            unit: unit,
            color: color,
            percentChange: trend.percentChange,
            isRecord: trend.isAtAllTimeBest,
            requiresPro: requiresPro,
            lapsedSince: isLapsed ? points.last?.date : nil,
            showsEmptyPlaceholder: trend.allTimeBest == nil
        ) {
            ExerciseTileSparkline(
                points: points,
                color: color,
                window: isLapsed ? .recentHistory : .currentBest
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

/// Backs `ExerciseMetricTileLayout.Label.info` — `CurrentBestLabel`'s text + info-dot anatomy with
/// the texts supplied by the tile (the workout stat tiles explain their comparison basis here).
private struct MetricTileInfoLabel: View {
    let text: String
    let explanation: String
    @State private var isShowingInfo = false

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .fontWeight(.semibold)
            Button {
                isShowingInfo = true
            } label: {
                Image(systemName: "info.circle")
            }
            .popover(isPresented: $isShowingInfo) {
                Text(explanation)
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
