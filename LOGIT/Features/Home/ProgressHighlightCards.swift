//
//  ProgressHighlightCards.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.07.26.
//

import SwiftUI

// MARK: - Shared card metrics

/// Every highlight card is exactly this tall, whatever its content — a uniform carousel scrolls as
/// one calm strip instead of a skyline.
let HIGHLIGHT_CARD_HEIGHT: CGFloat = 200
/// Carousel card width; the remainder of the screen peeks the next card as the scroll affordance.
let HIGHLIGHT_CARD_WIDTH: CGFloat = 300

// MARK: - Carousel

/// The Summary's Highlights carousel: uniform-height cards, view-aligned paging, the next
/// card peeking. Clipping is disabled so cards sweep the full screen width while scrolling even
/// though the carousel sits inside the screen's horizontal padding.
struct ProgressHighlightsCarousel: View {
    let items: [ProgressHighlight]

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                ForEach(items) { item in
                    ProgressHighlightCardView(item: item, width: HIGHLIGHT_CARD_WIDTH)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

// MARK: - Card dispatch

/// One highlight as a tappable card: dispatches to the best-card or comparison-card face and pushes
/// the screen that proves the highlight — an exercise detail, a stat chart, the goal screen.
struct ProgressHighlightCardView: View {
    let item: ProgressHighlight
    /// Fixed width in the carousel; nil fills the available width (the See-All list).
    var width: CGFloat? = nil

    @EnvironmentObject private var homeNavigationCoordinator: HomeNavigationCoordinator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button {
            homeNavigationCoordinator.path.append(destination)
        } label: {
            card
                .frame(width: width)
                // Uniform height is what makes the carousel scroll as one calm strip — but at
                // accessibility text sizes the content no longer fits it, so the cards size to
                // their content instead (uneven, and legible) the way `MetricTile` does.
                .frame(height: dynamicTypeSize.isAccessibilitySize ? nil : HIGHLIGHT_CARD_HEIGHT)
                .contentShape(Rectangle())
        }
        .buttonStyle(TileButtonStyle())
    }

    @ViewBuilder
    private var card: some View {
        switch item {
        case let .record(records):
            HighlightBestCard(
                records: records, subject: records.lead,
                milestoneStepBaseValue: nil, isCompact: isCompact
            )
        case let .milestone(records, subject, step):
            HighlightBestCard(
                records: records, subject: subject,
                milestoneStepBaseValue: step, isCompact: isCompact
            )
        case let .trend(trend):
            HighlightComparisonCard(content: .init(trend: trend))
        case let .yearCrossing(crossing):
            HighlightComparisonCard(content: .init(crossing: crossing))
        }
    }

    /// A fixed width means the carousel, where the scoreboard has to shrink; full width is the
    /// See-All list, where it wears the record card's own size.
    private var isCompact: Bool { width != nil }

    /// Where the card taps through to — always the screen where the highlight's chart lives.
    private var destination: HomeNavigationDestinationType {
        switch item {
        case let .record(records):
            return .exercise(records.exercise)
        case let .milestone(records, _, _):
            return .exercise(records.exercise)
        case let .trend(trend):
            switch trend.kind {
            case .muscleGroupSets: return .muscleGroupDetail(trend.muscleGroup ?? .chest, trend.window)
            case .exerciseVolume:
                if let exercise = trend.exercise { return .exercise(exercise) }
                // Pinned to the window the card itself compares over, which is now nameable exactly
                // — it used to open a calendar month, the nearest thing the old picker offered.
                return .summaryStat(.volume, ProgressHighlights.recentWindow)
            }
        case .yearCrossing:
            return .summaryStat(.volume, .oneYear)
        }
    }
}

// MARK: - Best card (record / milestone)

/// A recent best, wearing the personal-record card's anatomy so the same event reads the same way
/// wherever it appears: the muscle-tinted trophy badge leading the exercise and metric, the dated
/// previous-best → new-record scoreboard (`MetricComparisonView`, the shared shape the chart headers
/// use) with the gain pill between them, over the exercise's all-time line for that metric bleeding
/// out the bottom. Differences from `WorkoutPersonalRecordCard`, both forced by the carousel: a
/// chevron (these cards navigate; that one doesn't) and a `.normal` scoreboard value so two
/// spelled-out numbers plus the pill fit a card narrower than the screen.
private struct HighlightBestCard: View {
    /// The exercise's records for this window — one card per exercise, matching the record cards.
    let records: WorkoutProgressReport.ExerciseRecords
    /// The record the card is about: the lead metric normally, the metric that crossed a ladder step
    /// on a milestone.
    let subject: WorkoutProgressReport.PRRecord
    /// Non-nil turns the card into a milestone: the subtitle names the crossed ladder step, and the
    /// scoreboard below tells the same before/after story a plain record's does.
    let milestoneStepBaseValue: Int?
    /// In the carousel the scoreboard drops to `.normal` values so two spelled-out numbers plus the
    /// pill fit a 300pt card; at full width it wears the record card's own `.large`.
    var isCompact: Bool = false

