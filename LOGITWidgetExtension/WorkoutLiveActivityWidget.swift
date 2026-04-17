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

    /// Third-tier text on black surfaces (dimmed below `workoutLiveActivitySecondary`).
    static var workoutLiveActivityTertiary: Color {
        Color(red: 0.53, green: 0.54, blue: 0.59)
    }

    /// Mirrors the app accent color asset for dark surfaces because the widget extension should not depend on loading `AccentColor`.
    static var workoutLiveActivityManualChronoTint: Color {
        Color(red: 0.729, green: 0.987, blue: 0.310)
    }
}

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutLiveActivityAttributes.self) { context in
            WorkoutLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(context.state.liveActivityChromeTint)
            } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WorkoutLiveActivityExpandedHeaderLeading(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutLiveActivityExpandedHeaderTrailing(
                        attributes: context.attributes,
                        state: context.state
                    )
                }
                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WorkoutLiveActivityExpandedContent(state: context.state)
                        .padding(.top, 2)
                        .padding(.bottom, 4)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                WorkoutCompactIslandLeadingContent(state: context.state)
            } compactTrailing: {
                WorkoutCompactIslandTrailingContent(
                    state: context.state,
                    startedAt: context.attributes.startedAt,
                    font: .caption2.weight(.bold)
                )
            } minimal: {
                WorkoutMinimalIslandContent(
                    state: context.state,
                    font: .caption2.weight(.bold)
                )
            }
            .keylineTint(context.state.liveActivityChromeTint)
        }
    }
}

private struct WorkoutLiveActivityLockScreenContent: View {
    let attributes: WorkoutLiveActivityAttributes
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkoutLiveActivityHeaderRow(attributes: attributes, state: state)

            WorkoutLiveActivityPrimaryContent(state: state, chronoChipUsesCompactStyle: false)
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

private struct WorkoutLiveActivityPrimaryContent: View {
    let state: WorkoutLiveActivityAttributes.ContentState
    let chronoChipUsesCompactStyle: Bool

    var body: some View {
        if let chip = state.chronoChip {
            WorkoutLiveActivityRunningFocus(
                state: state,
                chip: chip,
                compactLayout: chronoChipUsesCompactStyle
            )
                .frame(maxWidth: .infinity)
        } else {
            WorkoutExerciseCard(
                state: state,
                chronoChip: state.chronoChip,
                chronoChipUsesCompactStyle: chronoChipUsesCompactStyle
            )
        }
    }
}

private struct WorkoutLiveActivityExpandedContent: View {
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        if let chip = state.chronoChip {
            WorkoutLiveActivityExpandedRunningFocus(state: state, chip: chip)
        } else {
            WorkoutLiveActivityExpandedExerciseCard(state: state)
        }
    }
}

private func workoutLiveActivityRestTimeString(seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    return "\(m):\(String(format: "%02d", s))"
}

private func workoutLiveActivityDurationString(totalSeconds: Int) -> String {
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
        return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
    }

    return workoutLiveActivityRestTimeString(seconds: totalSeconds)
}

private func workoutLiveActivityCountdownRange(
    endingAt endDate: Date,
    referenceDate: Date = .now
) -> ClosedRange<Date> {
    let clampedEndDate = max(endDate, referenceDate)
    return referenceDate ... clampedEndDate
}

private extension WorkoutLiveActivityChronoChip {
    var isRunning: Bool {
        switch phase {
        case .timerRunning, .stopwatchRunning:
            true
        case .timerPaused, .stopwatchPaused:
            false
        }
    }

    func displayText(at referenceDate: Date) -> String? {
        switch phase {
        case .timerRunning:
            guard let end = timerEndDate else { return nil }
            let remainingSeconds = max(0, Int(end.timeIntervalSince(referenceDate).rounded(.down)))
            return workoutLiveActivityRestTimeString(seconds: remainingSeconds)
        case .stopwatchRunning:
            guard let start = stopwatchStartDate else { return nil }
            let elapsedSeconds = max(0, Int(referenceDate.timeIntervalSince(start).rounded(.down)))
            return workoutLiveActivityRestTimeString(seconds: elapsedSeconds)
        case .timerPaused, .stopwatchPaused:
            guard let staticTickSeconds else { return nil }
            return workoutLiveActivityRestTimeString(seconds: staticTickSeconds)
        }
    }

