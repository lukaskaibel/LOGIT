//
//  StopwatchView.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 01.04.22.
//

import SwiftUI

struct StopwatchView: View {
    let startTime: Date

    @State private var updater = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        if updater || !updater {
            Text(workoutDurationString)
                .onReceive(timer) { _ in
                    updater.toggle()
                }
        }
    }

    private var workoutDuration: Int {
        Int(NSInteger(Date().timeIntervalSince(startTime)))
    }

    private var workoutDurationString: String {
        "\(workoutDuration / 3600):\(workoutDuration / 60 / 10 % 6)\(workoutDuration / 60 % 10):\(workoutDuration % 60 / 10)\(workoutDuration % 60 % 10)"
    }
}
