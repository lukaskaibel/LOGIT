//
//  PreviewEnvironmentObjects.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 16.10.23.
//

import SwiftUI

struct PreviewEnvironmentObjects: ViewModifier {
    
    @StateObject private var database: Database
    @StateObject private var workoutRepository: WorkoutRepository
    @StateObject private var workoutSetRepository: WorkoutSetRepository
    @StateObject private var templateService: TemplateService
    @StateObject private var measurementController: MeasurementEntryController
    @StateObject private var purchaseManager: PurchaseManager
    @StateObject private var networkMonitor: NetworkMonitor
    @StateObject private var workoutRecorder: WorkoutRecorder
    
    init() {
        let db = Database(isPreview: true)
        let cwm = CurrentWorkoutManager(database: db)
        let wr = WorkoutRepository(database: db, currentWorkoutManager: cwm)
        let wsr = WorkoutSetRepository(database: db, currentWorkoutManager: cwm)
        _database = StateObject(wrappedValue: db)
        _workoutRepository = StateObject(wrappedValue: wr)
        _workoutSetRepository = StateObject(wrappedValue: wsr)
        _templateService = StateObject(wrappedValue: TemplateService(database: db))
        _measurementController = StateObject(wrappedValue: MeasurementEntryController(database: db))
        _purchaseManager = StateObject(wrappedValue: PurchaseManager())
        _networkMonitor = StateObject(wrappedValue: NetworkMonitor())
        _workoutRecorder = StateObject(wrappedValue: WorkoutRecorder(database: db, workoutRepository: wr, currentWorkoutManager: cwm))
    }

    func body(content: Content) -> some View {
        content
            .environmentObject(database)
            .environmentObject(workoutRepository)
            .environmentObject(workoutSetRepository)
            .environmentObject(templateService)
            .environmentObject(measurementController)
            .environmentObject(purchaseManager)
            .environmentObject(networkMonitor)
            .environmentObject(workoutRecorder)
            .task {
                Task {
                    do {
                        try await purchaseManager.loadProducts()
                    } catch {
                        print(error)
                    }
                }
            }
    }
}

extension View {
    func previewEnvironmentObjects() -> some View {
        modifier(PreviewEnvironmentObjects())
    }
}
