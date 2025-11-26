//
//  MeasurementsScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 25.09.23.
//

import SwiftUI

struct MeasurementsScreen: View {
    // MARK: - Environment

    @EnvironmentObject var database: Database
    @EnvironmentObject var measurementController: MeasurementEntryController

    // MARK: - Properties

    private let allMeasurements: [MeasurementEntryType] = {
        var measurements: [MeasurementEntryType] = [.bodyweight, .bodyFatPercentage, .muscleMass]
        measurements.append(contentsOf: LengthMeasurementEntryType.allCases.map { .length($0) })
        return measurements
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(allMeasurements, id: \.rawValue) { measurementType in
                    NavigationLink {
                        MeasurementDetailScreen(measurementType: measurementType)
                    } label: {
                        MeasurementTile(measurementType: measurementType)
                    }
                    .buttonStyle(TileButtonStyle())
                }
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .navigationTitle(NSLocalizedString("measurements", comment: ""))
    }
}

struct MeasurementsScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MeasurementsScreen()
        }
        .previewEnvironmentObjects()
    }
}
