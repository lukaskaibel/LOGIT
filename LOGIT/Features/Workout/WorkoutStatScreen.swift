//
//  WorkoutStatScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.06.26.
//

import Charts
import SwiftUI

/// Detail screen behind a workout stat tile: the stat workout by workout, this one against the
/// sessions that led up to it — the tile's mini chart, zoomed out and made walkable.
///
/// The axis carries no time: it counts *workouts*, one fixed-width bar each, oldest to newest, and
/// gaps in the calendar don't show up as gaps in the chart. That's the comparison the screen is
/// actually for ("how does this session stack up against the ones before it?") and the one the tile
/// already draws, where a time axis answered a different question — a bar there could be a whole
/// month's average. Tile and screen show the *same* eight workouts (`WorkoutRunHistory.windowCount`,
/// the shared window): tapping a tile only lets you walk further back, it never changes what you're
/// being compared against. It also retires the machinery that time cost us: the
/// 3M / 1Y / All picker (a run axis has one zoom), the month-average bars, and this workout's
/// dedicated column beside the chart — the column only existed because a month bucket can't be a
/// single session; on a run axis this workout simply *is* the bar at the right edge.
///
/// Eight workouts stand in the window at a time — scroll right for older ones, and the window
/// opens on this workout at its right edge. Fewer than eight on record right-aligns into eight
/// slots (bars keep their width) rather than stretching three bars across the chart, exactly like
/// the tile's five. This workout's bar wears the workout's muscle-group gradient, every other stays
/// a quiet gray, and a tapped bar lights up white.
///
/// The x-axis carries **no labels**: an axis of workouts has no scale to label, and dates written
/// under evenly spaced bars quietly become one (see `windowDescription`). The header holds the
/// dates instead — a two-value scoreboard like the in-workout metric popover: the average across
/// the *shown* eight over the span they were logged in (the reference — neutral, and both move as
/// you scroll) on one side, this workout's own value and date (the bold constant) on the other, and
/// a pill between them reading this workout against that average. One screen serves all four
/// stats — `WorkoutStatMetric` supplies values, formatting, and texts.
struct WorkoutStatScreen: View {
    /// One bar of the chart: a single workout at a fixed slot on the run axis.
    private struct Run: Identifiable {
        let id: AnyHashable
        /// Slot on the x axis — chronological, 0 = the oldest workout on record.
        let index: Int
        let date: Date
        let name: String?
        /// Raw units (grams, minutes, counts) — formatted only for display.
        let rawValue: Double
        /// Display units for the chart's y-axis.
        let value: Double
        /// The workout the screen was opened from — drawn with its muscle-group gradient.
        let isCurrent: Bool
    }

    // MARK: - Constants

    /// Workouts in the window at once — shared with the stat tiles, whose bars are this same
    /// window (`WorkoutRunHistory.windowCount`), so the tile and the screen it opens never disagree
    /// about which sessions this workout is measured against. Also the minimum width of the domain,
    /// so a history shorter than this right-aligns into eight slots instead of stretching its bars
    /// across the chart.
    private static let visibleRunCount = WorkoutRunHistory.windowCount

    // MARK: - Variables

    let metric: WorkoutStatMetric
    /// The workout the screen was opened from — names the screen, supplies its theme, and anchors
    /// both the opening window and the header's subject side.
    @ObservedObject var workout: Workout

    // MARK: - Environment

    @EnvironmentObject private var muscleGroupService: MuscleGroupService

    // MARK: - State

    /// Leading edge of the window, as the slot instant it rests on (see "Slot geometry"). Nil until
    /// the chart reports a scroll, which is what lets the window open on this workout without an
    /// `onAppear` — the binding below hands the chart the anchored position for as long as nobody
    /// has scrolled, so the first frame is already the right one.
    @State private var scrollPosition: Date?
    /// Where the user tapped on the axis — resolved to the bar in that slot.
    @State private var selectedX: Date?

