//
//  DistanceConverting.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 21.07.26.
//

import Foundation

private let KM_TO_MM: Double = 1_000_000.0
private let MI_TO_MM: Double = 1_609_344.0
private let M_TO_MM: Double = 1000.0
private let YD_TO_MM: Double = 914.4

/// How many decimals a distance is entered and displayed with, in either unit system.
///
/// Two, and not by taste: millimeter storage round-trips every two-decimal value in all four
/// units exactly, and a third decimal is where the imperial side gives out — 0.006 yd stores as
/// 5 mm and redisplays as 0.005 yd. (Storing centimeters instead would already break the
/// *second* decimal in yards: 0.06 yd → 5 cm → 0.05 yd, 856 of the first 10 000 values.) One
/// centimeter of resolution is also finer than anything a gym floor or a treadmill reports.
public let DISTANCE_DECIMAL_PLACES: Int = 2

// MARK: - Long Distances (km/mi — cardio-scale)

/// Converts a distance from display units (km or mi) to storage units (millimeters).
/// - Parameter value: Distance in km or mi (as displayed to user)
/// - Returns: Distance in millimeters (for storage in database)
public func convertDistanceForStoring(_ value: Double) -> Int64 {
    switch DistanceUnit.used {
    case .km: return Int64(round(value * KM_TO_MM))
    case .mi: return Int64(round(value * MI_TO_MM))
    }
}

/// Converts a distance from storage units (millimeters) to display units (km or mi)
/// with up to `DISTANCE_DECIMAL_PLACES` decimal places.
public func convertDistanceForDisplayingDecimal(_ millimeters: Int64) -> Double {
    let result: Double
    switch DistanceUnit.used {
    case .km: result = Double(millimeters) / KM_TO_MM
    case .mi: result = Double(millimeters) / MI_TO_MM
    }
    return roundedToDisplayDecimals(result)
}

/// Formats a distance from storage units (millimeters) to a display string in km or mi,
/// showing decimals only when needed.
public func formatDistanceForDisplay(_ millimeters: Int64) -> String {
    formatDistanceNumber(convertDistanceForDisplayingDecimal(millimeters))
}

public func formatDistanceForDisplay(_ millimeters: Int) -> String {
    formatDistanceForDisplay(Int64(millimeters))
}

// MARK: - Short Distances (m/yd — carry-scale)

/// Converts a short distance from display units (m or yd) to storage units (millimeters).
public func convertShortDistanceForStoring(_ value: Double) -> Int64 {
    switch DistanceUnit.used {
    case .km: return Int64(round(value * M_TO_MM))
    case .mi: return Int64(round(value * YD_TO_MM))
    }
}

/// Converts a short distance from storage units (millimeters) to display units (m or yd)
/// with up to `DISTANCE_DECIMAL_PLACES` decimal places.
public func convertShortDistanceForDisplayingDecimal(_ millimeters: Int64) -> Double {
    let result: Double
    switch DistanceUnit.used {
    case .km: result = Double(millimeters) / M_TO_MM
    case .mi: result = Double(millimeters) / YD_TO_MM
    }
    return roundedToDisplayDecimals(result)
}

// MARK: - Shared Number Formatting

private func roundedToDisplayDecimals(_ value: Double) -> Double {
    let scale = pow(10.0, Double(DISTANCE_DECIMAL_PLACES))
    return (value * scale).rounded() / scale
}

/// One decimal spelling for every distance, in either scale: the fraction shows only when the
/// value carries one, so a 40 m carry stays "40" and a measured 40.25 m reads in full.
private func formatDistanceNumber(_ value: Double) -> String {
    if value == 0 {
        return "0"
    }

    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = DISTANCE_DECIMAL_PLACES
    formatter.decimalSeparator = "."
    formatter.groupingSeparator = ""

    return formatter.string(from: NSNumber(value: value)) ?? "0"
}

// MARK: - Style Dispatch

/// Formats a stored distance (millimeters) for display in the unit matching `style` — long
/// distances in km/mi, short ones in m/yd, both showing decimals only when the value has them.
/// The single entry point for read-only distance text (history rows, badges, Live Activity),
/// so every surface agrees.
func formatDistanceForDisplay(
    _ millimeters: Int64, style: SetMeasurementType.DistanceStyle
) -> String {
    switch style {
    case .long: return formatDistanceForDisplay(millimeters)
    case .short: return formatDistanceNumber(convertShortDistanceForDisplayingDecimal(millimeters))
    }
}

/// Converts a stored distance (millimeters) to the decimal value entered and shown in the unit
/// matching `style`.
func convertDistanceForDisplayingDecimal(
    _ millimeters: Int64, style: SetMeasurementType.DistanceStyle
) -> Double {
    switch style {
    case .long: return convertDistanceForDisplayingDecimal(millimeters)
    case .short: return convertShortDistanceForDisplayingDecimal(millimeters)
    }
}

/// Converts an entered decimal distance in the unit matching `style` to storage millimeters.
func convertDistanceForStoring(
    _ value: Double, style: SetMeasurementType.DistanceStyle
) -> Int64 {
    switch style {
    case .long: return convertDistanceForStoring(value)
    case .short: return convertShortDistanceForStoring(value)
    }
}

/// The display unit string for `style` — "km"/"mi" for long distances, "m"/"yd" for short.
func distanceUnitTitle(for style: SetMeasurementType.DistanceStyle) -> String {
    switch style {
    case .long: return DistanceUnit.used.rawValue
    case .short: return DistanceUnit.used.shortUnit
    }
}

/// The full menu label for choosing `style` in the user's unit system — "Kilometers (km)" /
/// "Meters (m)", or "Miles (mi)" / "Yards (yd)".
func distanceStyleTitle(for style: SetMeasurementType.DistanceStyle) -> String {
    switch (DistanceUnit.used, style) {
    case (.km, .long): return NSLocalizedString("unitKilometers", comment: "")
    case (.km, .short): return NSLocalizedString("unitMeters", comment: "")
    case (.mi, .long): return NSLocalizedString("unitMiles", comment: "")
    case (.mi, .short): return NSLocalizedString("unitYards", comment: "")
    }
}
