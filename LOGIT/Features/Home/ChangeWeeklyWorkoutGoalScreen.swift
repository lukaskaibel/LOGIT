//
//  ChangeWeeklyWorkoutGoalScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 18.10.24.
//

import SwiftUI

struct ChangeWeeklyWorkoutGoalScreen: View {
    @AppStorage("workoutPerWeekTarget") var targetPerWeek: Int = 3

    @Environment(\.dismiss) var dismiss

    @State private var selectedValue: Int = 0

    var body: some View {
        VStack {
            VStack(spacing: 25) {
                Text(NSLocalizedString("weeklyWorkoutGoal", comment: ""))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Set this to how many workouts you want to perform per week, to keep you motivated.")
                    .multilineTextAlignment(.center)
            }
            .padding(.top)
            Spacer()
            VStack {
                HStack {
                    Button {
                        guard selectedValue > 1 else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        selectedValue -= 1
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .font(.system(size: 50))
                    .disabled(selectedValue <= 1)
                    Text("\(selectedValue)")
                        .font(.system(size: 80))
                        .frame(minWidth: 160)
                        .fontWeight(.semibold)
                    Button {
                        guard selectedValue < 9 else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        selectedValue += 1
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .font(.system(size: 50))
                    .disabled(selectedValue >= 9)
                }
                .fontDesign(.rounded)
                Text(NSLocalizedString("workout\(selectedValue == 1 ? "" : "s")", comment: ""))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            Spacer()
            Button {
                targetPerWeek = selectedValue
                dismiss()
            } label: {
                Label(NSLocalizedString("changeGoal", comment: ""), systemImage: "checkmark")
            }
            .buttonStyle(PrimaryButtonStyle())
            Spacer()
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Text(NSLocalizedString("cancel", comment: ""))
                }
            }
        }
        .onAppear {
            // Default to 3 if no goal has been set yet (-1 means unset)
            selectedValue = targetPerWeek > 0 ? targetPerWeek : 3
        }
    }
}

#Preview {
    NavigationView {
        ChangeWeeklyWorkoutGoalScreen()
    }
    .previewEnvironmentObjects()
}
