//
//  LiveActivityShowcaseView.swift
//  LOGIT
//
//  Marketing-only Lock Screen used by fastlane snapshot to capture a single
//  App Store asset showing LOGIT's Live Activity in both modes: the rest timer
//  and a set being logged. Only the Lock Screen around the cards is staged
//  (wallpaper, clock, captions); each card is the widget's own
//  `WorkoutLiveActivityLockScreenView`, so the screenshot changes whenever the
//  Live Activity does. frameit adds the device frame and headline like the
//  rest of the screenshot set.
//
//  Only presented when `ScreenshotFixtures.shouldShowLiveActivityShowcase`
//  is true. Not wired into any user-facing flow.
//

import SwiftUI

struct LiveActivityShowcaseView: View {
    var body: some View {
        ZStack(alignment: .top) {
            LiveActivityShowcaseBackground()

            VStack(spacing: 0) {
                LiveActivityShowcaseClock()
                    .padding(.top, 44)

                Spacer(minLength: 28)

                VStack(alignment: .leading, spacing: 18) {
                    LiveActivityShowcaseModeCaption(
                        text: NSLocalizedString("screenshotLiveActivityModeAutoCaption", comment: "")
                    )

                    LiveActivityShowcaseCard(state: LiveActivityShowcaseState.restTimer())

                    LiveActivityShowcaseModeCaption(
                        text: NSLocalizedString("screenshotLiveActivityModeLoggingCaption", comment: "")
                    )

                    LiveActivityShowcaseCard(state: LiveActivityShowcaseState.setLogging())
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 36)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}

// MARK: - Background

private struct LiveActivityShowcaseBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.05, blue: 0.18),
                    Color(red: 0.11, green: 0.07, blue: 0.24),
                    Color(red: 0.04, green: 0.03, blue: 0.1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.96, green: 0.55, blue: 0.28).opacity(0.45),
                    Color.clear,
                ],
                center: .init(x: 0.15, y: 0.12),
                startRadius: 30,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    Color(red: 0.29, green: 0.68, blue: 1.0).opacity(0.35),
                    Color.clear,
                ],
                center: .init(x: 0.92, y: 0.78),
                startRadius: 30,
                endRadius: 560
            )

            RadialGradient(
                colors: [
                    Color(red: 0.73, green: 0.99, blue: 0.31).opacity(0.2),
                    Color.clear,
                ],
                center: .init(x: 0.5, y: 0.42),
                startRadius: 40,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Lock Screen clock

private struct LiveActivityShowcaseClock: View {
    var body: some View {
        VStack(spacing: 6) {
            Text(NSLocalizedString("screenshotLockScreenDate", comment: ""))
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.85))

            Text("9:41")
                .font(.system(size: 116, weight: .light, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.35), radius: 16, y: 4)
        }
    }
}

// MARK: - Mode captions

private struct LiveActivityShowcaseModeCaption: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(Color.white.opacity(0.55))
            .padding(.leading, 4)
    }
}

// MARK: - Cards

/// The Lock Screen platter around the real Live Activity content: the system paints the widget's
/// `activityBackgroundTint` in a rounded card, and that is all the showcase adds.
private struct LiveActivityShowcaseCard: View {
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        WorkoutLiveActivityLockScreenView(attributes: LiveActivityShowcaseState.attributes, state: state)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(WorkoutLiveActivityLockScreenView.backgroundTint)
            )
            .shadow(color: Color.black.opacity(0.45), radius: 28, y: 12)
            .environment(\.colorScheme, .dark)
    }
}

/// The two moments the screenshot shows, on the same set of the same workout, with names from the
/// localized screenshot keys so every locale reads in its own language.
private enum LiveActivityShowcaseState {
    static let attributes = WorkoutLiveActivityAttributes(
        workoutID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        startedAt: Date().addingTimeInterval(-(22 * 60 + 14))
    )

    /// Resting before set 3 of 4: the chest-tinted countdown owns the card, with that set underneath.
    static func restTimer(now: Date = .now) -> WorkoutLiveActivityAttributes.ContentState {
        state(
            setIndex: 3,
            reps: ("10", true),
            weight: ("32.5", true),
            chronoChip: WorkoutLiveActivityChronoChip(
                phase: .timerRunning,
                tintKind: .restTimer,
                muscleThemeToken: .chest,
                timerEndDate: now.addingTimeInterval(97),
                timerTotalSeconds: 150,
                staticTickSeconds: nil,
                stopwatchStartDate: nil
            )
        )
    }

    /// Logging set 3: the reps are in, the weight still shows the template's value in placeholder grey.
    static func setLogging() -> WorkoutLiveActivityAttributes.ContentState {
        state(setIndex: 3, reps: ("10", false), weight: ("32.5", true), chronoChip: nil)
    }

    private static func state(
        setIndex: Int,
        reps: (value: String, isPlaceholder: Bool),
        weight: (value: String, isPlaceholder: Bool),
        chronoChip: WorkoutLiveActivityChronoChip?
    ) -> WorkoutLiveActivityAttributes.ContentState {
        WorkoutLiveActivityAttributes.ContentState(
            workoutTitle: NSLocalizedString("screenshotPushDay", comment: ""),
            exerciseIndex: 2,
            exerciseCount: 3,
            setIndex: setIndex,
            setCount: 4,
            primaryExerciseName: NSLocalizedString("screenshotInclineDumbbellPress", comment: ""),
            secondaryExerciseName: nil,
            supersetPartnerIsLeading: false,
            primaryMetrics: ExerciseMetricDisplay(
                repetitionSegments: [reps.value],
                repetitionSegmentPlaceholders: [reps.isPlaceholder],
                repetitionsUnit: NSLocalizedString("reps", comment: ""),
                weightSegments: [weight.value],
                weightSegmentPlaceholders: [weight.isPlaceholder],
                weightUnit: "kg"
            ),
            themeToken: .chest,
            chronoChip: chronoChip,
            hasPendingSet: true
        )
    }
}

#Preview {
    LiveActivityShowcaseView()
}