    var body: some View {
        let color = records.exercise.muscleGroup?.color ?? .accentColor
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                header(color: color)
                comparison(color: color)
            }
            .padding([.horizontal, .top], CELL_PADDING)
            ExerciseTileSparkline(points: sparklinePoints, color: color, window: .allTime, bleeds: true)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                Text(records.exercise.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            NavigationChevron()
                .foregroundStyle(Color.secondaryLabel)
        }
    }

    /// The record card's scoreboard verbatim — dated previous best, gain pill, dated new record —
    /// only at the carousel's smaller value size.
    private func comparison(color: Color) -> some View {
        let previous = personalRecordDisplay(subject.previousBest, metric: subject.metric, exercise: subject.exercise)
        let current = personalRecordDisplay(subject.value, metric: subject.metric, exercise: subject.exercise)
        let percentChange = subject.previousBest > 0
            ? (Double(subject.value) - Double(subject.previousBest)) / Double(subject.previousBest) * 100
            : nil
        return MetricComparisonView(
            leading: .init(
                label: NSLocalizedString("previousBest", comment: ""),
                value: previous.value,
                unit: previous.unit,
                caption: dateCaption(subject.previousBestDate)
            ),
            trailing: .init(
                label: NSLocalizedString("newRecord", comment: ""),
                value: current.value,
                unit: current.unit,
                caption: dateCaption(subject.date)
            ),
            trailingValueStyle: AnyShapeStyle(color.gradient),
            valueConfiguration: isCompact ? .normal : .large,
            percentChange: percentChange,
            positiveColor: color,
            positiveStyle: AnyShapeStyle(color.gradient)
        )
    }

    /// Metric name, and for a milestone the step it crossed — the one line that separates "you beat
    /// your best" from "you went past a number that matters".
    private var subtitle: String {
        guard let milestoneStepBaseValue else {
            // Every metric that set a record, the way the shared record rows list them.
            return records.records.map(\.metric.title).joined(separator: " · ")
        }
        let step = personalRecordDisplay(milestoneStepBaseValue, metric: subject.metric, exercise: subject.exercise)
        let milestone = String(
            format: NSLocalizedString("firstTimePast", comment: ""),
            "\(step.value) \(step.unit)"
        )
        return "\(subject.metric.title) · \(milestone)"
    }

    /// A scoreboard caption date — day and month, with the year only when it isn't the current one,
    /// matching the record card's captions.
    private func dateCaption(_ date: Date?) -> String? {
        guard let date else { return nil }
        return date.isInCurrentYear
            ? date.formatted(.dateTime.day().month())
            : date.formatted(.dateTime.day().month().year())
    }

    /// The exercise's daily best for this metric up to the record — the same series the records
    /// screen charts under each record card.
    private var sparklinePoints: [ExerciseTileSparkline.Point] {
        let cutoff = subject.date ?? .now
        let sets = records.exercise.sets.filter { ($0.workout?.date ?? .distantFuture) <= cutoff }
        let grouped = Dictionary(grouping: sets) {
            Calendar.current.startOfDay(for: $0.workout?.date ?? .now)
        }
        return grouped.compactMap { day, daySets -> ExerciseTileSparkline.Point? in
            let best = daySets.map { metricValue($0) }.max() ?? 0
            guard best > 0 else { return nil }
            return ExerciseTileSparkline.Point(date: day, value: Double(best))
        }
        .sorted { $0.date < $1.date }
    }

