//
//  WorkoutRecorderFloatingTimerButton.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 23.03.26.
//

import SwiftUI

struct WorkoutRecorderFloatingTimerButton: View {
    @ObservedObject var chronograph: Chronograph
    @ObservedObject var workoutRecorder: WorkoutRecorder
    @AppStorage("lastTimerDuration") private var lastTimerDuration: Int = 30
    @AppStorage(AutoRestSettings.enabledKey) private var autoRestEnabled: Bool = false

    let action: () -> Void

    private enum DisplayState {
        case activeTimer(Int)
        case activeStopwatch(Int)
        case idleManual(Chronograph.Mode)
        case idleAutoTimer(Int)
        case idleAutoStopwatch
    }

    var body: some View {
        ChronographView(chronograph: chronograph) { seconds in
            floatingButton(for: seconds)
        }
    }

    private func floatingButton(for seconds: Double) -> some View {
        let displayState = displayState(for: seconds)

        return Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: iconName(for: displayState))
                    .font(.body.weight(.semibold))

                if case .idleAutoStopwatch = displayState {
                    Text("0:00")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                } else if let timeText = timeText(for: displayState) {
                    if case .idleAutoTimer = displayState {
                        Text(timeText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    } else {
                        Text(timeText)
                            .font(.body.weight(.semibold).monospacedDigit())
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.18), value: timeText)
                    }
                }
            }
            .foregroundStyle(tint(for: displayState))
            .padding(.horizontal, horizontalPadding(for: displayState))
            // The same height as the keyboard accessory's capsules, which this button parks beside
            // whenever one is open.
            .frame(height: KEYBOARD_TOOLBAR_HEIGHT)
            .background {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        // Liquid Glass, like every other control this button ever sits next to.
                        // No hairline and no drop shadow: glass draws its own edge and depth, and
                        // the accessory's capsules carry neither.
                        Color.clear.glassEffect(.regular, in: .capsule)

                        // Behind the label, so the rest remaining reads as the capsule filling
                        // rather than as a tint over the time.
                        if let progress = timerProgress(for: seconds, displayState: displayState) {
                            Rectangle()
                                .fill(tint(for: displayState).opacity(0.24))
                                .frame(width: proxy.size.width * progress)
                        }
                    }
                }
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: displayState))
        .accessibilityIdentifier("recorderFloatingTimerButton")
    }

    private func tint(for displayState: DisplayState) -> Color {
        if let exerciseColor = workoutRecorder.activeRestTimerSet?.exercise?.muscleGroup?.color {
            return exerciseColor
        }

        switch displayState {
        case .idleManual, .idleAutoTimer, .idleAutoStopwatch:
            return .white
        case .activeTimer, .activeStopwatch:
            return .accentColor
        }
    }

    private func displayState(for seconds: Double) -> DisplayState {
        let roundedSeconds = max(0, Int(seconds.rounded(.down)))

        if workoutRecorder.activeRestTimerSet != nil || chronograph.status != .idle {
            return chronograph.mode == .timer ? .activeTimer(roundedSeconds) : .activeStopwatch(roundedSeconds)
        }

        if chronograph.mode == .stopwatch, roundedSeconds > 0 {
            return .activeStopwatch(roundedSeconds)
        }

        if autoRestEnabled {
            return chronograph.mode == .timer ? .idleAutoTimer(lastTimerDuration) : .idleAutoStopwatch
        }

        return .idleManual(chronograph.mode)
    }

    private func iconName(for displayState: DisplayState) -> String {
        switch displayState {
        case .activeTimer, .idleAutoTimer, .idleManual(.timer):
            return "timer"
        case .activeStopwatch, .idleAutoStopwatch, .idleManual(.stopwatch):
            return "stopwatch"
        }
    }

    private func timeText(for displayState: DisplayState) -> String? {
        switch displayState {
        case let .activeTimer(seconds), let .activeStopwatch(seconds):
            return restTimeString(seconds: seconds)
        case let .idleAutoTimer(duration):
            return restTimeString(seconds: duration)
        case .idleManual, .idleAutoStopwatch:
            return nil
        }
    }

    private func showsAutoIndicator(for displayState: DisplayState) -> Bool {
        switch displayState {
        case .idleAutoTimer, .idleAutoStopwatch:
            return true
        case .activeTimer, .activeStopwatch, .idleManual:
            return false
        }
    }

    private func horizontalPadding(for displayState: DisplayState) -> CGFloat {
        timeText(for: displayState) != nil || showsAutoIndicator(for: displayState) ? 16 : 14
    }

    private func accessibilityLabel(for displayState: DisplayState) -> String {
        switch displayState {
        case let .activeTimer(seconds):
            return "\(NSLocalizedString("timer", comment: "")), \(restTimeString(seconds: seconds))"
        case let .activeStopwatch(seconds):
            return "\(NSLocalizedString("stopwatch", comment: "")), \(restTimeString(seconds: seconds))"
        case .idleManual(.timer):
            return NSLocalizedString("timer", comment: "")
        case .idleManual(.stopwatch):
            return NSLocalizedString("stopwatch", comment: "")
        case let .idleAutoTimer(duration):
            return "\(NSLocalizedString("autoRestTimer", comment: "")), \(restTimeString(seconds: duration))"
        case .idleAutoStopwatch:
            return NSLocalizedString("autoRestStopwatch", comment: "")
        }
    }

    private func timerProgress(for seconds: Double, displayState: DisplayState) -> CGFloat? {
        guard case .activeTimer = displayState else { return nil }

        let totalSeconds = max(chronograph.initialTimerSeconds, 0)
        guard totalSeconds > 0 else { return nil }

        return min(max(CGFloat(seconds / totalSeconds), 0), 1)
    }
}

