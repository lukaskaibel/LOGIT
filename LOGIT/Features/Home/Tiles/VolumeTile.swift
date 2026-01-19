//
//  VolumeTile.swift
//  LOGIT
//
//  Created by Volker Kaibel on 06.10.24.
//

import Charts
import SwiftUI

struct VolumeTile: View {
    let workouts: [Workout]

    var body: some View {
        // Limit to last 4 full weeks (including current) to mirror ExerciseVolumeTile
        let startDate = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: .now)!.startOfWeek
        let workoutSets = workouts
            .flatMap { $0.sets }
            .filter { if let d = $0.workout?.date { return d >= startDate && d <= .now } else { return false } }
        let groupedWorkoutSets = Dictionary(grouping: workoutSets) { $0.workout?.date?.startOfWeek ?? .now }
            .sorted { $0.key < $1.key }
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("volume", comment: ""))
                        .tileHeaderStyle()
                }
                Spacer()
                NavigationChevron()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("thisWeek", comment: ""))
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                        .fontWeight(.semibold)
                    let thisWeekStart = Date.now.startOfWeek
                    let setsThisWeek = groupedWorkoutSets.first(where: { Calendar.current.isDate($0.key, equalTo: thisWeekStart, toGranularity: .weekOfYear) })?.value ?? []
                    UnitView(
                        value: "\(formatWeightForDisplay(getVolume(of: setsThisWeek)))",
                        unit: WeightUnit.used.rawValue.uppercased(),
                        configuration: .large,
                        unitColor: .secondaryLabel
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                }
                Spacer()
                Chart {
                    ForEach(groupedWorkoutSets, id: \.0) { key, workoutSets in
                        BarMark(
                            x: .value("Weeks before now", key, unit: .weekOfYear),
                            y: .value("Volume in week", convertWeightForDisplayingDecimal(getVolume(of: workoutSets))),
                            width: .ratio(0.5)
                        )
                        .foregroundStyle(Calendar.current.isDate(key, equalTo: .now, toGranularity: .weekOfYear) ? Color.accentColor : Color.fill)
                    }
                }
                .chartXScale(domain: xDomain(startDate: startDate))
                .chartXAxis {}
                .chartYAxis {}
                .frame(width: 120, height: 70)
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }

    private func xDomain(startDate: Date) -> some ScaleDomain {
        startDate ... Date.now.endOfWeek
    }
}

#Preview {
    FetchRequestWrapper(Workout.self) { workouts in
        VolumeTile(workouts: workouts)
            .previewEnvironmentObjects()
            .padding()
    }
}