    private func metricValue(_ workoutSet: WorkoutSet) -> Int {
        switch subject.metric {
        case .estimatedOneRepMax: return workoutSet.estimatedOneRepMax(for: records.exercise)
        case .weight: return workoutSet.maximum(.weight, for: records.exercise)
        case .repetitions: return workoutSet.maximum(.repetitions, for: records.exercise)
        case .duration: return workoutSet.maximum(.duration, for: records.exercise)
        case .distance: return workoutSet.maximum(.distance, for: records.exercise)
        }
    }
}

// MARK: - Comparison card (trend / year crossing)

/// A now-vs-before comparison in the app's `ComparisonBar` language. Wears the same header as the
/// best cards — a tinted glyph disc leading a headline and a scope · window caption — so the two
/// card families read as one system in the carousel; below it, the current value over its tinted bar
/// and the previous value over the gray one, each bar carrying its period label. Trends add the
/// trend pill beside the current value; the year crossing lets the two bars speak for themselves.
private struct HighlightComparisonCard: View {
    /// Everything the card renders, prepared by the initializers so the view stays dumb.
    struct Content {
        let symbol: String
        let headline: String
        let caption: String
        let currentValue: String
        let previousValue: String
        let unit: String
        let currentLabel: String
        let previousLabel: String
        let currentNumeric: Double
        let previousNumeric: Double
        let percentChange: Double?
        let tint: Color
    }

    let content: Content

    var body: some View {
        let maxValue = max(content.currentNumeric, content.previousNumeric, 1)
        VStack(alignment: .leading, spacing: 8) {
            header
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    UnitView(value: content.currentValue, unit: content.unit, unitColor: .secondaryLabel)
                        .foregroundStyle(Color.label)
                    if let percentChange = content.percentChange {
                        TrendIndicatorView(percentChange: percentChange, positiveColor: content.tint)
                    }
                    Spacer(minLength: 0)
                }
                ComparisonBar(
                    value: content.currentNumeric,
                    maxValue: maxValue,
                    tint: content.tint,
                    label: content.currentLabel,
                    labelColor: .black,
                    trackColor: .tertiaryBackground
                )
                .frame(height: 24)
                .padding(.top, 4)

                UnitView(value: content.previousValue, unit: content.unit)
                    .foregroundStyle(Color.secondaryLabel)
                    .padding(.top, 8)
                ComparisonBar(
                    value: content.previousNumeric,
                    maxValue: maxValue,
                    tint: Color.gray.opacity(0.25),
                    label: content.previousLabel,
                    trackColor: .tertiaryBackground
                )
                .frame(height: 24)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(CELL_PADDING)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tileStyle()
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(content.tint.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: content.symbol)
                    .font(.subheadline)
                    .foregroundStyle(content.tint.gradient)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(content.headline)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(content.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            NavigationChevron()
                .foregroundStyle(Color.secondaryLabel)
        }
    }
}

extension HighlightComparisonCard.Content {
    /// A rolling-window trend, worded and tinted by its scope. The headline states only *what* went
    /// up — the caption below it owns the window, so the two can never contradict each other.
    init(trend: ProgressTrend) {
        symbol = "chart.line.uptrend.xyaxis"
        // The window the trend was actually measured over, not a fixed "last 4 weeks" — the
        // highlights screen can widen it. The two bars below carry both periods, so naming the
        // current one here is enough.
        let windowCaption = trend.window.currentWindowLabel
        let scopeName: String
        switch trend.kind {
        case .muscleGroupSets:
            scopeName = trend.muscleGroup?.description ?? ""
        case .exerciseVolume:
            scopeName = trend.exercise?.displayName ?? ""
        }

        switch trend.kind {
        case .muscleGroupSets:
            headline = String(
                format: NSLocalizedString("trendMuscleSets", comment: ""),
                trend.muscleGroup?.description ?? ""
            )
        case .exerciseVolume:
            headline = String(
                format: NSLocalizedString("trendExerciseVolume", comment: ""),
                trend.exercise?.displayName ?? ""
            )
        }
        caption = "\(scopeName) · \(windowCaption)"

        switch trend.kind {
        case .exerciseVolume:
            currentValue = abbreviatedVolume(convertWeightForDisplaying(trend.currentValue))
            previousValue = abbreviatedVolume(convertWeightForDisplaying(trend.previousValue))
            unit = WeightUnit.used.rawValue
        case .muscleGroupSets:
            currentValue = String(trend.currentValue)
            previousValue = String(trend.previousValue)
            unit = NSLocalizedString("sets", comment: "")
        }

        currentLabel = trend.window.currentWindowLabel
        // "4 weeks before" is a phrase that only exists for the default window; a rolling three-month
        // or year-long block has no name, so the older bar can only honestly say which dates it holds
        // — the rule `TrendWindow.windowTitle` follows everywhere else.
        previousLabel = trend.window == .fourWeeks
            ? NSLocalizedString("fourWeeksBefore", comment: "")
            : trend.window.windowTitle(windowsAgo: 1)
        currentNumeric = Double(trend.currentValue)
        previousNumeric = Double(trend.previousValue)
        percentChange = Double(trend.displayedPercent)
        switch trend.kind {
        case .muscleGroupSets:
            tint = trend.muscleGroup?.color ?? .accentColor
        case .exerciseVolume:
            tint = trend.exercise?.muscleGroup?.color ?? .accentColor
        }
    }

