//
//  DurationFormatting.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 27.07.26.
//

import Foundation

/// How a *timer* duration — a rest interval, a countdown, an elapsed stopwatch — is written where
/// it is displayed rather than edited: the digital reading the rest timer and stopwatch already
/// use, so a 90-second rest and a 90-second hold are spelled the same way.
///
/// "0:45", "1:30", "21:20", and "1:01:40" once past an hour. The string carries its own separators,
/// so callers pass an **empty unit** instead of "sec" — a bare seconds count ("1280 SEC") is
/// unreadable at a glance and can't be compared against another at a glance either.
///
/// Recorded set durations are milliseconds since model v11 and take the overload below; the
/// argument label is what keeps the two units from being handed to the wrong one silently.
public func formatDurationForDisplay(seconds: Int) -> String {
    let total = max(seconds, 0)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secondsPart = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secondsPart)
    }
    return String(format: "%d:%02d", minutes, secondsPart)
}

/// How a *recorded set* duration is written — the same digital reading, plus hundredths when the
/// value actually carries them: "1:30" for a whole-second plank, "0:12.34" for a sprint.
///
/// Hundredths appear only when the stored value has a sub-second part, so every duration logged
/// before v11 (and every one entered without decimals since) reads exactly as it always has. The
/// value is rounded to hundredths first, so 12_999 ms reads "0:13" rather than "0:12.99".
public func formatDurationForDisplay(milliseconds: Int64) -> String {
    let hundredths = (max(milliseconds, 0) + 5) / 10
    let whole = Int(hundredths / 100)
    let fraction = Int(hundredths % 100)
    let digital = formatDurationForDisplay(seconds: whole)
    guard fraction > 0 else { return digital }
    return digital + String(format: ".%02d", fraction)
}

/// The seconds value as it appears in a duration *input field*, where the unit is spelled beside
/// the number ("12.34 SEC") instead of being carried by colons: a plain decimal, with the fraction
/// shown only when the value has one. This is also what the delta pill beneath the field prints,
/// so the entered number and the change from last time are written the same way.
public func formatDurationSecondsForEntry(milliseconds: Int64) -> String {
    let seconds = Double(max(milliseconds, 0)) / 1000
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = DURATION_DECIMAL_PLACES
    formatter.decimalSeparator = "."
    formatter.groupingSeparator = ""
    return formatter.string(from: NSNumber(value: seconds)) ?? "0"
}

/// How many decimals a duration is entered and displayed with. Hundredths: what a stopwatch
/// shows, what a sprint is timed to, and exactly representable in millisecond storage.
public let DURATION_DECIMAL_PLACES: Int = 2

// MARK: - Clock Entry

/// How many digits a clock field holds, and so the longest effort it can spell: `99:59:59`.
/// Six is not a limit anyone reaches — it is the point past which another digit would have to
/// push the hours off the left edge, which would destroy what was already typed.
public let MAX_CLOCK_ENTRY_DIGITS: Int = 6

/// The digits a stored duration is typed as in a clock field, leading zeros stripped:
/// 1_935_000 ms → "3215", 45_000 ms → "45", 0 → "".
///
/// Sub-second precision is dropped, because a clock field enters whole seconds — the stored
/// value keeps its hundredths until the set is actually re-typed (see `DurationClockField`).
public func clockEntryDigits(forDuration milliseconds: Int64) -> String {
    let seconds = max(milliseconds, 0) / 1000
    guard seconds > 0 else { return "" }
    let hours = seconds / 3600
    let digits = String(format: "%d%02d%02d", hours, (seconds % 3600) / 60, seconds % 60)
    return String(digits.drop(while: { $0 == "0" }))
}

/// The duration a clock-entry digit buffer spells: "3215" → 1_935_000 ms.
///
/// The groups are summed WITHOUT being validated — seconds are the last two digits, minutes the
/// two before them, hours whatever is left, and the total is `h*3600 + m*60 + s`. A group over
/// 59 is a legal intermediate state, not an error: digits shift in from the right, so reaching
/// 9:59 (type 9, 5, 9) has to pass through 0:95 on the way, and 95 seconds really is 95 seconds.
/// Rejecting or clamping it here would make the second half of the clock untypeable.
public func durationMilliseconds(fromClockEntryDigits digits: String) -> Int64 {
    let buffer = digits.filter(\.isNumber)
    guard !buffer.isEmpty else { return 0 }
    let seconds = Int64(buffer.suffix(2)) ?? 0
    let minutes = Int64(buffer.dropLast(2).suffix(2)) ?? 0
    let hours = Int64(buffer.dropLast(4)) ?? 0
    return (hours * 3600 + minutes * 60 + seconds) * 1000
}

