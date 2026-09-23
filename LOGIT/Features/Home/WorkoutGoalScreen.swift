//
//  WorkoutGoalScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// The weekly-goal detail screen, reached from the Summary's weekly-goal pill. One subject, read top
/// to bottom: a 240° arc carrying this week's count, the week itself as muscle-coloured day rings,
/// then the streak drawn as a chain with its milestones on it.
///
/// The month calendar and the 52-week year grid that used to open this screen are gone — History
/// already renders a ring calendar, and a year grid is that same calendar in another costume.
///
/// The streak and its milestones used to be a lone streak row over a separate "Milestones" list, and
/// a tester couldn't tell what a milestone was or what it had to do with the streak. Now the running
/// count sits in the section header, and the milestones form one chain under it: the one being
/// chased on top, then every mark this streak has reached — milestones, and the week it became a new
/// record — down to its first week, joined by one line. A milestone reads as what it is, a length
/// the streak reaches.
///
/// The goal reads as the nav bar's subtitle ("4 workouts a week") and changes from the slider button
/// beside it — the same pair the Muscle Groups screen uses for its focus. It used to sit in the arc as
/// a tappable "of your 4-workout goal ›" line, which testers didn't read as a button and which
/// crowded the count. An About section at the foot explains the goal, the streak and the milestones.
struct WorkoutGoalScreen: View {
    let workouts: [Workout]

    @AppStorage("workoutPerWeekTarget") private var target: Int = -1

