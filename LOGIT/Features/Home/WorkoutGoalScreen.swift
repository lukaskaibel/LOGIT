//
//  WorkoutGoalScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// The weekly-goal detail screen, reached from the Summary's weekly-goal pill. One subject, read top
/// to bottom: a 240° arc carrying this week's count, the week itself as muscle-coloured day rings,
/// then a hairline, the streak as a single row, and the milestone ladder the streak is climbing.
///
/// The month calendar and the 52-week year grid that used to open this screen are gone — History
/// already renders a ring calendar, and a year grid is that same calendar in another costume. The
/// milestones stay: the one being chased leads the list, carrying the progress ring the old streak
/// scoreboard wore, and the flags already planted sit underneath it, newest first.
///
/// The goal itself moved out of the toolbar and into the sentence under the count ("of your
/// 4-workout goal ›"), the way Books puts a reading goal under the day's minutes.
struct WorkoutGoalScreen: View {
    let workouts: [Workout]

    @AppStorage("workoutPerWeekTarget") private var target: Int = -1

    @State private var isShowingChangeGoalScreen = false

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                arcHero
                if hasGoal {
                    WeeklyGoalStrip(workouts: workouts, target: target, showsCompletionRing: false)
                        .padding(.top, 20)
                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 0.5)
                        .padding(.top, 24)
                    streakRow
                        .padding(.top, 20)
                    milestoneSection
                        .padding(.top, 26)
                } else {
                    setGoalButton
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(NSLocalizedString("workoutGoal", comment: ""))
                    .font(.headline)
            }
        }
        .sheet(isPresented: $isShowingChangeGoalScreen) {
            NavigationStack {
                ChangeWeeklyWorkoutGoalScreen()
            }
        }
    }

    // MARK: - Hero

    private var arcHero: some View {
        ZStack {
            WeeklyGoalArc(progress: progress, lineWidth: Self.arcLineWidth)
                .frame(width: Self.arcSize, height: Self.arcSize)
                .accessibilityHidden(true)
            VStack(spacing: 2) {
                Text(NSLocalizedString("thisWeek", comment: ""))
                    .font(.system(size: 10, weight: .heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(count > 0 ? Color.accentColor : Color.secondaryLabel)
                countLabel
                if hasGoal {
                    goalButton
                }
            }
            // The arc opens at the bottom, so the block sits a touch high inside it — that keeps the
            // goal line clear of the two arc ends rather than wedged between them.
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        // Reclaim the empty band under the arc's ends, or the strip floats away from the gauge.
        .padding(.bottom, -WeeklyGoalArc<EmptyView>.bottomInset(size: Self.arcSize, lineWidth: Self.arcLineWidth))
    }

    private static let arcSize: CGFloat = 250
    private static let arcLineWidth: CGFloat = 14

    /// Once the week is won the count has said all it can, so the check takes its place — the same
    /// swap the week rings make. Overshoot keeps reading as met; the day rings below carry the extras.
    @ViewBuilder
    private var countLabel: some View {
        if isMet {
            Image(systemName: "checkmark")
                .font(.system(size: 70, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .frame(height: 84)
                .accessibilityHidden(true)
        } else {
            Text("\(count)")
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(count > 0 ? Color.label : Color.secondaryLabel)
                .frame(height: 84)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(goalAccessibilityLabel)
        }
    }

    private var goalButton: some View {
        Button {
            isShowingChangeGoalScreen = true
        } label: {
            HStack(spacing: 3) {
                Text(String(format: NSLocalizedString("weeklyGoalSubtitle", comment: ""), target))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityLabel(NSLocalizedString("changeGoal", comment: ""))
        .accessibilityIdentifier("weeklyGoalTargetButton")
    }

    /// Only reachable if something pushes this screen without a goal set — the Summary's pill opens
    /// the picker directly in that case. Cheap to keep honest rather than render "of your 0-workout goal".
    private var setGoalButton: some View {
        Button {
            isShowingChangeGoalScreen = true
        } label: {
            Label(NSLocalizedString("setGoal", comment: ""), systemImage: "target")
        }
        .buttonStyle(PrimaryButtonStyle())
        .frame(maxWidth: .infinity)
    }

    // MARK: - Streak

    private var streakRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .foregroundStyle(streak > 0 ? Color.accentColor : Color.secondaryLabel)
            Text("\(streak)")
                .font(.title2.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(streak > 0 ? Color.accentColor : Color.secondaryLabel)
            Text(NSLocalizedString("weekStreakSuffix", comment: ""))
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if isRecordStreak {
                Text(NSLocalizedString("newRecord", comment: ""))
                    .font(.caption.weight(.heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Milestones

    /// The ladder: the flag being chased on top — the next milestone, or the personal best when that
    /// is the nearer goal (`StreakMilestone.target`) — then every milestone already reached, newest
    /// first. The top row is the only one that moves week to week, so it is the one wearing the ring.
    private var milestoneSection: some View {
        let goal = StreakMilestone.target(current: streak, previousBest: previousBest)
        let achieved = StreakMilestone.all.filter { $0 <= streak }.sorted(by: >)
        return VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("milestones", comment: ""))
                .tileHeaderStyle()
            VStack(spacing: 8) {
                nextMilestoneRow(goal: goal)
                ForEach(achieved, id: \.self) { milestone in
                    achievedMilestoneRow(milestone)
                }
            }
        }
    }

    private func nextMilestoneRow(goal: (value: Int, isBest: Bool)) -> some View {
        let fact = goal.isBest ? "" : StreakMilestone.fact(for: goal.value)
        let remaining = max(goal.value - streak, 0)
        return HStack(spacing: 12) {
            ZStack {
                CompletionRing(
                    progress: goal.value > 0 ? Double(streak) / Double(goal.value) : 0,
                    lineWidth: 3
                )
                Image(systemName: goal.isBest ? "flame.fill" : "flag")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(NSLocalizedString(goal.isBest ? "personalBest" : "nextMilestone", comment: ""))
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.accentColor)
                UnitView(
                    value: "\(goal.value)",
                    unit: weeksUnit(goal.value),
                    configuration: .small,
                    unitColor: Color.secondaryLabel
                )
                if !fact.isEmpty {
                    Text(fact)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(String(format: NSLocalizedString("weeksToGo", comment: ""), remaining))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(CELL_PADDING - 2)
        // Dashed rather than filled: this flag isn't planted yet. The radius matches
        // `secondaryTileStyle` so it lines up with the achieved rows below it.
        .overlay {
            RoundedRectangle(cornerRadius: 25)
                .strokeBorder(Color.fill, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        }
        .accessibilityElement(children: .combine)
    }

    private func achievedMilestoneRow(_ milestone: Int) -> some View {
        let fact = StreakMilestone.fact(for: milestone)
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor)
                Image(systemName: "flag.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                UnitView(
                    value: "\(milestone)",
                    unit: weeksUnit(milestone),
                    configuration: .small,
                    unitColor: Color.secondaryLabel
                )
                if !fact.isEmpty {
                    Text(fact)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(shortDate(milestoneWeek(offset: milestone - streak)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(CELL_PADDING - 2)
        .secondaryTileStyle()
        .accessibilityElement(children: .combine)
    }

    private func milestoneWeek(offset: Int) -> Date {
        calendar.date(byAdding: .weekOfYear, value: offset, to: Date.now.startOfWeek) ?? .now
    }

    private func shortDate(_ date: Date) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: .now)
        return sameYear
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func weeksUnit(_ n: Int) -> String {
        NSLocalizedString(n == 1 ? "week" : "weeks", comment: "")
    }

    // MARK: - Data

    private var hasGoal: Bool { target > 0 }

    private var count: Int {
        let week = Date.now.startOfWeek ... Date.now.endOfWeek
        return workouts.filter { !$0.isEmpty && week.contains($0.date ?? .distantPast) }.count
    }

    private var isMet: Bool { hasGoal && count >= target }

    /// Clamped, so an over-delivered week can't wrap the arc round and read as a fresh one.
    private var progress: Double {
        hasGoal ? min(Double(count) / Double(target), 1) : 0
    }

    private var streak: Int {
        SummaryViewModel.currentWeeklyStreak(workouts: workouts, target: target)
    }

    private var previousBest: Int {
        SummaryViewModel.previousBestWeeklyStreak(workouts: workouts, target: target)
    }

    /// A run that has passed everything before it. Held to two weeks so the very first won week
    /// doesn't announce itself as a record.
    private var isRecordStreak: Bool { streak >= 2 && streak > previousBest }

    private var goalAccessibilityLabel: Text {
        Text(String(format: NSLocalizedString("weeklyGoalAccessibility", comment: ""), count, target))
    }
}

#Preview {
    FetchRequestWrapper(Workout.self) { workouts in
        NavigationStack {
            WorkoutGoalScreen(workouts: workouts)
        }
        .previewEnvironmentObjects()
    }
}
