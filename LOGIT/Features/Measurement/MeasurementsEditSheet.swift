//
//  MeasurementsEditSheet.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 26.11.24.
//

import SwiftUI

struct MeasurementsEditSheet: View {
    @Binding var pinnedMeasurements: [MeasurementEntryType]
    @Environment(\.dismiss) private var dismiss

    private let allMeasurements: [MeasurementEntryType] = {
        var measurements: [MeasurementEntryType] = [.bodyweight, .bodyFatPercentage, .muscleMass]
        let sortedLengthMeasurements = LengthMeasurementEntryType.allCases
            .map { MeasurementEntryType.length($0) }
            .sorted { $0.title < $1.title }
        measurements.append(contentsOf: sortedLengthMeasurements)
        return measurements
    }()

    @State private var editMode: EditMode = .active

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(pinnedMeasurements.enumerated()), id: \.offset) { index, measurement in
                        HStack {
                            Text(measurement.title)
                            Spacer()
                            Text(measurement.unit.uppercased())
                                .font(.footnote)
                                .foregroundStyle(Color.secondaryLabel)
                        }
                    }
                    .onMove(perform: move)
                    .onDelete(perform: delete)
                } header: {
                    Text(NSLocalizedString("pinned", comment: ""))
                } footer: {
                    Text(NSLocalizedString("dragToReorder", comment: "Drag to reorder measurements"))
                }

                if !unpinnedMeasurements.isEmpty {
                    Section {
                        ForEach(unpinnedMeasurements, id: \.rawValue) { measurement in
                            Button {
                                pinnedMeasurements.append(measurement)
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(measurement.title)
                                        .foregroundStyle(Color.label)
                                    Spacer()
                                    Text(measurement.unit.uppercased())
                                        .font(.footnote)
                                        .foregroundStyle(Color.secondaryLabel)
                                }
                            }
                        }
                    } header: {
                        Text(NSLocalizedString("unpinned", comment: ""))
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle(NSLocalizedString("editPinnedMeasurements", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("done", comment: "")) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var unpinnedMeasurements: [MeasurementEntryType] {
        allMeasurements.filter { measurement in
            !pinnedMeasurements.contains(where: { $0.rawValue == measurement.rawValue })
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        pinnedMeasurements.move(fromOffsets: source, toOffset: destination)
    }

    private func delete(at offsets: IndexSet) {
        pinnedMeasurements.remove(atOffsets: offsets)
    }
}

struct MeasurementsEditSheet_Previews: PreviewProvider {
    static var previews: some View {
        MeasurementsEditSheet(
            pinnedMeasurements: .constant([.bodyweight, .length(.chest), .length(.bicepsLeft)])
        )
    }
}
