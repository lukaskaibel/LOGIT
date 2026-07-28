//
//  WeeklyGoalCountPill.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 28.07.26.
//

import SwiftUI

/// The Summary's weekly goal, reduced to a title-row control: a completion ring and the `2/4` fraction.
///
/// It replaces the weekly-goal hero tile. Once This Week and Progress became one scroll, the week
/// stopped being the screen's subject and became one fact among many — and a fact that already had a
/// whole screen behind it. A tile was too much furniture for that; a control on the title row is the
/// right size, and it puts the week where the eye already starts.
///
/// The count wears the label colour and the `/4` the secondary one: that split is what makes it read
/// as a *goal* rather than a score. Day-level muscle colours deliberately don't come along — those
/// are something you look at on purpose, and `WorkoutGoalScreen` renders them full size one tap away.
struct WeeklyGoalCountPill: View {
    let workouts: [Workout]
    /// Opens the goal screen — used whenever a target exists.
    let onOpen: () -> Void
    /// Opens the "pick a target" flow, used only while there is no goal to open.
    let onSetGoal: () -> Void

    @AppStorage("workoutPerWeekTarget") private var target: Int = -1

    private static let ringSize: CGFloat = 22
    private static let ringWidth: CGFloat = 3

    private var hasGoal: Bool { target > 0 }
    private var count: Int {
        let week = Date.now.startOfWeek ... Date.now.endOfWeek
        return workouts.filter { !$0.isEmpty && week.contains($0.date ?? .distantPast) }.count
    }

    private var isMet: Bool { hasGoal && count >= target }
    private var streak: Int { SummaryViewModel.currentWeeklyStreak(workouts: workouts, target: target) }
    /// Once the week is won the check already says so, so the text slot is spent on the streak — the
    /// one number that lost its home when the hero tile went away.
    private var showsStreak: Bool { isMet && streak >= 2 }

    var body: some View {
        Button {
            hasGoal ? onOpen() : onSetGoal()
        } label: {
            Group {
                if hasGoal {
                    HStack(spacing: 6) {
                        ring
                        label
                    }
                } else {
                    Text(NSLocalizedString("setGoal", comment: ""))
                        .font(.subheadline.weight(.semibold))
                }
            }
            // Collapsed inside the label, not on the Button: `.accessibilityElement(children: .ignore)`
            // applied to the Button replaces its element and drops the button trait with it, so
            // `app.buttons["weeklyGoalPill"]` finds nothing. Flattening the label instead leaves one
            // button element that reads as a sentence rather than "2", "/", "4".
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        }
        .contentShape(Capsule())
        .accessibilityIdentifier("weeklyGoalPill")
    }

    private var ring: some View {
        ZStack {
            // Clamped, so an over-delivered week can't wrap round and read as a fresh one.
            CompletionRing(
                progress: target > 0 ? min(Double(count) / Double(target), 1) : 0,
                lineWidth: Self.ringWidth,
                color: count > 0 ? .accentColor : .secondaryLabel
            )
            if isMet {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
    }

    @ViewBuilder
    private var label: some View {
        if showsStreak {
            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                    .font(.caption2.weight(.bold))
                Text("\(streak)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(Color.accentColor)
        } else {
            HStack(spacing: 0) {
                Text("\(count)")
                    // A zero week is a quiet nothing, not an accent-coloured one.
                    .foregroundStyle(count > 0 ? Color.label : Color.secondaryLabel)
                Text("/\(target)")
                    .foregroundStyle(Color.secondaryLabel)
            }
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
        }
    }

    private var accessibilityLabel: Text {
        guard hasGoal else { return Text(NSLocalizedString("setGoal", comment: "")) }
        let base = String(
            format: NSLocalizedString("weeklyGoalAccessibility", comment: ""),
            count, target
        )
        guard showsStreak else { return Text(base) }
        return Text(base + ", \(streak) " + NSLocalizedString("weekStreakSuffix", comment: ""))
    }
}
