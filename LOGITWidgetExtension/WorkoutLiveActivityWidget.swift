//
//  WorkoutLiveActivityWidget.swift
//  LOGITWidgetExtension
//
//  Created by Codex on 28.03.26.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutLiveActivityAttributes.self) { context in
            WorkoutLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(context.state.themeToken.accentColor)
            } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WorkoutElapsedTime(startedAt: context.attributes.startedAt)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.workoutTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WorkoutExerciseCard(state: context.state, dense: false)
                }
            } compactLeading: {
                WorkoutCompactDuration(startedAt: context.attributes.startedAt)
            } compactTrailing: {
                WorkoutCompactSetFraction(state: context.state)
            } minimal: {
                WorkoutMinimalBadge(startedAt: context.attributes.startedAt)
            }
            .keylineTint(context.state.themeToken.accentColor)
        }
    }
}

private struct WorkoutLiveActivityLockScreenView: View {
    let context: ActivityViewContext<WorkoutLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(context.state.workoutTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                WorkoutElapsedTime(startedAt: context.attributes.startedAt)
            }

            WorkoutExerciseCard(state: context.state, dense: false)
        }
        .padding(16)
        .background(context.state.themeToken.backgroundGradient, in: RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 999)
                .fill(context.state.themeToken.accentGradient)
                .frame(width: 78, height: 4)
                .padding(.top, 12)
                .padding(.leading, 16)
        }
        .padding(.horizontal, 4)
    }
}

private struct WorkoutExerciseCard: View {
    let state: WorkoutLiveActivityAttributes.ContentState
    let dense: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: dense ? 8 : 10) {
            Text(state.primaryExerciseName)
                .font(dense ? .headline.weight(.semibold) : .title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)

            if let secondaryExerciseName = state.secondaryExerciseName {
                Text(secondaryExerciseName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 8) {
                WorkoutMetricRow(
                    setFraction: state.setFractionLabel,
                    metrics: state.primaryMetrics,
                    accent: state.themeToken.accentColor,
                    dense: dense
                )

                if let secondaryExerciseName = state.secondaryExerciseName,
                   let secondaryMetrics = state.secondaryMetrics
                {
                    WorkoutMetricRow(
                        setFraction: nil,
                        metrics: secondaryMetrics,
                        accent: state.themeToken.secondaryAccentColor,
                        dense: dense
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkoutMetricRow: View {
    let setFraction: String?
    let metrics: ExerciseMetricDisplay
    let accent: Color
    let dense: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let setFraction {
                Text(setFraction)
                    .font((dense ? Font.caption2 : Font.caption).weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: dense ? 28 : 32, alignment: .leading)
            }

            HStack(spacing: 8) {
                if let repetitionsText = metrics.repetitionsText {
                    WorkoutMetricPill(text: repetitionsText, accent: accent)
                }
                if let weightText = metrics.weightText {
                    WorkoutMetricPill(text: weightText, accent: accent.opacity(0.75))
                }
            }
            .lineLimit(1)

            if metrics.isEmpty {
                Text(NSLocalizedString("addExercise", comment: ""))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct WorkoutMetricPill: View {
    let text: String
    let accent: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(accent.opacity(0.18), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(accent.opacity(0.45), lineWidth: 1)
            }
    }
}

private struct WorkoutElapsedTime: View {
    let startedAt: Date

    var body: some View {
        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
    }
}

private struct WorkoutCompactDuration: View {
    let startedAt: Date

    var body: some View {
        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
    }
}

private struct WorkoutCompactSetFraction: View {
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        Text(state.setFractionLabel ?? "—")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
    }
}

private struct WorkoutMinimalBadge: View {
    let startedAt: Date

    var body: some View {
        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
    }
}

private extension WorkoutLiveActivityThemeToken {
    var accentColor: Color {
        switch self {
        case .chest:
            Color(red: 160 / 255, green: 210 / 255, blue: 120 / 255)
        case .triceps:
            Color(red: 100 / 255, green: 200 / 255, blue: 1)
        case .shoulders:
            Color(red: 1, green: 170 / 255, blue: 100 / 255)
        case .biceps:
            Color(red: 64 / 255, green: 224 / 255, blue: 208 / 255)
        case .back:
            Color(red: 90 / 255, green: 150 / 255, blue: 200 / 255)
        case .legs:
            Color(red: 1, green: 112 / 255, blue: 100 / 255)
        case .abdominals:
            Color(red: 140 / 255, green: 120 / 255, blue: 200 / 255)
        case .cardio:
            Color(red: 180 / 255, green: 160 / 255, blue: 220 / 255)
        case .neutral:
            Color(red: 0.63, green: 0.68, blue: 0.76)
        }
    }

    var secondaryAccentColor: Color {
        accentColor.opacity(0.78)
    }

    var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentColor, accentColor.opacity(0.55)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.11, green: 0.12, blue: 0.15),
                Color(red: 0.06, green: 0.07, blue: 0.09),
                accentColor.opacity(0.18),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
