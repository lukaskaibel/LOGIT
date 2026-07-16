//
//  TemplateDTO.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 05.10.23.
//

import Foundation

struct TemplateDTO: Codable {
    /// Format version for future compatibility. Version 2 added per-set `entries` (measurement
    /// types, durations); the legacy per-type fields stay populated so version-1 receivers can
    /// still import the reps-and-weight portion.
    static let formatVersion = 2
    
    let formatVersion: Int?
    let name: String
    /// Optional template description (added in app version 7 files; absent in older ones)
    let description: String?
    let setGroups: [TemplateSetGroupDTO]

    /// App Store URL for users who don't have the app installed
    let appStoreURL: String?

    /// Initialize from a Core Data Template entity for sharing.
    /// Exports the resolved (localized) name and description, not `_default.` keys, so
    /// receivers on older app versions still see readable text.
    init(from template: Template) {
        self.formatVersion = Self.formatVersion
        self.name = template.resolvedName ?? ""
        self.description = template.displayDescription
        self.setGroups = template.setGroups.map { TemplateSetGroupDTO(from: $0) }
        self.appStoreURL = "https://apps.apple.com/app/logit-track-your-workouts/id6444813640"
    }

    /// Initialize for decoding (used by AI generation and import)
    init(name: String, setGroups: [TemplateSetGroupDTO], formatVersion: Int? = nil, appStoreURL: String? = nil, description: String? = nil) {
        self.formatVersion = formatVersion
        self.name = name
        self.description = description
        self.setGroups = setGroups
        self.appStoreURL = appStoreURL
    }
}
