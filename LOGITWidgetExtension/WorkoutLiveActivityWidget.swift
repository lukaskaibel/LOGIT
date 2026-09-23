//
//  WorkoutLiveActivityWidget.swift
//  LOGITWidgetExtension
//
//  Created by Codex on 28.03.26.
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Palette

/// The app's dark-mode surfaces and label tiers as literals: the extension can't load the app's asset
/// catalog, and the Live Activity has to look like the recorder regardless of the Lock Screen's appearance.
private enum LiveActivityPalette {
    /// `secondarySystemBackground` (dark) — the recorder's set-group card.
    static let card = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    /// `tertiarySystemBackground` (dark) — the set rows inside that card.
    static let row = Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255)
    /// `secondaryLabel` (dark).
    static let secondary = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.6)
    /// `placeholderText` (dark) — an untouched field, exactly as `IntegerField` draws it.
    static let placeholder = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.3)
    /// The `AccentColor` asset's dark appearance.
    static let accent = Color(red: 0.729, green: 0.987, blue: 0.310)
}

// MARK: - Widget

/// One card, one job: while a set is being logged the activity is that exercise and its set row; while a
/// timer or stopwatch runs it is the clock, with what comes next as a single quiet line underneath.
// Qualified because this file is also compiled into the app, where `Widget` is a Core Data entity.
struct WorkoutLiveActivityWidget: SwiftUI.Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutLiveActivityAttributes.self) { context in
            WorkoutLiveActivityLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(LiveActivityPalette.card)
                .activitySystemActionForegroundColor(context.state.tint)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.iconName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(context.state.tint)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutElapsedClock(startedAt: context.attributes.startedAt)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LiveActivityPalette.secondary)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Group {
                        if let chip = context.state.chronoChip {
                            WorkoutChronoContent(
                                state: context.state,
                                chip: chip,
                                header: nil,
                                digitSize: 46
                            )
                        } else {
                            WorkoutLoggingContent(state: context.state, startedAt: nil)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.iconName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(context.state.tint)
            } compactTrailing: {
                WorkoutCompactTrailingContent(state: context.state, startedAt: context.attributes.startedAt)
            } minimal: {
                WorkoutMinimalContent(state: context.state)
            }
            .keylineTint(context.state.tint)
        }
    }
}

// MARK: - Lock Screen

/// Also compiled into the app, where `LiveActivityShowcaseView` draws the App Store screenshot with it — so
/// the screenshot is the real Lock Screen card, not a replica that drifts when this one changes.
struct WorkoutLiveActivityLockScreenView: View {
    /// The card colour the system paints behind this view (`activityBackgroundTint`).
    static let backgroundTint = LiveActivityPalette.card

    let attributes: WorkoutLiveActivityAttributes
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        Group {
            if let chip = state.chronoChip {
                WorkoutChronoContent(
                    state: state,
                    chip: chip,
                    header: attributes.startedAt,
                    digitSize: 54
                )
            } else {
                WorkoutLoggingContent(state: state, startedAt: attributes.startedAt)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }
}

// MARK: - Logging

/// The exercise as the recorder shows it — name, the muscle group in its colour, and the set being logged as a
/// set row. `startedAt` puts the elapsed clock beside the name; the island passes nil because its own header
/// already carries the clock.
private struct WorkoutLoggingContent: View {
    let state: WorkoutLiveActivityAttributes.ContentState
    let startedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(state.headingTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let startedAt {
                    WorkoutElapsedClock(startedAt: startedAt)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LiveActivityPalette.secondary)
                }
            }

            WorkoutIdentityLine(state: state)
                .padding(.top, 2)

