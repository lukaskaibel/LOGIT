//
//  ProfileView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 01.10.21.
//

import SwiftUI
import StoreKit

struct SettingsScreen: View {
    
    @EnvironmentObject private var purchaseManager: PurchaseManager

    // MARK: - UserDefaults

    @AppStorage("weightUnit") var weightUnit: WeightUnit = .kg
    @AppStorage("workoutPerWeekTarget") var workoutPerWeekTarget: Int = 3
    @AppStorage("preventAutoLock") var preventAutoLock: Bool = true
    @AppStorage("timerIsMuted") var timerIsMuted: Bool = false
    
    // MARK: - State
    
    @State private var isShowingUpgradeToPro = false
    @State private var isShowingPrivacyPolicy = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                VStack(spacing: CELL_SPACING) {
                    HStack {
                        Text(NSLocalizedString("targetPerWeek", comment: ""))
                        Spacer()
                        Picker(
                            NSLocalizedString("targetPerWeek", comment: ""),
                            selection: $workoutPerWeekTarget
                        ) {
                            ForEach(1..<10, id: \.self) { i in
                                Text(String(i)).tag(i)
                            }
                        }
                    }
                    .padding(CELL_PADDING)
                    .tileStyle()
                    HStack {
                        Text(NSLocalizedString("unit", comment: ""))
                        Spacer()
                        Picker(
                            NSLocalizedString("unit", comment: ""),
                            selection: $weightUnit,
                            content: {
                                Text("kg").tag(WeightUnit.kg)
                                Text("lbs").tag(WeightUnit.lbs)
                            }
                        )
                    }
                    .padding(CELL_PADDING)
                    .tileStyle()
                }
                
                VStack(spacing: CELL_SPACING) {
                    VStack(alignment: .leading) {
                        Toggle(NSLocalizedString("preventAutoLock", comment: ""), isOn: $preventAutoLock)
                        Text(NSLocalizedString("preventAutoLockDescription", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(CELL_PADDING)
                    .tileStyle()
                    Toggle(NSLocalizedString("timerIsMuted", comment: ""), isOn: $timerIsMuted)
                        .padding(CELL_PADDING)
                        .tileStyle()
                }
                
                VStack(spacing: CELL_SPACING) {
                    Button {
                        isShowingPrivacyPolicy = true
                    } label: {
                        HStack {
                            Text(NSLocalizedString("privacyPolicy", comment: ""))
                            Spacer()
                            NavigationChevron()
                        }
                        .padding(CELL_PADDING)
                        .tileStyle()
                    }
                    Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                        HStack {
                            Text(NSLocalizedString("licenceAgreement", comment: ""))
                            Spacer()
                            Image(systemName: "arrow.up.forward.square")
                        }
                        .padding(CELL_PADDING)
                        .tileStyle()
                    }
                    
                }
                
                VStack(spacing: SECTION_HEADER_SPACING) {
                    Text(NSLocalizedString("subscription", comment: ""))
                        .sectionHeaderStyle2()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: CELL_SPACING) {
                        Button {
                            if purchaseManager.hasUnlockedPro {
                                Task {
                                    if let window = UIApplication.shared.connectedScenes.first {
                                       do {
                                           try  await AppStore.showManageSubscriptions(in: window as! UIWindowScene)
                                       } catch {
                                           print("Error:(error)")
                                       }
                                   }
                                }
                            } else {
                                isShowingUpgradeToPro = true
                            }
                        } label: {
                            if purchaseManager.hasUnlockedPro {
                                Text(NSLocalizedString("showSubscriptions", comment: ""))
                            } else {
                                HStack {
                                    Image(systemName: "crown.fill")
                                    Text(NSLocalizedString("upgradeTo", comment: ""))
                                    LogitProLogo()
                                        .environment(\.colorScheme, .light)
                                }
                            }
                        }
                        .buttonStyle(BigButtonStyle())
                    }
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle(NSLocalizedString("settings", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $isShowingUpgradeToPro) {
            UpgradeToProScreen()
        }
        .sheet(isPresented: $isShowingPrivacyPolicy) {
            NavigationStack {
                PrivacyPolicyScreen()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                isShowingPrivacyPolicy = false
                            } label: {
                                Text(NSLocalizedString("done", comment: ""))
                            }
                        }
                    }
                    .navigationBarTitleDisplayMode(.large)
            }
        }
    }

}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SettingsScreen()
        }
        .environmentObject(PurchaseManager())
    }
}
