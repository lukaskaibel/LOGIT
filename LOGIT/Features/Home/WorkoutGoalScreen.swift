//
//  WorkoutGoalScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// The rich weekly-goal detail (`goal-screen-v2.html`): a goal-ring + streak hero, a "This Year" band
/// of 12 monthly completion rings, and a muscle-coloured month calendar where each workout day is
/// tinted by that day's dominant muscle group, with a per-week completion ring on the right edge.
/// Reached from the Summary's Weekly Goal hero. All rings are the shared `CompletionRing`.
struct WorkoutGoalScreen: View {
    let workouts: [Workout]

    @AppStorage("workoutPerWeekTarget") private var target: Int = -1
    @EnvironmentObject private var muscleGroupService: MuscleGroupService

    @State private var displayedMonth: Date = .now.startOfMonth

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                hero
                yearSection
                monthSection
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
        }
    }

    // MARK: - Hero

    private var hero: some View {
        let count = currentWeekCount
        let progress = target > 0 ? min(Double(count) / Double(target), 1) : 0
        let streak = SummaryViewModel.currentWeeklyStreak(workouts: workouts, target: target)
        let remaining = max(0, target - count)
        return HStack(spacing: 18) {
            CompletionRing(progress: progress, lineWidth: 9) {
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text("\(count)")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                    Text("/\(max(target, 0))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 7) {
                if streak > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("\(streak)")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                        Text(NSLocalizedString("weekStreakSuffix", comment: ""))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(remaining == 0
                    ? NSLocalizedString("weeklyGoalReached", comment: "")
                    : (remaining == 1
                        ? NSLocalizedString("weeklyGoalToGoOne", comment: "")
                        : String(format: NSLocalizedString("weeklyGoalToGoMany", comment: ""), remaining)))
                    .font(.subheadline.weight(.bold))
            }
            Spacer()
        }
        .padding(16)
        .tileStyle()
    }

    // MARK: - Year

    private var yearSection: some View {
        let counts = weeklyCounts(in: Date.now.startOfYear ... Date.now.endOfYear)
        let currentMonth = calendar.component(.month, from: .now)
        let year = calendar.component(.year, from: .now)
        var totalOnTarget = 0
        var totalWeeks = 0
        var best = 0
        var run = 0
        let orderedWeekStarts = counts.keys.sorted()
        for start in orderedWeekStarts where start <= Date.now {
            totalWeeks += 1
            if (counts[start] ?? 0) >= target, target > 0 {
                totalOnTarget += 1
                run += 1
                best = max(best, run)
            } else {
                run = 0
            }
        }
        return VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
            HStack {
                Text(NSLocalizedString("thisYear", comment: ""))
                    .sectionHeaderStyle2()
                Spacer()
                Text(verbatim: "\(year)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 16) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 14) {
                    ForEach(1 ... 12, id: \.self) { month in
                        monthRing(month: month, year: year, currentMonth: currentMonth, counts: counts)
                    }
                }
                HStack {
                    Text(String(format: NSLocalizedString("yearWeeksOnTarget", comment: ""), totalOnTarget, totalWeeks))
                    Spacer()
                    Text(String(format: NSLocalizedString("bestStreakLabel", comment: ""), best))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5)
                }
            }
            .padding(CELL_PADDING)
            .tileStyle()
        }
    }

    private func monthRing(month: Int, year: Int, currentMonth: Int, counts: [Date: Int]) -> some View {
        let monthStart = firstOfMonth(year: year, month: month)
        let weekStarts = self.weekStarts(in: monthStart)
        let onTarget = weekStarts.filter { (counts[$0] ?? 0) >= target && target > 0 }.count
        let progress = weekStarts.isEmpty ? 0 : Double(onTarget) / Double(weekStarts.count)
        let isFuture = month > currentMonth
        let isCurrent = month == currentMonth
        let complete = progress >= 1 && !weekStarts.isEmpty
        return VStack(spacing: 7) {
            ZStack {
                CompletionRing(
                    progress: isFuture ? 0 : progress,
                    lineWidth: 4,
                    trackColor: isFuture ? Color.secondaryBackground : Color.fill
                )
                .frame(width: 36, height: 36)
                .overlay {
                    if isCurrent {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                if complete {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            Text(monthAbbreviation(month))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
        }
    }

    // MARK: - Month calendar

    private var monthSection: some View {
        let monthWorkouts = workouts.filter {
            guard !$0.isEmpty, let d = $0.date else { return false }
            return d >= displayedMonth.startOfMonth && d <= displayedMonth.endOfMonth
        }
        return VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
            HStack {
                Text(displayedMonth.formatted(.dateTime.month(.wide)))
                    .sectionHeaderStyle2()
                Spacer()
                Text(String(format: NSLocalizedString("monthWorkoutsCount", comment: ""), monthWorkouts.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            calendarTile
        }
    }

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
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                Image(systemName: "target")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 34)
            }
            ForEach(weeksOfMonth, id: \.self) { week in
                HStack(spacing: 12) {
                    HStack(spacing: 0) {
                        ForEach(week, id: \.self) { day in
                            dayCell(day)
                        }
                    }
                    weekRing(for: week)
                }
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)
        let isFuture = day > Date.now && !isToday
        let muscleColor = dominantMuscleColor(on: day)
        return Text("\(calendar.component(.day, from: day))")
            .font(.system(size: 13, weight: muscleColor != nil ? .bold : .semibold))
            .foregroundStyle(dayForeground(inMonth: inMonth, isToday: isToday, isFuture: isFuture, tinted: muscleColor != nil))
            .frame(width: 34, height: 34)
            .background {
                if let muscleColor {
                    Circle().fill(muscleColor)
                } else if isToday {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 1.6)
                }
            }
            .frame(maxWidth: .infinity)
    }

    private func dayForeground(inMonth: Bool, isToday: Bool, isFuture: Bool, tinted: Bool) -> Color {
        if tinted { return .black }
        if isToday { return .accentColor }
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

    private func dominantMuscleColor(on day: Date) -> Color? {
        let dayWorkouts = workouts.filter {
            guard !$0.isEmpty, let d = $0.date else { return false }
            return calendar.isDate(d, inSameDayAs: day)
        }
        guard !dayWorkouts.isEmpty else { return nil }
        return muscleGroupService.getMuscleGroupOccurances(in: dayWorkouts).first?.0.color
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

    private func weekStarts(in monthStart: Date) -> [Date] {
        let days = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        var starts = Set<Date>()
        for offset in 0 ..< days {
            let date = calendar.date(byAdding: .day, value: offset, to: monthStart) ?? monthStart
            starts.insert(date.startOfWeek)
        }
        return starts.sorted()
    }

    private func firstOfMonth(year: Int, month: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return (calendar.date(from: components) ?? .now).startOfMonth
    }

    private func monthAbbreviation(_ month: Int) -> String {
        let symbols = calendar.shortMonthSymbols
        return month >= 1 && month <= symbols.count ? symbols[month - 1] : "\(month)"
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
