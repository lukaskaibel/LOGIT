//
//  UpgradeToProScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 14.09.23.
//

import SwiftUI

struct UpgradeToProScreen: View {
    /// A failed StoreKit interaction, surfaced as an alert — a silent failure at the moment
    /// someone tries to pay is the most expensive bug a paywall can have.
    private enum PurchaseFlowError: Identifiable {
        case purchaseFailed, restoreFailed

        var id: Self { self }

        var title: String {
            switch self {
            case .purchaseFailed: return NSLocalizedString("purchaseFailed", comment: "")
            case .restoreFailed: return NSLocalizedString("restoreFailed", comment: "")
            }
        }

        var message: String {
            switch self {
            case .purchaseFailed: return NSLocalizedString("purchaseFailedText", comment: "")
            case .restoreFailed: return NSLocalizedString("restoreFailedText", comment: "")
            }
        }
    }

    // MARK: - Environment

    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @Environment(\.dismiss) var dismiss

    // MARK: - State

    @State private var purchaseFlowError: PurchaseFlowError?

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
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading) {
                                    Text(NSLocalizedString("stayMotivated", comment: "").uppercased())
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                    Text(NSLocalizedString("liveProgress", comment: ""))
                                        .font(.title3.weight(.bold))
                                    Text(NSLocalizedString("liveProgressPromotionText", comment: ""))
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
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
                    Text("\(NSLocalizedString("autoRenewMonth", comment: "")) — \(NSLocalizedString("cancelAnytime", comment: ""))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task {
                        guard networkMonitor.isConnected else { return }
                        do {
                            try await purchaseManager.subscribeToProMonthly()
                        } catch {
                            purchaseFlowError = .purchaseFailed
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
                            purchaseFlowError = .restoreFailed
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
        .onChange(of: purchaseManager.hasUnlockedPro) { _, newValue in
            if newValue {
                dismiss()
            }
        }
        .alert(
            purchaseFlowError?.title ?? "",
            isPresented: Binding(
                get: { purchaseFlowError != nil },
                set: { if !$0 { purchaseFlowError = nil } }
            ),
            presenting: purchaseFlowError
        ) { _ in
            Button(NSLocalizedString("ok", comment: "")) {}
        } message: { error in
            Text(error.message)
        }
    }
}

struct UpgradeToProScreen_Previews: PreviewProvider {
    static var previews: some View {
        UpgradeToProScreen()
            .previewEnvironmentObjects()
    }
}
