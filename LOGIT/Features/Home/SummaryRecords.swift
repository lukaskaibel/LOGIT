//
//  SummaryRecords.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

// MARK: - Aggregation

/// Aggregates the personal records set across a period's workouts. Reuses `WorkoutProgressReport`'s
/// verified "is this a record as of that date" detection per workout, then unions the results — the
/// highest value per exercise+metric, grouped into one entry per exercise (newest record first, the
/// same per-exercise unit every other record surface counts) — instead of re-deriving prior-best
/// math.
enum SummaryRecords {
    static func records(in workouts: [Workout], database: Database) -> [WorkoutProgressReport.ExerciseRecords] {
        var best: [String: WorkoutProgressReport.PRRecord] = [:]
        for workout in workouts {
            let report = WorkoutProgressReport.compute(for: workout, database: database)
            for record in report.exerciseRecords.flatMap(\.records) {
                if let existing = best[record.id] {
                    if record.value > existing.value { best[record.id] = record }
                } else {
                    best[record.id] = record
                }
            }
        }
        let newestFirst = best.values.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return WorkoutProgressReport.ExerciseRecords.grouped(newestFirst)
    }

    static func periodCaption(_ period: StatPeriod) -> String {
        switch period {
        case .week: return NSLocalizedString("thisWeek", comment: "")
        case .month: return NSLocalizedString("thisMonth", comment: "")
        case .year: return NSLocalizedString("thisYear", comment: "")
        }
    }
}

// MARK: - Summary Records Tile

/// The Summary screen's period-scoped Records tile — identical record rows to the workout-detail tile
/// (the shared `PersonalBestRow`), under a trophy-badge header reading "N New Records · THIS
/// WEEK/MONTH/YEAR". Free: the PR celebration is the teaser that sells Pro (the full per-record
/// history charts live behind the wall on the detail screen).
struct SummaryRecordsTile: View {
    /// The period's records, one entry per exercise, supplied by the host so it can hide the tile
    /// entirely when empty.
    let records: [WorkoutProgressReport.ExerciseRecords]
    let period: StatPeriod
    var maxShown: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding([.top, .horizontal], CELL_PADDING)
            VStack(spacing: 8) {
                ForEach(Array(records.prefix(maxShown))) { exerciseRecords in
                    PersonalBestRow(records: exerciseRecords)
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, CELL_PADDING / 2)
            .padding(.bottom, CELL_PADDING / 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileStyle()
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: "trophy.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor.gradient)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.label)
                Text(SummaryRecords.periodCaption(period))
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !records.isEmpty {
                Text(String(format: NSLocalizedString("personalRecordsMoreCount", comment: ""), max(0, records.count - maxShown)))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .opacity(records.count > maxShown ? 1 : 0)
            }
            NavigationChevron()
                .foregroundStyle(.secondary)
        }
    }

    private var headline: String {
        switch records.count {
        case 0: return NSLocalizedString("summaryRecordsNone", comment: "")
        case 1: return NSLocalizedString("summaryRecordsCountOne", comment: "")
        default: return String(format: NSLocalizedString("summaryRecordsCountMany", comment: ""), records.count)
        }
    }
}

// MARK: - Summary Records Screen

/// The full period-scoped records screen behind the Summary Records tile: every record set in the
/// period as a `WorkoutPersonalRecordCard` (now dated off the record itself, since they come from
/// different workouts). Pro — the tile is the free hook.
struct SummaryRecordsScreen: View {
    let workouts: [Workout]
    let period: StatPeriod

    @EnvironmentObject private var database: Database
    @State private var records: [WorkoutProgressReport.ExerciseRecords] = []

    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                header
                VStack(spacing: 10) {
                    ForEach(records) { exerciseRecords in
                        WorkoutPersonalRecordCard(records: exerciseRecords)
                    }
                }
                .emptyPlaceholder(records) {
                    Text(NSLocalizedString("summaryRecordsNone", comment: ""))
                }
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(NSLocalizedString("personalRecords", comment: ""))
                    .font(.headline)
            }
        }
        .task(id: period.rawValue) {
            records = SummaryRecords.records(in: workouts, database: database)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor.gradient)
            }
            Text(headline)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.label)
            Text(SummaryRecords.periodCaption(period))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top)
    }

    private var headline: String {
        records.count == 1
            ? NSLocalizedString("personalRecord", comment: "")
            : String(format: NSLocalizedString("personalRecordsCount", comment: ""), records.count)
    }
}
