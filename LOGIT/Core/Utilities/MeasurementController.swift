//
//  MeasurementController.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 20.09.23.
//

import Foundation

class MeasurementEntryController: ObservableObject {
    // MARK: - Statics

    // MARK: - Constants

    private let database: Database

    // MARK: - Init

    init(database: Database) {
        self.database = database
        if database.isPreview {
            setupPreviewMeasurementEntries()
        }
    }

    func save() {
        database.save()
    }

    func getMeasurementEntries(ofType type: MeasurementEntryType) -> [MeasurementEntry] {
        (database.fetch(MeasurementEntry.self, sortingKey: "date", ascending: false)
            as! [MeasurementEntry])
            .filter { $0.type == type }
    }

    func addMeasurementEntry(ofType type: MeasurementEntryType, value: Int, onDate date: Date) {
        let measurement = MeasurementEntry(context: database.context)
        measurement.id = UUID()
        measurement.type = type
        measurement.value = value
        measurement.date = date
        save()
        objectWillChange.send()
    }

    func addMeasurementEntry(ofType type: MeasurementEntryType, decimalValue: Double, onDate date: Date) {
        let measurement = MeasurementEntry(context: database.context)
        measurement.id = UUID()
        measurement.type = type
        measurement.decimalValue = decimalValue
        measurement.date = date
        save()
        objectWillChange.send()
    }

    func deleteMeasurementEntry(_ measurement: MeasurementEntry) {
        database.delete(measurement, saveContext: true)
        objectWillChange.send()
    }

    // MARK: - Setup Controller for Preview

    private func setupPreviewMeasurementEntries() {
        // Starting weight in grams (for example, 100,000 grams or 100 kg)
        var currentWeight = 100

        // Define the date six months ago from today
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date())!

        // The current date we're adding data for
        var currentDate = sixMonthsAgo

        while currentDate < Date() {
            // Randomly decide how much weight to lose (between 200 to 900 grams)
            let weightLoss = Int.random(in: 1 ... 3)
            currentWeight -= weightLoss

            // Add the measurement entry
            addMeasurementEntry(ofType: .bodyweight, value: currentWeight, onDate: currentDate)

            // Randomly decide the next date (within a week, but not exactly 7 days every time)
            let randomDays = Int.random(in: 7 ... 11)
            currentDate = Calendar.current.date(byAdding: .day, value: randomDays, to: currentDate)!
        }
    }
}
