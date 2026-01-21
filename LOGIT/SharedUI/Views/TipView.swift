//
//  TipView.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 22.08.23.
//

import SwiftUI

struct TipView: View {
    struct ButtonAction {
        let title: String
        let action: () -> Void
    }

    let title: String
    let description: String
    let buttonAction: ButtonAction?

    @Binding var isShown: Bool

    init(
        title: String,
        description: String,
        buttonAction: ButtonAction? = nil,
        isShown: Binding<Bool>
    ) {
        self.title = title
        self.description = description
        self.buttonAction = buttonAction
        _isShown = isShown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
            HStack {
                HStack {
                    Image(systemName: "info.circle")
                    Text(title)
                }
                .tileHeaderStyle()
                Spacer()
                Button {
                    isShown = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            Text(description)
            if let buttonAction = buttonAction {
                Button {
                    buttonAction.action()
                } label: {
                    Text(buttonAction.title)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top)
            }
        }
    }
}

struct TipView_Previews: PreviewProvider {
    static var previews: some View {
        TipView(
            title: "Lets Work-Out 🏋️",
            description:
            "You haven't logged any workouts in LOGIT yet. Start your journey by clicking the button below to record your first workout!",
            buttonAction: .init(title: "Start Workout", action: { print("Create Workout") }),
            isShown: .constant(true)
        )
        .padding(CELL_PADDING)
        .tileStyle()
    }
}
