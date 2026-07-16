// Generates a legacy (model v7) LOGIT SQLite store used as the migration-test fixture.
// Run on macOS: swift make_v7_fixture.swift <path to "LOGIT 7.0.mom"> <output .sqlite>
//
// Runs in its own process on purpose: the app's NSManagedObject subclasses don't exist here,
// so loading the v7 model can never register competing entity->class claims in the test
// process (the +entity ambiguity / Core Data 134020 hazard).
//
// Everything is written via KVC with deterministic UUIDs so the XCTest side can address every
// object individually.

import CoreData
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fatalError("Usage: swift make_v7_fixture.swift <LOGIT 7.0.mom> <output.sqlite>")
}
let momURL = URL(fileURLWithPath: arguments[1])
let outURL = URL(fileURLWithPath: arguments[2])

guard let model = NSManagedObjectModel(contentsOf: momURL) else {
    fatalError("Could not load model at \(momURL.path)")
}
guard !model.entities.contains(where: { $0.name == "SetEntry" }) else {
    fatalError("Model contains SetEntry — this is not the v7 model")
}

try? FileManager.default.removeItem(at: outURL)
let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
try coordinator.addPersistentStore(
    ofType: NSSQLiteStoreType,
    configurationName: nil,
    at: outURL,
    // Single-file store: no -wal/-shm sidecars to ship as test resources.
    options: [NSSQLitePragmasOption: ["journal_mode": "DELETE"]]
)
let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
context.persistentStoreCoordinator = coordinator

func uuid(_ suffix: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
}

func insert(_ entityName: String, id: Int) -> NSManagedObject {
    let object = NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
    object.setValue(uuid(id), forKey: "id")
    return object
}

// MARK: - Exercises

let benchPress = insert("Exercise", id: 1)
benchPress.setValue("Bench Press", forKey: "name")
benchPress.setValue("chest", forKey: "muscleGroupString")

let cableFly = insert("Exercise", id: 2)
cableFly.setValue("Cable Fly", forKey: "name")
cableFly.setValue("chest", forKey: "muscleGroupString")

let squat = insert("Exercise", id: 3)
squat.setValue("Squat", forKey: "name")
squat.setValue("legs", forKey: "muscleGroupString")

// MARK: - Workout

let workout = insert("Workout", id: 10)
workout.setValue("Push Day Legacy", forKey: "name")
workout.setValue(Date(timeIntervalSince1970: 1_780_315_200), forKey: "date") // 2026-06-01 UTC
workout.setValue([uuid(11), uuid(12), uuid(13), uuid(14)], forKey: "setGroupOrder")

func makeSetGroup(id: Int, exercises: [NSManagedObject], setIds: [Int]) -> NSManagedObject {
    let group = insert("WorkoutSetGroup", id: id)
    group.setValue(workout, forKey: "workout")
    group.setValue(NSSet(array: exercises), forKey: "exercises_")
    group.setValue(exercises.map { $0.value(forKey: "id") as! UUID }, forKey: "exerciseOrder")
    group.setValue(setIds.map { uuid($0) }, forKey: "setOrder")
    return group
}

// G1: standard sets on Bench Press
let group1 = makeSetGroup(id: 11, exercises: [benchPress], setIds: [21, 22, 23])
let standard1 = insert("StandardSet", id: 21)
standard1.setValue(Int64(12), forKey: "repetitions")
standard1.setValue(Int64(80000), forKey: "weight")
standard1.setValue(Int64(90), forKey: "restDuration")
standard1.setValue(group1, forKey: "setGroup")
let standard2 = insert("StandardSet", id: 22) // untouched placeholder set
standard2.setValue(Int64(0), forKey: "repetitions")
standard2.setValue(Int64(0), forKey: "weight")
standard2.setValue(group1, forKey: "setGroup")
let standard3 = insert("StandardSet", id: 23)
standard3.setValue(Int64(8), forKey: "repetitions")
standard3.setValue(Int64(102_500), forKey: "weight")
standard3.setValue(group1, forKey: "setGroup")

// G2: drop sets on Squat, including malformed array shapes
let group2 = makeSetGroup(id: 12, exercises: [squat], setIds: [31, 32, 33, 34, 35])
let drop1 = insert("DropSet", id: 31)
drop1.setValue([Int64(10), Int64(8), Int64(6)], forKey: "repetitions")
drop1.setValue([Int64(140_000), Int64(120_000), Int64(100_000)], forKey: "weights")
drop1.setValue(Int64(120), forKey: "restDuration")
drop1.setValue(group2, forKey: "setGroup")
let drop2 = insert("DropSet", id: 32) // desynced: more reps than weights
drop2.setValue([Int64(10), Int64(8)], forKey: "repetitions")
drop2.setValue([Int64(60000)], forKey: "weights")
drop2.setValue(group2, forKey: "setGroup")
let drop3 = insert("DropSet", id: 33) // desynced: more weights than reps
drop3.setValue([Int64(12)], forKey: "repetitions")
drop3.setValue([Int64(50000), Int64(40000)], forKey: "weights")
drop3.setValue(group2, forKey: "setGroup")
let drop4 = insert("DropSet", id: 34) // nil arrays
drop4.setValue(group2, forKey: "setGroup")
let drop5 = insert("DropSet", id: 35) // empty arrays
drop5.setValue([Int64](), forKey: "repetitions")
drop5.setValue([Int64](), forKey: "weights")
drop5.setValue(group2, forKey: "setGroup")

