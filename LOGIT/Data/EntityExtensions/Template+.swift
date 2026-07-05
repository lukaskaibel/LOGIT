//
//  Template+.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 02.04.22.
//

import Foundation
import Ifrit

// MARK: - Fuzzy Search Properties

extension Template {
    var searchProperties: [FuseProp] {
        var props: [FuseProp] = []
        if let name = resolvedName {
            props.append(FuseProp(name, weight: 1.0))
        }
        let exerciseNames = exercises.compactMap { $0.displayName }.joined(separator: " ")
        if !exerciseNames.isEmpty {
            props.append(FuseProp(exerciseNames, weight: 0.5))
        }
        return props.isEmpty ? [FuseProp("")] : props
    }
}

// MARK: - Template Extension

extension Template {
    /// `name` with `_default.` localization keys resolved (bundled templates store the key, not
    /// a language-specific string, so every device shows its own language). Preserves nil and
    /// empty names — use this wherever `template.name` used to be read directly.
    var resolvedName: String? {
        guard let name = name else { return nil }
        return name.hasPrefix("_default.") ? NSLocalizedString(name, comment: "") : name
    }

    /// The name to render in cells and headers, mirroring `Exercise.displayName`.
    var displayName: String {
        guard let resolvedName = resolvedName, !resolvedName.isEmpty else {
            return NSLocalizedString("noName", comment: "")
        }
        return resolvedName
    }

    var isDefaultTemplate: Bool {
        name?.hasPrefix("_default.") ?? false
    }

    /// Localized description for display, or nil when there is none. Bundled templates store a
    /// `_default.` localization key in `descriptionText`; user descriptions are literal text.
    var displayDescription: String? {
        guard let descriptionText = descriptionText, !descriptionText.isEmpty else { return nil }
        return descriptionText.hasPrefix("_default.")
            ? NSLocalizedString(descriptionText, comment: "")
            : descriptionText
    }

    var workouts: [Workout] {
        get {
            (workouts_?.allObjects as? [Workout] ?? .emptyList)
                .sorted {
                    $0.date ?? .now < $1.date ?? .now
                }
        }
        set {
            workouts_ = NSSet(array: newValue)
        }
    }

    var lastUsed: Date? {
        return workouts.last?.date
    }

    var sets: [TemplateSet] {
        var result = [TemplateSet]()
        for setGroup in setGroups {
            result.append(contentsOf: setGroup.sets)
        }
        return result
    }

    var setGroups: [TemplateSetGroup] {
        get {
            return (templateSetGroupOrder ?? .emptyList)
                .compactMap { id in
                    (setGroups_?.allObjects as? [TemplateSetGroup])?
                        .first { templateSetGroup in
                            templateSetGroup.id == id
                        }
                }
        }
        set {
            templateSetGroupOrder = newValue.map { $0.id! }
            setGroups_ = NSSet(array: newValue)
        }
    }

    var numberOfSetGroups: Int {
        setGroups.count
    }

    var exercises: [Exercise] {
        var result = [Exercise]()
        for setGroup in setGroups {
            if let exercise = setGroup.exercise {
                result.append(exercise)
            }
            if setGroup.setType == .superSet, let secondaryExercise = setGroup.secondaryExercise {
                result.append(secondaryExercise)
            }
        }
        return result
    }

    func index(of templateSetGroup: TemplateSetGroup) -> Int? {
        setGroups.firstIndex(of: templateSetGroup)
    }

    var muscleGroups: [MuscleGroup] {
        let uniqueMuscleGroups = Array(Set(exercises.compactMap { $0.muscleGroup }))
        return uniqueMuscleGroups.sorted {
            guard let leftIndex = MuscleGroup.allCases.firstIndex(of: $0),
                  let rightIndex = MuscleGroup.allCases.firstIndex(of: $1)
            else {
                return false
            }
            return leftIndex < rightIndex
        }
    }
}
