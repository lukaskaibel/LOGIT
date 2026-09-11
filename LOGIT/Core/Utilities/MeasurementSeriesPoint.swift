//
//  MeasurementSeriesPoint.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 11.09.26.
//

import Foundation

/// One point on a measurement's timeline: a date and a value, plus the entry behind it when there
/// is one.
///
/// The tile and the detail screen used to read `MeasurementEntry` directly, which quietly required
/// every measurement to be something the user had logged. BMI isn't — it is body weight divided by
/// the height in Settings — so both now draw from this instead, and `entry` is `nil` for a derived
/// point. That nil is also what withholds delete: there is no row in the store to remove.
struct MeasurementSeriesPoint: Identifiable {
    let id: UUID
    let date: Date
    let value: Double
    let entry: MeasurementEntry?
}