// G3: super sets on Bench Press + Cable Fly
let group3 = makeSetGroup(id: 13, exercises: [benchPress, cableFly], setIds: [41, 42])
let superSet1 = insert("SuperSet", id: 41)
superSet1.setValue(Int64(10), forKey: "repetitionsFirstExercise")
superSet1.setValue(Int64(80000), forKey: "weightFirstExercise")
superSet1.setValue(Int64(12), forKey: "repetitionsSecondExercise")
superSet1.setValue(Int64(25000), forKey: "weightSecondExercise")
superSet1.setValue(Int64(180), forKey: "restDuration")
superSet1.setValue(group3, forKey: "setGroup")
let superSet2 = insert("SuperSet", id: 42) // untouched placeholder super set
superSet2.setValue(group3, forKey: "setGroup")

// G4: super set whose group lost its secondary exercise, values in second slot anyway
let group4 = makeSetGroup(id: 14, exercises: [cableFly], setIds: [43])
let superSet3 = insert("SuperSet", id: 43)
superSet3.setValue(Int64(8), forKey: "repetitionsFirstExercise")
superSet3.setValue(Int64(30000), forKey: "weightFirstExercise")
superSet3.setValue(Int64(15), forKey: "repetitionsSecondExercise")
superSet3.setValue(Int64(10000), forKey: "weightSecondExercise")
superSet3.setValue(group4, forKey: "setGroup")

// Orphan sets: no set group at all
let orphanStandard = insert("StandardSet", id: 51)
orphanStandard.setValue(Int64(5), forKey: "repetitions")
orphanStandard.setValue(Int64(200_000), forKey: "weight")
let orphanDrop = insert("DropSet", id: 52)
orphanDrop.setValue([Int64(3), Int64(2)], forKey: "repetitions")
orphanDrop.setValue([Int64(180_000), Int64(190_000)], forKey: "weights")

// Exercise -> set group order lists (kept realistic; the app maintains these)
benchPress.setValue([uuid(11), uuid(13)], forKey: "setGroupOrder")
cableFly.setValue([uuid(13), uuid(14)], forKey: "setGroupOrder")
squat.setValue([uuid(12)], forKey: "setGroupOrder")

// MARK: - Template

let template = insert("Template", id: 60)
template.setValue("Push Template Legacy", forKey: "name")
template.setValue(Date(timeIntervalSince1970: 1_780_000_000), forKey: "creationDate")
template.setValue([uuid(61), uuid(62), uuid(63)], forKey: "templateSetGroupOrder")

func makeTemplateSetGroup(id: Int, exercises: [NSManagedObject], setIds: [Int]) -> NSManagedObject {
    let group = insert("TemplateSetGroup", id: id)
    group.setValue(template, forKey: "workout")
    group.setValue(NSSet(array: exercises), forKey: "exercises_")
    group.setValue(exercises.map { $0.value(forKey: "id") as! UUID }, forKey: "exerciseOrder")
    group.setValue(setIds.map { uuid($0) }, forKey: "setOrder")
    return group
}

let templateGroup1 = makeTemplateSetGroup(id: 61, exercises: [benchPress], setIds: [71])
let templateStandard = insert("TemplateStandardSet", id: 71)
templateStandard.setValue(Int64(10), forKey: "repetitions")
templateStandard.setValue(Int64(77500), forKey: "weight")
templateStandard.setValue(Int64(60), forKey: "restDuration")
templateStandard.setValue(templateGroup1, forKey: "setGroup")

let templateGroup2 = makeTemplateSetGroup(id: 62, exercises: [squat], setIds: [72])
let templateDrop = insert("TemplateDropSet", id: 72) // desynced arrays, template side
templateDrop.setValue([Int64(9), Int64(7)], forKey: "repetitions")
templateDrop.setValue([Int64(130_000)], forKey: "weights")
templateDrop.setValue(templateGroup2, forKey: "setGroup")

let templateGroup3 = makeTemplateSetGroup(id: 63, exercises: [benchPress, cableFly], setIds: [73])
let templateSuper = insert("TemplateSuperSet", id: 73)
templateSuper.setValue(Int64(8), forKey: "repetitionsFirstExercise")
templateSuper.setValue(Int64(70000), forKey: "weightFirstExercise")
templateSuper.setValue(Int64(10), forKey: "repetitionsSecondExercise")
templateSuper.setValue(Int64(20000), forKey: "weightSecondExercise")
templateSuper.setValue(templateGroup3, forKey: "setGroup")

benchPress.setValue([uuid(61), uuid(63)], forKey: "templateSetGroupOrder")
cableFly.setValue([uuid(63)], forKey: "templateSetGroupOrder")
squat.setValue([uuid(62)], forKey: "templateSetGroupOrder")

try context.save()

// Sanity counts before shipping the fixture.
func count(_ entityName: String) -> Int {
    let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
    return (try? context.count(for: request)) ?? -1
}
assert(count("StandardSet") == 4)
assert(count("DropSet") == 6)
assert(count("SuperSet") == 3)
assert(count("WorkoutSet") == 13)
assert(count("TemplateSet") == 3)
assert(count("Exercise") == 3)
print("Fixture written to \(outURL.path)")
print("WorkoutSets: \(count("WorkoutSet")), TemplateSets: \(count("TemplateSet"))")
