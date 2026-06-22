//
//  MuscleGroup.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 18.04.22.
//

import SwiftUI

public enum MuscleGroup: String, Codable, Identifiable, CaseIterable, Comparable, Equatable {
    case chest, triceps, shoulders, biceps, back, legs, abdominals, cardio

    public var id: String { rawValue }

    var description: String {
        NSLocalizedString(rawValue, comment: "")
    }

    public static func < (lhs: MuscleGroup, rhs: MuscleGroup) -> Bool {
        return lhs.rawValue > rhs.rawValue
    }

//    var color: Color {
//        switch self {
//        case .chest: return .green
//        case .triceps: return .yellow
//        case .shoulders: return .orange
//        case .biceps: return .mint
//        case .back: return .blue
//        case .legs: return .pink
//        case .abdominals: return .brown
//        case .cardio: return .gray
//        }
//    }

//    var color: Color {
//        switch self {
//        case .chest: return Color(red: 227 / 255.0, green: 227 / 255.0, blue: 227 / 255.0)
//        case .triceps: return Color(red: 198 / 255.0, green: 198 / 255.0, blue: 198 / 255.0)
//        case .shoulders: return Color(red: 170 / 255.0, green: 170 / 255.0, blue: 170 / 255.0)
//        case .biceps: return Color(red: 142 / 255.0, green: 142 / 255.0, blue: 142 / 255.0)
//        case .back: return Color(red: 113 / 255.0, green: 113 / 255.0, blue: 113 / 255.0)
//        case .legs: return Color(red: 85 / 255.0, green: 85 / 255.0, blue: 85 / 255.0)
//        case .abdominals: return Color(red: 57 / 255.0, green: 57 / 255.0, blue: 57 / 255.0)
//        case .cardio: return Color(red: 28 / 255.0, green: 28 / 255.0, blue: 28 / 255.0)
//        }
//    }

    var color: Color {
        switch self {
        case .chest: return Color(red: 166 / 255.0, green: 206 / 255.0, blue: 134 / 255.0) // Soft green
        case .triceps: return Color(red: 132 / 255.0, green: 190 / 255.0, blue: 232 / 255.0) // Sky blue
        case .shoulders: return Color(red: 240 / 255.0, green: 176 / 255.0, blue: 128 / 255.0) // Apricot
        case .biceps: return Color(red: 118 / 255.0, green: 207 / 255.0, blue: 192 / 255.0) // Teal
        case .back: return Color(red: 142 / 255.0, green: 150 / 255.0, blue: 222 / 255.0) // Periwinkle
        case .legs: return Color(red: 230 / 255.0, green: 202 / 255.0, blue: 114 / 255.0) // Gold
        case .abdominals: return Color(red: 168 / 255.0, green: 146 / 255.0, blue: 214 / 255.0) // Soft violet
        case .cardio: return Color(red: 224 / 255.0, green: 138 / 255.0, blue: 166 / 255.0) // Rose
        }
    }
}
