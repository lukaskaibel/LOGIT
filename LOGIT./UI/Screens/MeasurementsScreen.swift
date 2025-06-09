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

    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                WidgetCollectionView(
                    type: .baseMeasurements,
                    title: NSLocalizedString("coreMetrics", comment: ""),
                    views: [
                        MeasurementEntryView(measurementType: .bodyweight)
                            .padding(CELL_PADDING)
                            .tileStyle()
                            .widget(ofType: .measurement(.bodyweight), isAddedByDefault: true),
                        MeasurementEntryView(measurementType: .caloriesBurned)
                            .padding(CELL_PADDING)
                            .tileStyle()
                            .widget(ofType: .measurement(.caloriesBurned), isAddedByDefault: false),
                    ],
                    database: database
                )

                WidgetCollectionView(
                    type: .circumferenceMeasurements,
                    title: NSLocalizedString("bodyParts", comment: ""),
                    views: LengthMeasurementEntryType.allCases.map {
                        MeasurementEntryView(measurementType: .length($0))
                            .padding(CELL_PADDING)
                            .tileStyle()
                            .widget(ofType: .measurement(.length($0)), isAddedByDefault: false)
                    },
                    database: database
                )
            }
            .padding(.horizontal)
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
