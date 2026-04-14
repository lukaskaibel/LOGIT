//
//  Chronograph.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 20.07.23.
//

import Combine
import Foundation
import UIKit
import UserNotifications

class Chronograph: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    // MARK: - Enums

    enum Mode: String {
        case timer
        case stopwatch
    }

    enum NotificationHaptic: Equatable {
        case selection
        case warning
        case success

        func play() {
            switch self {
            case .selection:
                UISelectionFeedbackGenerator().selectionChanged()
            case .warning:
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            case .success:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    enum ChronographStatus {
        case idle
        case running
        case paused
    }

    // MARK: - Properties

    private static let modeStorageKey = "selectedChronographMode"
    private static let timerFinishedNotificationIdentifier = "timerFinished"
    private static let timerWarningNotificationIdentifierPrefix = "timerWarning"
    private static let stopwatchNotificationIdentifierPrefix = "stopwatchMinute"
    private static let timerNotificationSoundName = "timer.wav"
    private static let timerNotificationAutoDismissInterval: TimeInterval = 1.5
    private static let timerWarningNotificationOffsets = [30, 10]
    private static let stopwatchNotificationInterval: TimeInterval = 30
    static let maxPendingStopwatchNotifications = 64

    struct TimerWarningNotificationSchedule: Equatable {
        let remainingSeconds: Int
        let timeInterval: TimeInterval
    }

    struct StopwatchNotificationSchedule: Equatable {
        let elapsedSecondsMark: Int
        let timeInterval: TimeInterval
    }

    @Published var mode: Mode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeStorageKey)
        }
    }
    @Published var status: ChronographStatus = .idle

    var onTimerFired: (() -> Void)?

    var seconds: TimeInterval = 0
    /// The initial duration set for timer mode, used to compute elapsed time.
    private(set) var initialTimerSeconds: TimeInterval = 0
    /// Wall-clock instant when the running countdown timer is expected to hit zero (timer mode only).
    @Published private(set) var timerWallClockEndDate: Date?
    private var timer: Timer?
    var startDate: Date?
    private var pauseTime: TimeInterval?

    /// How many seconds have elapsed since the timer started (timer mode only).
    var elapsedTimerSeconds: Int {
        max(0, Int(initialTimerSeconds - seconds))
    }

    /// How many seconds have elapsed for the active chronograph mode.
    var elapsedSeconds: Int {
        switch mode {
        case .timer:
            elapsedTimerSeconds
        case .stopwatch:
            max(0, Int(seconds.rounded(.down)))
        }
    }

    // MARK: - Init

    override init() {
        mode = Self.storedMode
        super.init()
        // Set delegate for handling notifications when app is in foreground
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Methods

    func start() {
        if pauseTime != nil {
            seconds = pauseTime!
            pauseTime = nil
        }

        scheduleNotificationsForCurrentState()

        if mode == .timer {
            timerWallClockEndDate = Date().addingTimeInterval(seconds)
        } else {
            timerWallClockEndDate = nil
        }

        startDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if let start = self.startDate {
                let timePassed = Date().timeIntervalSince(start)
                switch self.mode {
                case .timer:
                    self.seconds -= timePassed
                    if self.seconds <= 0 {
                        self.seconds = 0
                        self.scheduleTimerNotificationAutoDismiss()
                        self.reset()
                        self.onTimerFired?()
                    }
                case .stopwatch:
                    self.seconds += timePassed
                }
                self.startDate = Date()
            }
        }
        status = .running
        objectWillChange.send()
    }

    func cancel() {
        reset()
        cancelNotifications()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        timerWallClockEndDate = nil
        status = .paused
        cancelNotifications()
        objectWillChange.send()
    }

    func setSeconds(
        _ seconds: Double,
        preservingElapsed: Bool = false,
        timerTotalSecondsOverride: Double? = nil
    ) {
        let elapsedBeforeUpdate = mode == .timer ? max(0, initialTimerSeconds - self.seconds) : 0
        self.seconds = seconds
        if mode == .timer {
            if let timerTotalSecondsOverride {
                initialTimerSeconds = timerTotalSecondsOverride
            } else if preservingElapsed {
                initialTimerSeconds = elapsedBeforeUpdate + seconds
            } else {
                // When not overriding and not preserving elapsed, treat `seconds` as the new total
                // timer duration, regardless of whether the timer is idle, running, or paused.
                initialTimerSeconds = seconds
            }
            if status == .running {
                timerWallClockEndDate = Date().addingTimeInterval(self.seconds)
            }
        }
        objectWillChange.send()
        if status == .running {
            scheduleNotificationsForCurrentState()
        }
    }

    func adjustStopwatch(by adjustment: TimeInterval) {
        guard mode == .stopwatch else { return }

        let updatedSeconds = max(0, seconds + adjustment)
        seconds = updatedSeconds

        if status == .running {
            startDate = Date()
            scheduleNotificationsForCurrentState()
        }

        objectWillChange.send()
    }

    private func reset() {
        timer?.invalidate()
        timer = nil
        startDate = nil
        seconds = 0
        timerWallClockEndDate = nil
        status = .idle
    }

    private var timesUpNotificationRequest: UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("timesUp", comment: "")
        content.body = NSLocalizedString("timesUpBody", comment: "")
        let timerIsMuted = UserDefaults.standard.bool(forKey: "timerIsMuted")
        if !timerIsMuted {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(Self.timerNotificationSoundName))
        }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Self.notificationTriggerInterval(forTimerSeconds: seconds),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: Self.timerFinishedNotificationIdentifier,
            content: content,
            trigger: trigger
        )
        return request
    }

    private func stopwatchNotificationRequest(
        identifier: String,
        elapsedSecondsMark: Int,
        timeInterval: TimeInterval
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("stopwatchMinuteTitle", comment: "")
        content.body = String(
            format: NSLocalizedString("stopwatchMinuteBody", comment: ""),
            Self.formattedStopwatchElapsedTimeMark(elapsedSecondsMark)
        )

        let timerIsMuted = UserDefaults.standard.bool(forKey: "timerIsMuted")
        if !timerIsMuted {
            content.sound = .default
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)

        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
    }

    private func timerWarningNotificationRequest(
        identifier: String,
        remainingSeconds: Int,
        timeInterval: TimeInterval
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("timer", comment: "")
        content.body = String(
            format: NSLocalizedString("timerWarningBody", comment: ""),
            Self.formattedDuration(seconds: remainingSeconds)
        )

        let timerIsMuted = UserDefaults.standard.bool(forKey: "timerIsMuted")
        if !timerIsMuted {
            content.sound = .default
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)

        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
    }

    private func scheduleTimerNotification(inSeconds seconds: TimeInterval) {
        UNUserNotificationCenter.current().add(timesUpNotificationRequest) { error in
            if let error = error {
                print("Error scheduling notification: \(error)")
            } else {
                print("Timer notification scheduled in \(seconds) seconds.")
            }
        }
    }

    private func scheduleStopwatchNotifications(fromElapsedSeconds elapsedSeconds: TimeInterval) {
        cancelStopwatchNotifications()

        let center = UNUserNotificationCenter.current()
        let schedules = Self.stopwatchNotificationSchedule(elapsedSeconds: elapsedSeconds)

        for (index, schedule) in schedules.enumerated() {
            let request = stopwatchNotificationRequest(
                identifier: stopwatchNotificationIdentifier(at: index),
                elapsedSecondsMark: schedule.elapsedSecondsMark,
                timeInterval: schedule.timeInterval
            )
            center.add(request) { error in
                if let error {
                    print("Error scheduling stopwatch notification: \(error)")
                }
            }
        }
    }

    private func scheduleTimerWarningNotifications(fromRemainingSeconds remainingSeconds: TimeInterval) {
        cancelTimerWarningNotifications()

        let center = UNUserNotificationCenter.current()
        let schedules = Self.timerWarningNotificationSchedule(remainingSeconds: remainingSeconds)

        for schedule in schedules {
            let request = timerWarningNotificationRequest(
                identifier: timerWarningNotificationIdentifier(forRemainingSeconds: schedule.remainingSeconds),
                remainingSeconds: schedule.remainingSeconds,
                timeInterval: schedule.timeInterval
            )
            center.add(request) { error in
                if let error {
                    print("Error scheduling timer warning notification: \(error)")
                }
            }
        }
    }

    private func scheduleNotificationsForCurrentState() {
        cancelNotifications()

        switch mode {
        case .timer:
            scheduleTimerWarningNotifications(fromRemainingSeconds: seconds)
            scheduleTimerAlert(inSeconds: seconds)
        case .stopwatch:
            scheduleStopwatchNotifications(fromElapsedSeconds: seconds)
        }
    }

    private func cancelNotifications() {
        cancelTimerNotification()
        cancelTimerWarningNotifications()
        cancelStopwatchNotifications()
    }

    private func cancelTimerNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.timerFinishedNotificationIdentifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.timerFinishedNotificationIdentifier])
        print("Timer notification cancelled.")
    }

    private func scheduleTimerAlert(inSeconds seconds: TimeInterval) {
        guard seconds > 0 else { return }
        scheduleTimerNotification(inSeconds: seconds)
    }

    private func scheduleTimerNotificationAutoDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timerNotificationAutoDismissInterval) {
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: [Self.timerFinishedNotificationIdentifier]
            )
        }
    }

    private func cancelStopwatchNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: Self.stopwatchNotificationIdentifiers
        )
    }

    private func cancelTimerWarningNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: Self.timerWarningNotificationIdentifiers
        )
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: Self.timerWarningNotificationIdentifiers
        )
    }

    private func timerWarningNotificationIdentifier(forRemainingSeconds remainingSeconds: Int) -> String {
        "\(Self.timerWarningNotificationIdentifierPrefix)-\(remainingSeconds)"
    }

    private func stopwatchNotificationIdentifier(at index: Int) -> String {
        "\(Self.stopwatchNotificationIdentifierPrefix)-\(index + 1)"
    }

    private func triggerForegroundNotificationHaptic(forNotificationIdentifier identifier: String) {
        // Timer completion already produces an in-app success haptic via `onTimerFired`.
        guard identifier != Self.timerFinishedNotificationIdentifier else { return }
        Self.notificationHaptic(forNotificationIdentifier: identifier)?.play()
    }

    func userNotificationCenter(_: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    {
        triggerForegroundNotificationHaptic(forNotificationIdentifier: notification.request.identifier)
        // Show banner, sound, and badge even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    private static var storedMode: Mode {
        guard let rawValue = UserDefaults.standard.string(forKey: modeStorageKey),
              let mode = Mode(rawValue: rawValue)
        else {
            return .timer
        }

        return mode
    }

    static func notificationHaptic(forNotificationIdentifier identifier: String) -> NotificationHaptic? {
        if identifier == timerFinishedNotificationIdentifier {
            return .success
        }

        if identifier.hasPrefix(timerWarningNotificationIdentifierPrefix) {
            return .warning
        }

        if identifier.hasPrefix(stopwatchNotificationIdentifierPrefix) {
            return .selection
        }

        return nil
    }

    static func stopwatchNotificationSchedule(
        elapsedSeconds: TimeInterval,
        maxNotificationCount: Int = maxPendingStopwatchNotifications
    ) -> [StopwatchNotificationSchedule] {
        guard maxNotificationCount > 0 else { return [] }

        let safeElapsedSeconds = max(0, elapsedSeconds)
        let completedIntervals = Int(safeElapsedSeconds / Self.stopwatchNotificationInterval)
        let nextElapsedSecondsMark = Int(Double(completedIntervals + 1) * Self.stopwatchNotificationInterval)
        let secondsUntilNextNotification = max(1, Double(nextElapsedSecondsMark) - safeElapsedSeconds)

        return (0 ..< maxNotificationCount).map { index in
            StopwatchNotificationSchedule(
                elapsedSecondsMark: nextElapsedSecondsMark + Int(Double(index) * Self.stopwatchNotificationInterval),
                timeInterval: secondsUntilNextNotification + Double(index) * Self.stopwatchNotificationInterval
            )
        }
    }

    static func timerWarningNotificationSchedule(
        remainingSeconds: TimeInterval,
        warningOffsets: [Int] = timerWarningNotificationOffsets
    ) -> [TimerWarningNotificationSchedule] {
        let safeRemainingSeconds = max(0, remainingSeconds)

        return warningOffsets.compactMap { warningOffset in
            let warningTriggerTime = safeRemainingSeconds - Double(warningOffset)
            guard warningTriggerTime > 1 else { return nil }

            return TimerWarningNotificationSchedule(
                remainingSeconds: warningOffset,
                timeInterval: notificationTriggerInterval(forTimerSeconds: warningTriggerTime)
            )
        }
    }

    private static var stopwatchNotificationIdentifiers: [String] {
        (0 ..< maxPendingStopwatchNotifications).map {
            "\(stopwatchNotificationIdentifierPrefix)-\($0 + 1)"
        }
    }

    private static var timerWarningNotificationIdentifiers: [String] {
        timerWarningNotificationOffsets.map {
            "\(timerWarningNotificationIdentifierPrefix)-\($0)"
        }
    }

    private static func formattedStopwatchElapsedTimeMark(_ elapsedSecondsMark: Int) -> String {
        formattedDuration(seconds: elapsedSecondsMark)
    }

    private static func formattedDuration(seconds totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private static func notificationTriggerInterval(forTimerSeconds seconds: TimeInterval) -> TimeInterval {
        max(1, seconds - 1)
    }
}
