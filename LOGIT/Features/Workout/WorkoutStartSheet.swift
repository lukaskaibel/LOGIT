//
//  WorkoutStartSheet.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.01.26.
//

import SwiftUI

struct WorkoutStartSheet: View {
    
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var purchaseManager: PurchaseManager
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(NSLocalizedString("startWorkout", comment: ""))
                        .font(.title2.bold())
                    Spacer()
                    Button(role: .close) {
                        
                    }
                    .labelStyle(.iconOnly)
                }
                Text("Use a template, scan an existing workout, or start a new one.")
            }
            VStack {
                Button {
                    
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            HStack(spacing: 15) {
                                Image(systemName: "list.bullet.rectangle.portrait")
                                VStack(alignment: .leading) {
                                    Text(NSLocalizedString("useTemplate", comment: ""))
                                    Text("Use a pre-made workout template")
                                        .fontWeight(.regular)
                                }
                                Spacer()
    //                            NavigationChevron()
                            }
                        }
                    }.padding(10)
                    .fontWeight(.bold)
                }
                .buttonStyle(.glass)
                Button {
                    
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            HStack(spacing: 15) {
                                Image(systemName: purchaseManager.hasUnlockedPro ? "camera.viewfinder" : "crown.fill")
                                VStack(alignment: .leading) {
                                    Text(NSLocalizedString("scanWorkout", comment: ""))
                                    Text("Upload a picture of a workout")
                                        .fontWeight(.regular)
                                }
                                Spacer()
    //                            NavigationChevron()
                            }
                        }
                    }
                    .padding(10)
                    .fontWeight(.bold)
                }
                .buttonStyle(.glass)
                
            }
            Button {
                
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        HStack(spacing: 15) {
                            Image(systemName: "plus")
                            VStack(alignment: .leading) {
                                Text(NSLocalizedString("newWorkout", comment: ""))
                                Text("Start a new empty workout")
                                    .fontWeight(.regular)
                            }
                            Spacer()
//                            NavigationChevron()
                        }
                    }
                }
                .padding(10)
                .fontWeight(.bold)
                .foregroundStyle(.black)
            }
            .buttonStyle(.glassProminent)
            Spacer()
        }
        .padding(20)
        .padding(.top, 5)
        .presentationDetents([.medium])
    }
}

#Preview {
    Text("Test")
        .sheet(isPresented: .constant(true)) {
            WorkoutStartSheet()
        }
        .previewEnvironmentObjects()
}
