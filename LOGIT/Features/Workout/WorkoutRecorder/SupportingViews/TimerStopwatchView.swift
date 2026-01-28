//
//  TimerStopwatchView.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 08.06.23.
//

import SwiftUI

struct TimerStopwatchView: View {
    // MARK: - Properties

    @ObservedObject var chronograph: Chronograph

    @AppStorage("lastTimerDuration") private var lastTimerDuration: Int = 30
    @AppStorage("hasRequestedNotificationPermission") private var hasRequestedNotificationPermission: Bool = false

    // MARK: - Constants

    private let timerValues = [
        0, 10, 15, 30, 45, 60, 90, 120, 150, 180, 240, 300, 360, 420, 480, 540, 600,
    ]
    private let opacityOfTimeWhenPaused = 0.7

    @State private var isShowingNotificationNotEnabledAlert = false
    @State private var isShowingNotificationExplanationAlert = false

    // MARK: - View

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if chronograph.mode != .timer {
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                    chronograph.mode = .timer
                } label: {
                    Text(NSLocalizedString("timer", comment: ""))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(chronograph.mode == .timer ? .white : .placeholder)
                }
                Spacer()
                Button {
                    if chronograph.mode != .stopwatch {
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                    chronograph.mode = .stopwatch
                } label: {
                    Text(NSLocalizedString("stopwatch", comment: ""))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(chronograph.mode == .stopwatch ? .white : .placeholder)
                }
            }
            Spacer()
            HStack {
                Spacer()
                if chronograph.mode == .timer {
                    timerDecreaseButton
                }
                Spacer()
                VStack {
                    if chronograph.status != .idle {
                        // Add this with opacity 0, s.t. the timer string stays centered
                        Text(timeString(seconds: Double(lastTimerDuration)))
                            .foregroundStyle(.secondary)
                            .font(.body.monospacedDigit())
                            .opacity(0)
                    }
                    ChronographView(chronograph: chronograph) { seconds in
                        Text(timeString(seconds: seconds))
                            .font(.system(size: 70, weight: .regular).monospacedDigit())
                            .fontDesign(.rounded)
                            .foregroundColor(.accentColor)
                            .lineLimit(1)
                            .minimumScaleFactor(1)
                    }
                    if chronograph.status != .idle {
                        HStack {
                            let minutes = lastTimerDuration / 60
                            let seconds = lastTimerDuration % 60
                            if minutes > 0 {
                                HStack(alignment: .lastTextBaseline, spacing: 2) {
                                    Text("\(minutes)")
                                        .font(.body.monospacedDigit())
                                    Text(NSLocalizedString("min", comment: ""))
                                        .font(.footnote)
                                }
                            }
                            if seconds > 0 {
                                HStack(alignment: .lastTextBaseline, spacing: 2) {
                                    Text("\(seconds)")
                                        .font(.body.monospacedDigit())
                                    Text(NSLocalizedString("sec", comment: ""))
                                        .font(.footnote)
                                }
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if chronograph.mode == .timer {
                    timerIncreaseButton
                }
                Spacer()
            }
            Spacer()
            HStack {
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    chronograph.status == .running ? chronograph.setSeconds(Double(lastTimerDuration) + 0.99) : chronograph.cancel()
                } label: {
                    Image(systemName: chronograph.status == .idle ? "xmark" : "arrow.trianglehead.counterclockwise")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .fontWeight(.bold)
                        .padding(25)
                        .background(Color.fill)
                        .clipShape(Circle())
                }
                .disabled(Int(chronograph.seconds) == 0)
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if chronograph.mode == .timer, chronograph.status == .idle {
                        lastTimerDuration = Int(chronograph.seconds)
                    }
                    chronograph.status == .running ? chronograph.stop() : chronograph.start()
                } label: {
                    Image(systemName: chronograph.status == .running ? "pause.fill" : "play.fill")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .fontWeight(.bold)
                        .padding(25)
                        .background(Color.accentColor.secondaryTranslucentBackground)
                        .clipShape(Circle())
                }
                .disabled(chronograph.mode == .timer && Int(chronograph.seconds) == 0)
                Spacer()
            }
        }
        .onChange(of: chronograph.status) {
            if chronograph.status == .idle && chronograph.mode == .timer {
                chronograph.setSeconds(Double(lastTimerDuration) + 0.99)
            }
        }
        .onChange(of: chronograph.mode) {
            chronograph.cancel()
            chronograph.setSeconds(chronograph.mode == .timer ? Double(lastTimerDuration) + 0.99 : 0)
        }
        .onAppear {
            checkNotificationPermission()
            if chronograph.mode == .timer, chronograph.status == .idle {
                chronograph.setSeconds(Double(lastTimerDuration) + 0.99)
            }
        }
        .alert(Text(NSLocalizedString("notificationsDisabled", comment: "")), isPresented: $isShowingNotificationNotEnabledAlert, actions: {
            Button(NSLocalizedString("openSettings", comment: "")) {
                if let url = URL(string: UIApplication.openSettingsURLString),
                   UIApplication.shared.canOpenURL(url)
                {
                    UIApplication.shared.open(url)
                }
            }
            .fontWeight(.bold)
            Button(NSLocalizedString("skip", comment: "")) {
                isShowingNotificationNotEnabledAlert = false
            }
        }, message: {
            Text(NSLocalizedString("notificationsDisabledMessage", comment: ""))
        })
        .alert(Text(NSLocalizedString("enableTimerNotifications", comment: "")), isPresented: $isShowingNotificationExplanationAlert, actions: {
            Button(NSLocalizedString("continue", comment: "")) {
                requestNotificationPermission()
            }
            .fontWeight(.bold)
            Button(NSLocalizedString("notNow", comment: ""), role: .cancel) {
                hasRequestedNotificationPermission = true
            }
        }, message: {
            Text(NSLocalizedString("enableTimerNotificationsMessage", comment: ""))
        })
    }

