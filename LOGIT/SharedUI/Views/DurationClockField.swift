//
//  DurationClockField.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 20.09.26.
//

import SwiftUI

/// A duration typed the way a stopwatch is read: digits shift in from the right, so 3, 2, 1, 5
/// reads "0:03", "0:32", "3:21", "32:15". The field for exercises whose efforts are minutes or
/// hours long — a treadmill session typed into the decimal-seconds field is "1935", which nobody
/// can read back, and past "9999" it cannot be typed at all.
///
/// It stays ONE field. A minute box beside a second box would give a duration two `tertiary`
/// indices, and `SetMeasurementType.inputFieldCount`, `weightFieldIndex` and
/// `SetFieldNavigation` all key off that number — shifting digits keeps every one of them true.
///
/// What the keyboard types into is not what the eye reads. The `TextField` holds only the raw
/// digits ("3215"), invisibly; the clock ("32:15") is a `Text` drawn where the field sits, and
/// the caret is kept after its last digit — the one place a keystroke ever lands. That split is
/// load-bearing: a field that rewrote its own visible text to move the colons would push a new
/// string back into UIKit on every keystroke, and a digit typed before that write landed was
/// overwritten — 3, 2, 1, 5 typed quickly read "0:25". Here a number pad can only append
/// digits, so ordinary typing needs no write back at all.
///
/// The value is milliseconds, like everywhere else since model v11; only whole seconds are typed
/// here. `DecimalField` remains the field for holds and sprints, where hundredths matter.
///
/// Unlike its two siblings this declares no `@EnvironmentObject var database` — `DecimalField`
/// and `IntegerField` both do and neither uses it, which is a crash waiting for the first call
/// site that forgets to inject one.
struct DurationClockField: View {
    // MARK: - Environment

    @Environment(\.canEdit) var canEdit: Bool
    @Environment(\.isIntegerFieldFocusSuppressed) private var isFocusSuppressed: Bool

    // MARK: - Parameters

    /// The template's planned duration, shown as the prompt while the field is empty.
    let placeholder: Int64
    @Binding var value: Int64
    let index: IntegerField.Index
    @Binding var focusedIntegerFieldIndex: IntegerField.Index?
    var trend: SetValueComparison? = nil
    var trendText: String = ""
    var trendColor: Color = .accentColor
    var previousValueText: String? = nil
    var onTapPreviousValue: (() -> Void)? = nil

    // MARK: - State