    // MARK: - Body

    var body: some View {
        FetchRequestWrapper(
            Workout.self,
            sortDescriptors: [SortDescriptor(\.date)],
            predicate: WorkoutPredicateFactory.getWorkouts()
        ) { allWorkouts in
            screen(runs: runs(in: allWorkouts))
        }
    }

    private func screen(runs: [Run]) -> some View {
        let window = visibleRuns(in: runs)
        let selectedRun = selectedRun(in: runs)
        // The average per workout across the visible eight — recomputed as the chart scrolls, so
        // the header's reference value and its pill always describe the window on screen.
        let visibleAverage = averageRaw(of: window)
        return ScrollView {
            VStack(spacing: SECTION_SPACING) {
                VStack(spacing: 16) {
                    header(visibleAverage: visibleAverage, window: window)
                    chart(runs: runs, selectedRun: selectedRun)
                }

                AboutSection(metricTitle: metric.title, text: metric.aboutText)
                    .padding(.horizontal)
            }
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .isBlockedWithoutPro(metric.requiresPro)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text(metric.title)
                        .font(.headline)
                    Text(workout.name ?? "")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
        }
    }

    // MARK: - Header

    /// A scoreboard like the in-workout metric popover: the average across the shown workouts (the
    /// reference, neutral, moving with the scroll) on the left, this workout's own value (the bold
    /// constant) on the right, the pill between them reading this workout against that average.
    /// We're in the workout detail, so this workout is always the subject — scrolling retargets the
    /// average and the pill, never the side they're compared to.
    private func header(visibleAverage: Double?, window: [Run]) -> some View {
        // This workout's own value for the metric — "––" when it has none (e.g. duration with no end).
        let raw = metric.rawValue(of: workout)
        // This workout vs the visible window's average — positive when this session beat it. Duration
        // stays neutral gray (longer is neither better nor worse), matching its tile.
        let percentChange: Double? = {
            guard let average = visibleAverage, average > 0, raw > 0 else { return nil }
            return (Double(raw) - average) / average * 100
        }()
        let isDuration = metric == .duration
        return MetricComparisonView(
            leading: .init(
                label: NSLocalizedString("average", comment: ""),
                value: visibleAverage.map { metric.formattedAverage(rawAverage: $0) } ?? "––",
                unit: metric.unit,
                caption: windowDescription(of: window)
            ),
            trailing: .init(
                label: NSLocalizedString("thisWorkout", comment: ""),
                value: raw > 0 ? metric.formattedValue(fromRaw: raw) : "––",
                unit: metric.unit,
                caption: workout.date?.formatted(.dateTime.day().month())
            ),
            trailingValueStyle: isDuration ? AnyShapeStyle(Color.label) : workout.sets.muscleGroupGradientStyle(startPoint: .bottomLeading, endPoint: .topTrailing),
            percentChange: percentChange,
            positiveColor: isDuration ? .secondary : dominantMuscleGroupColor,
            positiveStyle: isDuration ? nil : workout.sets.muscleGroupGradientStyle(startPoint: .bottomLeading, endPoint: .topTrailing)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    /// What the average describes, spelled out as the span the shown workouts were logged in
    /// ("12 Mar - 4 Jul"). The axis counts workouts, but the reader still wants to know *when* the
    /// eight on screen happened — a single day when they all fall on one.
    ///
    /// This line, with this workout's own date opposite it, is the **only** place dates appear on
    /// the chart, and deliberately so: the x-axis carries no labels. Dates under evenly spaced bars
    /// read as a scale, and this scale doesn't exist — two sessions a fortnight apart sit exactly as
    /// far apart as two on the same afternoon (which is also why sparse labels were worse than none:
    /// "8/2 … 8/5 … 8/10" over an even grid invites interpolating between them). A span in the
    /// header can't be misread that way, it retargets as you scroll, and a single bar's date is
    /// always one press away in its annotation card.
    private func windowDescription(of window: [Run]) -> String? {
        guard let first = window.first?.date, let last = window.last?.date else { return nil }
        let format = { (date: Date) in
            date.isInCurrentYear
                ? date.formatted(.dateTime.day().month())
                : date.formatted(.dateTime.day().month().year())
        }
        let start = format(first)
        let end = format(last)
        return start == end ? start : "\(start) - \(end)"
    }

    // MARK: - Chart

    /// The run axis: one bar per workout in a slot of its own, eight in view, scrollable back
    /// through the whole history. A bar sits at the middle of its slot, so every window edge lands
    /// on a slot boundary — that's what lets the scroll snap between bars instead of slicing them.
    private func chart(runs: [Run], selectedRun: Run?) -> some View {
        let yScaleMax = chartYScaleMax(for: runs)
        let windowStart = windowStartIndex(runs: runs)
        return Chart {
            if let selectedRun {
                RuleMark(x: .value("Selected", slotCenter(of: selectedRun.index), unit: .hour))
                    .foregroundStyle(Color.label.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .annotation(
                        position: annotationPosition(for: selectedRun, windowStart: windowStart),
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        annotationCard(for: selectedRun)
                    }
            }
            ForEach(runs) { run in
                BarMark(
                    x: .value("Workout", slotCenter(of: run.index), unit: .hour),
                    y: .value("Value", run.value),
                    width: .ratio(0.6)
                )
                .foregroundStyle(barStyle(for: run, selectedRun: selectedRun))
                .tileBarStyle()
                .opacity(selectedRun == nil || selectedRun?.id == run.id ? 1.0 : 0.4)
            }
        }
        .chartXScale(domain: xDomain(runCount: runs.count))
        .chartYScale(domain: 0 ... yScaleMax)
        .chartScrollableAxes(.horizontal)
        .chartScrollPosition(x: scrollPositionBinding(runs: runs))
        .chartScrollTargetBehavior(
            .valueAligned(matching: DateComponents(minute: 0), majorAlignment: .matching(DateComponents(minute: 0)))
        )
        .chartXSelection(value: $selectedX)
        .chartXVisibleDomain(length: Self.slotDuration * Double(Self.visibleRunCount))
        // No x-axis labels: see the note on `windowDescription`.
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: [0, yScaleMax / 2, yScaleMax])
        }
        .frame(height: 300)
        .padding(.leading)
        .padding(.trailing, 5)
        // Settle onto whole slots once the scroll stops. `chartScrollTargetBehavior` above snaps a
        // dragged window but lets a flicked one rest wherever its deceleration ran out, which slices
        // the bars at both edges of a chart whose whole premise is one bar per workout. Keying the
        // task to the position debounces it: every scroll update restarts it, so the nudge only
        // lands after the chart has been still for a moment.
        .task(id: scrollPosition) {
            guard let position = scrollPosition else { return }
            let snapped = slotStart(of: windowStartIndex(runs: runs))
            guard snapped != position else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { scrollPosition = snapped }
        }
        .emptyPlaceholder(runs) {
            Text(NSLocalizedString("noData", comment: ""))
        }
    }

    /// Where the tooltip hangs off the rule mark: bars in the right third of the window get a
    /// leading card, the left third a trailing one. `fit(to: .chart)` alone can't keep the card on
    /// screen here — the plot scrolls, so "the chart" includes off-viewport bars and an edge bar's
    /// card happily lays out into them, clipped by the viewport.
    private func annotationPosition(for run: Run, windowStart: Int) -> AnnotationPosition {
        let fraction = Double(run.index - windowStart) / Double(Self.visibleRunCount)
        if fraction > 0.66 { return .topLeading }
        if fraction < 0.33 { return .topTrailing }
        return .top
    }

    private func annotationCard(for run: Run) -> some View {
        VStack(alignment: .leading) {
            UnitView(value: metric.formattedValue(fromRaw: Int(run.rawValue.rounded())), unit: metric.unit, unitColor: .secondaryLabel)
                .foregroundStyle(Color.label)
            Text(annotationSubtitle(for: run))
                .fontWeight(.bold)
                .fontDesign(.rounded)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondaryBackground))
    }

