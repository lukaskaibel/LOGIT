//
//  WorkoutLiveActivityWidget.swift
//  LOGITWidgetExtension
//
//  Created by Codex on 28.03.26.
//

import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

private extension Color {
    /// Live Activity surfaces are dark; semantic `secondary` often maps too dim—this reads as a clear secondary tier on black.
    static var workoutLiveActivitySecondary: Color {
        Color(red: 0.74, green: 0.74, blue: 0.78)
    }

    /// Empty reps/weight (placeholder) on the **pure black** Live Activity card. `UIColor.placeholderText` is often
    /// translucent and nearly disappears on `#000`; this opaque muted gray matches the *legibility* of `Color.placeholder`
    /// on `WorkoutSetCell`’s near-black `IntegerField` / `DecimalField` tiles (still clearly below filled `.white` and unit secondary).
    static var workoutLiveActivityPlaceholderText: Color {
        Color(red: 0.56, green: 0.57, blue: 0.62)
    }

    /// The widget extension does not load the app’s `AccentColor` asset; `Color.accentColor` here can prevent the Live Activity from rendering on the lock screen.
    static var workoutLiveActivityManualChronoTint: Color {
        Color(red: 0.04, green: 0.52, blue: 1.0)
    }
}

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutLiveActivityAttributes.self) { context in
            WorkoutLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(context.state.themeToken.accentColor)
            } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutElapsedDurationLabel(startedAt: context.attributes.startedAt, font: .caption.weight(.bold))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.workoutTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.workoutLiveActivitySecondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WorkoutExerciseCard(
                        state: context.state,
                        chronoChip: context.state.chronoChip,
                        chronoChipUsesCompactStyle: true
                    )
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                WorkoutCompactIslandLeadingContent(state: context.state)
            } compactTrailing: {
                WorkoutCompactIslandTrailingContent(
                    startedAt: context.attributes.startedAt,
                    chronoChip: context.state.chronoChip,
                    font: .caption2.weight(.bold)
                )
            } minimal: {
                WorkoutCompactIslandTrailingContent(
                    startedAt: context.attributes.startedAt,
                    chronoChip: context.state.chronoChip,
                    font: .caption2.weight(.bold)
                )
            }
            .keylineTint(context.state.themeToken.accentColor)
        }
    }
}

private struct WorkoutLiveActivityLockScreenContent: View {
    let attributes: WorkoutLiveActivityAttributes
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(state.workoutTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.workoutLiveActivitySecondary)
                    .lineLimit(1)

                WorkoutElapsedDurationLabel(startedAt: attributes.startedAt, font: .caption.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            WorkoutExerciseCard(
                state: state,
                chronoChip: state.chronoChip,
                chronoChipUsesCompactStyle: false
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 4)
    }
}

private struct WorkoutLiveActivityLockScreenView: View {
    let context: ActivityViewContext<WorkoutLiveActivityAttributes>

    var body: some View {
        WorkoutLiveActivityLockScreenContent(attributes: context.attributes, state: context.state)
    }
}

private func workoutLiveActivityRestTimeString(seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    return "\(m):\(String(format: "%02d", s))"
}

/// Mirrors `WorkoutRecorderFloatingTimerButton` (capsule fill, stroke, shadow, optional timer progress fill).
/// Avoid `Button` and `Material` here—Live Activities on the lock screen often show a stuck spinner when those fail to resolve in the extension.
/// Running timer/stopwatch digits use `Text(timerInterval:showsHours:)` so the system updates the label locally—no Activity pushes each tick.
private struct WorkoutLiveActivityChronoChipView: View {
    let chip: WorkoutLiveActivityChronoChip
    var compact: Bool

    private var timeLabelFont: Font {
        compact ? .footnote.weight(.semibold) : .body.weight(.semibold)
    }

    var body: some View {
        let tint = chipForegroundTint
        HStack(spacing: compact ? 6 : 8) {
            Image(systemName: iconName)
                .font(compact ? .callout.weight(.semibold) : .body.weight(.semibold))

            chronoTimeText
                .font(timeLabelFont)
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, compact ? 10 : 13)
        .background {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.16))

