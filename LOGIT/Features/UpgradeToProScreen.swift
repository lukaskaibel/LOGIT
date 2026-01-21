//
//  UpgradeToProScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 14.09.23.
//

import SwiftUI

struct UpgradeToProScreen: View {
    // MARK: - Environment

    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Capsule()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 5)
                    .padding(.top)
                VStack(spacing: SECTION_SPACING) {
                    LogitProLogo()
                        .font(.largeTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()

                    VStack(alignment: .leading, spacing: 50) {
                        VStack {
                            HStack(spacing: 30) {
                                Image(systemName: "chart.bar.xaxis")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading) {
                                    Text(NSLocalizedString("visualise", comment: "").uppercased())
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                    Text(NSLocalizedString("charts", comment: ""))
                                        .font(.title3.weight(.bold))
                                    Text(NSLocalizedString("chartsPromotionText", comment: ""))
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                        VStack {
                            HStack(spacing: 30) {
                                Image(systemName: "camera")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading) {
                                    Text(NSLocalizedString("saveTime", comment: "").uppercased())
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(NSLocalizedString("scanAWorkout", comment: ""))
                                        .font(.title3.weight(.bold))
                                    Text(NSLocalizedString("scanAWorkoutPromotionText", comment: ""))
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                        VStack {
                            HStack(spacing: 30) {
                                Image(systemName: "ruler")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading) {
                                    Text(NSLocalizedString("trackMore", comment: "").uppercased())
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                    Text(NSLocalizedString("measurements", comment: ""))
                                        .font(.title3.weight(.bold))
                                    Text(NSLocalizedString("measurementsPromotionDescription", comment: ""))
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                    }
                    .padding(.leading, 25)
                    .padding(.trailing)
                }
            }
            .padding(.bottom, 200)
        }
        .overlay {
            VStack(spacing: 20) {
                VStack(alignment: .leading) {
                    HStack {
                        Text(NSLocalizedString("price", comment: ""))
                        Spacer()
                        HStack(alignment: .lastTextBaseline, spacing: 3) {
                            Text(purchaseManager.proSubscriptionMonthlyPriceString)
                                .font(.body.weight(.semibold))
                            Text("/ \(NSLocalizedString("month", comment: ""))")
                                .font(.footnote.weight(.semibold))
                        }
                    }
                    Text(NSLocalizedString("autoRenewMonth", comment: ""))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task {
                        guard networkMonitor.isConnected else { return }
                        do {
                            try await purchaseManager.subscribeToProMonthly()
                        } catch {
                            // TODO: Show Alert for Error during purchase
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "crown.fill")
                        Text(NSLocalizedString("upgradeTo", comment: ""))
                        LogitProLogo()
                            .environment(\.colorScheme, .light)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .requiresNetworkConnection()
                Button {
                    Task {
                        do {
                            try await purchaseManager.restorePurchase()
                        } catch {
                            // TODO: Show Alert for Restore Purchase failed
                        }
                    }
                } label: {
                    Text(NSLocalizedString("restorePurchase", comment: ""))
                        .foregroundStyle(Color.label)
                }
            }
            .padding()
            .background {
                Rectangle()
                    .foregroundStyle(.thinMaterial)
                    .edgesIgnoringSafeArea(.bottom)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .onChange(of: purchaseManager.hasUnlockedPro) { newValue in
            if newValue {
                dismiss()
            }
        }
    }
}

struct UpgradeToProScreen_Previews: PreviewProvider {
    static var previews: some View {
        UpgradeToProScreen()
            .previewEnvironmentObjects()
    }
}