    var liveActivityHeaderTitle: String {
        switch (tintKind, phase) {
        case (.restTimer, _):
            NSLocalizedString("autoRestTimer", comment: "")
        case (.restStopwatch, _):
            NSLocalizedString("autoRestStopwatch", comment: "")
        case (_, .timerRunning), (_, .timerPaused):
            NSLocalizedString("timer", comment: "")
        case (_, .stopwatchRunning), (_, .stopwatchPaused):
            NSLocalizedString("stopwatch", comment: "")
        }
    }

    var headerTrailingTitle: String? {
        switch phase {
        case .timerRunning:
            guard let totalSeconds = timerTotalSeconds else { return nil }
            return workoutLiveActivityDurationString(totalSeconds: max(0, Int(totalSeconds.rounded(.down))))
        case .timerPaused, .stopwatchRunning, .stopwatchPaused:
            return nil
        }
    }
}

private extension WorkoutLiveActivityAttributes.ContentState {
    var liveActivityChromeTint: Color {
        chronoChip?.liveActivityChronoForegroundTint ?? themeToken.accentColor
    }

    var liveActivityHeaderLeadingTitle: String {
        chronoChip?.liveActivityHeaderTitle ?? workoutTitle
    }

    var liveActivityHeaderLeadingColor: Color {
        chronoChip?.liveActivityChronoForegroundTint ?? Color.workoutLiveActivitySecondary
    }

    var liveActivityHeaderTrailingColor: Color {
        chronoChip?.liveActivityChronoForegroundTint ?? .white
    }

    var progressBadgeTitle: String? {
        if let setFractionLabel {
            return "\(NSLocalizedString("set", comment: "")) \(setFractionLabel)"
        }

        guard exerciseCount > 0, exerciseIndex > 0 else { return nil }
        return "\(NSLocalizedString("exercise", comment: "")) \(exerciseIndex)/\(exerciseCount)"
    }

    var expandedHeaderIconName: String {
        if let chronoChip {
            return chronoChip.compactIslandIconName
        }

        return "dumbbell.fill"
    }
}

private struct WorkoutLiveActivityHeaderRow: View {
    let attributes: WorkoutLiveActivityAttributes
    let state: WorkoutLiveActivityAttributes.ContentState

    private var activeChronoChip: WorkoutLiveActivityChronoChip? {
        state.chronoChip
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let activeChronoChip {
                    Image(systemName: activeChronoChip.compactIslandIconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(leadingColor)
                }

                Text(leadingTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(leadingColor)
                    .lineLimit(1)
            }

            trailingContent
        }
    }

    private var leadingTitle: String {
        state.liveActivityHeaderLeadingTitle
    }

    private var trailingTitle: String? {
        if let chip = activeChronoChip {
            return chip.headerTrailingTitle
        }
        return nil
    }

    private var leadingColor: Color {
        state.liveActivityHeaderLeadingColor
    }

    private var trailingColor: Color {
        state.liveActivityHeaderTrailingColor
    }

    private var progressBadgeTitle: String? {
        state.progressBadgeTitle
    }

    @ViewBuilder
    private var trailingContent: some View {
        if let trailingTitle {
            HStack(alignment: .center, spacing: 8) {
                if let progressBadgeTitle {
                    WorkoutLiveActivityProgressBadge(title: progressBadgeTitle)
                }

                Text(trailingTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(trailingColor)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else if activeChronoChip == nil {
            HStack(alignment: .center, spacing: 8) {
                if let progressBadgeTitle {
                    WorkoutLiveActivityProgressBadge(title: progressBadgeTitle)
                }

                WorkoutElapsedDurationLabel(
                    startedAt: attributes.startedAt,
                    font: .caption.weight(.bold)
                )
            }
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else if let progressBadgeTitle {
            WorkoutLiveActivityProgressBadge(title: progressBadgeTitle)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            Spacer(minLength: 0)
        }
    }
}

private struct WorkoutLiveActivityExpandedHeaderLeading: View {
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        Image(systemName: state.expandedHeaderIconName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(state.liveActivityChromeTint)
    }
}

private struct WorkoutLiveActivityExpandedHeaderTrailing: View {
    let attributes: WorkoutLiveActivityAttributes
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        WorkoutElapsedDurationLabel(
            startedAt: attributes.startedAt,
            font: .caption.weight(.bold),
            abbreviated: true
        )
    }
}

private struct WorkoutLiveActivityProgressBadge: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.bold))
            .fontDesign(.rounded)
            .foregroundStyle(Color.workoutLiveActivitySecondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(Color.white.opacity(0.07))
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    }
            }
    }
}