    /// The year crossing — "2026 already beat 2025", the two year totals as bars.
    init(crossing: ProgressYearCrossing) {
        symbol = "calendar"
        let year = String(crossing.year)
        let previousYear = String(crossing.previousYear)
        headline = String(format: NSLocalizedString("yearCrossingHeadline", comment: ""), year, previousYear)
        let spare: String?
        switch crossing.monthsToSpare {
        case 0: spare = nil
        case 1: spare = NSLocalizedString("monthToSpare", comment: "")
        default: spare = String(format: NSLocalizedString("monthsToSpare", comment: ""), crossing.monthsToSpare)
        }
        let volumeTitle = NSLocalizedString("volume", comment: "")
        caption = spare.map { "\(volumeTitle) · \($0)" } ?? volumeTitle
        currentValue = abbreviatedVolume(convertWeightForDisplaying(crossing.currentVolume))
        previousValue = abbreviatedVolume(convertWeightForDisplaying(crossing.previousVolume))
        unit = WeightUnit.used.rawValue
        currentLabel = String(format: NSLocalizedString("yearSoFar", comment: ""), year)
        previousLabel = previousYear
        currentNumeric = Double(crossing.currentVolume)
        previousNumeric = Double(crossing.previousVolume)
        percentChange = nil
        tint = .accentColor
    }
}

// MARK: - See-all screen

/// Every highlight in the chosen window as a vertical, priority-ordered list of the same cards — the
/// screen behind the carousel's "Show All" button.
///
/// It carries the shared `TrendWindowPicker` like every other detail screen, and it is the only place
/// a highlight's window can be widened: the Summary's carousel is pinned to the recent window so it
/// keeps meaning "what just happened" (see `SummaryHighlightsSection`), and this is where a reader
/// goes to ask the longer question. It opens on the recent window, so arriving here shows the same
/// feed the carousel was showing before offering to widen it.
struct ProgressHighlightsScreen: View {
    let workouts: [Workout]

    @EnvironmentObject private var database: Database
    @State private var window: TrendWindow = ProgressHighlights.recentWindow
    @State private var items: [ProgressHighlight] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                TrendWindowPicker(selection: $window)
                    .padding(.bottom, 6)
                if items.isEmpty {
                    emptyState
                } else {
                    ForEach(items) { item in
                        ProgressHighlightCardView(item: item)
                    }
                }
                footnote
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(NSLocalizedString("highlights", comment: ""))
                    .font(.headline)
            }
        }
        .task(id: "\(window.rawValue)-\(workouts.count)") {
            items = ProgressHighlights.compute(workouts: workouts, database: database, window: window)
        }
    }

    /// A window can legitimately hold no highlights — the noise floors scale with it, so a quiet
    /// three months reports nothing rather than promoting something that isn't a highlight. Say so,
    /// instead of leaving the picker floating over a footnote.
    private var emptyState: some View {
        Text(NSLocalizedString("noData", comment: ""))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .tileStyle()
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
            Text(NSLocalizedString("highlightsInfo", comment: ""))
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }
}
