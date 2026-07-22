//
//  SettingsScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 01.10.21.
//

import StoreKit
import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager

    // MARK: - UserDefaults

    @AppStorage("weightUnit") var weightUnit: WeightUnit = .kg
    @AppStorage("preventAutoLock") var preventAutoLock: Bool = true
    @AppStorage("timerIsMuted") var timerIsMuted: Bool = false

    // MARK: - State

    @State private var isShowingUpgradeToPro = false
    @State private var isShowingPrivacyPolicy = false
    @State private var isShowingTermsAndConditions = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                generalSection
                workoutSection
                feedbackSection
                aboutSection
                subscriptionSection
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
                            Button { isShowingPrivacyPolicy = false } label: {
                                Text(NSLocalizedString("done", comment: ""))
                            }
                        }
                    }
                    .navigationBarTitleDisplayMode(.large)
            }
        }
        .sheet(isPresented: $isShowingTermsAndConditions) {
            NavigationStack {
                TermsAndConditionsScreen()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { isShowingTermsAndConditions = false } label: {
                                Text(NSLocalizedString("done", comment: ""))
                            }
                        }
                    }
                    .navigationBarTitleDisplayMode(.large)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: SECTION_HEADER_SPACING) {
            Text(title)
                .sectionHeaderStyle2()
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
    }

    private var generalSection: some View {
        section(NSLocalizedString("general", comment: "")) {
            HStack {
                Text(NSLocalizedString("unit", comment: ""))
                Spacer()
                Picker(NSLocalizedString("unit", comment: ""), selection: $weightUnit) {
                    Text("kg").tag(WeightUnit.kg)
                    Text("lbs").tag(WeightUnit.lbs)
                }
            }
            .padding(CELL_PADDING)
            .tileStyle()
        }
    }

    private var workoutSection: some View {
        section(NSLocalizedString("workout", comment: "")) {
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
        }
    }

    private var feedbackSection: some View {
        section(NSLocalizedString("feedbackAndSupport", comment: "")) {
            VStack(spacing: CELL_SPACING) {
                Link(destination: URL(string: "mailto:\(FEEDBACK_EMAIL)?subject=Feature%20Idea")!) {
                    HStack(spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("suggestAFeature", comment: ""))
                                .foregroundStyle(Color.label)
                            Text(NSLocalizedString("suggestAFeatureSubtitle", comment: ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(.secondary)
                    }
                    .padding(CELL_PADDING)
                    .tileStyle()
                }
                Link(destination: URL(string: "mailto:\(FEEDBACK_EMAIL)?subject=LOGIT%20Support")!) {
                    settingsRow(NSLocalizedString("support", comment: ""), icon: "questionmark.circle.fill", trailingSystemImage: "envelope.fill")
                }
                // Deliberately NOT `requestReview()`: that's a rate-limited request the
                // system usually ignores, which made this button appear broken. The
                // write-review deep link always lands on the App Store review page.
                Link(destination: URL(string: APP_STORE_WRITE_REVIEW_URL)!) {
                    settingsRow(NSLocalizedString("rateLogit", comment: ""), icon: "star.fill", trailingSystemImage: "arrow.up.forward.square")
                }
            }
        }
    }

    private var aboutSection: some View {
        section(NSLocalizedString("about", comment: "")) {
            VStack(spacing: CELL_SPACING) {
                Button { isShowingPrivacyPolicy = true } label: {
                    settingsRow(NSLocalizedString("privacyPolicy", comment: ""), icon: "hand.raised.fill", trailingChevron: true)
                }
                Button { isShowingTermsAndConditions = true } label: {
                    settingsRow(NSLocalizedString("termsAndConditions", comment: ""), icon: "doc.text.fill", trailingChevron: true)
                }
                Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                    settingsRow(NSLocalizedString("licenceAgreement", comment: ""), icon: "checkmark.seal.fill", trailingSystemImage: "arrow.up.forward.square")
                }
            }
        }
    }

    private var subscriptionSection: some View {
        section(NSLocalizedString("subscription", comment: "")) {
            Button {
                if purchaseManager.hasUnlockedPro {
                    Task {
                        if let window = UIApplication.shared.connectedScenes.first {
                            do {
                                try await AppStore.showManageSubscriptions(in: window as! UIWindowScene)
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
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: - Row helper

    /// A standard settings row — an optional leading accent icon, the title, and either a trailing
    /// chevron (a push) or a trailing system image (an external/link affordance).
    private func settingsRow(
        _ title: String,
        icon: String? = nil,
        trailingSystemImage: String? = nil,
        trailingChevron: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
            }
            Text(title)
                .foregroundStyle(Color.label)
            Spacer()
            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .foregroundStyle(.secondary)
            }
            if trailingChevron {
                NavigationChevron()
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
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
