//
//  RestDurationPicker.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.03.26.
//

import SwiftUI

/// Inline rest duration editor shown between sets in templates and workouts.
/// Shows a compact row with clock icon and preset duration buttons.
struct RestDurationPicker: View {
    @Binding var restDurationSeconds: Int

    private let presets = [30, 60, 90, 120, 180]

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(presets, id: \.self) { seconds in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            if restDurationSeconds == seconds {
                                restDurationSeconds = 0
                            } else {
                                restDurationSeconds = seconds
                            }
                        } label: {
                            Text(seconds.restTimeString)
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    restDurationSeconds == seconds
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.fill
                                )
                                .foregroundStyle(
                                    restDurationSeconds == seconds
                                        ? Color.accentColor
                                        : .secondary
                                )
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            if restDurationSeconds > 0 {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        restDurationSeconds = 0
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// A compact label showing rest duration between sets (read-only).
struct RestDurationLabel: View {
    let seconds: Int
    var foregroundColor: Color = .secondary
    var iconName: String = "clock"
    var textFont: Font = .caption.weight(.medium)
    var iconFont: Font = .caption2

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(iconFont)
            Text(seconds.restTimeString)
                .font(textFont.monospacedDigit())
        }
        .foregroundStyle(foregroundColor)
    }
}
