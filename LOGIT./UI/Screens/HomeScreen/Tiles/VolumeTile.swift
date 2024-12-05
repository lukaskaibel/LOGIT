//
//  VolumeTile.swift
//  LOGIT
//
//  Created by Volker Kaibel on 06.10.24.
//

import Charts
import SwiftUI

struct VolumeTile: View {
    
    @EnvironmentObject private var workoutSetRepository: WorkoutSetRepository
    
    var body: some View {
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
            HStack {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("thisWeek", comment: ""))
                    UnitView(
                        value: "\(volumePerWeek(for: 0))",
                        unit: WeightUnit.used.rawValue,
                        configuration: .large
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                }
                Spacer()
                Chart {
                    ForEach(0..<5, id: \.self) { weeksBeforeNow in
                        let date = Calendar.current.date(byAdding: .weekOfYear, value: -weeksBeforeNow, to: .now) ?? .now
                        BarMark(
                            x: .value("Weeks before now", date, unit: .weekOfYear),
                            y: .value("Volume in week", volumePerWeek(for: weeksBeforeNow)),
                            width: .ratio(0.5)
                        )
                        .foregroundStyle((weeksBeforeNow == 0 ? Color.accentColor : Color.fill).gradient)
                    }
                }
                .chartXAxis {}
                .chartYAxis {}
                .frame(width: 120, height: 80)
                .padding(.trailing)
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }
    
    private func volumePerWeek(for weeksBeforeNow: Int) -> Int {
        guard let date = Calendar.current.date(byAdding: .weekOfYear, value: -(weeksBeforeNow), to: .now) else { return 0 }
        let workoutSetsThisWeek = workoutSetRepository.getWorkoutSets(
            for: [.weekOfYear, .yearForWeekOfYear],
            including: date
        )
        return convertWeightForDisplaying(getVolume(of: workoutSetsThisWeek))
    }

}

#Preview {
    VolumeTile()
        .previewEnvironmentObjects()
        .padding()
}
