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
/// - Returns: Weight in kg or lbs (for display to user) with up to 3 decimal places
public func convertWeightForDisplayingDecimal(_ value: Int64) -> Double {
    let unit = WeightUnit(rawValue: UserDefaults.standard.string(forKey: "weightUnit")!)!
    let result: Double
    switch unit {
    case .kg: result = Double(value) / KG_TO_GRAMS
    case .lbs: result = Double(value) / LBS_TO_GRAMS
    }
    // Round to 3 decimal places
    return round(result * 1000) / 1000
}

/// Converts a weight value from storage units (grams) to display units (kg or lbs)
/// - Parameter value: Weight in grams (from database)
/// - Returns: Weight in kg or lbs (for display to user) with up to 3 decimal places
public func convertWeightForDisplayingDecimal(_ value: Int) -> Double {
    return convertWeightForDisplayingDecimal(Int64(value))
}

/// Formats a weight value from storage units (grams) to a display string
/// - Parameter value: Weight in grams (from database)
/// - Returns: Formatted string with weight in kg or lbs, showing decimals only when needed
public func formatWeightForDisplay(_ value: Int64) -> String {
    let weight = convertWeightForDisplayingDecimal(value)
    if weight == 0 {
        return "0"
    }
    
    // Remove unnecessary trailing zeros
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 3
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
