//
//  WorkoutListScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.12.21.
//

import CoreData
import SwiftUI

struct WorkoutListScreen: View {
    // MARK: - Environment

    @EnvironmentObject private var database: Database

    // MARK: - State

    @State private var searchedText: String = ""
    @State private var filter = WorkoutFilter()
    @State private var isShowingAddWorkout = false
    @State private var isShowingFilters = false
    @State private var selectedWorkout: Workout?
    /// The day tapped in the calendar header — rings it and is scrolled to. Purely a scrubbing aid.
    @State private var selectedDay: Date?
    /// Object IDs of the fetched workouts that set at least one personal record, filled lazily while
    /// the "personal records only" filter is on (nil = not computed yet, so the list waits).
    @State private var personalRecordWorkoutIDs: Set<NSManagedObjectID>?

    // MARK: - Body

    var body: some View {
        FetchRequestWrapper(
            Workout.self,
            sortDescriptors: [SortDescriptor(\Workout.date, order: .reverse)],
            predicate: workoutPredicate
        ) { allWorkouts in
            let searched = FuzzySearchService.shared.searchWorkouts(searchedText, in: allWorkouts)
            let isSearching = !searchedText.isEmpty
            let displayed = displayedWorkouts(from: searched)
            let isComputingPRs = filter.prsOnly && personalRecordWorkoutIDs == nil

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: SECTION_SPACING) {
                        if isSearching {
                            // Flat list when searching - results ordered by relevance
                            workoutList(displayed)
                        } else if isComputingPRs {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                        } else {
                            if !displayed.isEmpty {
                                HistoryCalendarView(workouts: displayed, selectedDay: $selectedDay) { day in
                                    jump(to: day, in: displayed, proxy: proxy)
                                }
                                .padding(.horizontal)
                            }
                            ForEach(historySections(for: displayed)) { section in
                                WorkoutHistorySectionView(
                                    title: section.title,
                                    workouts: section.workouts,
                                    selectedWorkout: $selectedWorkout
                                )
                            }
                        }
                        EmptyView()
                            .emptyPlaceholder(displayed) {
                                Text(NSLocalizedString("noWorkouts", comment: ""))
                            }
                    }
                    .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
                }
                .task(id: PersonalRecordFilterKey(on: filter.prsOnly, ids: searched.map { $0.objectID })) {
                    guard filter.prsOnly else { personalRecordWorkoutIDs = nil; return }
                    var ids = Set<NSManagedObjectID>()
                    for workout in searched
                    where WorkoutProgressReport.compute(for: workout, database: database).prRecords.count > 0 {
                        ids.insert(workout.objectID)
                    }
                    personalRecordWorkoutIDs = ids
                }
            }
            .searchable(
                text: $searchedText,
                prompt: NSLocalizedString("searchWorkouts", comment: "")
            )
            .navigationTitle(NSLocalizedString("workoutHistory", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingFilters = true
                    } label: {
                        Image(systemName: filter.isActive
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        isShowingAddWorkout = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingFilters) {
                WorkoutFilterSheet(filter: $filter)
            }
            .sheet(isPresented: $isShowingAddWorkout) {
                WorkoutEditorScreen(workout: database.newWorkout(), isAddingNewWorkout: true)
            }
        }
        .navigationDestination(item: $selectedWorkout) { workout in
            WorkoutDetailScreen(workout: workout, canNavigateToTemplate: true)
        }
    }

    // MARK: - List

    private func workoutList(_ workouts: [Workout]) -> some View {
        VStack(spacing: 8) {
            ForEach(workouts) { workout in
                Button {
                    selectedWorkout = workout
                } label: {
                    WorkoutCell(workout: workout)
                }
                .buttonStyle(TileButtonStyle())
                .id(workout.objectID)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Filtering

    /// The fetch predicate for the muscle-group and template filters (search and the PR filter are
    /// applied in memory). The factory always returns at least the "exclude current workout" clause.
    private var workoutPredicate: NSPredicate? {
        var subpredicates = [NSPredicate]()
        if let base = WorkoutPredicateFactory.getWorkouts(nameIncluding: "", withMuscleGroup: filter.muscleGroup) {
            subpredicates.append(base)
        }
        if filter.fromTemplate {
            subpredicates.append(NSPredicate(format: "template != nil"))
        }
        return subpredicates.isEmpty ? nil : NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
    }

    private func displayedWorkouts(from workouts: [Workout]) -> [Workout] {
        guard filter.prsOnly, let ids = personalRecordWorkoutIDs else { return workouts }
        return workouts.filter { ids.contains($0.objectID) }
    }

    /// Scrolls the list to the workout on the tapped calendar day and rings that day. A scrubber —
    /// the list itself is never filtered by the tap.
    private func jump(to day: Date, in workouts: [Workout], proxy: ScrollViewProxy) {
        guard let target = workouts.first(where: {
            guard let date = $0.date else { return false }
            return Calendar.current.isDate(date, inSameDayAs: day)
        }) else { return }
        selectedDay = day
        withAnimation {
            proxy.scrollTo(target.objectID, anchor: .top)
        }
    }

    // MARK: - Grouping

    /// One dated group in the history list: the current and previous week broken out relative-style,
    /// then everything older grouped by calendar month.
    private struct HistorySection: Identifiable {
        let id: String
        let title: String
        let workouts: [Workout]
    }

    /// Splits the (date-descending) workouts into This Week, Last Week, then month groups. The weeks
    /// win the overlap: a workout in the current or previous week is never also listed under its
    /// month, so a month near the top only holds what its earlier days contributed. Empty weeks are
    /// dropped, like empty months, so the list never opens on a blank "This Week".
    private func historySections(for workouts: [Workout]) -> [HistorySection] {
        let calendar = Calendar.current
        let thisWeekStart = Date.now.startOfWeek
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) ?? thisWeekStart

        var thisWeek: [Workout] = []
        var lastWeek: [Workout] = []
        var older: [Workout] = []
        for workout in workouts {
            guard let date = workout.date else { older.append(workout); continue }
            if date >= thisWeekStart {
                thisWeek.append(workout)
            } else if date >= lastWeekStart {
                lastWeek.append(workout)
            } else {
                older.append(workout)
            }
        }

        var sections: [HistorySection] = []
        if !thisWeek.isEmpty {
            sections.append(HistorySection(id: "thisWeek", title: thisWeekStart.weekDescription, workouts: thisWeek))
        }
        if !lastWeek.isEmpty {
            sections.append(HistorySection(id: "lastWeek", title: lastWeekStart.weekDescription, workouts: lastWeek))
        }
        let byMonth = Dictionary(grouping: older) { ($0.date ?? .now).startOfMonth }
            .sorted { $0.key > $1.key }
        for (monthStart, monthWorkouts) in byMonth {
            sections.append(
                HistorySection(
                    id: "month-\(monthStart.timeIntervalSinceReferenceDate)",
                    title: monthStart.monthDescription,
                    workouts: monthWorkouts
                )
            )
        }
        return sections
    }
}

// MARK: - Filter model

/// The History list's filters. Muscle group and template origin narrow the fetch; personal-records
/// is judged in memory. `isActive` drives the filled toolbar icon.
private struct WorkoutFilter: Equatable {
    var muscleGroup: MuscleGroup?
    var prsOnly = false
    var fromTemplate = false

    var isActive: Bool { muscleGroup != nil || prsOnly || fromTemplate }
}

/// Task identity for the personal-records computation: recompute when the toggle flips or the fetched
/// set changes, and carry no ids while the filter is off so the work never runs then.
private struct PersonalRecordFilterKey: Equatable {
    let on: Bool
    let ids: [NSManagedObjectID]
}

// MARK: - History section

/// A single dated group in the history list — a relative week ("This Week", "Last Week") or a
/// calendar month — headed by its name and a one-line recap of the workouts inside it: how many,
/// their combined volume, and how many personal records they set. The recap mirrors the cell's own
/// "date · duration · PR" grammar so the header and the rows read the same way. The cells below are
/// unchanged.
private struct WorkoutHistorySectionView: View {
    @EnvironmentObject private var database: Database

    let title: String
    let workouts: [Workout]
    @Binding var selectedWorkout: Workout?

    /// Personal records across the whole section, summed from the same per-workout report the cells
    /// use so the header can never disagree with the "n PR" on the rows. Filled in `.task` rather
    /// than `body`, because the report scans each exercise's full history — running it for every
    /// section on every scroll would be far too heavy — and only for sections that actually appear.
    @State private var personalRecordCount: Int = 0

    var body: some View {
        VStack(spacing: SECTION_HEADER_SPACING) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .sectionHeaderStyle2()
                Text(statLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 8) {
                ForEach(workouts) { workout in
                    Button {
                        selectedWorkout = workout
                    } label: {
                        WorkoutCell(workout: workout)
                    }
                    .buttonStyle(TileButtonStyle())
                    .id(workout.objectID)
                }
            }
        }
        .padding(.horizontal)
        .task(id: workouts.map { $0.objectID }) {
            personalRecordCount = workouts.reduce(0) { partial, workout in
                partial + WorkoutProgressReport.compute(for: workout, database: database).prRecords.count
            }
        }
    }

    /// "3 workouts · 22k kg · 2 PR" — count always, then volume and PRs only when they have
    /// something to show, joined the way the cell joins its own metadata.
    private var statLine: String {
        var parts: [String] = []

        let countFormat = NSLocalizedString(
            workouts.count == 1 ? "monthWorkoutCount" : "monthWorkoutsCount",
            comment: ""
        )
        parts.append(String(format: countFormat, workouts.count))

        let volume = convertWeightForDisplaying(getVolume(of: workouts.flatMap { $0.sets }))
        if volume > 0 {
            parts.append("\(abbreviatedVolume(volume)) \(WeightUnit.used.rawValue)")
        }

        if personalRecordCount > 0 {
            let prFormat = NSLocalizedString(
                personalRecordCount == 1 ? "personalRecordShortCount" : "personalRecordsShortCount",
                comment: ""
            )
            parts.append(String(format: prFormat, personalRecordCount))
        }

        return parts.joined(separator: " · ")
    }

    /// Compact volume for the recap line: "22k" past a thousand (one decimal below ten thousand),
    /// the plain number under it. Keeps the header short where the full grouped figure would crowd
    /// the line — the exact totals live on the volume screens.
    private func abbreviatedVolume(_ value: Int) -> String {
        guard value >= 1000 else { return "\(value)" }
        let thousands = Double(value) / 1000
        if thousands >= 10 {
            return "\(Int(thousands.rounded()))k"
        }
        let formatted = String(format: "%.1f", thousands)
        return (formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted) + "k"
    }
}

