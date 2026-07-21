//
//  DistanceConverting.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 21.07.26.
//

import Foundation

private let KM_TO_METERS: Double = 1000.0
private let MI_TO_METERS: Double = 1609.344
private let YD_TO_METERS: Double = 0.9144

// MARK: - Long Distances (km/mi, decimal — cardio-scale)

/// Converts a distance from display units (km or mi) to storage units (meters).
/// - Parameter value: Distance in km or mi (as displayed to user)
/// - Returns: Distance in meters (for storage in database)
public func convertDistanceForStoring(_ value: Double) -> Int64 {
    switch DistanceUnit.used {
    case .km: return Int64(round(value * KM_TO_METERS))
    case .mi: return Int64(round(value * MI_TO_METERS))
    }
}

/// Converts a distance from storage units (meters) to display units (km or mi)
/// with up to 2 decimal places.
public func convertDistanceForDisplayingDecimal(_ value: Int64) -> Double {
    let result: Double
    switch DistanceUnit.used {
    case .km: result = Double(value) / KM_TO_METERS
    case .mi: result = Double(value) / MI_TO_METERS
    }
    return round(result * 100) / 100
}

/// Formats a distance from storage units (meters) to a display string in km or mi,
/// showing decimals only when needed.
public func formatDistanceForDisplay(_ value: Int64) -> String {
    let distance = convertDistanceForDisplayingDecimal(value)
    if distance == 0 {
        return "0"
    }

    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2
    formatter.decimalSeparator = "."
    formatter.groupingSeparator = ""

    return formatter.string(from: NSNumber(value: distance)) ?? "0"
}

public func formatDistanceForDisplay(_ value: Int) -> String {
    formatDistanceForDisplay(Int64(value))
}

// MARK: - Short Distances (m/yd, whole numbers — carry-scale)

/// Converts a short distance from display units (m or yd) to storage units (meters).
public func convertShortDistanceForStoring(_ value: Int64) -> Int64 {
    switch DistanceUnit.used {
    case .km: return value
    case .mi: return Int64(round(Double(value) * YD_TO_METERS))
    }
}

/// Converts a short distance from storage units (meters) to display units (m or yd).
public func convertShortDistanceForDisplaying(_ value: Int64) -> Int64 {
    switch DistanceUnit.used {
    case .km: return value
    case .mi: return Int64(round(Double(value) / YD_TO_METERS))
    }
}

// MARK: - Style Dispatch

/// Formats a stored distance (meters) for display in the unit matching `style` — long
/// distances in km/mi with decimals, short ones as whole m/yd. The single entry point for
/// read-only distance text (history rows, badges, Live Activity), so every surface agrees.
func formatDistanceForDisplay(
    _ value: Int64, style: SetMeasurementType.DistanceStyle
) -> String {
    switch style {
    case .long: return formatDistanceForDisplay(value)
    case .short: return String(convertShortDistanceForDisplaying(value))
    }
}

/// The display unit string for `style` — "km"/"mi" for long distances, "m"/"yd" for short.
func distanceUnitTitle(for style: SetMeasurementType.DistanceStyle) -> String {
    switch style {
    case .long: return DistanceUnit.used.rawValue
    case .short: return DistanceUnit.used.shortUnit
    }
}
