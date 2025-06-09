//
//  Chronograph.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 20.07.23.
//

import Combine
import SwiftUI

class Chronograph: ObservableObject {
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

    @Published var seconds: TimeInterval = 0
    @Published var mode: Mode = .timer
    @Published var status: ChronographStatus = .idle

    var onTimerFired: (() -> Void)?

    private var timer: Timer?
    private var startDate: Date?
    private var pauseTime: TimeInterval?

    // MARK: - Methods

    func start() {
        if pauseTime != nil {
            seconds = pauseTime!
            pauseTime = nil
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
                        self.cancel()
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

    func pause() {
        timer?.invalidate()
        timer = nil
        pauseTime = seconds
        status = .paused
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        startDate = nil
        seconds = 0
        status = .idle
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        status = .paused
    }
}
