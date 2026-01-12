//
//  CreateTemplateMenu.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 31.07.23.
//

import Combine
import OSLog
import PhotosUI
import SwiftUI

struct CreateTemplateMenu: View {
    @EnvironmentObject private var database: Database
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var networkMonitor: NetworkMonitor

    @State private var isShowingScanScreen = false
    @State private var isShowingUpgradeToProScreen = false
    @State private var isShowingPhotosPicker = false

    @State private var templateImage: UIImage?
    @State private var newTemplate: Template?

    var body: some View {
        Menu {
            Button {
                newTemplate = database.newTemplate()
                database.flagAsTemporary(newTemplate!)
            } label: {
                Label(NSLocalizedString("newTemplate", comment: ""), systemImage: "plus")
            }
            Button {
                guard networkMonitor.isConnected else { return }
                if !purchaseManager.hasUnlockedPro {
                    isShowingUpgradeToProScreen = true
                } else {
                    isShowingScanScreen = true
                }
            } label: {
                Text(NSLocalizedString("scanATemplate", comment: ""))
                if !purchaseManager.hasUnlockedPro {
                    Image(systemName: "crown")
                } else {
                    Image(systemName: "camera")
                }
            }
            .requiresNetworkConnection()
        } label: {
            Image(systemName: "plus")
        }
        .templateGeneration(from: $templateImage, to: $newTemplate)
        .onChange(of: newTemplate) { newValue in
            guard let template = newValue else { return }
            database.flagAsTemporary(template)
        }
        .sheet(item: $newTemplate) { template in
            TemplateEditorScreen(
                template: template,
                isEditingExistingTemplate: false
            )
            .presentationBackground(Color.black)
        }
        .sheet(isPresented: $isShowingUpgradeToProScreen) {
            UpgradeToProScreen()
        }
        .fullScreenCover(isPresented: $isShowingScanScreen) {
            NavigationStack {
                ScanScreen(selectedImage: $templateImage, isShowingPhotosPicker: $isShowingPhotosPicker, type: .template)
                    .ignoresSafeArea()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                isShowingPhotosPicker = true
                            } label: {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.body.weight(.medium))
                            }
                            .tint(.white)
                        }
                        ToolbarItem(placement: .principal) {
                            Text(NSLocalizedString("scanATemplate", comment: ""))
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button(role: .close) {
                                isShowingScanScreen = false
                            }
                            .buttonStyle(.plain)
                            .tint(.white)
                        }
                    }
            }
        }
    }
}

struct CreateTemplateMenu_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CreateTemplateMenu()
        }
        .previewEnvironmentObjects()
    }
}
