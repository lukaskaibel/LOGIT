//
//  StartWorkoutView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 13.05.24.
//

import SwiftUI

struct StartWorkoutView: View {
    
    // MARK: - Environment
    
    @EnvironmentObject var database: Database
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @EnvironmentObject var purchaseManager: PurchaseManager
    @EnvironmentObject var workoutRecorder: WorkoutRecorder
    
    // MARK: - State
    
    @State private var currentWorkoutViewHeight: CGFloat = 0
    @State private var isShowingScanScreen = false
    @State private var isShowingUpgradeToProSheet = false
    @State private var isShowingTemplateListScreen = false
    
    @State private var templateImage: UIImage?
    @State private var generatedTemplate: Template?
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            CurrentWorkoutView(workoutName: nil, workoutDate: .now)
                .opacity(0.0001)
                .fixedSize()
            HStack(spacing: 0) {
                Button {
                    withAnimation() {
                        workoutRecorder.startWorkout()
                    }
                } label: {
                    Label(NSLocalizedString("startWorkout", comment: ""), systemImage: "play.fill")
                        .font(.body.weight(.semibold))
                        .padding(20)
                        .frame(maxWidth: .infinity)
                }
                .background(.regularMaterial)
                .clipShape(UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: 15, bottomLeading: 15)))
                Rectangle()
                    .foregroundStyle(.clear)
                    .frame(width: 5)
                Menu {
                    Button {
                        isShowingTemplateListScreen = true
                    } label: {
                        Label("startFromTemplate", systemImage: "list.bullet.rectangle.portrait")
                    }
                    Button {
                        if purchaseManager.hasUnlockedPro {
                            guard networkMonitor.isConnected else { return }
                            isShowingScanScreen = true
                        } else {
                            isShowingUpgradeToProSheet = true
                        }
                    } label: {
                        Label("startFromScan", systemImage: purchaseManager.hasUnlockedPro ? "camera.fill" : "crown.fill")
                    }
                    .requiresNetworkConnection()
                } label: {
                    ZStack {
                        Text(" ")
                            .padding(20)
                        Image(systemName: "ellipsis")
                            .padding()
                            .frame(width: 60)
                            .font(.title3.weight(.semibold))
                    }
                }
                .background(.regularMaterial)
                .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 15, topTrailingRadius: 15))
            }
            .frame(height: currentWorkoutViewHeight)
        }
        .background {
            GeometryReader { geometry in
                Spacer()
                    .onAppear {
                        currentWorkoutViewHeight = geometry.size.height
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .templateGeneration(from: $templateImage, to: $generatedTemplate)
        .onChange(of: generatedTemplate) { newValue in
            if let template = newValue {
                database.flagAsTemporary(template)
                workoutRecorder.startWorkout(from: template)
            }
        }
        .fullScreenCover(isPresented: $isShowingScanScreen) {
            ScanScreen(selectedImage: $templateImage, type: .workout)
        }
        .sheet(isPresented: $isShowingUpgradeToProSheet) {
            UpgradeToProScreen()
        }
        .sheet(isPresented: $isShowingTemplateListScreen) {
            NavigationStack {
                TemplateListScreen(startWorkoutOnTap: true)
            }
        }
    }
}

#Preview {
    StartWorkoutView()
        .previewEnvironmentObjects()
}