    /// The digit buffer the keyboard types into — no colons, no leading zeros, at most
    /// `MAX_CLOCK_ENTRY_DIGITS`. The clock on screen is derived from it, never stored.
    @State private var digits: String = ""
    /// Pinned to the end of `digits` while editing — see `pinCaretToEnd()`.
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    // MARK: - Body

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Group {
                if canEdit {
                    Text(isEmpty ? promptText : reading)
                        .foregroundStyle(readingColor)
                        .accessibilityHidden(true)
                        .overlay {
                            TextField("", text: $digits, selection: $selection)
                                .focused($isFocused)
                                .keyboardType(.numberPad)
                                // Invisible: the clock drawn beneath is the reading. Trailing, so
                                // the buffer ends where the clock ends and the caret sits just
                                // after its last digit — "3215" is narrower than "32:15", and
                                // centered it would put the caret on top of the 5.
                                .foregroundStyle(Color.clear)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: digits) { _, newDigits in
                                    handleTyping(newDigits)
                                }
                                .onChange(of: selection) { _, _ in
                                    pinCaretToEnd()
                                }
                                // Reports the clock, not the raw buffer: it is what the screen
                                // shows, and "3215" would be read out as three thousand-odd.
                                .accessibilityValue(Text(isEmpty ? promptText : reading))
                        }
                } else {
                    Text(reading)
                        .foregroundColor(isEmpty ? .placeholder : .primary)
                        // Spoken as a pair of bare numbers otherwise — "32:15" reads
                        // "thirty-two fifteen".
                        .accessibilityValue(Text(accessibleDurationForDisplay(milliseconds: value)))
                }
            }
            .font(.system(.title3, design: .rounded, weight: .bold))
            .multilineTextAlignment(.center)
            // The clock carries its own separators, so it shows no unit — but the empty label
            // stays in the stack, because removing it changes the baseline geometry and the
            // field stops lining up with the weight beside it in a weight+duration set.
            Text("")
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .fixedSize()
        }
        .fixedSize()
        .onAppear {
            digits = seededDigits
        }
        .onChange(of: focusedIntegerFieldIndex) { _, newValue in
            guard !isFocusSuppressed else { return }
            let shouldBeFocused = newValue == index
            guard isFocused != shouldBeFocused else { return }
            if shouldBeFocused {
                // Set focus directly - don't resign first responder first
                isFocused = true
            } else if newValue == nil && isFocused {
                isFocused = false
            }
            // When transferring to another field, don't explicitly set isFocused = false;
            // the new field's focus will take over
        }
        .onChange(of: isFocused) { _, newValue in
            guard !isFocusSuppressed else { return }
            if newValue {
                UISelectionFeedbackGenerator().selectionChanged()
                if focusedIntegerFieldIndex != index {
                    focusedIntegerFieldIndex = index
                }
                pinCaretToEnd()
            } else {
                // Losing focus – re-seed from the stored value, which is what turns a buffer
                // typed mid-shift ("0:95") into the reading it actually means ("1:35").
                selection = nil
                let seeded = seededDigits
                if seeded != digits { digits = seeded }
            }
        }
        .onChange(of: value) { _, _ in
            // While the user is typing, the buffer is the source of truth; the model must not
            // overwrite the digits being entered.
            guard !isFocused else { return }
            let seeded = seededDigits
            if seeded != digits { digits = seeded }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .secondaryTileStyle(backgroundColor: isFocused ? Color.white : Color.black.opacity(0.000001))
        .setValueIndicator(
            trend: trend,
            trendText: trendText,
            positiveColor: trendColor,
            previousValueText: previousValueText,
            showPreviousValue: isEmpty,
            onTapPreviousValue: onTapPreviousValue,
            isVisible: canEdit
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.6, blendDuration: 0), value: isFocused)
        .frame(minWidth: 100, alignment: .trailing)
        .fixedSize(horizontal: true, vertical: false)
        .onTapGesture {
            guard !isFocusSuppressed else { return }
            isFocused = true
        }
        .id(index)
    }

    // MARK: - Computed Properties

    private var isEmpty: Bool { digits.isEmpty }

    /// The clock the buffer spells, grouped exactly as typed — "0:95" mid-shift, until blur.
    private var reading: String { formatClockEntryDigits(digits) }

    private var readingColor: Color {
        if isEmpty { return isFocused ? Color(UIColor.systemGray2) : Color.placeholder }
        return isFocused ? Color.black : Color.white
    }

    /// The buffer for the stored value when it is not being typed into: its whole seconds, or
    /// nothing at all at zero so the prompt shows through.
    private var seededDigits: String {
        clockEntryDigits(forDuration: value)
    }

    private var promptText: String {
        placeholder > 0 ? formatDurationForEntry(milliseconds: placeholder, style: .clock) : "0:00"
    }

    // MARK: - Helper Methods

    /// Keeps the caret after the last digit, whatever the user taps. Shifting digits in from the
    /// right only works if every keystroke lands at the end: a tap in the middle of the buffer
    /// would otherwise splice the next digit in there, and a backspace would eat one out of the
    /// middle — clearing "22:00" and typing 3, 2, 1, 5 read "22:02:15". A stopwatch has no caret
    /// to place, so this field doesn't either; it also turns a selection back into a caret, which
    /// is why select-and-replace isn't offered — six backspaces clear it.
    ///
    /// This writes only when the caret has actually moved away from the end — on a tap, never on
    /// an ordinary keystroke, which leaves the caret at the end by itself.
    private func pinCaretToEnd() {
        guard isFocused else { return }
        let end = TextSelection(insertionPoint: digits.endIndex)
        if selection != end { selection = end }
    }

    /// Reads the buffer after every change and stores what it spells. A number pad can only
    /// append digits or remove the last one, so the buffer normally needs no correcting and
    /// nothing is written back to the field — the one exception being the rare keystroke that
    /// would leave a leading zero or a seventh digit.
    private func handleTyping(_ newDigits: String) {
        // A leading zero is swallowed rather than shown, exactly as the decimal field does.
        let trimmed = String(newDigits.filter(\.isNumber).drop(while: { $0 == "0" }))
        // `prefix`, never `suffix`: insertion is always at the end, so the first six digits are
        // what was already there and the seventh keystroke becomes a no-op. Taking the suffix
        // would shift the hours off the left edge and silently destroy them.
        let clean = String(trimmed.prefix(MAX_CLOCK_ENTRY_DIGITS))
        if clean != digits { digits = clean }

        // Only a real keystroke may write the model. Re-seeding on blur assigns `digits`, which
        // lands back here — and a clock spells whole seconds, so without this guard merely
        // tapping into and out of the field would round a legacy 0:12.34 sprint down to 0:12.
        // Sub-second values are given up when a set is re-typed, never just by being looked at.
        guard isFocused else { return }
        let entered = durationMilliseconds(fromClockEntryDigits: clean)
        if entered != value { value = entered }
    }
}

struct DurationClockField_Previews: PreviewProvider {
    static var previews: some View {
        DurationClockField(
            placeholder: 0,
            value: .constant(1_935_000),
            index: .init(setID: UUID()),
            focusedIntegerFieldIndex: .constant(nil)
        )
        .padding(CELL_PADDING)
        .secondaryTileStyle()
        .previewEnvironmentObjects()
    }
}
