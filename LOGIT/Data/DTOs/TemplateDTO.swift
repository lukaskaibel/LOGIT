//
//  TemplateDTO.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 05.10.23.
//

import Foundation

struct TemplateDTO: Codable {
    /// Format version for future compatibility
    static let formatVersion = 1
    
    let formatVersion: Int?
    let name: String
    let setGroups: [TemplateSetGroupDTO]
    
    /// App Store URL for users who don't have the app installed
    let appStoreURL: String?
    
    /// Initialize from a Core Data Template entity for sharing
    init(from template: Template) {
        self.formatVersion = Self.formatVersion
        self.name = template.name ?? ""
        self.setGroups = template.setGroups.map { TemplateSetGroupDTO(from: $0) }
        self.appStoreURL = "https://apps.apple.com/app/logit-track-your-workouts/id6444813640"
    }
    
    /// Initialize for decoding (used by AI generation and import)
    init(name: String, setGroups: [TemplateSetGroupDTO], formatVersion: Int? = nil, appStoreURL: String? = nil) {
        self.formatVersion = formatVersion
        self.name = name
        self.setGroups = setGroups
        self.appStoreURL = appStoreURL
    }
}