                    if chip.phase == .timerRunning,
                       let end = chip.timerEndDate,
                       let total = chip.timerTotalSeconds,
                       total > 0
                    {
                        let start = end.addingTimeInterval(-total)
                        TimelineView(PeriodicTimelineSchedule(from: start, by: 1)) { timelineContext in
                            let remaining = max(0, end.timeIntervalSince(timelineContext.date))
                            let progress = CGFloat(min(max(remaining / total, 0), 1))
                            Rectangle()
                                .fill(tint.opacity(0.24))
                                .frame(width: max(0, proxy.size.width * progress))
                        }
                    }

                    Capsule()
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.9)
                }
            }
        }
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.12), radius: compact ? 12 : 18, y: compact ? 5 : 8)
    }

    @ViewBuilder
    private var chronoTimeText: some View {
        switch chip.phase {
        case .timerRunning:
            if let end = chip.timerEndDate, let total = chip.timerTotalSeconds, total > 0 {
                let start = end.addingTimeInterval(-total)
                Text(timerInterval: start...end, countsDown: true, showsHours: false)
            }
        case .stopwatchRunning:
            if let start = chip.stopwatchStartDate {
                Text(timerInterval: start...Date.distantFuture, countsDown: false, showsHours: false)
            }
        case .timerPaused, .stopwatchPaused:
            if let s = chip.staticTickSeconds {
                Text(workoutLiveActivityRestTimeString(seconds: s))
            }
        }
    }

    private var iconName: String {
        switch chip.phase {
        case .timerRunning, .timerPaused:
            return "timer"
        case .stopwatchRunning, .stopwatchPaused:
            return "stopwatch"
        }
    }

    private var horizontalPadding: CGFloat {
        showsTimeLabel ? (compact ? 12 : 16) : (compact ? 11 : 14)
    }

    private var showsTimeLabel: Bool {
        switch chip.phase {
        case .timerRunning:
            return chip.timerEndDate != nil
        case .timerPaused, .stopwatchPaused:
            return chip.staticTickSeconds != nil
        case .stopwatchRunning:
            return chip.stopwatchStartDate != nil
        }
    }

    private var chipForegroundTint: Color {
        chip.liveActivityChronoForegroundTint
    }
}

private extension Color {
    /// Distinct from muscle-group tints used for auto rest countdown.
    static var restStopwatchLiveActivityTint: Color {
        Color(red: 1, green: 0.58, blue: 0.22)
    }
}

private extension WorkoutLiveActivityChronoChip {
    /// Matches `WorkoutRecorderFloatingTimerButton`: muscle tint for auto rest timer, distinct auto stopwatch, app accent for manual.
    var liveActivityChronoForegroundTint: Color {
        switch tintKind {
        case .restTimer:
            (muscleThemeToken ?? .neutral).accentColor
        case .restStopwatch:
            Color.restStopwatchLiveActivityTint
        case .manual:
            Color.workoutLiveActivityManualChronoTint
        }
    }

    var showsRunningChronoInCompactIsland: Bool {
        switch phase {
        case .timerRunning:
            timerEndDate != nil && (timerTotalSeconds ?? 0) > 0
        case .stopwatchRunning:
            stopwatchStartDate != nil
        case .timerPaused, .stopwatchPaused:
            false
        }
    }
}

/// Superset: focused exercise (headline) + partner in smaller secondary type; arrow points at the partner.
private struct WorkoutLiveActivityExerciseTitleRow: View {
    let mainExerciseName: String
    let partnerExerciseName: String?
    let supersetPartnerIsLeading: Bool

