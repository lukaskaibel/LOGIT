//
//  SetEntryFieldsRow.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 16.07.26.
//

import CoreData
import SwiftUI

/// Both entry entities expose the same editable fields, so one row view serves the workout
/// recorder and the template editor.
protocol SetEntryFieldsEditable: NSManagedObject, ObservableObject {
    var repetitions: Int64 { get set }
    var weight: Int64 { get set }
    /// Milliseconds, and millimeters — the fine-grained units both entry entities store since
    /// model v11. The fields below enter them in whichever spelling the exercise asks for:
    /// decimal seconds or a clock, decimal km or whole m.
    var durationMs: Int64 { get set }
    var distanceMm: Int64 { get set }
    var type: SetMeasurementType { get }
    /// The exercise the entry trains — decides both per-exercise spellings: the distance scale
    /// (km vs m) and the duration format (seconds vs clock).
    var exercise: Exercise? { get }
}

extension SetEntry: SetEntryFieldsEditable {}
extension TemplateSetEntry: SetEntryFieldsEditable {}

/// The keyboard accessory's ± — the number pad has no minus key, and assistance is stored as a
/// negative weight, so this is the only way to type one.
///
/// A view of its own because it has to *observe* the set: flipping the sign mutates entries rather
/// than the set, and without something watching, the button would change the weights and go on
/// drawing itself un-latched.
struct KeyboardAssistedButton: View {
    @ObservedObject var workoutSet: WorkoutSet

    var body: some View {
        KeyboardToolbarIconButton(
            systemImage: workoutSet.isAssisted ? "plusminus.circle.fill" : "plusminus.circle",
            accessibilityLabel: NSLocalizedString("assisted", comment: ""),
            isOn: workoutSet.isAssisted
        ) {
            withAnimation(.interactiveSpring()) {
                workoutSet.setAssisted(!workoutSet.isAssisted)
                // The entries changed, not the set — the cells need telling, exactly as the set's
                // own context-menu toggle does.
                workoutSet.objectWillChange.send()
                workoutSet.setGroup?.objectWillChange.send()
            }
        }
        .accessibilityIdentifier("keyboardAssisted")
    }
}

// MARK: - Keyboard field navigation

/// A set the keyboard's Next button can walk: its identity and the entries it lays out.
/// Workouts and templates render the same rows, so they navigate by the same rules.
protocol SetFieldNavigable {
    var id: UUID? { get }
    var entryValues: [SetEntryValues] { get }
}

extension WorkoutSet: SetFieldNavigable {}
extension TemplateSet: SetFieldNavigable {}

/// Where the keyboard's Next button goes, in the order a set is actually typed: across the
/// entry's own fields first (reps, then weight), then on to the set's next entry — a drop, or
/// the other half of a superset, which is the next thing performed — and only then to the next
/// set. `SetEntryFieldsRow` decides which field a position means; this decides the order.
enum SetFieldNavigation {
    /// The field after `index`, or nil at the last field of the last set.
    static func index<S: SetFieldNavigable>(
        after index: IntegerField.Index,
        in sets: [S]
    ) -> IntegerField.Index? {
        guard let position = sets.firstIndex(where: { $0.id == index.setID }) else { return nil }
        let entries = sets[position].entryValues
        if let type = entries.value(at: index.secondary)?.type,
           index.tertiary + 1 < type.inputFieldCount
        {
            return IntegerField.Index(
                setID: index.setID, secondary: index.secondary, tertiary: index.tertiary + 1
            )
        }
        if index.secondary + 1 < entries.count {
            return IntegerField.Index(
                setID: index.setID, secondary: index.secondary + 1, tertiary: 0
            )
        }
        guard let nextSetID = sets.value(at: position + 1)?.id else { return nil }
        return IntegerField.Index(setID: nextSetID, secondary: 0, tertiary: 0)
    }
}

