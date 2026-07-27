//
//  DurationFormatting.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 27.07.26.
//

import Foundation

/// How a recorded duration (a held plank, a treadmill run — stored as whole seconds) is written
/// wherever it is *displayed* rather than edited: the digital reading the rest timer and stopwatch
/// already use, so a 90-second hold and a 90-second rest are spelled the same way.
///
/// "0:45", "1:30", "21:20", and "1:01:40" once past an hour. The string carries its own separators,
/// so callers pass an **empty unit** instead of "sec" — a bare seconds count ("1280 SEC") is
/// unreadable at a glance and can't be compared against another at a glance either.
///
/// The set-entry fields are deliberately not on this path: they are two separate minute and second
/// fields, and a combined string is not editable.
public func formatDurationForDisplay(_ seconds: Int) -> String {
    let total = max(seconds, 0)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secondsPart = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secondsPart)
    }
    return String(format: "%d:%02d", minutes, secondsPart)
}

/// The same duration spelled out for VoiceOver — "21 minutes, 20 seconds" — because the digital
/// reading is spoken as a pair of bare numbers ("twenty-one twenty"). Zero-valued units drop out,
/// so a sub-minute hold reads simply as "45 seconds".
public func accessibleDurationForDisplay(_ seconds: Int) -> String {
    Duration.seconds(max(seconds, 0)).formatted(
        .units(allowed: [.hours, .minutes, .seconds], width: .wide, zeroValueUnits: .hide)
    )
}
