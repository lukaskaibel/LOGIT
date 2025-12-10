//
//  PinnedExerciseTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 30.11.24.
//

import Foundation

enum ExerciseTileType: String, Codable, CaseIterable {
    case weight
    case repetitions
    case volume
    
    var title: String {
        switch self {
        case .weight: return NSLocalizedString("weight", comment: "")
        case .repetitions: return NSLocalizedString("repetitions", comment: "")
        case .volume: return NSLocalizedString("volume", comment: "")
        }
    }
}

struct PinnedExerciseTile: Codable, Equatable, Hashable, Identifiable {
    let exerciseID: UUID
    let tileType: ExerciseTileType
    
    var id: String {
        "\(exerciseID.uuidString)-\(tileType.rawValue)"
    }
    
    init(exerciseID: UUID, tileType: ExerciseTileType) {
        self.exerciseID = exerciseID
        self.tileType = tileType
    }
}
