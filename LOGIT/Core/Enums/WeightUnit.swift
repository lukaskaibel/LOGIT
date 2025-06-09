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

    var id: String {
        rawValue
    }
}
