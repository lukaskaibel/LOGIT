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
    /// Mirrors body measurements to Apple Health (see `BodyMeasurementSyncManager`). Optional so
    /// previews and tests can construct a controller without a Health store.
    private let bodyMeasurementSync: BodyMeasurementSyncManager?

    // MARK: - Init

    init(database: Database, bodyMeasurementSync: BodyMeasurementSyncManager? = nil) {
        self.database = database
        self.bodyMeasurementSync = bodyMeasurementSync
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

    /// The plotted timeline for a measurement, newest first — what the tile and the detail screen
    /// both draw. Stored types hand back their entries; BMI is computed here from body weight and
    /// the height in Settings, which is why the views read this rather than `getMeasurementEntries`.
    func series(ofType type: MeasurementEntryType) -> [MeasurementSeriesPoint] {
        guard type != .bmi else { return bmiSeries() }
        return getMeasurementEntries(ofType: type).compactMap { entry in
            guard let id = entry.id, let date = entry.date else { return nil }
            return MeasurementSeriesPoint(
                id: id, date: date, value: entry.decimalValue, entry: entry
            )
        }
    }

    /// Whether a measurement has anything to show. BMI needs both of its inputs — a height and at
    /// least one weight — and is hidden entirely until it has them, rather than appearing as an
    /// empty tile the user can't fill from the screen they're on.
    func isAvailable(_ type: MeasurementEntryType) -> Bool {
        guard type == .bmi else { return true }
        return UserHeight.isSet && !getMeasurementEntries(ofType: .bodyweight).isEmpty
    }

    /// One BMI point per body-weight entry: the weight is what moves, the height is a constant, so
    /// the two series share their dates exactly.
    ///
    /// Weight comes from `value_` (grams) rather than `decimalValue`, which would be pounds for a
    /// user on imperial — BMI is defined on kg/m² whatever the app is displaying.
    private func bmiSeries() -> [MeasurementSeriesPoint] {
        guard UserHeight.isSet else { return [] }
        return getMeasurementEntries(ofType: .bodyweight).compactMap { entry in
            guard let id = entry.id, let date = entry.date, entry.value_ > 0,
                  let bmi = UserHeight.bmi(forKilograms: Double(entry.value_) / 1000)
            else { return nil }
            return MeasurementSeriesPoint(id: id, date: date, value: bmi, entry: nil)
        }
    }

    func addMeasurementEntry(ofType type: MeasurementEntryType, value: Int, onDate date: Date) {
        let measurement = MeasurementEntry(context: database.context)
        measurement.id = UUID()
        measurement.type = type
        measurement.value = value
        measurement.date = date
        save()
        bodyMeasurementSync?.syncEntry(measurement)
        objectWillChange.send()
    }

    func addMeasurementEntry(ofType type: MeasurementEntryType, decimalValue: Double, onDate date: Date) {
        let measurement = MeasurementEntry(context: database.context)
        measurement.id = UUID()
        measurement.type = type
        measurement.decimalValue = decimalValue
        measurement.date = date
        save()
        bodyMeasurementSync?.syncEntry(measurement)
        objectWillChange.send()
    }

    func deleteMeasurementEntry(_ measurement: MeasurementEntry) {
        // Read the identifiers before the delete: afterwards the object is a fault with
        // nothing left to tell Health which sample to remove. The sync manager decides whether
        // this type is one it mirrors — body weight and body fat are, the rest fall through.
        let type = measurement.type
        let id = measurement.id
        let healthKitUUID = measurement.healthKitUUID
        database.delete(measurement, saveContext: true)
        bodyMeasurementSync?.removeEntry(ofType: type, id: id, healthKitUUID: healthKitUUID)
        objectWillChange.send()
    }

    // MARK: - Setup Controller for Preview

    // Internal so scenario launches can seed measurements explicitly (see TestScenario).
    func setupPreviewMeasurementEntries() {
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

        // Body fat %: gentle downward trend over the same 3-month window so
        // the Pro "Measurements" chart shows a visibly satisfying arc. We
        // use ~22 % → ~15 % drift with small random wobble so the line
        // isn't perfectly straight.
        var currentBodyFat = 22.4
        currentDate = sixMonthsAgo
        while currentDate < Date() {
            let drift = Double.random(in: 0.05 ... 0.28)
            currentBodyFat = max(13.5, currentBodyFat - drift)
            let noise = Double.random(in: -0.18 ... 0.18)
            let displayValue = (currentBodyFat + noise).rounded(toPlaces: 1)
            addMeasurementEntry(
                ofType: .bodyFatPercentage,
                decimalValue: displayValue,
                onDate: currentDate
            )
            let randomDays = Int.random(in: 6 ... 10)
            currentDate = Calendar.current.date(byAdding: .day, value: randomDays, to: currentDate)!
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