    var body: some View {
        Group {
            if let partner = partnerExerciseName, !partner.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if supersetPartnerIsLeading {
                        partnerText(partner)
                        arrowPointingToPartner(isLeftPointing: true)
                        mainText
                    } else {
                        mainText
                        arrowPointingToPartner(isLeftPointing: false)
                        partnerText(partner)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .minimumScaleFactor(0.78)
            } else {
                mainText
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var mainText: some View {
        Text(mainExerciseName)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(2)
            .layoutPriority(1)
    }

    private func partnerText(_ name: String) -> some View {
        Text(name)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.workoutLiveActivitySecondary)
            .lineLimit(2)
    }

    private func arrowPointingToPartner(isLeftPointing: Bool) -> some View {
        Image(systemName: isLeftPointing ? "arrow.left" : "arrow.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.workoutLiveActivitySecondary)
            .baselineOffset(-1)
    }
}

private struct WorkoutExerciseCard: View {
    let state: WorkoutLiveActivityAttributes.ContentState
    var chronoChip: WorkoutLiveActivityChronoChip?
    var chronoChipUsesCompactStyle: Bool

    init(
        state: WorkoutLiveActivityAttributes.ContentState,
        chronoChip: WorkoutLiveActivityChronoChip? = nil,
        chronoChipUsesCompactStyle: Bool = false
    ) {
        self.state = state
        self.chronoChip = chronoChip
        self.chronoChipUsesCompactStyle = chronoChipUsesCompactStyle
    }

    private var hasPreviousEntries: Bool {
        (state.previousPrimaryMetrics.map { !$0.isEmpty } ?? false)
            || (state.previousSecondaryMetrics.map { !$0.isEmpty } ?? false)
    }

    private var hasCurrentMetrics: Bool {
        !state.primaryMetrics.isEmpty
            || (state.secondaryMetrics.map { !$0.isEmpty } ?? false)
    }

    /// 1-based index of the set shown in the “previous” rows (`nil` on first set).
    private var previousSetOrdinal: Int? {
        guard state.setIndex > 1 else { return nil }
        return state.setIndex - 1
    }

    private var shouldShowCurrentSetOrdinal: Bool {
        state.setCount > 0 && state.setIndex > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkoutLiveActivityExerciseTitleRow(
                mainExerciseName: state.primaryExerciseName,
                partnerExerciseName: state.secondaryExerciseName,
                supersetPartnerIsLeading: state.supersetPartnerIsLeading ?? false
            )

            metricsAndOptionalChronoRow
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var metricsAndOptionalChronoRow: some View {
        let runningInline = chronoChip?.showsRunningChronoInCompactIsland == true

        VStack(alignment: .leading, spacing: 10) {
            if runningInline, let chip = chronoChip {
                HStack(alignment: .center, spacing: 12) {
                    metricsColumn
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    WorkoutLiveActivityChronoChipView(chip: chip, compact: chronoChipUsesCompactStyle)
                        .fixedSize(horizontal: true, vertical: false)
                }
            } else {
                metricsColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let chip = chronoChip, !runningInline {
                HStack {
                    Spacer(minLength: 0)
                    WorkoutLiveActivityChronoChipView(chip: chip, compact: chronoChipUsesCompactStyle)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }

    private var metricsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasPreviousEntries {
                VStack(alignment: .leading, spacing: 4) {
                    if let previous = state.previousPrimaryMetrics, !previous.isEmpty {
                        HStack(alignment: .lastTextBaseline, spacing: 8) {
                            if let ordinal = previousSetOrdinal {
                                WorkoutLiveActivitySetOrdinalLabel(setNumber: ordinal, style: .previous)
                            }
                            WorkoutLiveActivityMetricsUnitRow(metrics: previous, presentation: .smallSecondary)
                        }
                    }
                    if let previousSecondary = state.previousSecondaryMetrics, !previousSecondary.isEmpty {
                        HStack(alignment: .lastTextBaseline, spacing: 8) {
                            if let ordinal = previousSetOrdinal {
                                WorkoutLiveActivitySetOrdinalLabel(setNumber: ordinal, style: .previous)
                            }
                            WorkoutLiveActivityMetricsUnitRow(metrics: previousSecondary, presentation: .smallSecondary)
                        }
                    }
                }
            }

            if !hasCurrentMetrics {
                HStack(alignment: .center, spacing: 8) {
                    if shouldShowCurrentSetOrdinal {
                        WorkoutLiveActivitySetOrdinalLabel(setNumber: state.setIndex, style: .current)
                    }
                    Text(NSLocalizedString("addExercise", comment: ""))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.workoutLiveActivitySecondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if !state.primaryMetrics.isEmpty {
                        HStack(alignment: .lastTextBaseline, spacing: 8) {
                            if shouldShowCurrentSetOrdinal {
                                WorkoutLiveActivitySetOrdinalLabel(setNumber: state.setIndex, style: .current)
                            }
                            WorkoutLiveActivityMetricsUnitRow(metrics: state.primaryMetrics, presentation: .large)
                        }
                    }
                    if let secondary = state.secondaryMetrics, !secondary.isEmpty {
                        HStack(alignment: .lastTextBaseline, spacing: 8) {
                            if shouldShowCurrentSetOrdinal {
                                WorkoutLiveActivitySetOrdinalLabel(setNumber: state.setIndex, style: .current)
                            }
                            WorkoutLiveActivityMetricsUnitRow(metrics: secondary, presentation: .large)
                        }
                    }
                }
            }
        }
    }
}

/// Matches `WorkoutSetCell` set ordinal (`Text("\(n).")` bold rounded secondary); sizes differ for previous vs current.
private struct WorkoutLiveActivitySetOrdinalLabel: View {
    enum Style {
        case previous
        case current
    }

    let setNumber: Int
    let style: Style

    var body: some View {
        Text("\(setNumber).")
            .font(style == .previous ? .caption2.weight(.bold) : .title3.weight(.bold))
            .fontDesign(.rounded)
            .foregroundStyle(Color.workoutLiveActivitySecondary)
            .frame(minWidth: style == .previous ? 24 : 34, alignment: .trailing)
    }
}

private enum WorkoutLiveActivityUnitPresentation {
    /// Matches `UnitView` `.large` (lock screen + expanded Dynamic Island).
    case large
    /// Matches `UnitView` `.small` with value and unit in secondary styling.
    case smallSecondary
}

private struct WorkoutLiveActivityMetricsUnitRow: View {
    let metrics: ExerciseMetricDisplay
    let presentation: WorkoutLiveActivityUnitPresentation

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            if !metrics.repetitionSegments.isEmpty {
                WorkoutLiveActivitySegmentedNumericField(
                    segments: metrics.repetitionSegments,
                    segmentPlaceholders: metrics.repetitionSegmentPlaceholders,
                    unit: metrics.repetitionsUnit,
                    presentation: presentation
                )
            }
            if !metrics.weightSegments.isEmpty {
                WorkoutLiveActivitySegmentedNumericField(
                    segments: metrics.weightSegments,
                    segmentPlaceholders: metrics.weightSegmentPlaceholders,
                    unit: metrics.weightUnit,
                    presentation: presentation
                )
            }
        }
        .lineLimit(1)
    }
}

/// Typography aligned with `UnitView` / `IntegerField` + `DecimalField` in `WorkoutSetCell`.
private struct WorkoutLiveActivitySegmentedNumericField: View {
    let segments: [String]
    let segmentPlaceholders: [Bool]
    let unit: String
    let presentation: WorkoutLiveActivityUnitPresentation

    private var valueFont: Font {
        presentation == .large ? .title : .subheadline
    }

    private var unitFont: Font {
        presentation == .large ? .body : .caption2
    }

    private var allSegmentsPlaceholder: Bool {
        !segmentPlaceholders.isEmpty && segmentPlaceholders.allSatisfy(\.self)
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 {
                    Text(" / ")
                        .font(valueFont)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .foregroundStyle(separatorForeground)
                }
                Text(segment)
                    .font(valueFont)
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                    .foregroundStyle(foreground(forValueAt: index))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            if !unit.isEmpty {
                Text(unit.uppercased())
                    .font(unitFont)
                    .fontWeight(.semibold)
                    .fontDesign(.rounded)
                    .foregroundStyle(unitForeground)
            }
        }
    }

    private func foreground(forValueAt index: Int) -> Color {
        let isPlaceholder = index < segmentPlaceholders.count && segmentPlaceholders[index]
        switch presentation {
        case .large:
            if isPlaceholder { return Color.workoutLiveActivityPlaceholderText }
            return .white
        case .smallSecondary:
            return Color.workoutLiveActivitySecondary
        }
    }

    private var unitForeground: Color {
        switch presentation {
        case .large:
            if allSegmentsPlaceholder {
                return Color.workoutLiveActivityPlaceholderText
            }
            return Color.workoutLiveActivitySecondary
        case .smallSecondary:
            return Color.workoutLiveActivitySecondary
        }
    }

    private var separatorForeground: Color {
        switch presentation {
        case .large:
            Color.white.opacity(0.28)
        case .smallSecondary:
            Color.workoutLiveActivitySecondary.opacity(0.55)
        }
    }
}

#if DEBUG
private extension WorkoutLiveActivityAttributes {
    static var previewAttributes: WorkoutLiveActivityAttributes {
        WorkoutLiveActivityAttributes(
            workoutID: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
            startedAt: Date().addingTimeInterval(-22 * 60)
        )
    }

    static func previewDemoMetrics(
        reps: String,
        repsPlaceholder: Bool,
        weight: String,
        weightPlaceholder: Bool
    ) -> ExerciseMetricDisplay {
        ExerciseMetricDisplay(
            repetitionSegments: [reps],
            repetitionSegmentPlaceholders: [repsPlaceholder],
            repetitionsUnit: "reps",
            weightSegments: [weight],
            weightSegmentPlaceholders: [weightPlaceholder],
            weightUnit: "kg"
        )
    }

    static var previewCurrentSetEnteredWeightState: WorkoutLiveActivityAttributes.ContentState {
        WorkoutLiveActivityAttributes.ContentState(
            workoutTitle: "Current Workout",
            exerciseIndex: 2,
            exerciseCount: 5,
            setIndex: 3,
            setCount: 4,
            primaryExerciseName: "Incline Dumbbell Press",
            secondaryExerciseName: nil,
            supersetPartnerIsLeading: false,
            primaryMetrics: previewDemoMetrics(reps: "0", repsPlaceholder: true, weight: "32.5", weightPlaceholder: false),
            secondaryMetrics: nil,
            previousPrimaryMetrics: previewDemoMetrics(reps: "9", repsPlaceholder: false, weight: "30", weightPlaceholder: false),
            previousSecondaryMetrics: nil,
            themeToken: .chest,
            chronoChip: nil
        )
    }

    static var previewTemplateSetState: WorkoutLiveActivityAttributes.ContentState {
        WorkoutLiveActivityAttributes.ContentState(
            workoutTitle: "Push Day Template",
            exerciseIndex: 1,
            exerciseCount: 4,
            setIndex: 1,
            setCount: 3,
            primaryExerciseName: "Bench Press",
            secondaryExerciseName: nil,
            supersetPartnerIsLeading: false,
            primaryMetrics: previewDemoMetrics(reps: "8", repsPlaceholder: true, weight: "60", weightPlaceholder: true),
            secondaryMetrics: nil,
            previousPrimaryMetrics: nil,
            previousSecondaryMetrics: nil,
            themeToken: .chest,
            chronoChip: nil
        )
    }

    static var previewTimerRunningState: WorkoutLiveActivityAttributes.ContentState {
        WorkoutLiveActivityAttributes.ContentState(
            workoutTitle: "Push Day",
            exerciseIndex: 2,
            exerciseCount: 5,
            setIndex: 3,
            setCount: 4,
            primaryExerciseName: "Incline Dumbbell Press",
            secondaryExerciseName: nil,
            supersetPartnerIsLeading: false,
            primaryMetrics: previewDemoMetrics(reps: "10", repsPlaceholder: false, weight: "32.5", weightPlaceholder: false),
            secondaryMetrics: nil,
            previousPrimaryMetrics: previewDemoMetrics(reps: "8", repsPlaceholder: false, weight: "30", weightPlaceholder: false),
            previousSecondaryMetrics: nil,
            themeToken: .chest,
            chronoChip: WorkoutLiveActivityChronoChip(
                phase: .timerRunning,
                tintKind: .restTimer,
                muscleThemeToken: .chest,
                timerEndDate: Date().addingTimeInterval(95),
                timerTotalSeconds: 150,
                staticTickSeconds: nil,
                stopwatchStartDate: nil
            )
        )
    }

    static var previewStopwatchRunningState: WorkoutLiveActivityAttributes.ContentState {
        WorkoutLiveActivityAttributes.ContentState(
            workoutTitle: "Leg Day",
            exerciseIndex: 3,
            exerciseCount: 5,
            setIndex: 2,
            setCount: 4,
            primaryExerciseName: "Hack Squat",
            secondaryExerciseName: nil,
            supersetPartnerIsLeading: false,
            primaryMetrics: previewDemoMetrics(reps: "12", repsPlaceholder: false, weight: "140", weightPlaceholder: false),
            secondaryMetrics: nil,
            previousPrimaryMetrics: nil,
            previousSecondaryMetrics: nil,
            themeToken: .legs,
            chronoChip: WorkoutLiveActivityChronoChip(
                phase: .stopwatchRunning,
                tintKind: .manual,
                muscleThemeToken: nil,
                timerEndDate: nil,
                timerTotalSeconds: nil,
                staticTickSeconds: nil,
                stopwatchStartDate: Date().addingTimeInterval(-83)
            )
        )
    }

    /// First superset exercise not yet logged (`repetitionsFirstExercise == 0`): focus + metrics = first exercise.
    static var previewSupersetFocusFirstState: WorkoutLiveActivityAttributes.ContentState {
        WorkoutLiveActivityAttributes.ContentState(
            workoutTitle: "Arms",
            exerciseIndex: 4,
            exerciseCount: 6,
            setIndex: 2,
            setCount: 3,
            primaryExerciseName: "Cable Curls",
            secondaryExerciseName: "Rope Pushdowns",
            supersetPartnerIsLeading: false,
            primaryMetrics: previewDemoMetrics(reps: "12", repsPlaceholder: true, weight: "20", weightPlaceholder: true),
            secondaryMetrics: nil,
            previousPrimaryMetrics: previewDemoMetrics(reps: "10", repsPlaceholder: false, weight: "17.5", weightPlaceholder: false),
            previousSecondaryMetrics: previewDemoMetrics(reps: "12", repsPlaceholder: false, weight: "25", weightPlaceholder: false),
            themeToken: .biceps,
            chronoChip: nil
        )
    }

    /// First exercise has reps logged: focus + metrics = second exercise; partner (first) leads with arrow.
    static var previewSupersetStopwatchPausedState: WorkoutLiveActivityAttributes.ContentState {
        WorkoutLiveActivityAttributes.ContentState(
            workoutTitle: "Arms",
            exerciseIndex: 4,
            exerciseCount: 6,
            setIndex: 2,
            setCount: 3,
            primaryExerciseName: "Rope Pushdowns",
            secondaryExerciseName: "Cable Curls",
            supersetPartnerIsLeading: true,
            primaryMetrics: previewDemoMetrics(reps: "15", repsPlaceholder: false, weight: "27.5", weightPlaceholder: false),
            secondaryMetrics: nil,
            previousPrimaryMetrics: previewDemoMetrics(reps: "10", repsPlaceholder: false, weight: "17.5", weightPlaceholder: false),
            previousSecondaryMetrics: previewDemoMetrics(reps: "12", repsPlaceholder: false, weight: "25", weightPlaceholder: false),
            themeToken: .triceps,
            chronoChip: WorkoutLiveActivityChronoChip(
                phase: .stopwatchPaused,
                tintKind: .restStopwatch,
                muscleThemeToken: nil,
                timerEndDate: nil,
                timerTotalSeconds: nil,
                staticTickSeconds: 83,
                stopwatchStartDate: nil
            )
        )
    }
}

// Widget extension targets only support ActivityKit-style previews (`as: .content` / `.dynamicIsland(…)`).
// One `#Preview` per canvas tab (single `contentState` each).

#Preview("Lock · current set", as: .content, using: WorkoutLiveActivityAttributes.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityAttributes.previewCurrentSetEnteredWeightState
}

#Preview("Lock · template", as: .content, using: WorkoutLiveActivityAttributes.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityAttributes.previewTemplateSetState
}

#Preview("Lock · timer", as: .content, using: WorkoutLiveActivityAttributes.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityAttributes.previewTimerRunningState
}

