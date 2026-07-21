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
    var duration: Int64 { get set }
    var distance: Int64 { get set }
    var type: SetMeasurementType { get }
}

extension SetEntry: SetEntryFieldsEditable {}
extension TemplateSetEntry: SetEntryFieldsEditable {}

/// One set entry's input fields, laid out by the entry's measurement type:
/// reps+weight, reps only, duration, weight+duration, distance, distance+duration, or
/// weight+distance. This is the single row every set cell — standard, drop, super, workout
/// or template — renders per entry.
///
/// The focus index is (set position, entry position, field position); field positions must
/// stay consistent with `SetMeasurementType.inputFieldCount`, which the recorder's keyboard
/// next/previous navigation clamps against.
struct SetEntryFieldsRow<Entry: SetEntryFieldsEditable>: View {
    @ObservedObject var entry: Entry
    let primaryIndex: Int
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
                distanceField(tertiary: 0, style: .long)
            case .distanceAndDuration:
                distanceField(tertiary: 0, style: .long)
                // No trend on the duration beside a distance: a longer time for the same run
                // is worse, not better — only the distance carries the comparison.
                durationField(tertiary: 1, showsTrend: false)
            case .weightAndDistance:
                weightField(tertiary: 0)
                distanceField(tertiary: 1, style: .short)
            }
        }
    }

    // MARK: - Fields

    private func fieldIndex(_ tertiary: Int) -> IntegerField.Index {
        IntegerField.Index(primary: primaryIndex, secondary: secondaryIndex, tertiary: tertiary)
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
            decimalPlaces: 3,
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

    private func durationField(tertiary: Int, showsTrend: Bool = true) -> some View {
        let delta = showsTrend
            ? durationDelta(current: entry.duration, previous: reference?.duration)
            : (comparison: nil, text: "")
        return IntegerField(
            placeholder: placeholder?.duration ?? 0,
            value: $entry.duration,
            maxDigits: 4,
            index: fieldIndex(tertiary),
            focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
            unit: NSLocalizedString("sec", comment: ""),
            trend: delta.comparison,
            trendText: delta.text,
            trendColor: trendColor,
            previousValueText: (reference?.duration ?? 0) > 0
                ? String(reference!.duration) : nil,
            onTapPreviousValue: onTapPreviousValue
        )
    }

    /// The distance field in the scale the measurement type calls for: long distances as a
    /// decimal in km/mi (cardio), short ones as whole m/yd (carries). Stored in meters either way.
    @ViewBuilder
    private func distanceField(tertiary: Int, style: SetMeasurementType.DistanceStyle) -> some View {
        let delta = distanceDelta(
            currentMeters: entry.distance, previousMeters: reference?.distance, style: style
        )
        let previousText = (reference?.distance ?? 0) > 0
            ? formatDistanceForDisplay(reference!.distance, style: style) : nil
        switch style {
        case .long:
            DecimalField(
                placeholder: placeholder.map { convertDistanceForDisplayingDecimal($0.distance) } ?? 0,
                value: Binding(
                    get: { convertDistanceForDisplayingDecimal(entry.distance) },
                    set: { entry.distance = convertDistanceForStoring($0) }
                ),
                maxDigits: 4,
                decimalPlaces: 2,
                index: fieldIndex(tertiary),
                focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                unit: DistanceUnit.used.rawValue,
                trend: delta.comparison,
                trendText: delta.text,
                trendColor: trendColor,
                previousValueText: previousText,
                onTapPreviousValue: onTapPreviousValue
            )
        case .short:
            IntegerField(
                placeholder: placeholder.map { convertShortDistanceForDisplaying($0.distance) } ?? 0,
                value: Binding(
                    get: { convertShortDistanceForDisplaying(entry.distance) },
                    set: { entry.distance = convertShortDistanceForStoring($0) }
                ),
                maxDigits: 4,
                index: fieldIndex(tertiary),
                focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                unit: DistanceUnit.used.shortUnit,
                trend: delta.comparison,
                trendText: delta.text,
                trendColor: trendColor,
                previousValueText: previousText,
                onTapPreviousValue: onTapPreviousValue
            )
        }
    }
}

// MARK: - Duration Helpers

/// Compares an entered duration against the previous workout's value — longer is improved,
/// matching how holds are trained. Returns `(nil, "")` when there is nothing meaningful to show.
func durationDelta(current: Int64, previous: Int64?) -> (comparison: SetValueComparison?, text: String) {
    guard let previous, previous > 0, current > 0, current != previous else { return (nil, "") }
    return (current > previous ? .improved : .declined, String(abs(current - previous)))
}

/// Compares an entered distance (meters) against the previous workout's value — farther is
/// improved. Direction and text are computed in display units, like `weightDelta`, so they
/// match what the user sees.
func distanceDelta(
    currentMeters: Int64, previousMeters: Int64?, style: SetMeasurementType.DistanceStyle
) -> (comparison: SetValueComparison?, text: String) {
    guard let previousMeters, previousMeters > 0, currentMeters > 0 else { return (nil, "") }
    switch style {
    case .long:
        let current = convertDistanceForDisplayingDecimal(currentMeters)
        let previous = convertDistanceForDisplayingDecimal(previousMeters)
        guard current != previous else { return (nil, "") }
        return (
            current > previous ? .improved : .declined,
            formatDistanceForDisplay(convertDistanceForStoring(abs(current - previous)))
        )
    case .short:
        let current = convertShortDistanceForDisplaying(currentMeters)
        let previous = convertShortDistanceForDisplaying(previousMeters)
        guard current != previous else { return (nil, "") }
        return (current > previous ? .improved : .declined, String(abs(current - previous)))
    }
}
