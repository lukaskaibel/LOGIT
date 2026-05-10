//
//  Chronograph.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 20.07.23.
//

import AVFoundation
import Combine
import Foundation
import SwiftUI
import ActivityKit
import AlarmKit
import UserNotifications

class Chronograph: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    // MARK: - Enums

    enum Mode: String {
        case timer
        case stopwatch
    }

    enum ChronographStatus: Equatable {
        case idle
        case running
        case paused
    }

    // MARK: - Properties

    private static let modeStorageKey = "selectedChronographMode"
    private static let timerFinishedNotificationIdentifier = "timerFinished"
    private static let stopwatchMinuteNotificationIdentifierPrefix = "stopwatchMinute"
    private static let alarmKitTimerSoundName = "timer.wav"
    private static let alarmAutoDismissInterval: TimeInterval = 1.5
    static let maxPendingStopwatchMinuteNotifications = 64

    struct StopwatchMinuteNotificationSchedule: Equatable {
        let minuteMark: Int
        let timeInterval: TimeInterval
    }

    @Published var mode: Mode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeStorageKey)
        }
    }
    @Published var status: ChronographStatus = .idle

    var onTimerFired: (() -> Void)?
    var timerAlertTintColor: Color = .accentColor

    var seconds: TimeInterval = 0
    /// The initial duration set for timer mode, used to compute elapsed time.
    private(set) var initialTimerSeconds: TimeInterval = 0
    private var timer: Timer?
    var startDate: Date?
    private var pauseTime: TimeInterval?
    private var activeTimerAlarmID: UUID?
    private var timerAlarmScheduleToken = UUID()
    private var beepPlayer: AVAudioPlayer?
    private var didBeepAt30: Bool = false
    private var didBeepAt10: Bool = false

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
        } else if mode == .timer {
            didBeepAt30 = seconds <= 30
            didBeepAt10 = seconds <= 10
        }

        scheduleNotificationsForCurrentState()

        startDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if let start = self.startDate {
                let timePassed = Date().timeIntervalSince(start)
                switch self.mode {
                case .timer:
                    self.seconds -= timePassed
                    self.playCountdownBeepIfNeeded()
                    if self.seconds <= 0 {
                        self.seconds = 0
                        self.scheduleAlarmAutoDismiss()
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
    }

    func cancel() {
        reset()
        cancelNotifications()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        status = .paused
        cancelNotifications()
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
        status = .idle
        didBeepAt30 = false
        didBeepAt10 = false
    }

    private func playCountdownBeepIfNeeded() {
        let timerIsMuted = UserDefaults.standard.bool(forKey: "timerIsMuted")
        guard !timerIsMuted else { return }

        if !didBeepAt30 && seconds <= 30 {
            didBeepAt30 = true
            playBeep()
        }
        if !didBeepAt10 && seconds <= 10 {
            didBeepAt10 = true
            playBeep()
        }
    }

    private func playBeep() {
        guard let url = Bundle.main.url(forResource: "beep", withExtension: "wav") else { return }
        beepPlayer = try? AVAudioPlayer(contentsOf: url)
        beepPlayer?.play()
    }

    private var timesUpNotificationRequest: UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("timesUp", comment: "")
        content.body = NSLocalizedString("timesUpBody", comment: "")
        let timerIsMuted = UserDefaults.standard.bool(forKey: "timerIsMuted")
        if !timerIsMuted {
            content.sound = UNNotificationSound(named: UNNotificationSoundName("timer.wav"))
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

    private func stopwatchMinuteNotificationRequest(
        identifier: String,
        minuteMark: Int,
        timeInterval: TimeInterval
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("stopwatchMinuteTitle", comment: "")
        content.body = String(
            format: NSLocalizedString("stopwatchMinuteBody", comment: ""),
            Self.formattedStopwatchMinuteMark(minuteMark)
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

    private func scheduleStopwatchMinuteNotifications(fromElapsedSeconds elapsedSeconds: TimeInterval) {
        cancelStopwatchMinuteNotifications()

        let center = UNUserNotificationCenter.current()
        let schedules = Self.stopwatchMinuteNotificationSchedule(elapsedSeconds: elapsedSeconds)

        for (index, schedule) in schedules.enumerated() {
            let request = stopwatchMinuteNotificationRequest(
                identifier: stopwatchMinuteNotificationIdentifier(at: index),
                minuteMark: schedule.minuteMark,
                timeInterval: schedule.timeInterval
            )
            center.add(request) { error in
                if let error {
                    print("Error scheduling stopwatch minute notification: \(error)")
                }
            }
        }
    }

    private func scheduleNotificationsForCurrentState() {
        cancelNotifications()

        switch mode {
        case .timer:
            scheduleTimerAlert(inSeconds: seconds)
        case .stopwatch:
            scheduleStopwatchMinuteNotifications(fromElapsedSeconds: seconds)
        }
    }

    private func cancelNotifications() {
        cancelTimerAlarm()
        cancelTimerNotification()
        cancelStopwatchMinuteNotifications()
    }

    private func cancelTimerNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.timerFinishedNotificationIdentifier])
        print("Timer notification cancelled.")
    }

    private func scheduleTimerAlert(inSeconds seconds: TimeInterval) {
        guard seconds > 0 else { return }

        if shouldUseAlarmKitForTimerAlert {
            scheduleAlarmKitTimer(inSeconds: seconds)
        } else {
            scheduleTimerNotification(inSeconds: seconds)
        }
    }

    private var shouldUseAlarmKitForTimerAlert: Bool {
        if #available(iOS 26.0, *) {
            return !UserDefaults.standard.bool(forKey: "timerIsMuted")
        }

        return false
    }

    @available(iOS 26.0, *)
    private func scheduleAlarmKitTimer(inSeconds seconds: TimeInterval) {
        let token = UUID()
        let alarmID = UUID()
        timerAlarmScheduleToken = token
        activeTimerAlarmID = alarmID

        let configuration = timerAlarmConfiguration(duration: Self.notificationTriggerInterval(forTimerSeconds: seconds))

        Task { [weak self] in
            do {
                _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)

                DispatchQueue.main.async {
                    guard let self else {
                        try? AlarmManager.shared.cancel(id: alarmID)
                        return
                    }

                    guard self.timerAlarmScheduleToken == token,
                          self.activeTimerAlarmID == alarmID,
                          self.mode == .timer,
                          self.status == .running
                    else {
                        try? AlarmManager.shared.cancel(id: alarmID)
                        return
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard self.timerAlarmScheduleToken == token,
                          self.activeTimerAlarmID == alarmID
                    else { return }

                    self.activeTimerAlarmID = nil
                    print("Error scheduling AlarmKit timer: \(error)")
                    self.scheduleTimerNotification(inSeconds: seconds)
                }
            }
        }
    }

    @available(iOS 26.0, *)
    private func timerAlarmConfiguration(duration: TimeInterval) -> AlarmManager.AlarmConfiguration<TimerAlarmMetadata> {
        AlarmManager.AlarmConfiguration.timer(
            duration: duration,
            attributes: timerAlarmAttributes,
            sound: .named(Self.alarmKitTimerSoundName)
        )
    }

    @available(iOS 26.0, *)
    private var timerAlarmAttributes: AlarmAttributes<TimerAlarmMetadata> {
        let stopButton = AlarmButton(
            text: localizedAlarmString("dismiss"),
            textColor: .white,
            systemImageName: "stop.circle"
        )
        let presentation = AlarmPresentation(
            alert: AlarmPresentation.Alert(
                title: localizedAlarmString("timesUp"),
                stopButton: stopButton
            )
        )

        return AlarmAttributes(
            presentation: presentation,
            tintColor: timerAlertTintColor
        )
    }

    @available(iOS 26.0, *)
    private func localizedAlarmString(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(stringLiteral: NSLocalizedString(key, comment: ""))
    }

    private func scheduleAlarmAutoDismiss() {
        let alarmIDToCancel = activeTimerAlarmID

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.alarmAutoDismissInterval) { [weak self] in
            // Remove delivered local notification
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: [Self.timerFinishedNotificationIdentifier]
            )

            // Cancel AlarmKit alarm if it was active
            if let alarmIDToCancel {
                if #available(iOS 26.0, *) {
                    try? AlarmManager.shared.cancel(id: alarmIDToCancel)
                }
            }

            self?.activeTimerAlarmID = nil
        }
    }

    private func cancelTimerAlarm() {
        timerAlarmScheduleToken = UUID()

        guard let activeTimerAlarmID else { return }

        if #available(iOS 26.0, *) {
            try? AlarmManager.shared.cancel(id: activeTimerAlarmID)
        }

        self.activeTimerAlarmID = nil
    }

    private func cancelStopwatchMinuteNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: Self.stopwatchMinuteNotificationIdentifiers
        )
    }

    private func stopwatchMinuteNotificationIdentifier(at index: Int) -> String {
        "\(Self.stopwatchMinuteNotificationIdentifierPrefix)-\(index + 1)"
    }

    func userNotificationCenter(_: UNUserNotificationCenter,
                                willPresent _: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    {
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

    static func stopwatchMinuteNotificationSchedule(
        elapsedSeconds: TimeInterval,
        maxNotificationCount: Int = maxPendingStopwatchMinuteNotifications
    ) -> [StopwatchMinuteNotificationSchedule] {
        guard maxNotificationCount > 0 else { return [] }

        let safeElapsedSeconds = max(0, elapsedSeconds)
        let completedMinutes = Int(safeElapsedSeconds / 60)
        let nextMinuteMark = completedMinutes + 1
        let secondsUntilNextMinute = max(1, Double(nextMinuteMark * 60) - safeElapsedSeconds)

        return (0 ..< maxNotificationCount).map { index in
            StopwatchMinuteNotificationSchedule(
                minuteMark: nextMinuteMark + index,
                timeInterval: secondsUntilNextMinute + Double(index * 60)
            )
        }
    }

    private static var stopwatchMinuteNotificationIdentifiers: [String] {
        (0 ..< maxPendingStopwatchMinuteNotifications).map {
            "\(stopwatchMinuteNotificationIdentifierPrefix)-\($0 + 1)"
        }
    }

    private static func formattedStopwatchMinuteMark(_ minuteMark: Int) -> String {
        let totalSeconds = minuteMark * 60
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private static func notificationTriggerInterval(forTimerSeconds seconds: TimeInterval) -> TimeInterval {
        max(1, seconds - 1)
    }
}

@available(iOS 26.0, *)
private struct TimerAlarmMetadata: AlarmMetadata {}