    // MARK: - Subviews

    private var pickerView: some View {
        Picker("Select Timer or Stopwatch", selection: $chronograph.mode) {
            Image(systemName: "timer")
                .tag(Chronograph.Mode.timer)
            Image(systemName: "stopwatch")
                .tag(Chronograph.Mode.stopwatch)
        }
        .pickerStyle(.segmented)
    }

    private var timerDecreaseButton: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            guard
                let firstLargerTimerValueIndex = timerValues.firstIndex(where: {
                    $0 >= Int(chronograph.seconds)
                }), firstLargerTimerValueIndex > 0
            else { return }
            let updatedSeconds = Double(timerValues[firstLargerTimerValueIndex - 1]) + 0.99
            lastTimerDuration = Int(updatedSeconds)
            chronograph.setSeconds(updatedSeconds)
        } label: {
            Image(systemName: "minus")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .font(.title2.weight(.heavy))
                .padding(10)
                .background(Color.fill)
                .clipShape(Circle())
        }
        .disabled(Int(chronograph.seconds) == 0)
    }

    private var timerIncreaseButton: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            guard
                let firstLargerTimerValueIndex = timerValues.firstIndex(where: {
                    $0 > Int(chronograph.seconds)
                }), firstLargerTimerValueIndex > 0
            else { return }
            let updatedSeconds = Double(timerValues[firstLargerTimerValueIndex]) + 0.99
            lastTimerDuration = Int(updatedSeconds)
            chronograph.setSeconds(updatedSeconds)
        } label: {
            Image(systemName: "plus")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .font(.title2.weight(.heavy))
                .padding(10)
                .background(Color.fill)
                .clipShape(Circle())
        }
    }

    private func timeString(seconds: Double) -> String {
        "\(Int(seconds) / 60 / 10 % 6)\(Int(seconds) / 60 % 10):\(Int(seconds) % 60 / 10)\(Int(seconds) % 60 % 10)"
    }

    private func durationMinutesString(seconds: Double) -> String {
        "\(Int(seconds) / 60)"
    }

    private func durationSecondsString(seconds: Double) -> String {
        "\(Int(seconds) % 60)"
    }

    private func checkNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .notDetermined:
                    if !hasRequestedNotificationPermission {
                        isShowingNotificationExplanationAlert = true
                    }

                case .denied:
                    isShowingNotificationNotEnabledAlert = true

                case .authorized, .provisional, .ephemeral:
                    // Notifications are enabled, nothing to do
                    break

                @unknown default:
                    break
                }
            }
        }
    }
    
    private func requestNotificationPermission() {
        hasRequestedNotificationPermission = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification auth error: \(error)")
            } else if granted {
                print("User allowed notifications")
            } else {
                print("User denied notifications")
            }
        }
    }
}

struct TimerView_Previews: PreviewProvider {
    static var previews: some View {
        Rectangle()
            .foregroundStyle(.black)
            .sheet(isPresented: .constant(true)) {
                TimerStopwatchView(chronograph: Chronograph())
                    .padding()
                    .tileStyle()
                    .presentationDetents([.fraction(0.4)])
            }
    }
}