    private func annotationSubtitle(for run: Run) -> String {
        let day = run.date.formatted(.dateTime.day().month())
        guard let name = run.name, !name.isEmpty else { return day }
        return "\(name) · \(day)"
    }

    // MARK: - Runs

    /// Every workout on record as a bar, oldest first. Workouts without a usable value (e.g. no
    /// recorded end on the duration screen) would render as invisible bars, take up a slot and drag
    /// every average down — they don't count, and they don't get an index.
    private func runs(in workouts: [Workout]) -> [Run] {
        workouts
            .filter { $0.date != nil && metric.rawValue(of: $0) > 0 }
            .enumerated()
            .map { index, workout in
                let raw = metric.rawValue(of: workout)
                return Run(
                    id: workout.objectID,
                    index: index,
                    date: workout.date ?? .now,
                    name: workout.name,
                    rawValue: Double(raw),
                    value: metric.displayValue(fromRaw: raw),
                    isCurrent: workout.objectID == self.workout.objectID
                )
            }
    }

    // MARK: - Slot geometry

    /// Slots are laid out as *instants*, one hour apart, and the workout's real date is only ever a
    /// label. That looks like a detour and isn't: Swift Charts snaps a scroll to whole slots only on
    /// a date axis (`valueAligned(matching:)`, the same modifier the capability charts scroll with) —
    /// on a plain numeric axis the window comes to rest wherever the finger left it, slicing the bars
    /// at both edges, and no amount of rounding the reported position puts it back. A synthetic hour
    /// per workout buys that snapping, plus bar widths as a fraction of the slot. Hours, not days, so
    /// no daylight-saving jump can stretch one slot wider than its neighbours.
    ///
    /// The reference instant is nudged onto a *local* whole hour, because that is what the snapping
    /// matches: in a time zone offset by half or three quarters of an hour (India, Nepal, parts of
    /// Australia) a UTC-anchored slot grid would snap to positions that cut every bar in two.
    private static let slotReference: Date = {
        let raw = Date(timeIntervalSinceReferenceDate: 0)
        return raw.addingTimeInterval(Double(TimeZone.current.secondsFromGMT(for: raw) % 3600))
    }()
    private static let slotDuration: TimeInterval = 3600