// MARK: - Calendar header

/// The month calendar from the goal screen (`WorkoutGoalScreen.calendarTile`) reused as a History
/// header — each day tinted by that day's dominant muscle group — but stripped of the goal's target
/// column and per-week rings. Tapping a trained day calls `onSelectDate` so the list can jump to it.
private struct HistoryCalendarView: View {
    @EnvironmentObject private var muscleGroupService: MuscleGroupService

    let workouts: [Workout]
    @Binding var selectedDay: Date?
    let onSelectDate: (Date) -> Void

    @State private var displayedMonth: Date = .now.startOfMonth
    private let calendar = Calendar.current

    var body: some View {
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
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(weeksOfMonth, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { day in
                        dayCell(day)
                    }
                }
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)
        let muscleColor = dominantMuscleColor(on: day)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let cell = Text("\(calendar.component(.day, from: day))")
            .font(.system(size: 13, weight: muscleColor != nil ? .bold : .semibold))
            .foregroundStyle(dayForeground(inMonth: inMonth, isToday: isToday, tinted: muscleColor != nil))
            .frame(width: 34, height: 34)
            .background {
                if let muscleColor {
                    Circle().fill(muscleColor)
                } else if isToday {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 1.6)
                }
            }
            .overlay {
                if isSelected {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 2).padding(-3)
                }
            }
            .frame(maxWidth: .infinity)
        if muscleColor != nil {
            Button { onSelectDate(day) } label: { cell }
                .buttonStyle(.plain)
        } else {
            cell
        }
    }

    private func dayForeground(inMonth: Bool, isToday: Bool, tinted: Bool) -> Color {
        if tinted { return .black }
        if isToday { return .accentColor }
        if !inMonth { return Color.white.opacity(0.18) }
        return .secondary
    }

    private func dominantMuscleColor(on day: Date) -> Color? {
        let dayWorkouts = workouts.filter {
            guard !$0.isEmpty, let date = $0.date else { return false }
            return calendar.isDate(date, inSameDayAs: day)
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

// MARK: - Filter sheet

/// The History filters, moved off the list into a sheet so the calendar header can own the top of the
/// screen: the muscle-group selector (as on the old inline row), plus "personal records only" and
/// "from a template" toggles. Reached from the filter button beside the title.
private struct WorkoutFilterSheet: View {
    @Binding var filter: WorkoutFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SECTION_SPACING) {
                    VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
                        Text(NSLocalizedString("muscleGroup", comment: ""))
                            .sectionHeaderStyle2()
                        MuscleGroupSelector(selectedMuscleGroup: $filter.muscleGroup, withAnimation: true)
                    }
                    VStack(spacing: 0) {
                        Toggle(NSLocalizedString("personalRecords", comment: ""), isOn: $filter.prsOnly)
                            .padding(.vertical, 6)
                        Divider()
                        Toggle(NSLocalizedString("fromTemplate", comment: ""), isOn: $filter.fromTemplate)
                            .padding(.vertical, 6)
                    }
                    .tint(.accentColor)
                    .padding(.horizontal, CELL_PADDING)
                    .padding(.vertical, 4)
                    .tileStyle()
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle(NSLocalizedString("filters", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if filter.isActive {
                        Button(NSLocalizedString("reset", comment: "")) {
                            withAnimation { filter = WorkoutFilter() }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("done", comment: "")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct AllWorkoutsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            WorkoutListScreen()
        }
        .previewEnvironmentObjects()
    }
}