#Preview("Lock · stopwatch", as: .content, using: WorkoutLiveActivityAttributes.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityAttributes.previewStopwatchRunningState
}

#Preview("Lock · superset · 1st", as: .content, using: WorkoutLiveActivityAttributes.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityAttributes.previewSupersetFocusFirstState
}

#Preview("Lock · superset · 2nd", as: .content, using: WorkoutLiveActivityAttributes.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityAttributes.previewSupersetStopwatchPausedState
}

#Preview("Island expanded · timer", as: .dynamicIsland(.expanded), using: WorkoutLiveActivityAttributes.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityAttributes.previewTimerRunningState
}

#Preview("Island expanded · superset", as: .dynamicIsland(.expanded), using: WorkoutLiveActivityAttributes.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityAttributes.previewSupersetStopwatchPausedState
}

#Preview("Island compact · timer", as: .dynamicIsland(.compact), using: WorkoutLiveActivityAttributes.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityAttributes.previewTimerRunningState
}

#Preview("Island compact · superset", as: .dynamicIsland(.compact), using: WorkoutLiveActivityAttributes.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityAttributes.previewSupersetStopwatchPausedState
}

#Preview("Island minimal · timer", as: .dynamicIsland(.minimal), using: WorkoutLiveActivityAttributes.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityAttributes.previewTimerRunningState
}

