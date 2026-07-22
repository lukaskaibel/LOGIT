//
//  WeightConverting.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 02.10.23.
//

import Foundation

private let KG_TO_GRAMS: Double = 1000.0
private let LBS_TO_GRAMS: Double = 453.592

// MARK: - Legacy Integer Functions (for backward compatibility)

public func convertWeightForStoring(_ value: Int64) -> Int64 {
    let unit = WeightUnit(rawValue: UserDefaults.standard.string(forKey: "weightUnit")!)!
    switch unit {
    case .kg: return value * Int64(KG_TO_GRAMS)
    case .lbs: return Int64(Double(value) * LBS_TO_GRAMS)
    }
}

public func convertWeightForDisplaying(_ value: Int64) -> Int {
    let unit = WeightUnit(rawValue: UserDefaults.standard.string(forKey: "weightUnit")!)!
    switch unit {
    case .kg: return Int(round(Double(value) / KG_TO_GRAMS))
    case .lbs: return Int(round(Double(value) / LBS_TO_GRAMS))
    }
}

public func convertWeightForDisplaying(_ value: Int) -> Int {
    let unit = WeightUnit(rawValue: UserDefaults.standard.string(forKey: "weightUnit")!)!
    switch unit {
    case .kg: return Int(round(Double(value) / KG_TO_GRAMS))
    case .lbs: return Int(round(Double(value) / LBS_TO_GRAMS))
    }
}

// MARK: - Decimal Functions (for precise weight input/display)

/// Converts a weight value from display units (kg or lbs) to storage units (grams)
/// - Parameter value: Weight in kg or lbs (as displayed to user)
/// - Returns: Weight in grams (for storage in database)
public func convertWeightForStoring(_ value: Double) -> Int64 {
    let unit = WeightUnit(rawValue: UserDefaults.standard.string(forKey: "weightUnit")!)!
    switch unit {
    case .kg: return Int64(round(value * KG_TO_GRAMS))
    case .lbs: return Int64(round(value * LBS_TO_GRAMS))
    }
}

/// Converts a weight value from storage units (grams) to display units (kg or lbs)
/// - Parameter value: Weight in grams (from database)
/// - Returns: Weight in kg (up to 3 decimal places) or lbs (up to 2 decimal places)
public func convertWeightForDisplayingDecimal(_ value: Int64) -> Double {
    let unit = WeightUnit(rawValue: UserDefaults.standard.string(forKey: "weightUnit")!)!
    switch unit {
    case .kg:
        // Grams represent kilograms to exactly 3 decimal places.
        return round(Double(value) / KG_TO_GRAMS * 1000) / 1000
    case .lbs:
        // 1 g ≈ 0.0022 lbs, so a third decimal place is below the storage resolution:
        // 95 lbs stores as 43091 g, which reads back as 94.99947 and would show as
        // 94.999 at 3 decimals. At 2 decimals every entered value round-trips exactly
        // (max storage error 0.5 g ≈ 0.0011 lbs < 0.005).
        return round(Double(value) / LBS_TO_GRAMS * 100) / 100
    }
}

/// Converts a weight value from storage units (grams) to display units (kg or lbs)
/// - Parameter value: Weight in grams (from database)
/// - Returns: Weight in kg (up to 3 decimal places) or lbs (up to 2 decimal places)
public func convertWeightForDisplayingDecimal(_ value: Int) -> Double {
    return convertWeightForDisplayingDecimal(Int64(value))
}

/// Formats a weight value from storage units (grams) to a display string
/// - Parameter value: Weight in grams (from database)
/// - Returns: Formatted string with weight in kg or lbs, showing decimals only when needed
///
/// Fraction digits match what integer-gram storage can round-trip (3 in kg, 2 in lbs) so
/// gram-rounding noise never surfaces — at 3 lbs digits an entered 162.5 lbs printed as
/// "162.501" (the reported rounding artifact).
public func formatWeightForDisplay(_ value: Int64) -> String {
    let weight = convertWeightForDisplayingDecimal(value)
    if weight == 0 {
        return "0"
    }

    // Remove unnecessary trailing zeros
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = WeightUnit.used == .kg ? 3 : 2
    formatter.roundingMode = .halfUp
    formatter.decimalSeparator = "."
    formatter.groupingSeparator = ""

    return formatter.string(from: NSNumber(value: weight)) ?? "0"
}

/// Formats a weight value from storage units (grams) to a display string
/// - Parameter value: Weight in grams (from database)
/// - Returns: Formatted string with weight in kg or lbs, showing decimals only when needed
public func formatWeightForDisplay(_ value: Int) -> String {
    return formatWeightForDisplay(Int64(value))
}

/// Formats an estimated 1RM (stored in grams) as a clean, whole-number display string.
/// e1RM is a calculated estimate, so it is rounded to the nearest whole display unit
/// rather than carrying the fractional noise the Epley formula produces.
/// - Parameter grams: Estimated 1RM in grams
/// - Returns: Whole-number string in the user's weight unit (kg or lbs)
public func formatEstimatedOneRepMax(_ grams: Int) -> String {
    return String(Int(convertWeightForDisplayingDecimal(grams).rounded()))
}
