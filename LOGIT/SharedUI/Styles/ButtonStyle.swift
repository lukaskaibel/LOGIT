//
//  ButtonStyle.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 28.07.23.
//

import SwiftUI

private let MIN_BUTTON_SCALE: CGFloat = 0.97
private let SCALE_ANIMATION_TIME: CGFloat = 0.2


struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .bold))
            .foregroundColor(.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.accentColor)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? MIN_BUTTON_SCALE : 1.0)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
            .animation(.easeOut(duration: SCALE_ANIMATION_TIME), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    /// Tint for the label and, translucently, the capsule behind it. Defaults to the accent
    /// colour; pass a muscle-group gradient (e.g. `workout.sets.muscleGroupGradientStyle()`) to
    /// have the button carry the session's own colours.
    var tint: AnyShapeStyle = AnyShapeStyle(Color.accentColor)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .bold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            // The same 0.2 as `Color.secondaryTranslucentBackground`, which only exists for
            // colours — a gradient tint has to fade itself.
            .background(tint.opacity(0.2))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? MIN_BUTTON_SCALE : 1.0)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .animation(.easeOut(duration: SCALE_ANIMATION_TIME), value: configuration.isPressed)
    }
}

/// The neutral sibling of `SecondaryButtonStyle`: the same rounded-bold label and capsule, but a
/// gray `systemFill` background with muted text — for the quietest action in a row (e.g. Minimize
/// beside a tinted Finish).
struct TertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .bold))
            .foregroundColor(.secondaryLabel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.fill)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? MIN_BUTTON_SCALE : 1.0)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .animation(.easeOut(duration: SCALE_ANIMATION_TIME), value: configuration.isPressed)
    }
}

struct SelectionButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.background : .accentColor)
            .padding(3)
            .background(isSelected ? Color.accentColor.opacity(0.9) : .clear)
            .cornerRadius(8)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            }
    }
}

struct CapsuleButtonStyle: ButtonStyle {
    let color: Color?
    let isSelected: Bool
    /// Trims the horizontal padding for capsules that must wrap into rows rather than scroll —
    /// all eight muscle groups only settle into two rows on a phone at the tighter inset.
    let compact: Bool

    init(color: Color? = nil, isSelected: Bool = true, compact: Bool = false) {
        self.color = color
        self.isSelected = isSelected
        self.compact = compact
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(compact ? .subheadline : .headline, design: .rounded, weight: .semibold))
            .padding(.vertical, compact ? 7 : 8)
            .padding(.horizontal, compact ? 13 : 15)
            .foregroundStyle(
                (isSelected ? Color.background : (color ?? .label)).gradient
            )
            .background(
                ((color ?? .accentColor).opacity(isSelected ? 1.0 : 0.2))
                    .gradient
            )
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? MIN_BUTTON_SCALE : 1.0)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .animation(.easeOut(duration: SCALE_ANIMATION_TIME), value: configuration.isPressed)
    }
}

struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? MIN_BUTTON_SCALE : 1.0)
            .animation(.easeOut(duration: SCALE_ANIMATION_TIME), value: configuration.isPressed)
    }
}
