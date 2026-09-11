//
//  UserHeight.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 11.09.26.
//

import Foundation

/// The user's height, held as one value rather than a measurement series.
///
/// Height is not a `MeasurementEntryType` on purpose: it barely moves, nobody wants a chart of
/// it, and the only thing LOGIT needs it for is deriving BMI. So it lives in Settings as a single
/// number — typed there, or filled in from Apple Health, whichever happens first.
///
/// Stored in **centimetres**, matching the app's other body lengths (`MeasurementEntryType.length`
/// reads and writes cm), so the one place a conversion is needed is the metres BMI wants.
enum UserHeight {
    /// UserDefaults key. Public so Settings can bind to it with `@AppStorage`.
    static let storageKey = "userHeightCentimeters"

    /// Below this, a typed value is a slip rather than a person — and dividing by a near-zero
    /// height would produce a BMI in the thousands. Above it, likewise.
    static let plausibleRange: ClosedRange<Double> = 50...260

    /// The stored height in centimetres, or `nil` when unset or implausible. `nil` is what gates
    /// BMI: no height, no derivation.
    static var centimeters: Double? {
        let stored = UserDefaults.standard.double(forKey: storageKey)
        guard plausibleRange.contains(stored) else { return nil }
        return stored
    }

    /// The stored height in metres — the unit BMI is defined in.
    static var meters: Double? {
        centimeters.map { $0 / 100 }
    }

    static var isSet: Bool { centimeters != nil }

    /// Writes a height, ignoring implausible values so a stray import can't poison the setting.
    /// Passing `nil` clears it.
    static func set(centimeters: Double?) {
        guard let centimeters else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            return
        }
        guard plausibleRange.contains(centimeters) else { return }
        UserDefaults.standard.set(centimeters, forKey: storageKey)
    }

    /// BMI for a body weight in **kilograms**, or `nil` without a height.
    ///
    /// Kilograms, not the displayed weight: `MeasurementEntry.decimalValue` hands back pounds for
    /// a user on imperial, and BMI is defined on kg/m² regardless of what the app is showing.
    static func bmi(forKilograms kilograms: Double) -> Double? {
        guard let meters, meters > 0, kilograms > 0 else { return nil }
        return kilograms / (meters * meters)
    }
}
