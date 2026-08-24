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