            if state.hasExercise {
                WorkoutSetRow(state: state)
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The line under the exercise name: its muscle group in the group's colour, then either the group's place in the
/// workout ("2 of 3", the recorder's bulge label) or — in a superset — the partner exercise after the recorder's
/// turn arrow.
private struct WorkoutIdentityLine: View {
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 5) {
            if state.hasExercise {
                if let muscleName = state.themeToken.localizedName {
                    Text(muscleName)
                        .foregroundStyle(state.themeToken.color)
                    if trailingText != nil {
                        Text(verbatim: "·")
                    }
                }
                if let partner = state.secondaryExerciseName, !partner.isEmpty {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption.weight(.semibold))
                }
                if let trailingText {
                    Text(trailingText)
                }
            } else {
                Text(NSLocalizedString("addExercise", comment: ""))
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(LiveActivityPalette.secondary)
        .lineLimit(1)
    }

    private var trailingText: String? {
        if let partner = state.secondaryExerciseName, !partner.isEmpty {
            return partner
        }
        return state.positionLabel
    }
}

/// `WorkoutSetCell` at rest, built from the same values the app uses: the set number in body bold rounded
/// secondary (here with a smaller "/4" on its baseline), each field as `IntegerField`/`DecimalField` draw it —
/// title3 bold rounded value, footnote bold rounded uppercase unit, no gap, 5/8 pt padding, 100 pt minimum
/// width — on the cell's inset-shadowed tertiary background with a 15 pt corner.
///
/// Every `Text` carries its own font, set the way `UnitView` sets it (`.font` + `.fontWeight` + `.fontDesign`):
/// in a Live Activity both `Text` interpolation and `Font.system(_:design:weight:)` lose weight and design,
/// which rendered these numbers in regular SF.
private struct WorkoutSetRow: View {
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 0) {
            if state.setIndex > 0 {
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text(verbatim: "\(state.setIndex)")
                        .font(.body)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .foregroundStyle(LiveActivityPalette.secondary)
                    Text(verbatim: "/\(state.setCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .foregroundStyle(LiveActivityPalette.placeholder)
                }
                .fixedSize()
            }

            Spacer(minLength: 8)

            // A drop set's segments can outgrow the row; step the whole group down a size instead of
            // letting each field shrink on its own.
            ViewThatFits(in: .horizontal) {
                fields(value: .title3, unit: .footnote, minWidth: 100)
                fields(value: .body, unit: .caption2, minWidth: 0)
                fields(value: .subheadline, unit: .caption2, minWidth: 0)
            }
        }
        .padding(.leading, 14)
        .padding([.top, .trailing], 8)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(.shadow(.inner(color: .black.opacity(0.4), radius: 5)))
                .foregroundStyle(LiveActivityPalette.row)
        )
        .clipShape(RoundedRectangle(cornerRadius: 15))
    }

    private func fields(value: Font.TextStyle, unit: Font.TextStyle, minWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(state.primaryMetrics.fields.enumerated()), id: \.offset) { _, field in
                WorkoutMetricFieldView(
                    field: field,
                    valueStyle: value,
                    unitStyle: unit,
                    valueColor: .white,
                    unitColor: LiveActivityPalette.secondary,
                    placeholderColor: LiveActivityPalette.placeholder
                )
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .frame(minWidth: minWidth, alignment: .trailing)
            }
        }
        .padding(.vertical, 2.5)
        .fixedSize()
    }
}

// MARK: - Timer / stopwatch

/// The clock owns the card: a label and the elapsed workout clock on top (Lock Screen only — the island's regions
/// carry both), the digits large in the recorder's timer tint, a progress bar when the timer has a total, and the
/// next set as one grey line when there is one.
private struct WorkoutChronoContent: View {
    let state: WorkoutLiveActivityAttributes.ContentState
    let chip: WorkoutLiveActivityChronoChip
    /// The workout start for the Lock Screen's header row; nil hides the row.
    let header: Date?
    let digitSize: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            if let startedAt = header {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 5) {
                        Image(systemName: chip.iconName)
                        Text(chip.title)
                    }
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(chip.tint)

                    Spacer(minLength: 12)

                    WorkoutElapsedClock(startedAt: startedAt)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LiveActivityPalette.secondary)
                }
            }

            WorkoutChronoText(chip: chip)
                .font(.system(size: digitSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(chip.tint)
                .opacity(chip.isRunning ? 1 : 0.7)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.top, header == nil ? 0 : 4)

            if chip.showsProgress {
                WorkoutChronoProgressBar(chip: chip)
                    .padding(.top, 6)
            }

            if state.showsNextSet {
                WorkoutNextSetLine(state: state)
                    .padding(.top, chip.showsProgress ? 10 : 4)
            }
        }
    }
}

/// Running timers and stopwatches use system timer text so the digits advance without an Activity update per tick.
private struct WorkoutChronoText: View {
    let chip: WorkoutLiveActivityChronoChip