/// One set entry's input fields, laid out by the entry's measurement type:
/// reps+weight, reps only, duration, weight+duration, distance, distance+duration, or
/// weight+distance. This is the single row every set cell — standard, drop, super, workout
/// or template — renders per entry.
///
/// The focus index is (set id, entry position, field position); field positions must
/// stay consistent with `SetMeasurementType.inputFieldCount`, which `SetFieldNavigation`
/// walks when the keyboard's Next button advances the focus.
struct SetEntryFieldsRow<Entry: SetEntryFieldsEditable>: View {
    @ObservedObject var entry: Entry
    let setID: UUID
    let secondaryIndex: Int
    @Binding var focusedIntegerFieldIndex: IntegerField.Index?
    /// Like-for-like entry from the reference set (same position in the previous workout).
    /// Callers pass nil when the types don't match — a one-off timed set must not be compared
    /// against a reps entry.
    var reference: SetEntryValues? = nil
    /// The planned entry from the workout's template, shown as field placeholders.
    var placeholder: SetEntryValues? = nil
    /// Whether the set group this row belongs to is being trained with assistance. Last resort
    /// for the sign of a typed weight, after the entry's own value, the template's plan and last
    /// session's — it is what carries the sign into a set added *after* the group was marked.
    var entersAssistance: Bool = false
    var trendColor: Color = .accentColor
    var onTapPreviousValue: (() -> Void)? = nil

    var body: some View {
        HStack {
            Spacer()
            // The distance scale (km vs m) is a property of the entry's *exercise*, so the
            // fields must re-render when the exercise changes — flipping the unit in a
            // Measurement menu mutates the exercise, never the entry itself.
            if let exercise = entry.exercise {
                ExerciseObservingFields(row: self, exercise: exercise)
            } else {
                fields
            }
        }
    }

    @ViewBuilder
    fileprivate var fields: some View {
        switch entry.type {
        case .repsAndWeight:
            repetitionsField(tertiary: 0)
            weightField(tertiary: 1)
        case .repsOnly:
            repetitionsField(tertiary: 0)
        case .duration:
            durationField(tertiary: 0)
        case .weightAndDuration:
            weightField(tertiary: 0)
            durationField(tertiary: 1)
        case .distance:
            distanceField(tertiary: 0)
        case .distanceAndDuration:
            distanceField(tertiary: 0)
            // No trend on the duration beside a distance: a longer time for the same run
            // is worse, not better — only the distance carries the comparison.
            durationField(tertiary: 1, showsTrend: false)
        case .weightAndDistance:
            weightField(tertiary: 0)
            distanceField(tertiary: 1)
        }
    }

    // MARK: - Fields

    private func fieldIndex(_ tertiary: Int) -> IntegerField.Index {
        IntegerField.Index(setID: setID, secondary: secondaryIndex, tertiary: tertiary)
    }

    /// Whether a weight typed into this row should be recorded as assistance: what this entry
    /// already holds, else what the template planned, else what the same field held last session.
    private var assistanceSignHint: Bool {
        if entry.weight != 0 { return entry.weight < 0 }
        if let planned = placeholder?.weight, planned != 0 { return planned < 0 }
        if let previous = reference?.weight, previous != 0 { return previous < 0 }
        return entersAssistance
    }

    private func repetitionsField(tertiary: Int) -> some View {
        let delta = repsDelta(current: entry.repetitions, previous: reference?.repetitions)
        return IntegerField(
            placeholder: placeholder?.repetitions ?? 0,
            value: $entry.repetitions,
            maxDigits: 4,
            index: fieldIndex(tertiary),
            focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
            unit: NSLocalizedString("reps", comment: ""),
            trend: delta.comparison,
            trendText: delta.text,
            trendColor: trendColor,
            previousValueText: (reference?.repetitions ?? 0) > 0
                ? String(reference!.repetitions) : nil,
            onTapPreviousValue: onTapPreviousValue
        )
    }

