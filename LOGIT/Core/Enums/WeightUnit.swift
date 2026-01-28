//
//  WeightUnit.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 15.03.22.
//

import Foundation

enum WeightUnit: String, Codable, Identifiable {
    case kg, lbs

    static var used: WeightUnit {
        WeightUnit(rawValue: UserDefaults.standard.string(forKey: "weightUnit")!)!
    }
    
    /// Returns the appropriate weight unit based on user's locale.
    /// Returns .lbs for US measurement system, .kg for metric.
    static var defaultFromLocale: WeightUnit {
        Locale.current.measurementSystem == .us ? .lbs : .kg
    }

    var id: String {
        rawValue
    }
}