private struct WorkoutLiveActivityRunningChronoText: View {
    let chip: WorkoutLiveActivityChronoChip

    var body: some View {
        if chip.isRunning {
            runningText()
        } else if let label = chip.displayText(at: .now) {
            Text(label)
        } else {
            Text("0:00")
                .opacity(0)
        }
    }

    @ViewBuilder
    private func runningText() -> some View {
        switch chip.phase {
        case .timerRunning:
            if let end = chip.timerEndDate {
                Text(
                    timerInterval: workoutLiveActivityCountdownRange(endingAt: end),
                    countsDown: true
                )
            } else {
                Text("0:00").opacity(0)
            }
        case .stopwatchRunning:
            if let start = chip.stopwatchStartDate {
                Text(start, style: .timer)
            } else {
                Text("0:00").opacity(0)
            }
        case .timerPaused, .stopwatchPaused:
            Text("0:00").opacity(0)
        }
    }
}

private struct WorkoutLiveActivityRunningFocus: View {
    let state: WorkoutLiveActivityAttributes.ContentState
    let chip: WorkoutLiveActivityChronoChip
    var compactLayout: Bool = false

    private var nextSetTitle: String {
        let trimmedPrimary = state.primaryExerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPrimary.isEmpty ? NSLocalizedString("exercise", comment: "") : trimmedPrimary
    }

    private var hasCurrentMetrics: Bool {
        !state.primaryMetrics.isEmpty
    }

    private var verticalSpacing: CGFloat {
        compactLayout ? 2 : 10
    }

    private var chronoFontSize: CGFloat {
        compactLayout ? 32 : 42
    }

    private var contextLabelText: String {
        switch chip.tintKind {
        case .manual:
            "CURRENT"
        case .restTimer, .restStopwatch:
            "UP NEXT"
        }
    }

    private var contextLabelFont: Font {
        .caption2.weight(.semibold)
    }

    private var contextLabelLeadingInset: CGFloat {
        compactLayout ? 10 : 12
    }

    private var contextLabelBottomSpacing: CGFloat {
        compactLayout ? 1 : 5
    }

    var body: some View {
        VStack(spacing: verticalSpacing) {
            WorkoutLiveActivityRunningChronoText(chip: chip)
                .font(.system(size: chronoFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(chip.liveActivityChronoForegroundTint)
                .opacity(chip.isRunning ? 1 : 0.7)
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: contextLabelBottomSpacing) {
                Text(contextLabelText)
                    .font(contextLabelFont)
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.workoutLiveActivitySecondary)
                    .padding(.leading, contextLabelLeadingInset)

                WorkoutLiveActivityNextSetPill(
                    title: nextSetTitle,
                    partnerExerciseName: state.secondaryExerciseName,
                    supersetPartnerIsLeading: state.supersetPartnerIsLeading ?? false,
                    metrics: hasCurrentMetrics ? state.primaryMetrics : nil,
                    compactLayout: compactLayout
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct WorkoutLiveActivityExpandedRunningFocus: View {
    let state: WorkoutLiveActivityAttributes.ContentState
    let chip: WorkoutLiveActivityChronoChip

    private var hasCurrentMetrics: Bool {
        !state.primaryMetrics.isEmpty
    }

    private var contextLabelText: String {
        switch chip.tintKind {
        case .manual:
            "CURRENT"
        case .restTimer, .restStopwatch:
            "UP NEXT"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WorkoutLiveActivityExpandedTitleBar(state: state)

            WorkoutLiveActivityRunningChronoText(chip: chip)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(chip.liveActivityChronoForegroundTint)
                .opacity(chip.isRunning ? 1 : 0.7)
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)

            WorkoutLiveActivityExpandedMetricsBar(
                label: contextLabelText,
                metrics: hasCurrentMetrics ? state.primaryMetrics : nil
            )
        }
    }
}

/// Mirrors `WorkoutRecorderFloatingTimerButton` styling, but keeps the Live Activity chrono chip on a plain black capsule.
/// Avoid `Button` and `Material` here—Live Activities on the lock screen often show a stuck spinner when those fail to resolve in the extension.
/// Running timer/stopwatch digits use system timer text so the lock screen keeps advancing without Activity pushes every tick.
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
            ZStack {
                Capsule()
                    .fill(Color.black)

                Capsule()
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.9)
            }
        }
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.12), radius: compact ? 12 : 18, y: compact ? 5 : 8)
    }

    @ViewBuilder
    private var chronoTimeText: some View {
        if chip.isRunning {
            runningText()
        } else if let label = chip.displayText(at: .now) {
            Text(label)
        } else {
            Text("0:00")
                .opacity(0)
        }
    }

    @ViewBuilder
    private func runningText() -> some View {
        switch chip.phase {
        case .timerRunning:
            if let end = chip.timerEndDate {
                Text(
                    timerInterval: workoutLiveActivityCountdownRange(endingAt: end),
                    countsDown: true
                )
            } else {
                Text("0:00").opacity(0)
            }
        case .stopwatchRunning:
            if let start = chip.stopwatchStartDate {
                Text(start, style: .timer)
            } else {
                Text("0:00").opacity(0)
            }
        case .timerPaused, .stopwatchPaused:
            Text("0:00").opacity(0)
        }
    }
}