    private func weightField(tertiary: Int) -> some View {
        let delta = weightDelta(currentGrams: entry.weight, previousGrams: reference?.weight)
        // A number pad can't type a minus, and assistance is a negative weight — so a field
        // whose own value, planned value or last-session value was assistance keeps entering
        // assistance. Three sets on the machine are one toggle, not three; and because the
        // hint is per field, a drop set that runs belt → bodyweight → machine still enters
        // each of its drops with the right sign. The menus flip it deliberately.
        let recordsAssistance = assistanceSignHint
        return DecimalField(
            placeholder: placeholder.map { convertWeightForDisplayingDecimal($0.weight) } ?? 0,
            value: Binding(
                get: { convertWeightForDisplayingDecimal(entry.weight) },
                set: {
                    let stored = convertWeightForStoring(abs($0))
                    entry.weight = recordsAssistance ? -stored : stored
                }
            ),
            maxDigits: 4,
            // Match the input precision to what integer-gram storage can round-trip:
            // 3 decimals in kg (exact), 2 in lbs (a third decimal is below 1 g resolution).
            decimalPlaces: WeightUnit.used == .kg ? 3 : 2,
            // The one field whose value can be negative (assistance) — the duration and distance
            // fields below leave `allowsNegative` off, so a pasted minus can't reach their storage.
            allowsNegative: true,
            index: fieldIndex(tertiary),
            focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
            unit: WeightUnit.used.rawValue,
            trend: delta.comparison,
            trendText: delta.text,
            trendColor: trendColor,
            previousValueText: (reference?.weight ?? 0) != 0
                ? formatWeightForDisplay(reference!.weight) : nil,
            onTapPreviousValue: onTapPreviousValue
        )
    }

    /// The duration field in the entry's resolved spelling — the exercise's own choice when the
    /// user made one, else the measurement type's default. `.seconds` is decimal seconds entered
    /// to hundredths, so a sprint keeps the 12.34 it was timed at; `.clock` shifts digits in from
    /// the right, so a 32-minute run types as 32:15 instead of 1935. Stored as milliseconds
    /// either way, and it stays a single field in both — see `DurationClockField`.
    @ViewBuilder
    private func durationField(tertiary: Int, showsTrend: Bool = true) -> some View {
        let style = entry.type.durationStyle(for: entry.exercise) ?? .seconds
        // A duration beside a distance normally carries no trend (see `fields`) — but an
        // exercise that says its clock improves downward has just told us how to read it, so
        // a sprint gets its trend back.
        let goal = entry.exercise?.durationGoal ?? .longer
        let delta = showsTrend || goal == .faster
            ? durationDelta(
                currentMs: entry.durationMs, previousMs: reference?.durationMs, goal: goal,
                style: style
            )
            : (comparison: nil, text: "")
        let previousText = (reference?.durationMs ?? 0) > 0
            ? formatDurationForEntry(milliseconds: reference!.durationMs, style: style) : nil
        switch style {
        case .seconds:
            DecimalField(
                placeholder: Double(placeholder?.durationMs ?? 0) / 1000,
                value: Binding(
                    get: { Double(entry.durationMs) / 1000 },
                    set: { entry.durationMs = Int64(($0 * 1000).rounded()) }
                ),
                maxDigits: 4,
                decimalPlaces: DURATION_DECIMAL_PLACES,
                index: fieldIndex(tertiary),
                focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                unit: durationUnitTitle(for: .seconds),
                trend: delta.comparison,
                trendText: delta.text,
                trendColor: trendColor,
                previousValueText: previousText,
                onTapPreviousValue: onTapPreviousValue
            )
        case .clock:
            DurationClockField(
                placeholder: placeholder?.durationMs ?? 0,
                value: Binding(
                    get: { entry.durationMs },
                    set: { entry.durationMs = $0 }
                ),
                index: fieldIndex(tertiary),
                focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                trend: delta.comparison,
                trendText: delta.text,
                trendColor: trendColor,
                previousValueText: previousText,
                onTapPreviousValue: onTapPreviousValue
            )
        }
    }

