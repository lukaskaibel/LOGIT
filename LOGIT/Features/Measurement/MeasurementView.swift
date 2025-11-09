//
//  MeasurementView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 18.09.23.
//

import SwiftUI

struct MeasurementEntryView: View {
    @EnvironmentObject var measurementController: MeasurementEntryController

    let measurementType: MeasurementEntryType

    @State private var isAddingMeasurementEntry = false
    @State private var isShowingMeasurementEntryList = false

    @State private var newMeasurementDate: Date = .now
    @State private var newMeasurementValue: Int64 = 0

    var body: some View {
        ZStack {
            Color.secondaryBackground
            VStack {
                HStack {
                    if isAddingMeasurementEntry {
                        Button(NSLocalizedString("cancel", comment: "")) {
                            resetNewMeasurementEntries()
                            withAnimation {
                                isAddingMeasurementEntry = false
                            }
                        }
                        Spacer()
                    }
                    VStack(alignment: .leading) {
                        Text(
                            measurementType.title
                        )
                        .tileHeaderStyle()
                        if !isAddingMeasurementEntry {
                            Text(
                                WidgetType.measurement(measurementType).unit
                            )
                            .tileHeaderSecondaryStyle()
                        }
                    }
                    Spacer()
                    if isAddingMeasurementEntry {
                        Button(NSLocalizedString("add", comment: "")) {
                            measurementController.addMeasurementEntry(
                                ofType: measurementType,
                                value: Int(newMeasurementValue),
                                onDate: newMeasurementDate
                            )
                            resetNewMeasurementEntries()
                            withAnimation {
                                isAddingMeasurementEntry = false
                            }
                        }
                        .fontWeight(.bold)
                        .disabled(newMeasurementValue == 0)
                    } else {
                        Button {
                            withAnimation {
                                isAddingMeasurementEntry = true
                            }
                        } label: {
                            Image(systemName: "plus")
                                .tileHeaderStyle()
                        }
                    }
                }
                if isAddingMeasurementEntry {
                    Spacer()
                    VStack(alignment: .leading) {
                        HStack {
                            DatePicker(
                                "Day of Measurement",
                                selection: $newMeasurementDate,
                                displayedComponents: [.date]
                            )
                            .labelsHidden()
                            Spacer()
                            IntegerField(
                                placeholder: 0,
                                value: $newMeasurementValue,
                                maxDigits: 4,
                                index: .init(primary: 0),
                                focusedIntegerFieldIndex: .constant(nil),
                                unit: measurementType.unit
                            )
                        }
                        .padding(CELL_PADDING)
                        .secondaryTileStyle()
                    }
                    Spacer()
                } else {
                    DateLineChart(dateDomain: .threeMonths) {
                        measurementController.getMeasurementEntries(ofType: measurementType)
                            .map { .init(date: $0.date ?? .now, value: $0.value) }
                    }
                    .noDataPlaceholder(
                        measurementController.getMeasurementEntries(ofType: measurementType)
                    ) {
                        Text(NSLocalizedString("noMeasurements", comment: ""))
                    }
                    Button {
                        isShowingMeasurementEntryList = true
                    } label: {
                        HStack {
                            Text(NSLocalizedString("showMeasurements", comment: ""))
                            Spacer()
                            NavigationChevron()
                        }
                        .padding(.bottom, 5)
                        .padding(.top, 10)
                    }
                }
            }
            .navigationDestination(isPresented: $isShowingMeasurementEntryList) {
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading) {
                            Text(
                                measurementType.title
                            )
                            .screenHeaderStyle()
                            Text(NSLocalizedString("measurements", comment: ""))
                                .foregroundColor(.secondary)
                                .screenHeaderSecondaryStyle()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(spacing: CELL_SPACING) {
                            ForEach(
                                measurementController.getMeasurementEntries(ofType: measurementType)
                            ) { measurementEntry in
                                HStack {
                                    Text(measurementEntry.date?.description(.short) ?? "No Date")
                                    Spacer()
                                    HStack(alignment: .lastTextBaseline, spacing: 0) {
                                        Text(String(measurementEntry.value))
                                            .font(.title3)
                                        Text(measurementType.unit)
                                            .font(.footnote)
                                            .textCase(.uppercase)
                                    }
                                    .fontWeight(.semibold)
                                }
                                .padding(CELL_PADDING)
                                .onDeleteView {
                                    withAnimation {
                                        measurementController.deleteMeasurementEntry(
                                            measurementEntry
                                        )
                                    }
                                }
                                .tileStyle()
                            }
                        }
                        .emptyPlaceholder(
                            measurementController.getMeasurementEntries(ofType: measurementType)
                        ) {
                            Text(NSLocalizedString("noMeasurements", comment: ""))
                        }
                    }
                    .padding(.horizontal)
                }
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .frame(height: 250)
    }

    private func resetNewMeasurementEntries() {
        newMeasurementDate = .now
        newMeasurementValue = 0
    }
}

struct MeasurementEntryView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MeasurementEntryView(measurementType: .bodyweight)
                .padding(CELL_PADDING)
                .tileStyle()
                .previewEnvironmentObjects()
        }
    }
}
