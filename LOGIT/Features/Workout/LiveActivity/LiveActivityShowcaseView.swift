//
//  LiveActivityShowcaseView.swift
//  LOGIT
//
//  Marketing-only Lock Screen mockup used by fastlane snapshot to capture a
//  single App Store asset showing LOGIT's Live Activity in both modes: auto
//  rest countdown and normal set logging (previous + current weight). Copy is
//  only the fake Lock Screen (clock + cards); frameit adds the device frame
//  and headline like the rest of the screenshot set.
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

                    LiveActivityShowcaseAutoTimerCard()

                    LiveActivityShowcaseModeCaption(
                        text: NSLocalizedString("screenshotLiveActivityModeLoggingCaption", comment: "")
                    )

                    LiveActivityShowcaseCurrentSetCard()
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
            Text("Friday, November 14")
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

// MARK: - Shared card chrome

private struct LiveActivityShowcaseCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.55), radius: 32, y: 14)
    }
}

// MARK: - Auto timer card (Live Activity “chrono” mode)

private struct LiveActivityShowcaseAutoTimerCard: View {
    /// Chest muscle theme color mirrors `WorkoutLiveActivityThemeToken.chest`.
    private let timerTint = Color(red: 160 / 255, green: 210 / 255, blue: 120 / 255)

    var body: some View {
        LiveActivityShowcaseCard {
            VStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "timer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(timerTint)

                    Text(NSLocalizedString("autoRestTimer", comment: ""))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(timerTint)

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        pill(title: "\(NSLocalizedString("set", comment: "")) 3/4")
                        Text("2:30")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(timerTint)
                            .monospacedDigit()
                    }
                }

                Text("1:37")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(timerTint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("liveActivityContextLabelUpNext", comment: ""))
                        .font(.caption2.weight(.semibold))
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.white.opacity(0.72))
                        .textCase(.uppercase)
                        .padding(.leading, 12)

                    nextSetPill
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func pill(title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .fontDesign(.rounded)
            .foregroundStyle(Color.white.opacity(0.72))
            .textCase(.uppercase)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.07))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
            )
    }

    private var nextSetPill: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            Text("Incline Dumbbell Press")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 10)

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                unitChip(value: "10", unit: "REPS")
                unitChip(value: "32.5", unit: "KG")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.9)
                )
        )
    }

    private func unitChip(value: String, unit: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(Color.white.opacity(0.92))
            Text(unit)
                .font(.caption2.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(Color.white.opacity(0.68))
        }
    }
}

// MARK: - Current set card (normal mode — previous row + current weight)

private struct LiveActivityShowcaseCurrentSetCard: View {
    var body: some View {
        LiveActivityShowcaseCard {
            VStack(alignment: .leading, spacing: 14) {
                header

                Text("Incline Dumbbell Press")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                VStack(alignment: .leading, spacing: 0) {
                    previousPill
                    currentPill
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "dumbbell.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
                Text("Push Day")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                pill(title: "\(NSLocalizedString("set", comment: "")) 3/4")
                Text("22 min")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        }
    }

    private func pill(title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .fontDesign(.rounded)
            .foregroundStyle(Color.white.opacity(0.72))
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.07))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
            )
    }

    private var previousPill: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text(NSLocalizedString("liveActivitySetRowPrevious", comment: ""))
                .font(.caption2.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(Color.white.opacity(0.45))
                .textCase(.uppercase)

            Spacer(minLength: 10)

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                previousUnit(value: "9", unit: "reps")
                previousUnit(value: "30", unit: "kg")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .padding(.horizontal, 16)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 14,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 14,
                style: .continuous
            )
            .fill(Color.white.opacity(0.08))
        )
    }

    private var currentPill: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text(NSLocalizedString("liveActivitySetRowCurrent", comment: ""))
                .font(.caption2.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(Color.white.opacity(0.72))
                .textCase(.uppercase)

            Spacer(minLength: 10)

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                currentUnit(value: "10", unit: "REPS")
                currentUnit(value: "32.5", unit: "KG")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.9)
                )
        )
    }

    private func previousUnit(value: String, unit: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(Color.white.opacity(0.55))
            Text(unit)
                .font(.caption2.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(Color.white.opacity(0.45))
        }
    }

    private func currentUnit(value: String, unit: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(.white)
            Text(unit)
                .font(.subheadline.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(Color.white.opacity(0.72))
        }
    }
}

#Preview {
    LiveActivityShowcaseView()
}
