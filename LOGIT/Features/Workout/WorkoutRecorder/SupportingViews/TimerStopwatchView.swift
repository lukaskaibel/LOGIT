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
    @EnvironmentObject private var workoutRecorder: WorkoutRecorder

    @AppStorage("lastTimerDuration") private var lastTimerDuration: Int = 30
    @AppStorage("hasRequestedNotificationPermission") private var hasRequestedNotificationPermission: Bool = false
    @AppStorage("autoTimerEnabled") private var autoTimerEnabled: Bool = false
    @AppStorage("autoStopwatchEnabled") private var autoStopwatchEnabled: Bool = false
    @AppStorage("timerIsMuted") private var timerIsMuted: Bool = false

    // MARK: - Constants

    private let opacityOfTimeWhenPaused = 0.7
    private let transportButtonSize: CGFloat = 70
    private let transportButtonIconSize: CGFloat = 20
    private let stopwatchQuickAdjustments = [-15, -5, 5, 15]
    private let timerQuickAdjustments = [-15, -5, 5, 15]
    private let timerPresets = [10, 20, 30, 45, 60, 90, 120, 150, 180, 240, 300, 600]

    @State private var isShowingNotificationNotEnabledAlert = false
    @State private var isShowingNotificationExplanationAlert = false

    @Namespace private var transportNamespace

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
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: chronograph.mode == .timer ? "timer" : "stopwatch")
                    Text(activeExerciseName)
                        .lineLimit(1)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeColor)
                .transition(.opacity.combined(with: .offset(y: -4)))
            }

            Spacer()

            VStack(spacing: 6) {
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

                ChronographView(chronograph: chronograph) { seconds in
                    Text(timeString(seconds: seconds))
                        .font(.system(size: 70, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(themeColor)
                        .opacity(chronograph.status == .paused ? opacityOfTimeWhenPaused : 1)
                        .lineLimit(1)
                        .minimumScaleFactor(1)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.18), value: Int(seconds.rounded(.down)))
                }
                .frame(maxWidth: .infinity)

                
            }

            Spacer()
            
            secondaryControlsSection
                .padding(.top, 14)

            Spacer()
            
            transportControls

            Spacer()

            muteButton
                .opacity(chronograph.mode == .timer ? 1 : 0)
                .allowsHitTesting(chronograph.mode == .timer)

            Spacer(minLength: 20)

            autoTimerSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal)
        .padding(.top, 28)
        .padding(.bottom, 16)
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

    private var muteButton: some View {
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
            if showsLeadingTransportButton {
                Spacer(minLength: 0)
                playPauseButton
                    .matchedGeometryEffect(id: "playPause", in: transportNamespace)
                Spacer(minLength: 0)
                leadingTransportButton
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                playPauseButton
                    .matchedGeometryEffect(id: "playPause", in: transportNamespace)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var secondaryControlsSection: some View {
        ZStack {
            if chronograph.mode == .timer, chronograph.status == .idle {
                timerPresetControls
                    .transition(.blurReplace.combined(with: .opacity))
            } else if chronograph.mode == .timer {
                timerAdjustmentControls
                    .transition(.blurReplace.combined(with: .opacity))
            } else if chronograph.mode == .stopwatch {
                stopwatchAdjustmentControls
                    .transition(.blurReplace.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: chronograph.mode)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: chronograph.status)
    }

    private var timerAdjustmentControls: some View {
        HStack(spacing: 12) {
            ForEach(timerQuickAdjustments, id: \.self) { adjustment in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    adjustTimer(by: adjustment)
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
                .disabled(adjustment < 0 && Int(chronograph.seconds) == 0)
            }
        }
    }

    private var timerPresetControls: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(timerPresets, id: \.self) { preset in
                        let isSelected = lastTimerDuration == preset
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            applyTimerPreset(preset)
                        } label: {
                            Text(presetLabel(for: preset))
                                .font(.body.weight(.semibold).monospacedDigit())
                                .foregroundStyle(isSelected ? themeColor : .secondary)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .background(
                                    isSelected
                                        ? themeColor.secondaryTranslucentBackground
                                        : Color.fill
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(preset)
                    }
                }
                .padding(.horizontal, 2)
            }
            .onAppear {
                DispatchQueue.main.async {
                    scrollToSelectedPreset(using: proxy, animated: false)
                }
            }
            .onChange(of: lastTimerDuration) {
                scrollToSelectedPreset(using: proxy, animated: true)
            }
        }
    }

    private func scrollToSelectedPreset(using proxy: ScrollViewProxy, animated: Bool) {
        guard let target = timerPresets.first(where: { $0 == lastTimerDuration })
            ?? timerPresets.min(by: { abs($0 - lastTimerDuration) < abs($1 - lastTimerDuration) })
        else { return }

        let scroll = {
            proxy.scrollTo(target, anchor: .center)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                scroll()
            }
        } else {
            scroll()
        }
    }

    private var playPauseButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if chronograph.mode == .timer, chronograph.status == .idle {
                lastTimerDuration = Int(chronograph.seconds)
            }
            chronograph.status == .running ? chronograph.stop() : chronograph.start()
        } label: {
            Image(systemName: chronograph.status == .running ? "pause.fill" : "play.fill")
                .resizable()
                .frame(width: transportButtonIconSize, height: transportButtonIconSize)
                .fontWeight(.bold)
                .foregroundStyle(playPauseButtonForegroundColor)
                .frame(width: transportButtonSize, height: transportButtonSize)
                .background(playPauseButtonBackgroundColor)
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
            stopwatchTransportButton(symbolName: "stop.fill") {
                finishActiveRestIfNeeded(shouldPersistElapsed: false)
                chronograph.cancel()
            }
        } else if chronograph.mode == .timer, chronograph.status != .idle {
            stopwatchTransportButton(symbolName: "stop.fill") {
                // For an auto-rest timer, keep the elapsed rest time so far when cancelling.
                finishActiveRestIfNeeded(shouldPersistElapsed: true)
                chronograph.cancel()
            }
            .disabled(Int(chronograph.seconds) == 0)
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

    private func adjustTimer(by adjustment: Int) {
        let newRemaining = max(0, currentTimerDuration + adjustment)
        updateTimerDuration(to: newRemaining)
    }

    private func applyTimerPreset(_ preset: Int) {
        lastTimerDuration = preset
        chronograph.setSeconds(Double(preset) + 0.99)
    }

    private func presetLabel(for seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
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

    private var isIdleTimer: Bool {
        chronograph.mode == .timer && chronograph.status == .idle
    }

    private var playPauseButtonForegroundColor: Color {
        chronograph.status == .idle ? themeColor : .white
    }

    private var playPauseButtonBackgroundColor: Color {
        chronograph.status == .idle ? themeColor.secondaryTranslucentBackground : .fill
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
        if shouldPersistElapsed, activeMode == .stopwatch || activeMode == .timer {
            let elapsed = chronograph.elapsedSeconds
            if elapsed > 0 {
                workoutRecorder.recordRestDuration(elapsed, for: activeRestSet)
            }
        }

        workoutRecorder.activeRestTimerSet = nil
    }

    private var permissionDisabledTitle: String {
        NSLocalizedString("notificationsDisabled", comment: "")
    }

    private var permissionDisabledMessage: String {
        NSLocalizedString("notificationsDisabledMessage", comment: "")
    }

    private var permissionExplanationTitle: String {
        NSLocalizedString("enableTimerNotifications", comment: "")
    }

    private var permissionExplanationMessage: String {
        NSLocalizedString("enableTimerNotificationsMessage", comment: "")
    }

    private func checkPermissionRequirement() {
        checkNotificationPermission()
    }

    private func checkNotificationPermission() {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }
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

    private func requestPermission() {
        requestNotificationPermission()
    }

    private func markCurrentPermissionPromptSeen() {
        hasRequestedNotificationPermission = true
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
                    .previewEnvironmentObjects()
                    .presentationDetents([.fraction(0.88)])
                    .presentationDragIndicator(.visible)
            }
    }
}