private struct WorkoutRecorderFloatingTimerButtonPreviewWrapper: View {
    enum Scenario {
        case activeTimer
        case activeStopwatch
        case idleAutoTimer
    }

    @EnvironmentObject private var database: Database
    @EnvironmentObject private var workoutRecorder: WorkoutRecorder
    @EnvironmentObject private var chronograph: Chronograph

    private let scenario: Scenario

    init(scenario: Scenario) {
        self.scenario = scenario

        switch scenario {
        case .activeTimer:
            UserDefaults.standard.set(false, forKey: AutoRestSettings.enabledKey)
            UserDefaults.standard.set(90, forKey: "lastTimerDuration")
        case .activeStopwatch:
            UserDefaults.standard.set(false, forKey: AutoRestSettings.enabledKey)
            UserDefaults.standard.set(30, forKey: "lastTimerDuration")
        case .idleAutoTimer:
            UserDefaults.standard.set(true, forKey: AutoRestSettings.enabledKey)
            UserDefaults.standard.set(45, forKey: "lastTimerDuration")
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color.black.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            WorkoutRecorderFloatingTimerButton(
                chronograph: chronograph,
                workoutRecorder: workoutRecorder,
                action: {}
            )
            .padding()
        }
        .frame(height: 140)
        .onAppear {
            if workoutRecorder.workout == nil {
                workoutRecorder.startWorkout(from: database.testTemplate)
            }

            let activeSet = workoutRecorder.workout?.sets.first
            workoutRecorder.activeRestTimerSet = nil
            chronograph.onTimerFired = nil
            chronograph.cancel()

            switch scenario {
            case .activeTimer:
                chronograph.mode = .timer
                chronograph.setSeconds(45.99, timerTotalSecondsOverride: 90.99)
                chronograph.status = .running
                workoutRecorder.activeRestTimerSet = activeSet
            case .activeStopwatch:
                chronograph.mode = .stopwatch
                chronograph.setSeconds(73)
                chronograph.status = .running
                workoutRecorder.activeRestTimerSet = activeSet
            case .idleAutoTimer:
                chronograph.mode = .timer
                chronograph.setSeconds(45.99)
            }
        }
    }
}

struct WorkoutRecorderFloatingTimerButton_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            WorkoutRecorderFloatingTimerButtonPreviewWrapper(scenario: .activeTimer)
                .previewDisplayName("Active Timer")
            WorkoutRecorderFloatingTimerButtonPreviewWrapper(scenario: .activeStopwatch)
                .previewDisplayName("Active Stopwatch")
            WorkoutRecorderFloatingTimerButtonPreviewWrapper(scenario: .idleAutoTimer)
                .previewDisplayName("Idle Auto Timer")
        }
        .previewEnvironmentObjects()
    }
}