    var body: some View {
        switch chip.phase {
        case .timerRunning:
            if let end = chip.timerEndDate {
                Text(timerInterval: countdownRange(endingAt: end), countsDown: true)
            } else {
                Text(verbatim: "0:00")
            }
        case .stopwatchRunning:
            if let start = chip.stopwatchStartDate {
                Text(timerInterval: start ... start.addingTimeInterval(86400), countsDown: false)
            } else {
                Text(verbatim: "0:00")
            }
        case .timerPaused, .stopwatchPaused:
            Text(verbatim: clockString(seconds: chip.staticTickSeconds ?? 0))
        }
    }
}

/// How much rest is left, emptying as it runs out — the recorder's floating timer capsule fills the same way.
private struct WorkoutChronoProgressBar: View {
    let chip: WorkoutLiveActivityChronoChip

    var body: some View {
        Group {
            if chip.phase == .timerRunning, let end = chip.timerEndDate, let total = chip.timerTotalSeconds {
                ProgressView(
                    timerInterval: end.addingTimeInterval(-total) ... end,
                    countsDown: true,
                    label: { EmptyView() },
                    currentValueLabel: { EmptyView() }
                )
            } else if let total = chip.timerTotalSeconds {
                ProgressView(value: min(Double(chip.staticTickSeconds ?? 0), total), total: total)
            }
        }
        .progressViewStyle(.linear)
        .tint(chip.tint)
    }
}

/// "Up next  Incline Bench Press  8 REP  60 KG" — the only trace of the logging card while the clock runs.
private struct WorkoutNextSetLine: View {
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(NSLocalizedString("liveActivityNextUp", comment: ""))
                .fixedSize()

