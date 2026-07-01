//
//  WorkoutGoalScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// The weekly-goal detail screen, reached from the Summary's Weekly Goal hero. Three stacked,
/// self-labeling tiles — no hero, no section headers:
///  1. a muscle-coloured month **calendar** where each workout day is an occurrence ring (arcs sized
///     by that day's muscle-group set counts) and the current week is lifted into a highlighted tile
///     carrying its progress;
///  2. a **streak comparison** — the current weekly streak racing toward the all-time record;
///  3. a year-navigable **52-week strip**, one cell per week (filled = on target), with prev/next year.
struct WorkoutGoalScreen: View {
    let workouts: [Workout]

    @AppStorage("workoutPerWeekTarget") private var target: Int = -1
    @EnvironmentObject private var muscleGroupService: MuscleGroupService

    @State private var displayedMonth: Date = .now.startOfMonth
    @State private var displayedYear: Int = Calendar.current.component(.year, from: .now)
    @State private var isShowingChangeGoalScreen = false

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                calendarTile
                streakTile
                yearTile
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(NSLocalizedString("workoutGoal", comment: ""))
                    .font(.headline)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingChangeGoalScreen = true
                } label: {
                    Image(systemName: "plusminus.circle")
                }
            }
        }
        .sheet(isPresented: $isShowingChangeGoalScreen) {
            NavigationStack {
                ChangeWeeklyWorkoutGoalScreen()
            }
        }
    }

    // MARK: - Calendar

    private var calendarTile: some View {
        VStack(spacing: 12) {
            HStack {
                Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(displayedMonth.startOfMonth >= Date.now.startOfMonth)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, CELL_PADDING)
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
                Image(systemName: "target")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 34)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, CELL_PADDING)
            ForEach(weeksOfMonth, id: \.self) { week in
                weekRowView(week)
            }
        }
        .padding(.top, CELL_PADDING)
        .padding(.bottom, CELL_PADDING / 2)
        .tileStyle()
    }

    @ViewBuilder
    private func weekRowView(_ week: [Date]) -> some View {
        if isCurrentWeek(week) {
            currentWeekRow(week)
        } else {
            // 8 equal columns (7 days + the completion ring), each centred in its own column, so the
            // ring isn't flush-right and the layout matches the shared `WeeklyGoalStrip` below.
            HStack(spacing: 0) {
                ForEach(week, id: \.self) { day in
                    dayCell(day)
                }
                weekRing(for: week)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, CELL_PADDING)
        }
    }

    /// The current week, lifted into a secondary tile that mirrors the Summary screen's
    /// `WeeklyGoalHeroTile` exactly — the shared `WeeklyGoalStrip` (muscle-ring days with weekday letters
    /// + the week's completion ring) and a `StreakLine`. Inset CELL_PADDING/2, like a set cell sits
    /// inside a set-group cell.
    private func currentWeekRow(_ week: [Date]) -> some View {
        let streak = SummaryViewModel.currentWeeklyStreak(workouts: workouts, target: target)
        return VStack(alignment: .leading, spacing: 14) {
            Text(NSLocalizedString("thisWeek", comment: ""))
                .tileHeaderStyle()
                .frame(maxWidth: .infinity, alignment: .leading)
            WeeklyGoalStrip(workouts: workouts, target: target, showsDate: true)
            if streak > 0 {
                StreakLine(streak: streak)
            }
        }
        // Horizontal stays CELL_PADDING/2 so the dates line up with the month grid; vertical gets a
        // touch more breathing room.
        .padding(.vertical, CELL_PADDING * 3 / 4)
        .padding(.horizontal, CELL_PADDING / 2)
        .secondaryTileStyle()
        .padding(.horizontal, CELL_PADDING / 2)
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)
        let isFuture = day > Date.now && !isToday
        let occurrences = muscleOccurrences(on: day)
        let hasWorkout = !occurrences.isEmpty
        return ZStack {
            if isToday {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.7)
                    .frame(width: 32, height: 32)
            } else if hasWorkout {
                MuscleOccurrenceRing(occurrences: occurrences, lineWidth: 4)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
            }
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 13, weight: (isToday || hasWorkout) ? .bold : .semibold))
                .foregroundStyle(dayForeground(inMonth: inMonth, isToday: isToday, isFuture: isFuture, hasWorkout: hasWorkout))
        }
        .frame(width: 34, height: 34)
        .frame(maxWidth: .infinity)
    }

    private func dayForeground(inMonth: Bool, isToday: Bool, isFuture: Bool, hasWorkout: Bool) -> Color {
        if isToday { return .accentColor }
        if hasWorkout { return .primary }
        if !inMonth { return Color.white.opacity(0.18) }
        if isFuture { return .tertiaryLabel }
        return .secondaryLabel
    }

    @ViewBuilder
    private func weekRing(for week: [Date]) -> some View {
        let count = workoutCount(inWeekOf: week.first ?? .now)
        let weekIsFuture = (week.first ?? .now).startOfWeek > Date.now
        if target > 0, count >= target {
            ZStack {
                Circle().fill(Color.accentColor)
                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.black)
            }
            .frame(width: 34, height: 34)
        } else if count > 0 {
            ZStack {
                CompletionRing(progress: Double(count) / Double(max(target, 1)), lineWidth: 3.5)
                Text("\(count)").font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor)
            }
            .frame(width: 34, height: 34)
        } else {
            Circle()
                .strokeBorder(Color.fill, lineWidth: 2)
                .frame(width: 34, height: 34)
                .opacity(weekIsFuture ? 0.6 : 1)
        }
    }

    // MARK: - Streak

    private var streakTile: some View {
        let current = SummaryViewModel.currentWeeklyStreak(workouts: workouts, target: target)
        let previousBest = SummaryViewModel.previousBestWeeklyStreak(workouts: workouts, target: target)
        let allTimeBest = max(previousBest, current)
        // Chase the next milestone by default (always a near goal ahead); the best steps in only when it's
        // the nearer goal — see StreakMilestone.target. A bigger past record beyond the milestone keeps its
        // own row below instead, so it's never lost.
        let goal = StreakMilestone.target(current: current, previousBest: previousBest)
        return VStack(alignment: .leading, spacing: 12) {
            StreakScoreboard(current: current, target: goal.value, targetIsBest: goal.isBest)
            milestoneList(current: current, best: allTimeBest, showBest: allTimeBest > current && !goal.isBest)
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }

    /// The next milestone on top, then the milestones already reached (newest first) — each in its own
    /// secondary tile with a flag, the date it was (or will be) hit, and a calendar-meaning fact.
    private func milestoneList(current: Int, best: Int, showBest: Bool) -> some View {
        let achieved = StreakMilestone.all.filter { $0 <= current }.sorted(by: >)
        return VStack(spacing: 8) {
            if showBest, best > 0 {
                personalBestTile(best)
            }
            ForEach(achieved, id: \.self) { milestone in
                achievedMilestoneTile(milestone: milestone, current: current)
            }
        }
    }

    /// The all-time best streak, kept in its own row with the flame that marks a record throughout the
    /// app. The comparison above now chases milestones rather than the record, so this is where the best
    /// stays visible — shown unless the best is already the goal being chased in the scoreboard.
    private func personalBestTile(_ best: Int) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.18))
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(NSLocalizedString("personalBest", comment: ""))
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.accentColor)
                UnitView(value: "\(best)", unit: weeksUnit(best), configuration: .small, unitColor: Color.secondaryLabel)
            }
            Spacer(minLength: 8)
        }
        .padding(CELL_PADDING - 2)
        .secondaryTileStyle()
    }

    private func achievedMilestoneTile(milestone: Int, current: Int) -> some View {
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
                UnitView(value: "\(milestone)", unit: weeksUnit(milestone), configuration: .small, unitColor: Color.secondaryLabel)
                if !fact.isEmpty {
                    Text(fact)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(shortDate(milestoneWeek(offset: milestone - current)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(CELL_PADDING - 2)
        .secondaryTileStyle()
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

    // MARK: - Year strip

    private var yearTile: some View {
        let weeks = weekStartsInYear(displayedYear)
        let counts = weeklyCounts(in: yearRange(displayedYear))
        let now = Date.now
        let nowYear = calendar.component(.year, from: now)
        // Percentage is over every week of the year that has already elapsed — future weeks
        // haven't happened yet, so they're excluded from both the count and the denominator.
        var onTarget = 0
        var elapsedWeeks = 0
        for ws in weeks where ws <= now {
            elapsedWeeks += 1
            if target > 0, (counts[ws] ?? 0) >= target { onTarget += 1 }
        }
        let percent = elapsedWeeks > 0 ? Int((Double(onTarget) / Double(elapsedWeeks) * 100).rounded()) : 0
        return VStack(spacing: 14) {
            HStack {
                Button { displayedYear -= 1 } label: { Image(systemName: "chevron.left") }
                    .disabled(displayedYear <= earliestYear)
                Spacer()
                Text(verbatim: "\(displayedYear)")
                    .font(.headline)
                Spacer()
                Button { displayedYear += 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(displayedYear >= nowYear)
            }
            .foregroundStyle(.secondary)
            VStack(spacing: 5) {
                HStack(spacing: 3) {
                    ForEach(weeks, id: \.self) { ws in
                        yearCell(ws, now: now, counts: counts)
                    }
                }
                if let currentIndex = currentWeekIndex(in: weeks, now: now) {
                    weekNumberRow(
                        weeks: weeks,
                        currentIndex: currentIndex,
                        weekNumber: calendar.component(.weekOfYear, from: now)
                    )
                }
            }
            HStack(spacing: 0) {
                ForEach(Array(calendar.veryShortMonthSymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack {
                Text(String(format: NSLocalizedString("yearWeeksOnTarget", comment: ""), onTarget, elapsedWeeks))
                Spacer()
                Text(verbatim: "\(percent)%")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5)
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }

    private func yearCell(_ ws: Date, now: Date, counts: [Date: Int]) -> some View {
        // Three clearly separated tiers: accent (target met) · solid gray (an elapsed week that
        // missed) · faint ghost (a future week that hasn't happened yet).
        let isFuture = ws > now
        let met = !isFuture && target > 0 && (counts[ws] ?? 0) >= target
        let fill: Color = met
            ? Color.accentColor
            : (isFuture ? Color.white.opacity(0.08) : Color.white.opacity(0.3))
        return RoundedRectangle(cornerRadius: 2)
            .fill(fill)
            .frame(height: 22)
            .frame(maxWidth: .infinity)
    }

    /// Index of the week cell containing today, or `nil` when the displayed year isn't the current one.
    private func currentWeekIndex(in weeks: [Date], now: Date) -> Int? {
        weeks.firstIndex { calendar.isDate($0, equalTo: now, toGranularity: .weekOfYear) }
    }

    /// A thin row beneath the strip carrying a white "Week N" label aligned under the current-week cell.
    /// Mirrors the strip's equal-width columns so the label sits directly under its tick; the text is
    /// drawn in a zero-impact overlay so a long label can overhang neighbouring (empty) columns.
    private func weekNumberRow(weeks: [Date], currentIndex: Int, weekNumber: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { index, _ in
                Color.clear
                    .frame(height: 13)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        if index == currentIndex {
                            Text(String(format: NSLocalizedString("currentWeekNumber", comment: ""), weekNumber))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .fixedSize()
                        }
                    }
            }
        }
    }

    // MARK: - Data

    private var currentWeekCount: Int {
        workouts.filter {
            guard !$0.isEmpty, let d = $0.date else { return false }
            return d >= Date.now.startOfWeek && d <= Date.now.endOfWeek
        }.count
    }

    private func weeklyCounts(in range: ClosedRange<Date>) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for workout in workouts where !workout.isEmpty {
            guard let date = workout.date, range.contains(date) else { continue }
            counts[date.startOfWeek, default: 0] += 1
        }
        return counts
    }

    private func workoutCount(inWeekOf day: Date) -> Int {
        let start = day.startOfWeek
        return workouts.filter {
            guard !$0.isEmpty, let d = $0.date else { return false }
            return d.startOfWeek == start
        }.count
    }

    private func muscleOccurrences(on day: Date) -> [(MuscleGroup, Int)] {
        let dayWorkouts = workouts.filter {
            guard !$0.isEmpty, let d = $0.date else { return false }
            return calendar.isDate(d, inSameDayAs: day)
        }
        guard !dayWorkouts.isEmpty else { return [] }
        return muscleGroupService.getMuscleGroupOccurances(in: dayWorkouts)
    }

    private func isCurrentWeek(_ week: [Date]) -> Bool {
        week.contains { calendar.isDateInToday($0) }
    }

    private var weeksOfMonth: [[Date]] {
        let monthEnd = displayedMonth.endOfMonth
        var weeks: [[Date]] = []
        var cursor = displayedMonth.startOfMonth.startOfWeek
        while cursor <= monthEnd, weeks.count < 6 {
            let week = (0 ..< 7).map { calendar.date(byAdding: .day, value: $0, to: cursor) ?? cursor }
            weeks.append(week)
            cursor = calendar.date(byAdding: .day, value: 7, to: cursor) ?? cursor
        }
        return weeks
    }

    /// Ordered week-start dates belonging to the given calendar year (52 or 53 of them).
    private func weekStartsInYear(_ year: Int) -> [Date] {
        guard let yearStart = calendar.date(from: DateComponents(year: year)),
              let nextYearStart = calendar.date(from: DateComponents(year: year + 1)) else { return [] }
        var weeks: [Date] = []
        var cursor = yearStart.startOfWeek
        while cursor < nextYearStart {
            weeks.append(cursor)
            cursor = (calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) ?? cursor).startOfWeek
        }
        return weeks
    }

    private func yearRange(_ year: Int) -> ClosedRange<Date> {
        let start = (calendar.date(from: DateComponents(year: year)) ?? .now).startOfWeek
        let nextStart = calendar.date(from: DateComponents(year: year + 1)) ?? .now
        let end = calendar.date(byAdding: .second, value: -1, to: nextStart) ?? nextStart
        return start ... max(end, start)
    }

    private var earliestYear: Int {
        let nowYear = calendar.component(.year, from: .now)
        guard let earliest = workouts.compactMap({ $0.date }).min() else { return nowYear }
        return min(calendar.component(.year, from: earliest), nowYear)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func changeMonth(_ delta: Int) {
        withAnimation {
            displayedMonth = (calendar.date(byAdding: .month, value: delta, to: displayedMonth) ?? displayedMonth).startOfMonth
        }
    }
}