    /// Where bar *i* plots: the middle of its slot, so a window edge always lands on a whole hour.
    private func slotCenter(of index: Int) -> Date {
        Self.slotReference.addingTimeInterval((Double(index) + 0.5) * Self.slotDuration)
    }

    private func slotStart(of index: Int) -> Date {
        Self.slotReference.addingTimeInterval(Double(index) * Self.slotDuration)
    }

    /// The slot an instant falls in — the inverse of `slotStart`, for selection and scroll position.
    private func slotIndex(at date: Date) -> Int {
        Int((date.timeIntervalSince(Self.slotReference) / Self.slotDuration).rounded(.down))
    }

    // MARK: - Chart Window

    /// The scrollable domain: one slot per workout, but never narrower than the window, so a history
    /// of three bars right-aligns into eight slots instead of stretching across the chart.
    private func xDomain(runCount: Int) -> ClosedRange<Date> {
        slotStart(of: min(0, runCount - Self.visibleRunCount)) ... slotStart(of: max(runCount, Self.visibleRunCount))
    }

    /// The window's leading edge, defaulting to the position that puts this workout's bar at the
    /// right edge — an off-screen subject reads as a missing one, and the visible average then
    /// compares it against the workouts leading up to it. Clamped into the domain, so a subject
    /// among the very first workouts doesn't aim past the left edge.
    private func initialScrollPosition(runs: [Run]) -> Date {
        let anchorIndex = runs.first(where: \.isCurrent)?.index ?? (runs.count - 1)
        let firstVisible = anchorIndex + 1 - Self.visibleRunCount
        let lastPossible = max(runs.count, Self.visibleRunCount) - Self.visibleRunCount
        return slotStart(of: min(max(firstVisible, min(0, runs.count - Self.visibleRunCount)), lastPossible))
    }

