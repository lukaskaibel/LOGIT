//
//  FinishConfirmationSheet.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.03.25.
//

import SwiftUI

struct FinishConfirmationSheet: View {
    
    @Environment(\.dismiss) var dismiss
    
    let workout: Workout
    let onEndWorkout: () -> Void
    
    var body: some View {
        VStack {
            Text(NSLocalizedString("areYouSure?", comment: ""))
                .font(.title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            VStack(spacing: 10) {
                let setsWithoutEntry = workout.sets.filter({ !$0.hasEntry })
                Label("\(setsWithoutEntry.count > 0 ? "\(setsWithoutEntry.count)" : "") \(NSLocalizedString("\(setsWithoutEntry.count == 0 ? "allSetsCompleted" : "setsIncomplete")", comment: ""))", systemImage: setsWithoutEntry.count == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(setsWithoutEntry.count == 0 ? Color.accentColor : Color.secondary)
                    .fontWeight(.semibold)
                    .fontDesign(.rounded)
                    .font(.title3)
                if setsWithoutEntry.count > 0 {
                    Text(NSLocalizedString("incompleteSetsWillNotBeSaved", comment: ""))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 15) {
                Button {
                    dismiss()
                } label: {
                    Text(NSLocalizedString("continue", comment: ""))
                }
                .buttonStyle(BigButtonStyle())
                Button {
                    onEndWorkout()
                } label: {
                    Text(NSLocalizedString("endWorkout", comment: ""))
                }
                .buttonStyle(SecondaryBigButtonStyle())
            }
            Spacer()
        }
    }
}

private struct FinishConfirmationSheetPreviewWrapper: View {
    
    @EnvironmentObject private var database: Database
    
    var body: some View {
        Rectangle()
            .foregroundStyle(.gray)
            .sheet(isPresented: .constant(true)) {
                FinishConfirmationSheet(workout: database.testWorkout, onEndWorkout: {})
                    .padding([.top, .horizontal])
                    .presentationDetents([.fraction(0.4)])
            }
    }
}

#Preview {
    FinishConfirmationSheetPreviewWrapper()
        .previewEnvironmentObjects()
}
