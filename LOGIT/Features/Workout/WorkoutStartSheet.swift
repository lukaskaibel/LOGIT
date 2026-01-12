//
//  WorkoutStartSheet.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.01.26.
//

import SwiftUI

struct WorkoutStartSheet: View {
    
    // MARK: - Environment
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.presentWorkoutRecorder) var presentWorkoutRecorder
    @EnvironmentObject private var database: Database
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var workoutRecorder: WorkoutRecorder
    
    // MARK: - State
    
    @State private var isShowingScanScreen = false
    @State private var isShowingUpgradeToProSheet = false
    @State private var isShowingTemplateList = false
    @State private var isShowingPhotosPicker = false
    @State private var selectedDetent: PresentationDetent = .medium
    
    @State private var templateImage: UIImage?
    @State private var generatedTemplate: Template?
    
    // MARK: - Computed Properties
    
    private var currentTitle: String {
        if isShowingTemplateList {
            return NSLocalizedString("selectTemplate", comment: "")
        } else if isShowingScanScreen {
            return NSLocalizedString("scanAWorkout", comment: "")
        } else {
            return NSLocalizedString("startWorkout", comment: "")
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Group {
                if isShowingTemplateList {
                    TemplateListScreen(startWorkoutOnTap: true)
                } else if isShowingScanScreen {
                    ScanScreen(selectedImage: $templateImage, isShowingPhotosPicker: $isShowingPhotosPicker, type: .workout)
                } else {
                    mainContent
                        .padding(.horizontal, 20)
                        .padding(.top)
                        .edgesIgnoringSafeArea(.top)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(isShowingScanScreen ? .hidden : .automatic, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isShowingTemplateList {
                        Button {
                            withAnimation {
                                isShowingTemplateList = false
                                selectedDetent = .medium
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .fontWeight(.semibold)
                        }
                    } else if isShowingScanScreen {
                        Button {
                            withAnimation {
                                isShowingScanScreen = false
                                selectedDetent = .medium
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .fontWeight(.semibold)
                        }
                        .tint(.white)
                    }
                }
                ToolbarItem(placement: .principal) {
                    if isShowingTemplateList {
                        Text(currentTitle)
                            .font(.headline)
                    } else if isShowingScanScreen {
                        Text(currentTitle)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isShowingScanScreen {
                        Button {
                            isShowingPhotosPicker = true
                        } label: {
                            Image(systemName: "photo.on.rectangle")
                                .font(.body.weight(.medium))
                        }
                        .tint(.white)
                    } else if !isShowingTemplateList {
                        Button(role: .close) {
                            dismiss()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.hidden)
        .templateGeneration(from: $templateImage, to: $generatedTemplate)
        .onChange(of: generatedTemplate) { newValue in
            if let template = newValue {
                database.flagAsTemporary(template)
                workoutRecorder.startWorkout(from: template)
                dismiss()
                presentWorkoutRecorder()
            }
        }
        .sheet(isPresented: $isShowingUpgradeToProSheet) {
            UpgradeToProScreen()
        }
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(NSLocalizedString("startWorkout", comment: ""))
                    .font(.title)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(NSLocalizedString("workoutStartSheetDescription", comment: ""))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            VStack(spacing: 10) {
                Button {
                    withAnimation {
                        isShowingTemplateList = true
                        selectedDetent = .large
                    }
                } label: {
                    VStack(alignment: .leading) {
                        HStack(spacing: 15) {
                            Image(systemName: "list.bullet.rectangle.portrait")
                            VStack(alignment: .leading) {
                                Text(NSLocalizedString("useTemplate", comment: ""))
                                Text(NSLocalizedString("useTemplateDescription", comment: ""))
                                    .fontWeight(.regular)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .fontWeight(.bold)
                }
                .buttonStyle(.glass)
                
                Button {
                    if purchaseManager.hasUnlockedPro {
                        guard networkMonitor.isConnected else { return }
                        withAnimation {
                            isShowingScanScreen = true
                            selectedDetent = .large
                        }
                    } else {
                        isShowingUpgradeToProSheet = true
                    }
                } label: {
                    VStack(alignment: .leading) {
                        HStack(spacing: 15) {
                            Image(systemName: purchaseManager.hasUnlockedPro ? "camera.viewfinder" : "crown.fill")
                            VStack(alignment: .leading) {
                                Text(NSLocalizedString("scanWorkout", comment: ""))
                                Text(NSLocalizedString("scanWorkoutDescription", comment: ""))
                                    .fontWeight(.regular)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .fontWeight(.bold)
                }
                .buttonStyle(.glass)
                .requiresNetworkConnection()
            }
            
            Button {
                dismiss()
                workoutRecorder.startWorkout()
                presentWorkoutRecorder()
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        HStack(spacing: 15) {
                            Image(systemName: "plus")
                            VStack(alignment: .leading) {
                                Text(NSLocalizedString("newWorkout", comment: ""))
                                Text(NSLocalizedString("newWorkoutDescription", comment: ""))
                                    .fontWeight(.regular)
                            }
                            Spacer()
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
        .padding(.top, 5)
    }
}

#Preview {
    Text("Test")
        .sheet(isPresented: .constant(true)) {
            WorkoutStartSheet()
        }
        .previewEnvironmentObjects()
}
