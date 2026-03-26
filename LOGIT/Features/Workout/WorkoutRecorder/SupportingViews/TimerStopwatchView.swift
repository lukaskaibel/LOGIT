//
//  TimerStopwatchView.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 08.06.23.
//

import AlarmKit
import SwiftUI

struct TimerStopwatchView: View {
    // MARK: - Properties

    @ObservedObject var chronograph: Chronograph
    @EnvironmentObject private var workoutRecorder: WorkoutRecorder

    enum PermissionRequirement {
        case timerAlarm
        case notification
    }

    @AppStorage("lastTimerDuration") private var lastTimerDuration: Int = 30
    @AppStorage("hasRequestedNotificationPermission") private var hasRequestedNotificationPermission: Bool = false
    @AppStorage("hasRequestedAlarmPermission") private var hasRequestedAlarmPermission: Bool = false
    @AppStorage("autoTimerEnabled") private var autoTimerEnabled: Bool = false
    @AppStorage("autoStopwatchEnabled") private var autoStopwatchEnabled: Bool = false
    @AppStorage("timerIsMuted") private var timerIsMuted: Bool = false

    // MARK: - Constants

    private let timerValues = [
        0, 10, 15, 30, 45, 60, 90, 120, 150, 180, 240, 300, 360, 420, 480, 540, 600,
    ]
    private let opacityOfTimeWhenPaused = 0.7
    private let transportButtonSize: CGFloat = 70
    private let transportButtonIconSize: CGFloat = 20
    private let controlSectionHeight: CGFloat = 96
    private let stopwatchQuickAdjustments = [-15, -5, 5, 15]

    @State private var isShowingNotificationNotEnabledAlert = false
    @State private var isShowingNotificationExplanationAlert = false
    @State private var activePermissionRequirement: PermissionRequirement = .notification

    // MARK: - View

    var body: some View {
        VStack(spacing: 20) {
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
                        .foregroundStyle(chronograph.mode == .timer ? themeColor : .placeholder)
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
                        .foregroundStyle(chronograph.mode == .stopwatch ? themeColor : .placeholder)
                }
            }

            if let activeExerciseName, isWorkoutRestChronographActive {
                HStack(spacing: 6) {
                    Image(systemName: chronograph.mode == .timer ? "timer" : "stopwatch")
                    Text(activeExerciseName)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeColor)
                .padding(.bottom, 6)
            }
            
            Spacer(minLength: 0)

            VStack {
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
                .opacity(chronograph.mode == .timer && chronograph.status != .idle ? 1 : 0)
                
                HStack(alignment: .center) {
                    Spacer()
                    timerDecreaseButton
                        .opacity(chronograph.mode == .timer ? 1 : 0)
                        .allowsHitTesting(chronograph.mode == .timer)
                    Spacer()
                    ChronographView(chronograph: chronograph) { seconds in
                        Text(timeString(seconds: seconds))
                            .font(.system(size: 70, weight: .regular).monospacedDigit())
                            .fontDesign(.rounded)
                            .foregroundColor(themeColor)
                            .opacity(chronograph.status == .paused ? opacityOfTimeWhenPaused : 1)
                            .lineLimit(1)
                            .minimumScaleFactor(1)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    timerIncreaseButton
                        .opacity(chronograph.mode == .timer ? 1 : 0)
                        .allowsHitTesting(chronograph.mode == .timer)
                    Spacer()
                }
                muteButton

                if chronograph.mode == .stopwatch {
                    stopwatchAdjustmentControls
                        .padding(.top, 18)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                }
            }

            Spacer(minLength: 0)
            
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                transportControls
                Spacer(minLength: 0)
            }
            .frame(height: controlSectionHeight)
            
            Spacer(minLength: 0)

            autoTimerSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal)
        .padding(.top, 24)
        .padding(.bottom)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: chronograph.mode)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: chronograph.status)
        .onChange(of: chronograph.status) {
            if chronograph.status == .idle && chronograph.mode == .timer {
                chronograph.setSeconds(Double(lastTimerDuration) + 0.99)
            }
        }
        .onChange(of: chronograph.mode) { oldMode, newMode in
            finishActiveRestIfNeeded(
                shouldPersistElapsed: oldMode == .stopwatch,
                mode: oldMode
            )
            chronograph.cancel()
            chronograph.setSeconds(newMode == .timer ? Double(lastTimerDuration) + 0.99 : 0)
            checkPermissionRequirement()
        }
        .onChange(of: timerIsMuted) {
            guard chronograph.mode == .timer, chronograph.status != .running else { return }
            checkPermissionRequirement()
        }
        .onAppear {
            checkPermissionRequirement()
            if chronograph.mode == .timer, chronograph.status == .idle {
                chronograph.setSeconds(Double(lastTimerDuration) + 0.99)
            }
        }
        .alert(Text(permissionDisabledTitle), isPresented: $isShowingNotificationNotEnabledAlert, actions: {
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
            Text(permissionDisabledMessage)
        })
        .alert(Text(permissionExplanationTitle), isPresented: $isShowingNotificationExplanationAlert, actions: {
            Button(NSLocalizedString("continue", comment: "")) {
                requestPermission()
            }
            .fontWeight(.bold)
            Button(NSLocalizedString("notNow", comment: ""), role: .cancel) {
                markCurrentPermissionPromptSeen()
            }
        }, message: {
            Text(permissionExplanationMessage)
        })
    }

    // MARK: - Subviews

    private var autoTimerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: autoRestBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "repeat")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(themeColor)
                        Text(autoRestTitle)
                            .font(.subheadline.weight(.semibold))
                    }

                    Text(autoRestDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(themeColor)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private var muteButton: some View {
        if chronograph.mode == .timer {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                timerIsMuted.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: timerIsMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.footnote.weight(.semibold))
                    Text(
                        timerIsMuted
                            ? NSLocalizedString("timerIsMuted", comment: "")
                            : NSLocalizedString("timerSoundOn", comment: "")
                    )
                    .font(.footnote.weight(.medium))
                }
                .foregroundStyle(timerIsMuted ? themeColor.opacity(0.8) : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    timerIsMuted
                        ? themeColor.secondaryTranslucentBackground.opacity(0.7)
                        : Color.fill.opacity(0.5),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                timerIsMuted
                    ? NSLocalizedString("timerIsMuted", comment: "")
                    : NSLocalizedString("timerSoundOn", comment: "")
            )
        }
    }

    private var stopwatchAdjustmentControls: some View {
        HStack(spacing: 12) {
            ForEach(stopwatchQuickAdjustments, id: \.self) { adjustment in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    chronograph.adjustStopwatch(by: Double(adjustment))
                } label: {
                    Text(adjustmentLabel(for: adjustment))
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(adjustment < 0 ? .secondary : themeColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            adjustment < 0
                                ? Color.fill
                                : themeColor.secondaryTranslucentBackground
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!showsStopwatchAdjustmentControls)
            }
        }
        .opacity(showsStopwatchAdjustmentControls ? 1 : 0)
        .offset(y: showsStopwatchAdjustmentControls ? 0 : -10)
        .allowsHitTesting(showsStopwatchAdjustmentControls)
    }

    private var transportControls: some View {
        HStack(spacing: 24) {
            Spacer()
            if showsLeadingTransportButton {
                leadingTransportButton
                Spacer()
            }
            playPauseButton
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var timerDecreaseButton: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            guard
                let currentTimerValueIndex = timerValues.lastIndex(where: {
                    $0 <= currentTimerDuration
                }), currentTimerValueIndex > 0
            else { return }
            updateTimerDuration(to: timerValues[currentTimerValueIndex - 1])
        } label: {
            Image(systemName: "minus")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .font(.title2.weight(.heavy))
                .foregroundStyle(themeColor)
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
                    $0 > currentTimerDuration
                })
            else { return }
            updateTimerDuration(to: timerValues[firstLargerTimerValueIndex])
        } label: {
            Image(systemName: "plus")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .font(.title2.weight(.heavy))
                .foregroundStyle(themeColor)
                .padding(10)
                .background(Color.fill)
                .clipShape(Circle())
        }
    }

    private var playPauseButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if chronograph.mode == .timer, chronograph.status == .idle {
                lastTimerDuration = Int(chronograph.seconds)
            }
            if chronograph.mode == .timer, chronograph.status != .running {
                chronograph.timerAlertTintColor = themeColor
            }
            chronograph.status == .running ? chronograph.stop() : chronograph.start()
        } label: {
            Image(systemName: chronograph.status == .running ? "pause.fill" : "play.fill")
                .resizable()
                .frame(width: transportButtonIconSize, height: transportButtonIconSize)
                .fontWeight(.bold)
                .foregroundStyle(themeColor)
                .frame(width: transportButtonSize, height: transportButtonSize)
                .background(themeColor.secondaryTranslucentBackground)
                .clipShape(Circle())
        }
        .disabled(chronograph.mode == .timer && Int(chronograph.seconds) == 0)
    }

    @ViewBuilder
    private var leadingTransportButton: some View {
        if isRunningStopwatch {
            stopwatchTransportButton(symbolName: "stop.fill") {
                workoutRecorder.endStopwatch(using: chronograph)
            }
        } else if isPausedStopwatch {
            stopwatchTransportButton(symbolName: "arrow.trianglehead.counterclockwise") {
                finishActiveRestIfNeeded(shouldPersistElapsed: false)
                chronograph.cancel()
            }
        } else if chronograph.mode == .timer, chronograph.status != .idle {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                finishActiveRestIfNeeded(shouldPersistElapsed: false)
                chronograph.cancel()
            } label: {
                Image(systemName: "arrow.trianglehead.counterclockwise")
                    .resizable()
                    .frame(width: 20, height: 20)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.label)
                    .padding(25)
                    .background(Color.fill)
                    .clipShape(Circle())
            }
            .disabled(Int(chronograph.seconds) == 0)
        } else {
            Color.clear
                .frame(width: 70, height: 70)
        }
    }

    private func stopwatchTransportButton(symbolName: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(themeColor)
                .frame(width: transportButtonIconSize, height: transportButtonIconSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(themeColor.secondaryTranslucentBackground)
        .frame(width: transportButtonSize, height: transportButtonSize)
    }

    private func updateTimerDuration(to remainingDuration: Int) {
        let updatedTotalDuration = currentElapsedTimerDuration + remainingDuration
        lastTimerDuration = updatedTotalDuration
        chronograph.setSeconds(
            Double(remainingDuration) + 0.99,
            timerTotalSecondsOverride: Double(updatedTotalDuration) + 0.99
        )
    }

    // MARK: - Supporting Properties

    private var themeColor: Color {
        if isWorkoutRestChronographActive,
           let exerciseColor = workoutRecorder.activeRestTimerSet?.exercise?.muscleGroup?.color {
            return exerciseColor
        }

        return .accentColor
    }

    private var currentTimerDuration: Int {
        return Int(chronograph.seconds.rounded(.down))
    }

    private var currentElapsedTimerDuration: Int {
        max(0, currentOverallTimerDuration - currentTimerDuration)
    }

    private var currentOverallTimerDuration: Int {
        if chronograph.mode == .timer, chronograph.status != .idle {
            return Int(chronograph.initialTimerSeconds.rounded(.down))
        }

        return lastTimerDuration
    }

    private var isWorkoutRestChronographActive: Bool {
        (chronograph.status == .running || chronograph.status == .paused)
            && workoutRecorder.activeRestTimerSet != nil
    }

    private var isRunningStopwatch: Bool {
        chronograph.mode == .stopwatch
            && chronograph.status == .running
    }

    private var isPausedStopwatch: Bool {
        chronograph.mode == .stopwatch
            && chronograph.status == .paused
    }

    private var showsStopwatchAdjustmentControls: Bool {
        chronograph.mode == .stopwatch
            && chronograph.status == .running
    }

    private var showsLeadingTransportButton: Bool {
        isRunningStopwatch
            || isPausedStopwatch
            || (chronograph.mode == .timer && chronograph.status != .idle)
    }

    private var activeExerciseName: String? {
        workoutRecorder.activeRestTimerSet?.exercise?.displayName
    }

    private var autoRestBinding: Binding<Bool> {
        Binding(
            get: { chronograph.mode == .timer ? autoTimerEnabled : autoStopwatchEnabled },
            set: {
                if chronograph.mode == .timer {
                    autoTimerEnabled = $0
                } else {
                    autoStopwatchEnabled = $0
                }
            }
        )
    }

    private var autoRestTitle: String {
        chronograph.mode == .timer
            ? NSLocalizedString("autoRestTimer", comment: "")
            : NSLocalizedString("autoRestStopwatch", comment: "")
    }

    private var autoRestDescription: String {
        chronograph.mode == .timer
            ? NSLocalizedString("autoRestTimerDescription", comment: "")
            : NSLocalizedString("autoRestStopwatchDescription", comment: "")
    }

    // MARK: - Supporting Methods

    private func timeString(seconds: Double) -> String {
        "\(Int(seconds) / 60 / 10 % 6)\(Int(seconds) / 60 % 10):\(Int(seconds) % 60 / 10)\(Int(seconds) % 60 % 10)"
    }

    private func adjustmentLabel(for adjustment: Int) -> String {
        let sign = adjustment > 0 ? "+" : ""
        return "\(sign)\(adjustment)s"
    }

    private func finishActiveRestIfNeeded(
        shouldPersistElapsed: Bool,
        mode: Chronograph.Mode? = nil
    ) {
        guard let activeRestSet = workoutRecorder.activeRestTimerSet else { return }

        let activeMode = mode ?? chronograph.mode
        if shouldPersistElapsed, activeMode == .stopwatch {
            let elapsed = chronograph.elapsedSeconds
            if elapsed > 0 {
                workoutRecorder.recordRestDuration(elapsed, for: activeRestSet)
            }
        }

        workoutRecorder.activeRestTimerSet = nil
    }

    private var permissionDisabledTitle: String {
        switch activePermissionRequirement {
        case .timerAlarm:
            NSLocalizedString("timerAlertsDisabled", comment: "")
        case .notification:
            NSLocalizedString("notificationsDisabled", comment: "")
        }
    }

    private var permissionDisabledMessage: String {
        switch activePermissionRequirement {
        case .timerAlarm:
            NSLocalizedString("timerAlertsDisabledMessage", comment: "")
        case .notification:
            NSLocalizedString("notificationsDisabledMessage", comment: "")
        }
    }

    private var permissionExplanationTitle: String {
        switch activePermissionRequirement {
        case .timerAlarm:
            NSLocalizedString("enableTimerAlerts", comment: "")
        case .notification:
            NSLocalizedString("enableTimerNotifications", comment: "")
        }
    }

    private var permissionExplanationMessage: String {
        switch activePermissionRequirement {
        case .timerAlarm:
            NSLocalizedString("enableTimerAlertsMessage", comment: "")
        case .notification:
            NSLocalizedString("enableTimerNotificationsMessage", comment: "")
        }
    }

    private var currentPermissionRequirement: PermissionRequirement {
        if chronograph.mode == .timer && !timerIsMuted {
            return .timerAlarm
        }

        return .notification
    }

    private func checkPermissionRequirement() {
        switch currentPermissionRequirement {
        case .timerAlarm:
            checkAlarmPermission()
        case .notification:
            checkNotificationPermission()
        }
    }

    private func checkNotificationPermission() {
        activePermissionRequirement = .notification
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
                    break

                @unknown default:
                    break
                }
            }
        }
    }

    private func checkAlarmPermission() {
        activePermissionRequirement = .timerAlarm

        switch AlarmManager.shared.authorizationState {
        case .notDetermined:
            if !hasRequestedAlarmPermission {
                isShowingNotificationExplanationAlert = true
            }

        case .denied:
            isShowingNotificationNotEnabledAlert = true

        case .authorized:
            break
        @unknown default:
            break
        }
    }

    private func requestPermission() {
        switch activePermissionRequirement {
        case .timerAlarm:
            requestAlarmPermission()
        case .notification:
            requestNotificationPermission()
        }
    }

    private func markCurrentPermissionPromptSeen() {
        switch activePermissionRequirement {
        case .timerAlarm:
            hasRequestedAlarmPermission = true
        case .notification:
            hasRequestedNotificationPermission = true
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

    private func requestAlarmPermission() {
        hasRequestedAlarmPermission = true

        Task {
            do {
                let state = try await AlarmManager.shared.requestAuthorization()
                if state == .denied {
                    await MainActor.run {
                        isShowingNotificationNotEnabledAlert = true
                    }
                }
            } catch {
                print("Alarm auth error: \(error)")
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
                    .previewEnvironmentObjects()
                    .presentationDetents([.medium, .large])
            }
    }
}
