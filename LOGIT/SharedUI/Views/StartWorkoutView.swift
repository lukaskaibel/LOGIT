//
//  StartWorkoutView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 13.05.24.
//

import SwiftUI

struct StartWorkoutView: View {
    // MARK: - Environment

    @Environment(\.presentWorkoutRecorder) var presentWorkoutRecorder
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
            Menu {
                Button {
                    workoutRecorder.startWorkout()
                    presentWorkoutRecorder()
                } label: {
                    Label(NSLocalizedString("newWorkout", comment: ""), systemImage: "play.fill")
                        .font(.body.weight(.bold))
                        .padding(20)
                        .frame(maxWidth: .infinity)
                }
                ControlGroup {
                    Button {
                        isShowingTemplateListScreen = true
                    } label: {
                        Label("useTemplate", systemImage: "list.bullet.rectangle.portrait")
                    }
                    Button {
                        if purchaseManager.hasUnlockedPro {
                            guard networkMonitor.isConnected else { return }
                            isShowingScanScreen = true
                        } else {
                            isShowingUpgradeToProSheet = true
                        }
                    } label: {
                        Label("scanWorkout", systemImage: purchaseManager.hasUnlockedPro ? "camera.viewfinder" : "crown.fill")
                    }
                    .requiresNetworkConnection()
                }
            } label: {
                Label(NSLocalizedString("startWorkout", comment: ""), systemImage: "play.fill")
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }
            .tint(Color.label)
            .labelStyle(.titleAndIcon)
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
                presentWorkoutRecorder()
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
        .padding(10)
}
