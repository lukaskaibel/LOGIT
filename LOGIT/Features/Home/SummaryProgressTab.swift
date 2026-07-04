//
//  SummaryProgressTab.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 30.06.26.
//

import CoreData
import SwiftUI

// MARK: - Summary tab

/// The Summary screen's top switcher: the everyday `This Week` view vs the new `Progress` lens
/// (recent highlights + the overall strength trend). Replaces the old Week / Month / Year period
/// segments on the Summary — the longer windows still live on the stat detail screens.
enum SummaryTab: String, CaseIterable, Identifiable {
    case thisWeek, progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thisWeek: return NSLocalizedString("thisWeek", comment: "")
        case .progress: return NSLocalizedString("progress", comment: "")
        }
    }
}

/// The shared segmented `This Week` / `Progress` control, mirroring `PeriodPicker`'s styling.
struct SummaryTabPicker: View {
    @Binding var selection: SummaryTab

    var body: some View {
        Picker(NSLocalizedString("progress", comment: ""), selection: $selection) {
            ForEach(SummaryTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

// MARK: - Progress tab

/// The `Progress` tab body: recent highlights on top, the overall strength-trend tile below. Computes
/// both off the already-fetched `[Workout]` in a `.task` (no new Core Data fetches), the way the
/// Summary's records tile does.
struct SummaryProgressTab: View {
    let workouts: [Workout]

    @EnvironmentObject private var database: Database
    @State private var overall: OverallProgress = .empty
    @State private var highlights: [WorkoutProgressReport.PRRecord] = []

    var body: some View {
        VStack(spacing: 8) {
            if !highlights.isEmpty {
                ProgressHighlightsTile(records: highlights)
            }
            OverallProgressTile(progress: overall)
        }
        .task(id: workouts.count) {
            overall = OverallProgress.compute(workouts: workouts)
            highlights = SummaryRecords.records(in: recentWorkouts, database: database)
        }
    }

    /// Workouts of the last 30 days — the window the highlights are drawn from, so the feed stays
    /// "recent" rather than all-time.
    private var recentWorkouts: [Workout] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        return workouts.filter { !$0.isEmpty && ($0.date ?? .distantPast) >= cutoff }
    }
}

// MARK: - Overall progress model

/// The whole-training strength trend: each trained exercise's percent change in estimated 1RM over
/// the recent block vs the equally long block before it, volume-weighted (by recent set count) into
/// one overall figure plus a per-muscle-group breakdown. Cardio / bodyweight sets carry no e1RM and
/// drop out; an exercise needs a usable best in BOTH blocks to count — with nothing to compare
/// against there is no trend.
struct OverallProgress {
    struct GroupProgress: Identifiable {
        let muscleGroup: MuscleGroup
        let percentChange: Double
        var id: String { muscleGroup.rawValue }
    }

    /// Volume-weighted mean percent change across all qualifying exercises, or nil when none qualify.
    let overallPercentChange: Double?
    /// Per-muscle-group weighted mean — groups with data only, sorted strongest gain first.
    let groups: [GroupProgress]

    var hasData: Bool { overallPercentChange != nil }

    static let empty = OverallProgress(overallPercentChange: nil, groups: [])

    /// Outlier guard so one freak set can't swing the headline.
    private static let maxAbsPercentChange = 50.0

    static func compute(workouts: [Workout], recentWeeks: Int = 8, reference: Date = .now) -> OverallProgress {
        let calendar = Calendar.current
        guard
            let recentStart = calendar.date(byAdding: .weekOfYear, value: -recentWeeks, to: reference),
            let priorStart = calendar.date(byAdding: .weekOfYear, value: -2 * recentWeeks, to: reference)
        else { return .empty }

        // Unique exercises trained across the fetched workouts.
        var exercises: [Exercise] = []
        var seen = Set<NSManagedObjectID>()
        for workout in workouts where !workout.isEmpty {
            for exercise in workout.exercises where !seen.contains(exercise.objectID) {
                seen.insert(exercise.objectID)
                exercises.append(exercise)
            }
        }

        struct Change { let group: MuscleGroup; let percent: Double; let weight: Double }
        var changes: [Change] = []

        for exercise in exercises {
            guard let group = exercise.muscleGroup else { continue }
            var recentBest = 0
            var priorBest = 0
            var recentSetCount = 0
            for set in exercise.sets {
                guard let date = set.workout?.date else { continue }
                let e1rm = set.estimatedOneRepMax(for: exercise)
                guard e1rm > 0 else { continue }
                if date >= recentStart, date <= reference {
                    recentBest = max(recentBest, e1rm)
                    recentSetCount += 1
                } else if date >= priorStart, date < recentStart {
                    priorBest = max(priorBest, e1rm)
                }
            }
            guard recentBest > 0, priorBest > 0 else { continue }
            let raw = (Double(recentBest) - Double(priorBest)) / Double(priorBest) * 100
            let clamped = min(max(raw, -maxAbsPercentChange), maxAbsPercentChange)
            changes.append(Change(group: group, percent: clamped, weight: Double(max(recentSetCount, 1))))
        }

        guard !changes.isEmpty else { return .empty }

        let totalWeight = changes.reduce(0) { $0 + $1.weight }
        let overall = changes.reduce(0) { $0 + $1.percent * $1.weight } / totalWeight

        var byGroup: [MuscleGroup: (sum: Double, weight: Double)] = [:]
        for change in changes {
            let current = byGroup[change.group] ?? (0, 0)
            byGroup[change.group] = (current.sum + change.percent * change.weight, current.weight + change.weight)
        }
        let groups = byGroup
            .map { GroupProgress(muscleGroup: $0.key, percentChange: $0.value.sum / $0.value.weight) }
            .sorted { $0.percentChange > $1.percentChange }

        return OverallProgress(overallPercentChange: overall, groups: groups)
    }
}

// MARK: - Trend arrow helpers

/// Below this magnitude (in %) a trend reads as flat — a deadband so the arrow doesn't twitch.
private let trendDeadband = 1.0

private func trendIsUp(_ percent: Double) -> Bool { percent >= trendDeadband }
private func trendIsDown(_ percent: Double) -> Bool { percent <= -trendDeadband }

/// Accent for a gain; neutral grey for flat or a decline — progress green is the only colour that
/// ever means "good", and a dip is never coloured as a warning.
private func trendColor(_ percent: Double) -> Color {
    trendIsUp(percent) ? .accentColor : .secondaryLabel
}

/// Continuous arrow angle in degrees (0 = flat/right, positive = up), scaled from the percent and
/// clamped so big swings still read as "steeply up/down" without spinning past vertical.
private func trendAngle(_ percent: Double) -> Double {
    min(max(percent * 6, -62), 80)
}

private func signedPercent(_ percent: Double, fractionDigits: Int) -> String {
    String(format: "%+.\(fractionDigits)f%%", percent)
}

/// A right-pointing arrow rotated to the trend angle — the shared glyph for the hero and the
/// per-muscle rows. Positive angle rotates it up (counter-clockwise).
private struct TrendArrow: View {
    let percent: Double
    let color: Color
    let size: CGFloat

    var body: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(color)
            .rotationEffect(.degrees(-trendAngle(percent)))
    }
}

// MARK: - Overall progress tile

/// The Progress tab's headline tile: one continuous arrow for the whole-training trend, then a small
/// per-muscle-group arrow in each group's colour. No detail screen yet, so no chevron.
struct OverallProgressTile: View {
    let progress: OverallProgress

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TileHeader(NSLocalizedString("overallProgress", comment: ""), showsChevron: false)
                .padding([.top, .horizontal], CELL_PADDING)

            if let overall = progress.overallPercentChange {
                hero(overall)
                    .padding(.horizontal, CELL_PADDING)
                    .padding(.top, 12)

                if !progress.groups.isEmpty {
                    Divider()
                        .padding(.horizontal, CELL_PADDING)
                        .padding(.vertical, 12)
                    muscleBreakdown
                        .padding(.horizontal, CELL_PADDING)
                        .padding(.bottom, CELL_PADDING)
                } else {
                    Spacer().frame(height: CELL_PADDING)
                }
            } else {
                emptyState
                    .padding(CELL_PADDING)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileStyle()
    }

    private func hero(_ overall: Double) -> some View {
        let color = trendColor(overall)
        return HStack(spacing: 15) {
            ZStack {
                Circle().fill(color.opacity(0.13)).frame(width: 60, height: 60)
                TrendArrow(percent: overall, color: color, size: 24)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(statusText(overall))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(color)
                Text(signedPercent(overall, fractionDigits: 1))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.label)
                    .monospacedDigit()
                Text(NSLocalizedString("overallProgressBasis", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var muscleBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("byMuscleGroup", comment: ""))
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(progress.groups) { group in
                    muscleRow(group)
                }
            }
        }
    }

    private func muscleRow(_ group: OverallProgress.GroupProgress) -> some View {
        let color = group.muscleGroup.color
        let dimmed = !trendIsUp(group.percentChange)
        return HStack(spacing: 8) {
            TrendArrow(percent: group.percentChange, color: color, size: 13)
                .opacity(dimmed ? 0.6 : 1)
                .frame(width: 18)
            Text(group.muscleGroup.description)
                .font(.subheadline)
                .foregroundStyle(Color.label)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(signedPercent(group.percentChange, fractionDigits: 0))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color.opacity(dimmed ? 0.6 : 1))
                .monospacedDigit()
        }
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("overallProgressEmpty", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func statusText(_ percent: Double) -> String {
        if trendIsUp(percent) { return NSLocalizedString("trendingUp", comment: "") }
        if trendIsDown(percent) { return NSLocalizedString("trendingDown", comment: "") }
        return NSLocalizedString("trendingSteady", comment: "")
    }
}

// MARK: - Highlights tile

/// The Progress tab's highlights: the most recent personal record as a prominent hero (exercise,
/// metric, the new value and the gain over the old best), then up to a couple more recent records as
/// the shared `PersonalBestRow`. Hidden entirely when there are no recent records — like the Summary
/// records tile, an empty highlights tile would be worse than none.
struct ProgressHighlightsTile: View {
    /// Recent, deduped records (one per exercise+metric, newest first) from `SummaryRecords.records`.
    let records: [WorkoutProgressReport.PRRecord]
    var maxRows: Int = 3

    var body: some View {
        if let top = records.first {
            VStack(alignment: .leading, spacing: 0) {
                TileHeader(NSLocalizedString("highlights", comment: ""), showsChevron: false)
                    .padding([.top, .horizontal], CELL_PADDING)
                hero(top)
                    .padding(.horizontal, CELL_PADDING)
                    .padding(.top, 12)
                let rest = Array(records.dropFirst().prefix(max(0, maxRows - 1)))
                if !rest.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(rest) { PersonalBestRow(record: $0) }
                    }
                    .padding(.horizontal, CELL_PADDING / 2)
                    .padding(.top, 10)
                }
            }
            .padding(.bottom, CELL_PADDING / 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tileStyle()
        }
    }

    private func hero(_ record: WorkoutProgressReport.PRRecord) -> some View {
        let color = record.exercise.muscleGroup?.color ?? .accentColor
        let display = personalRecordDisplay(record.value, metric: record.metric)
        let gain: Double? = record.previousBest > 0
            ? (Double(record.value) - Double(record.previousBest)) / Double(record.previousBest) * 100
            : nil
        return HStack(spacing: 13) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 46, height: 46)
                Image(systemName: "trophy.fill")
                    .font(.title3)
                    .foregroundStyle(color.gradient)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(record.exercise.displayName)
                    .font(.headline)
                    .foregroundStyle(Color.label)
                    .lineLimit(1)
                Text("\(NSLocalizedString("newRecord", comment: "")) · \(record.metric.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                UnitView(value: display.value, unit: display.unit)
                    .foregroundStyle(color.gradient)
                if let gain {
                    TrendIndicatorView(
                        percentChange: gain,
                        positiveColor: color,
                        positiveStyle: AnyShapeStyle(color.gradient)
                    )
                }
            }
        }
    }
}