            Text(state.primaryExerciseName)
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ForEach(Array(state.primaryMetrics.fields.filter { !$0.isUnplannedZero }.enumerated()), id: \.offset) { _, field in
                    WorkoutMetricFieldView(
                        field: field,
                        valueStyle: .footnote,
                        unitStyle: .caption2,
                        valueColor: LiveActivityPalette.secondary,
                        unitColor: LiveActivityPalette.secondary,
                        placeholderColor: LiveActivityPalette.secondary
                    )
                }
            }
            .fixedSize()
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(LiveActivityPalette.secondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Compact & minimal

private struct WorkoutCompactTrailingContent: View {
    let state: WorkoutLiveActivityAttributes.ContentState
    let startedAt: Date

    var body: some View {
        Group {
            if let chip = state.chronoChip {
                WorkoutCompactChronoLabel(chip: chip)
                    .foregroundStyle(chip.tint)
            } else {
                WorkoutElapsedClock(startedAt: startedAt, showsHours: false)
                    .foregroundStyle(.white)
            }
        }
        .font(.caption2.weight(.bold))
        .monospacedDigit()
    }
}

private struct WorkoutMinimalContent: View {
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        if let chip = state.chronoChip {
            WorkoutCompactChronoLabel(chip: chip)
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(chip.tint)
        } else {
            Image(systemName: state.iconName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(state.tint)
        }
    }
}

/// In the compact island a bare `Text(timerInterval:)` under the trailing region does not lay out to a visible
/// width, so the running digits vanish. A hidden monospaced sizer pins the width and the live text is drawn
/// trailing-aligned over it.
private struct WorkoutCompactChronoLabel: View {
    let chip: WorkoutLiveActivityChronoChip

    var body: some View {
        switch chip.phase {
        case .timerRunning:
            if let end = chip.timerEndDate {
                WorkoutReservedTimerText(range: countdownRange(endingAt: end), countsDown: true, showsHours: false)
            } else {
                Text(verbatim: "0:00")
            }
        case .stopwatchRunning:
            if let start = chip.stopwatchStartDate {
                WorkoutReservedTimerText(
                    range: start ... start.addingTimeInterval(86400),
                    countsDown: false,
                    showsHours: false
                )
            } else {
                Text(verbatim: "0:00")
            }
        case .timerPaused, .stopwatchPaused:
            Text(verbatim: clockString(seconds: chip.staticTickSeconds ?? 0))
                .opacity(0.7)
        }
    }
}

/// The workout's running clock, like the recorder header's — ticking on its own, no Activity updates needed.
private struct WorkoutElapsedClock: View {
    let startedAt: Date
    /// The compact island has no room for hours: past an hour it keeps counting minutes ("63:20").
    var showsHours: Bool = true

    var body: some View {
        WorkoutReservedTimerText(
            range: startedAt ... startedAt.addingTimeInterval(86400),
            countsDown: false,
            showsHours: showsHours
        )
    }
}

private struct WorkoutReservedTimerText: View {
    let range: ClosedRange<Date>
    let countsDown: Bool
    let showsHours: Bool

    var body: some View {
        Text(verbatim: showsHours ? "0:00:00" : "00:00")
            .monospacedDigit()
            .hidden()
            .overlay(alignment: .trailing) {
                Text(timerInterval: range, countsDown: countsDown, showsHours: showsHours)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
    }
}

// MARK: - Formatting

private extension Font {
    /// The plain text-style font (`.title3`, `.footnote`, …) — see `WorkoutSetRow` for why not `.system(_:)`.
    init(textStyle: Font.TextStyle) {
        switch textStyle {
        case .largeTitle: self = .largeTitle
        case .title: self = .title
        case .title2: self = .title2
        case .title3: self = .title3
        case .headline: self = .headline
        case .subheadline: self = .subheadline
        case .callout: self = .callout
        case .footnote: self = .footnote
        case .caption: self = .caption
        case .caption2: self = .caption2
        default: self = .body
        }
    }
}

private func countdownRange(endingAt endDate: Date, referenceDate: Date = .now) -> ClosedRange<Date> {
    referenceDate ... max(endDate, referenceDate)
}

private func clockString(seconds: Int) -> String {
    "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
}

/// One field of the set row — reps (or a duration/distance) or weight — with every drop of a drop set as a segment.
private struct WorkoutMetricField {
    let segments: [String]
    let placeholders: [Bool]
    let unit: String

    func isPlaceholder(at index: Int) -> Bool {
        index < placeholders.count && placeholders[index]
    }

    var isAllPlaceholder: Bool {
        !placeholders.isEmpty && placeholders.allSatisfy(\.self)
    }

    /// Nothing typed and nothing planned — the set row still shows the recorder's grey "0", but a
    /// one-line hint of what's next reads cleaner without "0 REP 0 KG".
    var isUnplannedZero: Bool {
        isAllPlaceholder
            && segments.allSatisfy { segment in !segment.contains { "123456789".contains($0) } }
    }
}

/// One field in `IntegerField`'s typography: bold rounded value(s), bold rounded uppercase unit directly after,
/// placeholder grey while untouched. A drop set lists its drops as " / "-separated segments.
private struct WorkoutMetricFieldView: View {
    let field: WorkoutMetricField
    let valueStyle: Font.TextStyle
    let unitStyle: Font.TextStyle
    let valueColor: Color
    let unitColor: Color
    let placeholderColor: Color

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            ForEach(Array(field.segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 {
                    Text(verbatim: " / ")
                        .font(Font(textStyle: valueStyle))
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .foregroundStyle(placeholderColor)
                }
                Text(verbatim: segment)
                    .font(Font(textStyle: valueStyle))
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                    .foregroundStyle(field.isPlaceholder(at: index) ? placeholderColor : valueColor)
            }
            if !field.unit.isEmpty {
                Text(verbatim: field.unit.uppercased())
                    .font(Font(textStyle: unitStyle))
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                    .foregroundStyle(field.isAllPlaceholder ? placeholderColor : unitColor)
            }
        }
        .lineLimit(1)
    }
}

private extension ExerciseMetricDisplay {
    var fields: [WorkoutMetricField] {
        var fields: [WorkoutMetricField] = []
        if !repetitionSegments.isEmpty {
            fields.append(WorkoutMetricField(
                segments: repetitionSegments,
                placeholders: repetitionSegmentPlaceholders,
                unit: repetitionsUnit
            ))
        }
        if !weightSegments.isEmpty {
            fields.append(WorkoutMetricField(
                segments: weightSegments,
                placeholders: weightSegmentPlaceholders,
                unit: weightUnit
            ))
        }
        return fields
    }
}

// MARK: - State helpers

private extension WorkoutLiveActivityAttributes.ContentState {
    /// A set group with a set to show; an empty workout has neither and falls back to its title.
    var hasExercise: Bool {
        setCount > 0
    }

    var headingTitle: String {
        hasExercise ? primaryExerciseName : workoutTitle
    }

    /// "2 of 3" — the set group's place in the workout.
    var positionLabel: String? {
        guard exerciseIndex > 0, exerciseCount > 0 else { return nil }
        return String.localizedStringWithFormat(
            NSLocalizedString("groupIndexOfTotal", comment: ""), exerciseIndex, exerciseCount
        )
    }

    var showsNextSet: Bool {
        hasExercise && (hasPendingSet ?? true)
    }

    var tint: Color {
        chronoChip?.tint ?? themeToken.color
    }

    var iconName: String {
        chronoChip?.iconName ?? "dumbbell.fill"
    }
}

private extension WorkoutLiveActivityChronoChip {
    var isRunning: Bool {
        phase == .timerRunning || phase == .stopwatchRunning
    }

    var isTimer: Bool {
        phase == .timerRunning || phase == .timerPaused
    }

    /// Only a timer knows how long it runs.
    var showsProgress: Bool {
        isTimer && (timerTotalSeconds ?? 0) > 0
            && (phase == .timerPaused ? staticTickSeconds != nil : timerEndDate != nil)
    }

    var iconName: String {
        isTimer ? "timer" : "stopwatch"
    }

    var title: String {
        if !isRunning {
            return NSLocalizedString("paused", comment: "")
        }
        switch tintKind {
        case .restTimer, .restStopwatch:
            return NSLocalizedString("liveActivityRest", comment: "")
        case .manual:
            return NSLocalizedString(isTimer ? "timer" : "stopwatch", comment: "")
        }
    }

    /// `WorkoutRecorderFloatingTimerButton`'s tint: the resting set's muscle colour, the accent for a manual clock.
    var tint: Color {
        switch tintKind {
        case .restTimer, .restStopwatch:
            (muscleThemeToken ?? .neutral).color
        case .manual:
            LiveActivityPalette.accent
        }
    }
}

private extension WorkoutLiveActivityThemeToken {
    /// Mirrors `MuscleGroup.color`; the extension doesn't compile the app's model layer.
    var color: Color {
        switch self {
        case .chest: Color(red: 166 / 255, green: 206 / 255, blue: 134 / 255)
        case .triceps: Color(red: 132 / 255, green: 190 / 255, blue: 232 / 255)
        case .shoulders: Color(red: 240 / 255, green: 176 / 255, blue: 128 / 255)
        case .biceps: Color(red: 118 / 255, green: 207 / 255, blue: 192 / 255)
        case .back: Color(red: 142 / 255, green: 150 / 255, blue: 222 / 255)
        case .legs: Color(red: 230 / 255, green: 202 / 255, blue: 114 / 255)
        case .abdominals: Color(red: 168 / 255, green: 146 / 255, blue: 214 / 255)
        case .cardio: Color(red: 224 / 255, green: 138 / 255, blue: 166 / 255)
        case .neutral: LiveActivityPalette.accent
        }
    }

    /// The muscle group's name, as `MuscleGroup.description` localizes it.
    var localizedName: String? {
        self == .neutral ? nil : NSLocalizedString(rawValue, comment: "")
    }
}

// MARK: - Previews

#if DEBUG
private extension WorkoutLiveActivityFixture {
    static let previewAttributes = WorkoutLiveActivityAttributes(
        workoutID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        startedAt: Date().addingTimeInterval(-(23 * 60 + 41))
    )
}

#Preview("Lock · template set", as: .content, using: WorkoutLiveActivityFixture.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityFixture.templateSet.state()
}

#Preview("Lock · superset", as: .content, using: WorkoutLiveActivityFixture.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityFixture.superset.state()
}

#Preview("Lock · drop set", as: .content, using: WorkoutLiveActivityFixture.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityFixture.dropSetLongName.state()
}

#Preview("Lock · rest timer", as: .content, using: WorkoutLiveActivityFixture.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityFixture.restTimer.state()
}

#Preview("Lock · manual stopwatch", as: .content, using: WorkoutLiveActivityFixture.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityFixture.manualStopwatch.state()
}

#Preview("Island expanded · set", as: .dynamicIsland(.expanded), using: WorkoutLiveActivityFixture.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityFixture.templateSet.state()
}

#Preview("Island expanded · rest timer", as: .dynamicIsland(.expanded), using: WorkoutLiveActivityFixture.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityFixture.restTimer.state()
}

#Preview("Island compact · rest timer", as: .dynamicIsland(.compact), using: WorkoutLiveActivityFixture.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityFixture.restTimer.state()
}

#Preview("Island minimal · idle", as: .dynamicIsland(.minimal), using: WorkoutLiveActivityFixture.previewAttributes) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutLiveActivityFixture.templateSet.state()
}
#endif
