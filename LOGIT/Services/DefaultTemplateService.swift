//
//  DefaultTemplateService.swift
//  LOGIT
//

import Combine
import CoreData
import Foundation
import OSLog

struct DefaultTemplateData: Codable {
    let version: Int
    let templates: [DefaultTemplate]
}

struct DefaultTemplate: Codable {
    let id: String
    let nameKey: String
    let descriptionKey: String
    let setGroups: [DefaultTemplateSetGroup]
}

struct DefaultTemplateSetGroup: Codable {
    let exerciseId: String
    let sets: Int
    let repetitions: Int
    let restDuration: Int
}

/// Seeds the bundled starter templates (push/pull/legs, full body) so first-time users have
/// ready-made workouts to pick from.
///
/// Unlike `DefaultExerciseService`, which re-applies the bundled data on every version bump,
/// templates are starting points the user is expected to edit — so each template is created at
/// most once. `seededTemplateIdsKey` remembers every id that was ever seeded: a template the
/// user deleted stays deleted, and one the user edited or renamed is never touched again. A
/// future JSON version bump therefore only adds templates that are new to the file.
class DefaultTemplateService: ObservableObject {
    private let database: Database
    private let defaults: UserDefaults
    private let lastLoadedVersionKey = "lastLoadedDefaultTemplatesVersion"
    private let seededTemplateIdsKey = "seededDefaultTemplateIds"

    init(database: Database, defaults: UserDefaults = .standard) {
        self.database = database
        self.defaults = defaults
    }

    /// Must run after `DefaultExerciseService.loadDefaultExercisesIfNeeded()` — the templates
    /// reference default exercises by id and a template is skipped when one is missing.
    func loadDefaultTemplatesIfNeeded() {
        backfillMissingTemplateIds()

        guard let url = Bundle.main.url(forResource: "default_templates", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let templateData = try? JSONDecoder().decode(DefaultTemplateData.self, from: data) else {
            os_log("DefaultTemplateService: Failed to load default templates JSON", type: .error)
            return
        }

        guard templateData.version > defaults.integer(forKey: lastLoadedVersionKey) else { return }

        var seededIds = defaults.stringArray(forKey: seededTemplateIdsKey) ?? []
        var didSeedAll = true
        for template in templateData.templates {
            guard !seededIds.contains(template.id) else { continue }
            if fetchTemplateByDefaultId(template.id) != nil {
                // Already present without a local seeding record — e.g. synced in from
                // another device. Record it so it can't be seeded twice.
                seededIds.append(template.id)
                continue
            }
            if createDefaultTemplate(template) {
                seededIds.append(template.id)
            } else {
                didSeedAll = false
            }
        }

        defaults.set(seededIds, forKey: seededTemplateIdsKey)
        // Only advance the version once every template made it in, so a template that was
        // skipped (its exercises weren't seeded yet) gets another chance on the next launch.
        if didSeedAll {
            defaults.set(templateData.version, forKey: lastLoadedVersionKey)
        }
        database.save()
        os_log("DefaultTemplateService: Loaded default templates version %d", type: .info, templateData.version)
    }

    /// The `id` attribute arrived with model version 7, so templates created before it carry
    /// nil. Everything else identifies templates by objectID, but nil ids would make future
    /// id-based features (sharing, dedup) silently misbehave — assign one wherever it's missing.
    private func backfillMissingTemplateIds() {
        let request = Template.fetchRequest()
        request.predicate = NSPredicate(format: "id == nil")
        guard let templates = try? database.context.fetch(request), !templates.isEmpty else { return }
        for template in templates {
            template.id = UUID()
        }
        database.save()
    }

    /// Creates the template with all set groups, or leaves the store untouched and returns
    /// false when a referenced exercise is missing — half a template is worse than none.
    private func createDefaultTemplate(_ templateData: DefaultTemplate) -> Bool {
        var exercises = [Exercise]()
        for setGroupData in templateData.setGroups {
            guard let exercise = fetchExerciseByDefaultId(setGroupData.exerciseId) else {
                os_log(
                    "DefaultTemplateService: Missing default exercise %{public}@ — skipping template %{public}@",
                    type: .error, setGroupData.exerciseId, templateData.id
                )
                return false
            }
            exercises.append(exercise)
        }

        let template = database.newTemplate(name: templateData.nameKey)
        template.id = DeterministicUUID.make(namespace: "com.logit.defaulttemplate", id: templateData.id)
        template.descriptionText = templateData.descriptionKey
        for (setGroupData, exercise) in zip(templateData.setGroups, exercises) {
            let setGroup = database.newTemplateSetGroup(
                createFirstSetAutomatically: false,
                exercise: exercise,
                template: template
            )
            for _ in 0..<setGroupData.sets {
                database.newTemplateStandardSet(
                    repetitions: setGroupData.repetitions,
                    weight: 0,
                    restDuration: setGroupData.restDuration,
                    setGroup: setGroup
                )
            }
        }
        return true
    }

    private func fetchTemplateByDefaultId(_ defaultId: String) -> Template? {
        let uuid = DeterministicUUID.make(namespace: "com.logit.defaulttemplate", id: defaultId)
        let request = Template.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        request.fetchLimit = 1
        return (try? database.context.fetch(request))?.first
    }

    private func fetchExerciseByDefaultId(_ defaultId: String) -> Exercise? {
        let uuid = DeterministicUUID.make(namespace: "com.logit.defaultexercise", id: defaultId)
        let request = Exercise.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        request.fetchLimit = 1
        return (try? database.context.fetch(request))?.first
    }
}
