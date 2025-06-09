//
//  ButtonStyle.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 28.07.23.
//

import SwiftUI

private let MIN_BUTTON_SCALE: CGFloat = 0.97
private let SCALE_ANIMATION_TIME: CGFloat = 0.2

struct BigButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .bold))
            .foregroundColor(.background)
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(Color.accentColor)
            .listRowBackground(Color.clear)
            .cornerRadius(15)
            .scaleEffect(configuration.isPressed ? MIN_BUTTON_SCALE : 1.0)
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
            .animation(.easeOut(duration: SCALE_ANIMATION_TIME), value: configuration.isPressed)
    }
}

struct SecondaryBigButtonStyle: ButtonStyle {
    var padding: CGFloat = 20
    var maxWidth: CGFloat? = .infinity
    var leadingCornerRadius: CGFloat = 15
    var trailingCornerRadius: CGFloat = 15

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .bold))
            .foregroundColor(.accentColor)
            .frame(maxWidth: maxWidth)
            .padding(padding)
            .background(Color.accentColor.secondaryTranslucentBackground)
            .listRowBackground(Color.clear)
            .clipShape(UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: leadingCornerRadius, bottomLeading: leadingCornerRadius, bottomTrailing: trailingCornerRadius, topTrailing: trailingCornerRadius)))
            .scaleEffect(configuration.isPressed ? MIN_BUTTON_SCALE : 1.0)
            .onChange(of: configuration.isPressed) { isPressed in
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
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            }
    }
}

struct CapsuleButtonStyle: ButtonStyle {
    let color: Color?
    let isSelected: Bool

    init(color: Color? = nil, isSelected: Bool = true) {
        self.color = color
        self.isSelected = isSelected
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .padding(.vertical, 8)
            .padding(.horizontal, 15)
            .foregroundStyle(
                (isSelected ? Color.background : (color ?? .label)).gradient
            )
            .background(
                ((color ?? .accentColor).opacity(isSelected ? 1.0 : 0.2))
                    .gradient
            )
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? MIN_BUTTON_SCALE : 1.0)
            .onChange(of: configuration.isPressed) { isPressed in
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
