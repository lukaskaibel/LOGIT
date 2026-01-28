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

    let category: String?
    let title: String
    let description: String
    let buttonAction: ButtonAction?
    let showDismissButton: Bool

    @Binding var isShown: Bool

    init(
        category: String? = nil,
        title: String,
        description: String,
        buttonAction: ButtonAction? = nil,
        showDismissButton: Bool = true,
        isShown: Binding<Bool>
    ) {
        self.category = category
        self.title = title
        self.description = description
        self.buttonAction = buttonAction
        self.showDismissButton = showDismissButton
        _isShown = isShown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with category and close button
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    if let category = category {
                        Text(category.uppercased())
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                    Text(title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                }
                Spacer()
                if showDismissButton {
                    Button {
                        withAnimation {
                            isShown = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Color.fill)
                            .clipShape(Circle())
                    }
                }
            }
            
            // Title
            
            
            // Description
            Text(description)
//                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Optional action button
            if let buttonAction = buttonAction {
                Button {
                    buttonAction.action()
                } label: {
                    Text(buttonAction.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(Color.accentColor.secondaryTranslucentBackground)
                        .clipShape(Capsule())
                }
                .padding(.top, 4)
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }
}

#Preview {
    VStack(spacing: 20) {
        TipView(
            category: "Getting Started",
            title: "No Workouts Yet",
            description: "Start logging your training to track your progress.",
            isShown: .constant(true)
        )
        
        TipView(
            category: "Exercise Library",
            title: "No Exercises Yet",
            description: "Build your personal exercise library to get started.",
            buttonAction: .init(title: "Create Exercise", action: { }),
            isShown: .constant(true)
        )
        
        TipView(
            category: "Plan Ahead",
            title: "No Templates Yet",
            description: "Save your favorite routines for quick access.",
            buttonAction: .init(title: "Create Template", action: { }),
            isShown: .constant(true)
        )
    }
    .padding()
}