    /// Hands the chart the anchored opening position until the user scrolls, and follows the scroll
    /// afterwards.
    private func scrollPositionBinding(runs: [Run]) -> Binding<Date> {
        Binding(
            get: { scrollPosition ?? initialScrollPosition(runs: runs) },
            set: { scrollPosition = $0 }
        )
    }

    /// The window's leading slot — what the header's average, its caption and the axis labels are
    /// keyed to. The scroll settles on whole slots, but it reports its position continuously while
    /// it is still moving; taking the nearest slot keeps those three describing whole bars
    /// throughout, and describing the same bars the reader mostly sees on the way there.
    private func windowStartIndex(runs: [Run]) -> Int {
        let position = scrollPosition ?? initialScrollPosition(runs: runs)
        return slotIndex(at: position.addingTimeInterval(Self.slotDuration / 2))
    }

    /// The workouts inside the window — what the header's average and its caption describe.
    private func visibleRuns(in runs: [Run]) -> [Run] {
        let start = windowStartIndex(runs: runs)
        let window = start ..< start + Self.visibleRunCount
        return runs.filter { window.contains($0.index) }
    }

    // MARK: - Averages

    /// Mean raw value per workout across the given bars, or nil when there is none.
    private func averageRaw(of runs: [Run]) -> Double? {
        guard !runs.isEmpty else { return nil }
        return runs.map(\.rawValue).reduce(0, +) / Double(runs.count)
    }

    /// Smallest "nice" number (1/2/2.5/5 × power of ten) at or above the tallest bar, so the y-axis
    /// marks land on round values whatever unit the stat uses. Taken over the whole history, not the
    /// window: a scale that rescaled under the scroll would make the bars lie about each other.
    private func chartYScaleMax(for runs: [Run]) -> Double {
        let maxValue = runs.map(\.value).max() ?? 0
        guard maxValue > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(maxValue)))
        let normalized = maxValue / magnitude
        let niceNormalized: Double = normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 2.5 ? 2.5 : normalized <= 5 ? 5 : 10
        return niceNormalized * magnitude
    }

    // MARK: - Selection

    /// The bar under the tap: the slot the tapped position falls into, ignoring taps on the empty
    /// slots a short history right-aligns away from.
    private func selectedRun(in runs: [Run]) -> Run? {
        guard let selectedX else { return nil }
        let index = slotIndex(at: selectedX)
        return runs.first { $0.index == index }
    }

    // MARK: - Colors

    /// The bar for the workout the screen was opened from wears the workout's own muscle-group
    /// gradient — its identity color, the screen's accent. A bar tapped to inspect lights up white
    /// ("now showing this"); every other bar stays a quiet gray. `isCurrent` wins when the current
    /// bar is itself the tapped one — its gradient already stands out.
    private func barStyle(for run: Run, selectedRun: Run?) -> AnyShapeStyle {
        if run.isCurrent { return workout.sets.muscleGroupGradientStyle(startPoint: .bottom, endPoint: .top) }
        if selectedRun?.id == run.id { return AnyShapeStyle(Color.label) }
        return AnyShapeStyle(Color.fill)
    }

    private var dominantMuscleGroupColor: Color {
        muscleGroupService.getMuscleGroupOccurances(in: workout).first?.0.color ?? .accentColor
    }
}

// MARK: - Preview

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        NavigationStack {
            WorkoutStatScreen(metric: .volume, workout: database.testWorkout)
        }
    }
}

struct WorkoutStatScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