    /// The distance field in the entry's resolved scale — the exercise's own km/m choice when
    /// the user made one, else the measurement type's default. Both scales enter as decimals
    /// (km/mi, or m/yd since v11 — a measured 40.25 m carry is a real number); only the unit
    /// label and the digit budget differ. Stored in millimeters either way.
    private func distanceField(tertiary: Int) -> some View {
        let style = entry.type.distanceStyle(for: entry.exercise) ?? .short
        let delta = distanceDelta(
            currentMm: entry.distanceMm, previousMm: reference?.distanceMm, style: style
        )
        return DecimalField(
            placeholder: placeholder
                .map { convertDistanceForDisplayingDecimal($0.distanceMm, style: style) } ?? 0,
            value: Binding(
                get: { convertDistanceForDisplayingDecimal(entry.distanceMm, style: style) },
                set: { entry.distanceMm = convertDistanceForStoring($0, style: style) }
            ),
            // 5 integer digits in the short scale, not 4: a 10 km run in meters is a
            // five-digit entry.
            maxDigits: style == .short ? 5 : 4,
            decimalPlaces: DISTANCE_DECIMAL_PLACES,
            index: fieldIndex(tertiary),
            focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
            unit: distanceUnitTitle(for: style),
            trend: delta.comparison,
            trendText: delta.text,
            trendColor: trendColor,
            previousValueText: (reference?.distanceMm ?? 0) > 0
                ? formatDistanceForDisplay(reference!.distanceMm, style: style) : nil,
            onTapPreviousValue: onTapPreviousValue
        )
    }
}

/// Re-renders an entry row's fields when its exercise changes. The row itself observes only
/// the entry; the exercise carries the user's per-exercise spellings — the distance scale and
/// the duration format — and without this hop switching either would leave already-rendered
/// rows in the stale one until an unrelated re-render.
private struct ExerciseObservingFields<Entry: SetEntryFieldsEditable>: View {
    let row: SetEntryFieldsRow<Entry>
    @ObservedObject var exercise: Exercise

    var body: some View {
        row.fields
    }
}

// MARK: - Duration Helpers

/// Compares an entered duration (milliseconds) against the previous workout's value, judged by the
/// exercise's own goal: a hold improves by lasting longer, a timed effort by ending sooner.
///
/// The arrow always points the way the number moved; only the tint follows the goal — negating the
/// number to make a quicker sprint point up would put a rising arrow beside a falling time.
/// Direction and text are computed on the value the user sees — in the entry's own spelling, so a
/// change too small to show (hundredths in a seconds field, a fraction of a second in a clock)
/// shows no arrow at all. Returns `(nil, "")` when there is nothing meaningful to show.
func durationDelta(
    currentMs: Int64, previousMs: Int64?, goal: ExerciseDurationGoal = .longer,
    style: SetMeasurementType.DurationStyle
) -> (comparison: SetValueComparison?, text: String) {
    guard let previousMs, previousMs > 0, currentMs > 0 else { return (nil, "") }
    let current = formatDurationForEntry(milliseconds: currentMs, style: style)
    let previous = formatDurationForEntry(milliseconds: previousMs, style: style)
    guard current != previous else { return (nil, "") }
    let rose = currentMs > previousMs
    return (
        SetValueComparison(
            direction: rose ? .up : .down,
            isImprovement: goal == .faster ? !rose : rose
        ),
        formatDurationForEntry(milliseconds: abs(currentMs - previousMs), style: style)
    )
}

/// Compares an entered distance (millimeters) against the previous workout's value — farther is
/// improved. Direction and text are computed in display units, like `weightDelta`, so they
/// match what the user sees.
func distanceDelta(
    currentMm: Int64, previousMm: Int64?, style: SetMeasurementType.DistanceStyle
) -> (comparison: SetValueComparison?, text: String) {
    guard let previousMm, previousMm > 0, currentMm > 0 else { return (nil, "") }
    let current = convertDistanceForDisplayingDecimal(currentMm, style: style)
    let previous = convertDistanceForDisplayingDecimal(previousMm, style: style)
    guard current != previous else { return (nil, "") }
    return (
        current > previous ? .improved : .declined,
        formatDistanceForDisplay(
            convertDistanceForStoring(abs(current - previous), style: style), style: style
        )
    )
}