private extension WorkoutLiveActivityChronoChipView {
    var iconName: String {
        switch chip.phase {
        case .timerRunning, .timerPaused:
            return "timer"
        case .stopwatchRunning, .stopwatchPaused:
            return "stopwatch"
        }
    }

    var horizontalPadding: CGFloat {
        showsTimeLabel ? (compact ? 12 : 16) : (compact ? 11 : 14)
    }

    var showsTimeLabel: Bool {
        chip.displayText(at: .now) != nil
    }

    var chipForegroundTint: Color {
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
            staticTickSeconds != nil
        }
    }

    var compactIslandIconName: String {
        switch phase {
        case .timerRunning, .timerPaused:
            "timer"
        case .stopwatchRunning, .stopwatchPaused:
            "stopwatch"
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
                        arrowPointingToFocusedExercise
                        mainText
                    } else {
                        mainText
                        arrowPointingToFocusedExercise
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

    private var arrowPointingToFocusedExercise: some View {
        Image(systemName: "arrow.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.workoutLiveActivitySecondary)
            .baselineOffset(-1)
    }
}

private struct WorkoutLiveActivityCompactExerciseTitleRow: View {
    let mainExerciseName: String
    let partnerExerciseName: String?
    let supersetPartnerIsLeading: Bool

    var body: some View {
        Group {
            if let partnerExerciseName, !partnerExerciseName.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if supersetPartnerIsLeading {
                        partnerText(partnerExerciseName)
                        arrowPointingToFocusedExercise
                        mainText
                    } else {
                        mainText
                        arrowPointingToFocusedExercise
                        partnerText(partnerExerciseName)
                    }
                }
            } else {
                mainText
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mainText: some View {
        Text(mainExerciseName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .layoutPriority(1)
    }

    private func partnerText(_ name: String) -> some View {
        Text(name)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.workoutLiveActivitySecondary)
    }

    private var arrowPointingToFocusedExercise: some View {
        Image(systemName: "arrow.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.workoutLiveActivitySecondary)
            .baselineOffset(-0.5)
    }
}

private struct WorkoutLiveActivityExpandedTitleBar: View {
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            WorkoutLiveActivityExerciseTitleRow(
                mainExerciseName: state.primaryExerciseName,
                partnerExerciseName: state.secondaryExerciseName,
                supersetPartnerIsLeading: state.supersetPartnerIsLeading ?? false
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if let progressBadgeTitle = state.progressBadgeTitle {
                WorkoutLiveActivityProgressBadge(title: progressBadgeTitle)
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
    }
}

private struct WorkoutLiveActivityExpandedExerciseCard: View {
    let state: WorkoutLiveActivityAttributes.ContentState

    private var displayedPreviousMetrics: [ExerciseMetricDisplay] {
        let metrics = [state.previousPrimaryMetrics, state.previousSecondaryMetrics]
            .compactMap { metric -> ExerciseMetricDisplay? in
                guard let metric, !metric.isEmpty else { return nil }
                return metric
            }

        return state.secondaryExerciseName == nil ? metrics : Array(metrics.prefix(1))
    }

    private var hasCurrentMetrics: Bool {
        !state.primaryMetrics.isEmpty
            || (state.secondaryMetrics.map { !$0.isEmpty } ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkoutLiveActivityExpandedTitleBar(state: state)

            VStack(alignment: .leading, spacing: 6) {
                if let previous = displayedPreviousMetrics.first {
                    WorkoutLiveActivitySetPillRow(label: "prev", style: .previous) {
                        WorkoutLiveActivityMetricsUnitRow(metrics: previous, presentation: .smallTertiary)
                    }
                }

                if !hasCurrentMetrics {
                    WorkoutLiveActivitySetPillRow(label: "current", style: .current) {
                        Text(NSLocalizedString("addExercise", comment: ""))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.workoutLiveActivitySecondary)
                    }
                } else {
                    WorkoutLiveActivitySetPillRow(label: "current", style: .current) {
                        WorkoutLiveActivityMetricsUnitRow(metrics: state.primaryMetrics, presentation: .normal)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct WorkoutLiveActivityExpandedMetricsBar: View {
    let label: String
    let metrics: ExerciseMetricDisplay?

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(Color.workoutLiveActivitySecondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let metrics, !metrics.isEmpty {
                WorkoutLiveActivityMetricsUnitRow(metrics: metrics, presentation: .small)
            } else {
                Text(NSLocalizedString("addExercise", comment: ""))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.workoutLiveActivitySecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.9)
                }
        }
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
        !displayedPreviousMetrics.isEmpty
    }

    private var hasCurrentMetrics: Bool {
        !state.primaryMetrics.isEmpty
            || (state.secondaryMetrics.map { !$0.isEmpty } ?? false)
    }

    private var usesCondensedLayout: Bool {
        chronoChipUsesCompactStyle && chronoChip == nil
    }

    /// 1-based index of the set shown in the “previous” rows (`nil` on first set).
    private var previousSetOrdinal: Int? {
        guard state.setIndex > 1 else { return nil }
        return state.setIndex - 1
    }

    private var shouldShowCurrentSetOrdinal: Bool {
        state.setCount > 0 && state.setIndex > 0
    }

    private var displayedPreviousMetrics: [ExerciseMetricDisplay] {
        let metrics = [state.previousPrimaryMetrics, state.previousSecondaryMetrics]
            .compactMap { metric -> ExerciseMetricDisplay? in
                guard let metric, !metric.isEmpty else { return nil }
                return metric
            }

        // Supersets only surface the focused exercise in the Live Activity.
        return state.secondaryExerciseName == nil ? metrics : Array(metrics.prefix(1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow

            metricsAndOptionalChronoRow
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var titleRow: some View {
        if usesCondensedLayout {
            WorkoutLiveActivityCompactExerciseTitleRow(
                mainExerciseName: state.primaryExerciseName,
                partnerExerciseName: state.secondaryExerciseName,
                supersetPartnerIsLeading: state.supersetPartnerIsLeading ?? false
            )
            .font(.headline.weight(.semibold))
        } else {
            WorkoutLiveActivityExerciseTitleRow(
                mainExerciseName: state.primaryExerciseName,
                partnerExerciseName: state.secondaryExerciseName,
                supersetPartnerIsLeading: state.supersetPartnerIsLeading ?? false
            )
        }
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
        VStack(alignment: .leading, spacing: 0) {
            if hasPreviousEntries && !usesCondensedLayout {
                VStack(alignment: .leading, spacing: 4) {
                    if let previous = displayedPreviousMetrics.first {
                        WorkoutLiveActivitySetPillRow(label: "prev", style: .previous) {
                            WorkoutLiveActivityMetricsUnitRow(metrics: previous, presentation: .smallTertiary)
                        }
                    }
                    if displayedPreviousMetrics.count > 1, let previousSecondary = displayedPreviousMetrics.last {
                        WorkoutLiveActivitySetPillRow(label: "prev", style: .previous) {
                            WorkoutLiveActivityMetricsUnitRow(metrics: previousSecondary, presentation: .smallTertiary)
                        }
                    }
                }
            }

            if !hasCurrentMetrics {
                WorkoutLiveActivitySetPillRow(label: "current", style: .current) {
                    Text(NSLocalizedString("addExercise", comment: ""))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.workoutLiveActivitySecondary)
                }
            } else {
                VStack(alignment: .leading, spacing: usesCondensedLayout ? 0 : 8) {
                    currentMetricsRow

                    if !usesCondensedLayout,
                       let secondary = state.secondaryMetrics,
                       !secondary.isEmpty
                    {
                        WorkoutLiveActivitySetPillRow(label: "current", style: .current) {
                            WorkoutLiveActivityMetricsUnitRow(metrics: secondary, presentation: .normal)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var currentMetricsRow: some View {
        if !state.primaryMetrics.isEmpty {
            WorkoutLiveActivitySetPillRow(label: "current", style: .current) {
                WorkoutLiveActivityMetricsUnitRow(
                    metrics: state.primaryMetrics,
                    presentation: usesCondensedLayout ? .small : .normal
                )
            }
        }
    }
}

/// Matches `WorkoutSetCell` set ordinal (`Text("\(n)")` bold rounded secondary); sizes differ for previous vs current.
private struct WorkoutLiveActivitySetOrdinalLabel: View {
    enum Style {
        case previous
        case current
    }

    let setNumber: Int
    let style: Style

    var body: some View {
        Text("\(setNumber)")
            .font(style == .previous ? .caption2.weight(.bold) : .title3.weight(.bold))
            .fontDesign(.rounded)
            .foregroundStyle(Color.workoutLiveActivitySecondary)
            .frame(minWidth: style == .previous ? 24 : 34, alignment: .trailing)
    }
}

private enum WorkoutLiveActivityUnitPresentation {
    /// Matches `UnitView` `.normal`.
    case normal
    /// Matches `UnitView` `.small`.
    case small
    /// Matches `UnitView` `.small`, but in tertiary styling.
    case smallTertiary
}

private struct WorkoutLiveActivityMetricsUnitRow: View {
    let metrics: ExerciseMetricDisplay
    let presentation: WorkoutLiveActivityUnitPresentation

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            if presentation == .normal {
                if !metrics.repetitionSegments.isEmpty {
                    WorkoutLiveActivityUnitViewGroup(
                        segments: metrics.repetitionSegments,
                        segmentPlaceholders: metrics.repetitionSegmentPlaceholders,
                        unit: metrics.repetitionsUnit.uppercased(),
                        configuration: .normal
                    )
                }
                if !metrics.weightSegments.isEmpty {
                    WorkoutLiveActivityUnitViewGroup(
                        segments: metrics.weightSegments,
                        segmentPlaceholders: metrics.weightSegmentPlaceholders,
                        unit: metrics.weightUnit.uppercased(),
                        configuration: .normal
                    )
                }
            } else {
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
        }
        .lineLimit(1)
    }
}

private struct WorkoutLiveActivityUnitView: View {
    let value: String
    let unit: String
    let configuration: WorkoutLiveActivityUnitViewConfiguration
    let valueColor: Color
    let unitColor: Color

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(value)
                .font(configuration == .large ? .title : configuration == .small ? .subheadline : .title3)
                .fontWeight(.bold)
                .fontDesign(.rounded)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            if !unit.isEmpty {
                Text(unit)
                    .font(configuration == .large ? .body : configuration == .small ? .caption2 : .subheadline)
                    .fontWeight(.semibold)
                    .fontDesign(.rounded)
                    .foregroundStyle(unitColor)
                    .lineLimit(1)
            }
        }
    }
}

private enum WorkoutLiveActivityUnitViewConfiguration {
    case normal, large, small
}

private struct WorkoutLiveActivityUnitViewGroup: View {
    let segments: [String]
    let segmentPlaceholders: [Bool]
    let unit: String
    let configuration: WorkoutLiveActivityUnitViewConfiguration

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 {
                    Text(" / ")
                        .font(configuration == .small ? .subheadline : .title3)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.white.opacity(0.28))
                }

                let isPlaceholder = index < segmentPlaceholders.count && segmentPlaceholders[index]
                WorkoutLiveActivityUnitView(
                    value: segment,
                    unit: unit,
                    configuration: configuration,
                    valueColor: isPlaceholder ? Color.workoutLiveActivityPlaceholderText : .white,
                    unitColor: isPlaceholder ? Color.workoutLiveActivityPlaceholderText : Color.workoutLiveActivitySecondary
                )
            }
        }
    }
}

/// Typography aligned with `UnitView` / `IntegerField` + `DecimalField` in `WorkoutSetCell`.
private struct WorkoutLiveActivitySegmentedNumericField: View {
    let segments: [String]
    let segmentPlaceholders: [Bool]
    let unit: String
    let presentation: WorkoutLiveActivityUnitPresentation

    private var valueFont: Font {
        switch presentation {
        case .normal:
            return .title3
        case .small:
            return .subheadline
        case .smallTertiary:
            return .subheadline
        }
    }

    private var unitFont: Font {
        switch presentation {
        case .normal:
            return .subheadline
        case .small:
            return .caption2
        case .smallTertiary:
            return .caption2
        }
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
        case .normal:
            if isPlaceholder { return Color.workoutLiveActivityPlaceholderText }
            return .white
        case .small:
            return Color.workoutLiveActivitySecondary
        case .smallTertiary:
            return Color.workoutLiveActivityTertiary
        }
    }

    private var unitForeground: Color {
        switch presentation {
        case .normal:
            if allSegmentsPlaceholder {
                return Color.workoutLiveActivityPlaceholderText
            }
            return Color.workoutLiveActivitySecondary
        case .small:
            return Color.workoutLiveActivitySecondary
        case .smallTertiary:
            return Color.workoutLiveActivityTertiary
        }
    }

    private var separatorForeground: Color {
        switch presentation {
        case .normal:
            Color.white.opacity(0.28)
        case .small:
            Color.workoutLiveActivitySecondary.opacity(0.55)
        case .smallTertiary:
            Color.workoutLiveActivityTertiary.opacity(0.55)
        }
    }
}

private struct RoundedCornerRect: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

/// Stroke for the "prev" pill: draws only top + left/right edges (no bottom line).
private struct WorkoutLiveActivityPrevPillStroke: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()

        let r = min(radius, min(rect.width, rect.height) / 2)
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        // Left side up to the start of the top-left curve.
        p.move(to: CGPoint(x: minX, y: maxY))
        p.addLine(to: CGPoint(x: minX, y: minY + r))

        // Top-left corner arc.
        p.addArc(
            center: CGPoint(x: minX + r, y: minY + r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        // Top edge.
        p.addLine(to: CGPoint(x: maxX - r, y: minY))

        // Top-right corner arc.
        p.addArc(
            center: CGPoint(x: maxX - r, y: minY + r),
            radius: r,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Right side down.
        p.addLine(to: CGPoint(x: maxX, y: maxY))

        return p
    }
}

private struct WorkoutLiveActivitySetPillRow<Content: View>: View {
    enum Style {
        case current
        case previous
    }

    let label: String
    let style: Style
    @ViewBuilder var content: Content

    private var labelColor: Color {
        style == .previous ? Color.workoutLiveActivityTertiary : Color.workoutLiveActivitySecondary
    }

    private var innerVerticalPadding: CGFloat {
        style == .previous ? 5 : 10
    }

    private var innerHorizontalPadding: CGFloat {
        style == .previous ? 10 : 12
    }

    private var outerHorizontalInset: CGFloat {
        style == .previous ? 18 : 0
    }

    private var backgroundShape: some Shape {
        if style == .previous {
            return AnyShape(RoundedCornerRect(radius: 14, corners: [.topLeft, .topRight]))
        }
        return AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption2.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(labelColor)
                .textCase(.uppercase)

            Spacer(minLength: 10)

            content
        }
        .padding(.horizontal, innerHorizontalPadding)
        .padding(.vertical, innerVerticalPadding)
        .background {
            backgroundShape
                .fill(Color.white.opacity(0.08))
                .overlay {
                    if style == .previous {
                        WorkoutLiveActivityPrevPillStroke(radius: 14)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.9)
                    } else {
                        backgroundShape
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.9)
                    }
                }
        }
        .padding(.horizontal, outerHorizontalInset)
    }
}

private struct WorkoutLiveActivityNextSetPill: View {
    let title: String
    let partnerExerciseName: String?
    let supersetPartnerIsLeading: Bool
    let metrics: ExerciseMetricDisplay?
    var compactLayout: Bool = false

    private var verticalPadding: CGFloat {
        compactLayout ? 3 : 6
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            WorkoutLiveActivityCompactExerciseTitleRow(
                mainExerciseName: title,
                partnerExerciseName: partnerExerciseName,
                supersetPartnerIsLeading: supersetPartnerIsLeading
            )

            Spacer(minLength: 10)

            if let metrics, !metrics.isEmpty {
                WorkoutLiveActivityMetricsUnitRow(metrics: metrics, presentation: .small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, verticalPadding)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.9)
                }
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
            previousSecondaryMetrics: nil,
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
            previousPrimaryMetrics: previewDemoMetrics(reps: "12", repsPlaceholder: false, weight: "25", weightPlaceholder: false),
            previousSecondaryMetrics: nil,
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

#Preview("Island expanded · stopwatch", as: .dynamicIsland(.expanded), using: WorkoutLiveActivityAttributes.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityAttributes.previewStopwatchRunningState
}

#Preview("Island expanded · current set", as: .dynamicIsland(.expanded), using: WorkoutLiveActivityAttributes.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityAttributes.previewCurrentSetEnteredWeightState
}

#Preview("Island expanded · template", as: .dynamicIsland(.expanded), using: WorkoutLiveActivityAttributes.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityAttributes.previewTemplateSetState
}

#Preview("Island expanded · superset · 1st", as: .dynamicIsland(.expanded), using: WorkoutLiveActivityAttributes.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityAttributes.previewSupersetFocusFirstState
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

#Preview("Island compact · idle", as: .dynamicIsland(.compact), using: WorkoutLiveActivityAttributes.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityAttributes.previewCurrentSetEnteredWeightState
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

#Preview("Island minimal · idle", as: .dynamicIsland(.minimal), using: WorkoutLiveActivityAttributes.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityAttributes.previewCurrentSetEnteredWeightState
}
#endif

/// Compact / minimal Dynamic Island trailing: live rest timer or stopwatch (`m:ss` via `showsHours: false`) when running,
/// otherwise elapsed workout duration.
private struct WorkoutCompactIslandTrailingContent: View {
    let state: WorkoutLiveActivityAttributes.ContentState
    let startedAt: Date
    let font: Font

    var body: some View {
        if let chip = state.chronoChip, chip.showsRunningChronoInCompactIsland {
            WorkoutCompactIslandChronoLabel(chip: chip, font: font)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            WorkoutElapsedDurationLabel(startedAt: startedAt, font: font, abbreviated: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct WorkoutCompactIslandChronoLabel: View {
    let chip: WorkoutLiveActivityChronoChip
    let font: Font

    var body: some View {
        TimelineView(.periodic(from: timelineStartDate, by: 1)) { context in
            let label = chip.displayText(at: context.date)

            Text(label ?? "0:00")
                .font(font)
                .monospacedDigit()
                .foregroundStyle(chip.liveActivityChronoForegroundTint)
                .multilineTextAlignment(.trailing)
                .contentTransition(.numericText())
                .opacity(label == nil ? 0 : 1)
        }
    }

    private var timelineStartDate: Date {
        switch chip.phase {
        case .timerRunning:
            return .now
        case .stopwatchRunning:
            return chip.stopwatchStartDate ?? .now
        case .timerPaused, .stopwatchPaused:
            return .now
        }
    }
}

/// Elapsed workout time advances locally via `TimelineView`, so the widget keeps updating without Activity pushes.
private struct WorkoutElapsedDurationLabel: View {
    let startedAt: Date
    let font: Font
    var abbreviated: Bool = false

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 60)) { context in
            let minutes = max(0, Int(context.date.timeIntervalSince(startedAt) / 60))
            Text(abbreviated ? abbreviatedElapsedText(for: minutes) : "\(minutes) min")
                .font(font)
                .monospacedDigit()
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .contentTransition(.numericText())
        }
    }

    private func abbreviatedElapsedText(for totalMinutes: Int) -> String {
        if totalMinutes >= 60 {
            return "\(max(1, totalMinutes / 60))h"
        }

        return "\(totalMinutes)m"
    }
}

private struct WorkoutCompactIslandLeadingContent: View {
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        if let chip = state.chronoChip, chip.showsRunningChronoInCompactIsland {
            Image(systemName: chip.compactIslandIconName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(chip.liveActivityChronoForegroundTint)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            Image(systemName: "dumbbell.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(state.liveActivityChromeTint)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct WorkoutMinimalIslandContent: View {
    let state: WorkoutLiveActivityAttributes.ContentState
    let font: Font

    var body: some View {
        if let chip = state.chronoChip, chip.showsRunningChronoInCompactIsland {
            WorkoutCompactIslandChronoLabel(chip: chip, font: font)
        } else {
            Image(systemName: "dumbbell.fill")
                .font(font)
                .foregroundStyle(state.liveActivityChromeTint)
        }
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
