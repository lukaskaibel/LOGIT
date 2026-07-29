//
//  WeeklyGoalCountPill.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 28.07.26.
//

import SwiftUI

/// The Summary's weekly goal, reduced to a title-row control: the week's count inside a completion
/// ring.
///
/// It replaces the weekly-goal hero tile. Once This Week and Progress became one scroll, the week
/// stopped being the screen's subject and became one fact among many — and a fact that already had a
/// whole screen behind it. A tile was too much furniture for that; a control on the title row is the
/// right size, and it puts the week where the eye already starts.
///
/// The target is no longer spelled out: the ring *is* the target, so `3` inside a nearly closed ring
/// says everything `3/4` did in half the width. VoiceOver still hears the full fraction. Day-level
/// muscle colours deliberately don't come along — those are something you look at on purpose, and
/// `WorkoutGoalScreen` renders them full size one tap away.
struct WeeklyGoalCountPill: View {
    let workouts: [Workout]
    /// Opens the goal screen — used whenever a target exists.
    let onOpen: () -> Void
    /// Opens the "pick a target" flow, used only while there is no goal to open.
    let onSetGoal: () -> Void

    @AppStorage("workoutPerWeekTarget") private var target: Int = -1

    private static let ringSize: CGFloat = 28
    private static let ringWidth: CGFloat = 3
    /// A zero week still gets a mark: trimmed this short and drawn with round caps, the arc renders as
    /// a single dot at twelve o'clock. It reads as where the ring *starts*, not as progress — one
    /// workout would already sweep a quarter of the circle at the usual targets — and it keeps the
    /// control from looking switched off on the one day of the week it matters most.
    private static let minimumArc: Double = 0.005

    private var hasGoal: Bool { target > 0 }
    private var count: Int {
        let week = Date.now.startOfWeek ... Date.now.endOfWeek
        return workouts.filter { !$0.isEmpty && week.contains($0.date ?? .distantPast) }.count
    }

    private var isMet: Bool { hasGoal && count >= target }
    private var streak: Int { SummaryViewModel.currentWeeklyStreak(workouts: workouts, target: target) }
    /// Once the week is won the closed ring already says so, so the pill grows a text slot for the
    /// streak — the one number that lost its home when the hero tile went away.
    private var showsStreak: Bool { isMet && streak >= 2 }

    var body: some View {
        Button {
            hasGoal ? onOpen() : onSetGoal()
        } label: {
            Group {
                if hasGoal {
                    HStack(spacing: 6) {
                        ring
                        if showsStreak { streakLabel }
                    }
                } else {
                    Text(NSLocalizedString("setGoal", comment: ""))
                        .font(.body.weight(.semibold))
                }
            }
            // The style's own vertical padding is roughly half its horizontal one, which reads as a
            // squat pill around content this tall. The extra 5 pt evens the inset out on both axes.
            .padding(.vertical, 5)
            // Collapsed inside the label, not on the Button: `.accessibilityElement(children: .ignore)`
            // applied to the Button replaces its element and drops the button trait with it, so
            // `app.buttons["weeklyGoalPill"]` finds nothing. Flattening the label instead leaves one
            // button element that reads as a sentence rather than a bare "2".
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        }
        // Liquid glass, so the control reads as a control: the pill sits on the same scroll surface as
        // the tiles below it, and without a material of its own it looked like loose text that happened
        // to be tappable. Clear rather than regular, because it sits over the muscle wash at the top of
        // the screen and should let that colour through instead of frosting it. `.glass` also gives it
        // the standard press feedback for free.
        .buttonStyle(.glass(.clear))
        .accessibilityIdentifier("weeklyGoalPill")
    }

    /// The count sits in the ring's middle rather than beside it: the ring already carries the target,
    /// so the two belong to one mark. No checkmark for a met week — a closed ring says that, and the
    /// number keeps saying something the clamped arc can't, namely that five workouts beat a four.
    private var ring: some View {
        CompletionRing(
            // Clamped, so an over-delivered week can't wrap round and read as a fresh one, and floored
            // so a fresh week still shows its starting dot.
            progress: max(target > 0 ? min(Double(count) / Double(target), 1) : 0, Self.minimumArc),
            lineWidth: Self.ringWidth,
            color: .accentColor
        ) {
            Text("\(count)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
    }

    private var streakLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.caption.weight(.bold))
            Text("\(streak)")
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(Color.accentColor)
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
