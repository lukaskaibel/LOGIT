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
            HStack(spacing: 0) {
                Button {
                    workoutRecorder.startWorkout()
                    presentWorkoutRecorder()
                } label: {
                    Label(NSLocalizedString("startWorkout", comment: ""), systemImage: "play.fill")
                        .font(.body.weight(.bold))
                        .padding(20)
                        .frame(maxWidth: .infinity)
                }
                .foregroundStyle(.black)
                .background(Color.accentColor.opacity(0.9))
                .clipShape(UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: 15, bottomLeading: 15, bottomTrailing: 5, topTrailing: 5)))
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
                        Image(systemName: "play.fill")
                            .padding(2)
                            .overlay {
                                GeometryReader { geometry in
                                    ZStack {
                                        Circle()
                                            .fill(.black)
                                            .frame(width: geometry.size.width * 0.5, height: geometry.size.width * 0.5)
                                        Image(systemName: "ellipsis.circle.fill")
                                            .resizable()
                                            .frame(width: geometry.size.width * 0.4, height: geometry.size.width * 0.4)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                }
                            }
                            .padding()
                            .frame(width: 70)
                            .font(.title3.weight(.semibold))
                    }
                }
                .background(Color.accentColor.secondaryTranslucentBackground)
                .clipShape(UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: 5, bottomLeading: 5, bottomTrailing: 15, topTrailing: 15)))
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