    @State private var isShowingChangeGoalScreen = false

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                arcHero
                    .padding(.top, 24)
                if hasGoal {
                    WeeklyGoalStrip(workouts: workouts, target: target, showsCompletionRing: false)
                        .padding(.top, 36)
                    streakSection
                        .padding(.top, 36)
                    AboutSection(
                        metricTitle: NSLocalizedString("workoutGoal", comment: ""),
                        text: NSLocalizedString("workoutGoalAboutInfo", comment: "")
                    )
                    .padding(.top, SECTION_SPACING + 10)
                } else {
                    setGoalButton
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .navigationTitle(NSLocalizedString("workoutGoal", comment: ""))
        .navigationSubtitle(goalSubtitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingChangeGoalScreen = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel(Text(NSLocalizedString(hasGoal ? "changeGoal" : "setGoal", comment: "")))
                .accessibilityIdentifier("weeklyGoalTargetButton")
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
            }
            // The arc opens at the bottom, so its ink sits high in the square box; lifting the block
            // centres it on the arc rather than on the box.
            .padding(.bottom, 24)
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

    /// Only reachable if something pushes this screen without a goal set — the Summary's pill opens
    /// the picker directly in that case. Cheap to keep honest rather than render "0 workouts a week".
    private var setGoalButton: some View {
        Button {
            isShowingChangeGoalScreen = true
        } label: {
            Label(NSLocalizedString("setGoal", comment: ""), systemImage: "target")
        }
        .buttonStyle(PrimaryButtonStyle())
        .frame(maxWidth: .infinity)
    }

    // MARK: - Streak chain

    /// The header carries the running streak at its trailing end, so the chain below holds nothing
    /// but lengths the streak reaches. Top to bottom: the flag being chased — the next milestone, or
    /// the personal best when that is the nearer goal (`StreakMilestone.target`) — then, once a streak
    /// is running, every mark it has reached, newest first, down to its first week (itself a
    /// milestone, so the chain always ends on a flag). The line is dashed out of the flag being chased
    /// (weeks still to come) and solid below (weeks won).
    ///
    /// The streak used to be a row of its own inside the chain, and read as one more milestone.
    private var streakSection: some View {
        let goal = StreakMilestone.target(current: streak, previousBest: previousBest)
        let marks = reachedMarks
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("streak", comment: ""))
                    .tileHeaderStyle()
                Spacer(minLength: 8)
                streakCount
            }
            VStack(alignment: .leading, spacing: 0) {
                nextMilestoneRow(goal: goal)
                ForEach(Array(marks.enumerated()), id: \.element.weeks) { index, mark in
                    chainLink(isWon: index > 0)
                    reachedRow(mark)
                }
            }
        }
    }

    private var streakCount: some View {
        UnitView(
            value: "\(streak)",
            unit: weeksUnit(streak),
            configuration: .normal,
            unitColor: Color.secondaryLabel
        )
        .monospacedDigit()
        .foregroundStyle(streak > 0 ? Color.accentColor : Color.secondaryLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(streak) \(NSLocalizedString("weekStreakSuffix", comment: ""))"))
    }

    /// Every row keeps its icon in a column this wide at the same inset, so the links between the rows
    /// line up into one line through the icons' centres.
    private static let iconColumnWidth: CGFloat = 38
    private static let rowPadding: CGFloat = CELL_PADDING - 2
    private static let linkHeight: CGFloat = 14

    /// The piece of line in the gap between two rows.
    private func chainLink(isWon: Bool) -> some View {
        linkStroke(isWon: isWon)
            .frame(width: 2, height: Self.linkHeight)
            .padding(.leading, Self.rowPadding + Self.iconColumnWidth / 2 - 1)
            .accessibilityHidden(true)
    }

    /// Solid accent where the weeks are won; dashed where they're still to come.
    @ViewBuilder
    private func linkStroke(isWon: Bool) -> some View {
        if isWon {
            ChainLine().stroke(Color.accentColor, lineWidth: 2)
        } else {
            ChainLine().stroke(Color.fill, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
        }
    }

    private func nextMilestoneRow(goal: (value: Int, isBest: Bool)) -> some View {
        let fact = goal.isBest ? "" : StreakMilestone.fact(for: goal.value, isFirstStreak: previousBest == 0)
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
            .frame(width: Self.iconColumnWidth, height: Self.iconColumnWidth)
            VStack(alignment: .leading, spacing: 1) {
                Text(NSLocalizedString(goal.isBest ? "beatYourBest" : "nextMilestone", comment: ""))
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
        .padding(Self.rowPadding)
        // Dashed rather than filled: this flag isn't planted yet. The radius matches
        // `secondaryTileStyle` so it lines up with the filled rows below it.
        .overlay {
            RoundedRectangle(cornerRadius: 25)
                .strokeBorder(Color.fill, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        }
        .accessibilityElement(children: .combine)
    }

    private func reachedRow(_ mark: ReachedMark) -> some View {
        let fact = mark.isMilestone ? StreakMilestone.fact(for: mark.weeks, isFirstStreak: previousBest == 0) : ""
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor)
                // The flame for a record, as the personal-best goal wears it while it's still ahead.
                Image(systemName: mark.isRecord ? "flame.fill" : "flag.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
            }
            .frame(width: 30, height: 30)
            .frame(width: Self.iconColumnWidth)
            VStack(alignment: .leading, spacing: 1) {
                if mark.isRecord {
                    Text(NSLocalizedString("newRecord", comment: ""))
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.accentColor)
                }
                UnitView(
                    value: "\(mark.weeks)",
                    unit: weeksUnit(mark.weeks),
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
            Text(shortDate(streakWeek(mark.weeks)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(Self.rowPadding)
        .secondaryTileStyle()
        .accessibilityElement(children: .combine)
    }

    /// The first day of the streak's `n`th week (1 = the week it started). The streak's last week is
    /// this one only once it's met; until then the run ends last week (`weeklyStreak` neither counts
    /// nor breaks on an unmet current week), so the count runs one week further back.
    private func streakWeek(_ n: Int) -> Date {
        let offset = n - streak - (isMet ? 0 : 1)
        return calendar.date(byAdding: .weekOfYear, value: offset, to: Date.now.startOfWeek) ?? .now
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

    private var goalSubtitle: String {
        guard hasGoal else { return "" }
        return target == 1
            ? NSLocalizedString("workoutGoalPerWeekOne", comment: "")
            : String(format: NSLocalizedString("workoutGoalPerWeek", comment: ""), target)
    }

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

    /// The streak length at which this streak passed the previous best: nil until it has, and nil
    /// when there was no earlier streak to beat — a first streak is trivially the longest, and a
    /// "record" at week one would be noise.
    private var recordWeek: Int? {
        let best = previousBest
        guard best > 0, streak > best else { return nil }
        return best + 1
    }

    /// Everything on the solid part of the chain, newest first: the milestones this streak has
    /// reached plus the week it became the longest ever. A record that lands on a milestone's week
    /// shares that row rather than doubling it.
    private var reachedMarks: [ReachedMark] {
        let record = recordWeek
        var weeks = Set(StreakMilestone.all.filter { $0 <= streak })
        if let record { weeks.insert(record) }
        return weeks.sorted(by: >).map { weeks in
            ReachedMark(
                weeks: weeks,
                isMilestone: StreakMilestone.all.contains(weeks),
                isRecord: weeks == record
            )
        }
    }

    private var goalAccessibilityLabel: Text {
        Text(String(format: NSLocalizedString("weeklyGoalAccessibility", comment: ""), count, target))
    }
}

/// A streak length on the chain's solid part: a milestone, the week the streak beat the previous best,
/// or both at once.
private struct ReachedMark {
    let weeks: Int
    let isMilestone: Bool
    let isRecord: Bool
}

/// A vertical line down the middle of its frame — one piece of the streak chain.
private struct ChainLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
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
