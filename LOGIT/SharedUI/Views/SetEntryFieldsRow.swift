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
    /// model v11. The fields below enter them as decimal seconds and decimal m/km.
    var durationMs: Int64 { get set }
    var distanceMm: Int64 { get set }
    var type: SetMeasurementType { get }
    /// The exercise the entry trains — decides the distance scale (km vs m) via the user's
    /// per-exercise choice.
    var exercise: Exercise? { get }
}

extension SetEntry: SetEntryFieldsEditable {}
extension TemplateSetEntry: SetEntryFieldsEditable {}

/// One set entry's input fields, laid out by the entry's measurement type:
/// reps+weight, reps only, duration, weight+duration, distance, distance+duration, or
/// weight+distance. This is the single row every set cell — standard, drop, super, workout
/// or template — renders per entry.
///
/// The focus index is (set id, entry position, field position); field positions must
/// stay consistent with `SetMeasurementType.inputFieldCount`, which the recorder's keyboard
/// next/previous navigation clamps against.
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
        return DecimalField(
            placeholder: placeholder.map { convertWeightForDisplayingDecimal($0.weight) } ?? 0,
            value: Binding(
                get: { convertWeightForDisplayingDecimal(entry.weight) },
                set: { entry.weight = convertWeightForStoring($0) }
            ),
            maxDigits: 4,
            // Match the input precision to what integer-gram storage can round-trip:
            // 3 decimals in kg (exact), 2 in lbs (a third decimal is below 1 g resolution).
            decimalPlaces: WeightUnit.used == .kg ? 3 : 2,
            index: fieldIndex(tertiary),
            focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
            unit: WeightUnit.used.rawValue,
            trend: delta.comparison,
            trendText: delta.text,
            trendColor: trendColor,
            previousValueText: (reference?.weight ?? 0) > 0
                ? formatWeightForDisplay(reference!.weight) : nil,
            onTapPreviousValue: onTapPreviousValue
        )
    }

    /// Seconds, entered to hundredths. The stored value is milliseconds, so a sprint keeps the
    /// 12.34 it was timed at; whole-second holds still type as plainly as they did before.
    private func durationField(tertiary: Int, showsTrend: Bool = true) -> some View {
        let delta = showsTrend
            ? durationDelta(currentMs: entry.durationMs, previousMs: reference?.durationMs)
            : (comparison: nil, text: "")
        return DecimalField(
            placeholder: Double(placeholder?.durationMs ?? 0) / 1000,
            value: Binding(
                get: { Double(entry.durationMs) / 1000 },
                set: { entry.durationMs = Int64(($0 * 1000).rounded()) }
            ),
            maxDigits: 4,
            decimalPlaces: DURATION_DECIMAL_PLACES,
            index: fieldIndex(tertiary),
            focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
            unit: NSLocalizedString("sec", comment: ""),
            trend: delta.comparison,
            trendText: delta.text,
            trendColor: trendColor,
            previousValueText: (reference?.durationMs ?? 0) > 0
                ? formatDurationSecondsForEntry(milliseconds: reference!.durationMs) : nil,
            onTapPreviousValue: onTapPreviousValue
        )
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
/// the entry; the exercise carries the user's distance scale, and without this hop a unit
/// switch would leave already-rendered rows in the stale unit until an unrelated re-render.
private struct ExerciseObservingFields<Entry: SetEntryFieldsEditable>: View {
    let row: SetEntryFieldsRow<Entry>
    @ObservedObject var exercise: Exercise

    var body: some View {
        row.fields
    }
}

// MARK: - Duration Helpers

/// Compares an entered duration (milliseconds) against the previous workout's value — longer is
/// improved, matching how holds are trained. Direction and text are computed on the value the
/// user sees, so a change too small to show as hundredths shows no arrow at all. Returns
/// `(nil, "")` when there is nothing meaningful to show.
func durationDelta(
    currentMs: Int64, previousMs: Int64?
) -> (comparison: SetValueComparison?, text: String) {
    guard let previousMs, previousMs > 0, currentMs > 0 else { return (nil, "") }
    let current = formatDurationSecondsForEntry(milliseconds: currentMs)
    let previous = formatDurationSecondsForEntry(milliseconds: previousMs)
    guard current != previous else { return (nil, "") }
    return (
        currentMs > previousMs ? .improved : .declined,
        formatDurationSecondsForEntry(milliseconds: abs(currentMs - previousMs))
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