#Preview("Island minimal · superset", as: .dynamicIsland(.minimal), using: WorkoutLiveActivityAttributes.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityAttributes.previewSupersetStopwatchPausedState
}
#endif

/// Compact / minimal Dynamic Island trailing: live rest timer or stopwatch (`m:ss` via `showsHours: false`) when running,
/// otherwise elapsed workout duration.
private struct WorkoutCompactIslandTrailingContent: View {
    let startedAt: Date
    let chronoChip: WorkoutLiveActivityChronoChip?
    let font: Font

    var body: some View {
        if let chip = chronoChip, chip.showsRunningChronoInCompactIsland {
            WorkoutCompactIslandChronoLabel(chip: chip, font: font)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            WorkoutElapsedDurationLabel(startedAt: startedAt, font: font)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private struct WorkoutCompactIslandChronoLabel: View {
    let chip: WorkoutLiveActivityChronoChip
    let font: Font

    var body: some View {
        compactChronoText
            .font(font)
            .monospacedDigit()
            .foregroundStyle(chip.liveActivityChronoForegroundTint)
            .multilineTextAlignment(.trailing)
            .contentTransition(.numericText())
    }

    @ViewBuilder
    private var compactChronoText: some View {
        switch chip.phase {
        case .timerRunning:
            if let end = chip.timerEndDate, let total = chip.timerTotalSeconds, total > 0 {
                let start = end.addingTimeInterval(-total)
                Text(timerInterval: start...end, countsDown: true, showsHours: false)
            }
        case .stopwatchRunning:
            if let start = chip.stopwatchStartDate {
                Text(timerInterval: start...Date.distantFuture, countsDown: false, showsHours: false)
            }
        case .timerPaused, .stopwatchPaused:
            EmptyView()
        }
    }
}

/// Elapsed workout time in compact minutes (`12min`, `1h 5min`). Uses a **periodic timeline** from the
/// workout start (60s cadence) so the label advances on the extension side—no Activity pushes each minute—same idea as
/// `Text(timerInterval:)` for the rest chip (system/schedule-driven updates, app can be suspended).
private struct WorkoutElapsedDurationLabel: View {
    let startedAt: Date
    let font: Font

    var body: some View {
        TimelineView(PeriodicTimelineSchedule(from: startedAt, by: 60)) { _ in
            Text(WorkoutDurationFormatting.label(from: startedAt, reference: Date()))
                .font(font)
                .monospacedDigit()
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .contentTransition(.numericText())
        }
    }
}

private enum WorkoutDurationFormatting {
    static func label(from start: Date, reference now: Date) -> String {
        let totalSeconds = max(0, Int(now.timeIntervalSince(start)))
        let totalMinutes = totalSeconds / 60
        let hours = totalMinutes / 60
        let minutesRemainder = totalMinutes % 60
        let minToken = NSLocalizedString("min", comment: "")
        if hours > 0 {
            if minutesRemainder > 0 {
                return "\(hours)h \(minutesRemainder)\(minToken)"
            }
            return "\(hours)h"
        }
        return "\(totalMinutes)\(minToken)"
    }
}

/// Dynamic Island compact leading: first weight segment from current metrics, styled like `UnitView` (`.small`). Falls back to set fraction when there is no weight.
private struct WorkoutCompactIslandLeadingContent: View {
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        Group {
            if let triple = state.primaryMetrics.compactWeightValueUnitAndPlaceholder {
                WorkoutCompactIslandWeightUnitView(
                    value: triple.value,
                    unit: triple.unit,
                    valueUsesPlaceholderStyle: triple.isPlaceholder
                )
            } else {
                WorkoutCompactSetFraction(state: state)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Mirrors `UnitView` (`.small`): rounded bold value + smaller semibold unit; widget target cannot import app `UnitView`.
private struct WorkoutCompactIslandWeightUnitView: View {
    let value: String
    let unit: String
    var valueUsesPlaceholderStyle: Bool = false

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .fontDesign(.rounded)
                .foregroundStyle(valueUsesPlaceholderStyle ? Color.workoutLiveActivityPlaceholderText : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if !unit.isEmpty {
                Text(unit.uppercased())
                    .foregroundStyle(valueUsesPlaceholderStyle ? Color.workoutLiveActivityPlaceholderText : Color.workoutLiveActivitySecondary)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .fontDesign(.rounded)
                    .lineLimit(1)
            }
        }
    }
}

private struct WorkoutCompactSetFraction: View {
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        Text(state.setFractionLabel ?? "—")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
    }
}

private extension WorkoutLiveActivityThemeToken {
    var accentColor: Color {
        switch self {
        case .chest:
            Color(red: 160 / 255, green: 210 / 255, blue: 120 / 255)
        case .triceps:
            Color(red: 100 / 255, green: 200 / 255, blue: 1)
        case .shoulders:
            Color(red: 1, green: 170 / 255, blue: 100 / 255)
        case .biceps:
            Color(red: 64 / 255, green: 224 / 255, blue: 208 / 255)
        case .back:
            Color(red: 90 / 255, green: 150 / 255, blue: 200 / 255)
        case .legs:
            Color(red: 1, green: 112 / 255, blue: 100 / 255)
        case .abdominals:
            Color(red: 140 / 255, green: 120 / 255, blue: 200 / 255)
        case .cardio:
            Color(red: 180 / 255, green: 160 / 255, blue: 220 / 255)
        case .neutral:
            Color(red: 0.63, green: 0.68, blue: 0.76)
        }
    }

    var secondaryAccentColor: Color {
        accentColor.opacity(0.78)
    }
}