/// How a clock-entry digit buffer reads while it is being typed: "3" → "0:03", "32" → "0:32",
/// "321" → "3:21", "3215" → "32:15", "12345" → "1:23:45".
///
/// This prints the RAW grouping, so a buffer mid-shift shows exactly the digits that were typed
/// ("095" reads "0:95", not "1:35"). The canonical reading arrives when the field loses focus
/// and re-seeds from the stored value — the same round-trip `DecimalField` performs for the
/// decimal separator. For a well-formed buffer the two spellings are identical.
public func formatClockEntryDigits(_ digits: String) -> String {
    let buffer = digits.filter(\.isNumber)
    guard !buffer.isEmpty else { return "" }
    let seconds = buffer.suffix(2)
    let minutes = buffer.dropLast(2).suffix(2)
    let hours = buffer.dropLast(4)
    let paddedSeconds = String(repeating: "0", count: 2 - seconds.count) + seconds
    guard !minutes.isEmpty || !hours.isEmpty else { return "0:" + paddedSeconds }
    guard !hours.isEmpty else { return String(minutes) + ":" + paddedSeconds }
    let paddedMinutes = String(repeating: "0", count: 2 - minutes.count) + minutes
    return String(hours) + ":" + paddedMinutes + ":" + paddedSeconds
}

// MARK: - Style Dispatch

/// The entry spelling for `style`: the decimal seconds a field prints beside "SEC", or the
/// whole-second digital reading whose colons carry their own separators.
///
/// The clock truncates where `formatDurationForDisplay(milliseconds:)` rounds — 12_996 ms reads
/// "0:13" in history but "0:12" in a clock field. That is deliberate: a value the user is about
/// to overwrite must never be shown as more than it is.
func formatDurationForEntry(
    milliseconds: Int64, style: SetMeasurementType.DurationStyle
) -> String {
    switch style {
    case .seconds: return formatDurationSecondsForEntry(milliseconds: milliseconds)
    case .clock: return formatDurationForDisplay(seconds: Int(max(milliseconds, 0) / 1000))
    }
}

/// The unit written beside the number — "sec", or *nothing at all* for the clock. See this
/// file's opening note: a colon-separated reading passes an empty unit, because "1280 SEC" is
/// precisely the reading this format exists to replace.
func durationUnitTitle(for style: SetMeasurementType.DurationStyle) -> String? {
    switch style {
    case .seconds: return NSLocalizedString("sec", comment: "")
    case .clock: return nil
    }
}

/// The spelled-out menu label — "Seconds (sec)" / "Minutes & Seconds (m:ss)" — the counterpart
/// to `distanceStyleTitle(for:)`, used where a menu has room to explain itself.
func durationStyleTitle(for style: SetMeasurementType.DurationStyle) -> String {
    switch style {
    case .seconds: return NSLocalizedString("durationFormatSeconds", comment: "")
    case .clock: return NSLocalizedString("durationFormatClock", comment: "")
    }
}

/// The same duration spelled out for VoiceOver — "21 minutes, 20 seconds" — because the digital
/// reading is spoken as a pair of bare numbers ("twenty-one twenty"). Zero-valued units drop out,
/// so a sub-minute hold reads simply as "45 seconds".
public func accessibleDurationForDisplay(seconds: Int) -> String {
    Duration.seconds(max(seconds, 0)).formatted(
        .units(allowed: [.hours, .minutes, .seconds], width: .wide, zeroValueUnits: .hide)
    )
}

/// VoiceOver reading of a recorded set duration. Sub-second precision is spoken as a decimal
/// ("12.34 seconds") rather than as a separate milliseconds unit, which is how a stopwatch time
/// is said out loud; whole values keep the spelled-out form above.
public func accessibleDurationForDisplay(milliseconds: Int64) -> String {
    let hundredths = (max(milliseconds, 0) + 5) / 10
    let fraction = Int(hundredths % 100)
    guard fraction > 0 else {
        return accessibleDurationForDisplay(seconds: Int(hundredths / 100))
    }
    return Duration.milliseconds(hundredths * 10).formatted(
        .units(
            allowed: [.hours, .minutes, .seconds],
            width: .wide,
            maximumUnitCount: 3,
            zeroValueUnits: .hide,
            fractionalPart: .show(length: 2)
        )
    )
}
