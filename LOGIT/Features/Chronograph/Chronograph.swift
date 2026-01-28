//
//  Chronograph.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 20.07.23.
//

import Combine
import Foundation
import SwiftUI
import UserNotifications

class Chronograph: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    // MARK: - Enums

    enum Mode {
        case timer
        case stopwatch
    }

    enum ChronographStatus {
        case idle
        case running
        case paused
    }

    // MARK: - Properties

    @Published var mode: Mode = .timer
    @Published var status: ChronographStatus = .idle

    var onTimerFired: (() -> Void)?

    var seconds: TimeInterval = 0
    private var timer: Timer?
    var startDate: Date?
    private var pauseTime: TimeInterval?

    // MARK: - Init

    override init() {
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

        if mode == .timer {
            scheduleTimerNotification(inSeconds: seconds)
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
        cancelTimerNotification()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        status = .paused
        cancelTimerNotification()
    }

    func setSeconds(_ seconds: Double) {
        self.seconds = seconds
        objectWillChange.send()
        if status == .running {
            cancelTimerNotification()
            scheduleTimerNotification(inSeconds: seconds)
        }
    }

    private func reset() {
        timer?.invalidate()
        timer = nil
        startDate = nil
        seconds = 0
        status = .idle
    }

    private var timesUpNotificationRequest: UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("timesUp", comment: "")
        content.body = NSLocalizedString("timesUpBody", comment: "")
        let timerIsMuted = UserDefaults.standard.bool(forKey: "timerIsMuted")
        if !timerIsMuted {
            content.sound = UNNotificationSound(named: UNNotificationSoundName("timer.wav"))
        }
        content.interruptionLevel = .critical

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds - 1, repeats: false)

        let request = UNNotificationRequest(
            identifier: "timerFinished",
            content: content,
            trigger: trigger
        )
        return request
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

    private func cancelTimerNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["timerFinished"])
        print("Timer notification cancelled.")
    }

    func userNotificationCenter(_: UNUserNotificationCenter,
                                willPresent _: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    {
        // Show banner, sound, and badge even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
}
