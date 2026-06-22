//
//  PurchaseManager.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.10.23.
//

import OSLog
import StoreKit
import SwiftUI

enum PurchaseError: Error {
    case productNotFound
}

@MainActor
class PurchaseManager: NSObject, ObservableObject {
    // MARK: - Constants

    private let proSubscriptionMonthlyId = "com.lukaskbl.LOGIT.prosubscriptionmonthly"

    // MARK: - Private Variables

    private var products: [Product]?
    private var purchasedProductIDs: [String]?
    private var updates: Task<Void, Never>? = nil
    private var purchaseIntents: Task<Void, Never>? = nil

    // MARK: - Init / Deinit

    override init() {
        super.init()
        updates = observeTransactionUpdates()
        purchaseIntents = observePurchaseIntents()
    }

    deinit {
        self.updates?.cancel()
        self.purchaseIntents?.cancel()
    }

    // MARK: - Public Methods / Variables

    func loadProducts() async throws {
        products = try await Product.products(for: [proSubscriptionMonthlyId])
        proSubscriptionMonthlyPriceString = products?.first(where: { $0.id == proSubscriptionMonthlyId })?.displayPrice ?? proSubscriptionMonthlyPriceString
        await updateProExpirationDate()
    }

    func restorePurchase() async throws {
        try await AppStore.sync()
    }

    var proExpirationDate: Date? {
        get {
            Self.storedProExpirationDate
        }
        set {
            UserDefaults(suiteName: "com.lukaskbl.LOGIT")?.set(newValue, forKey: "com.lukaskbl.LOGIT.expirationDate")
            objectWillChange.send()
        }
    }

    private nonisolated static var storedProExpirationDate: Date? {
        UserDefaults(suiteName: "com.lukaskbl.LOGIT")?.object(forKey: "com.lukaskbl.LOGIT.expirationDate") as? Date
    }

    var proSubscriptionMonthlyPriceString: String {
        get {
            (UserDefaults(suiteName: "com.lukaskbl.LOGIT")?.object(forKey: "com.lukaskbl.LOGIT.proSubscriptionMonthlyPriceString") as? String) ?? "-.--"
        }
        set {
            UserDefaults(suiteName: "com.lukaskbl.LOGIT")?.set(newValue, forKey: "com.lukaskbl.LOGIT.proSubscriptionMonthlyPriceString")
            objectWillChange.send()
        }
    }

    var hasUnlockedPro: Bool {
        Self.isProUnlocked
    }

    /// Pro state readable without a `PurchaseManager` instance — the entitlement's expiration date
    /// is persisted in UserDefaults (see `proExpirationDate`), so non-view code like the
    /// Pro-dependent default progress metric can consult it. `hasUnlockedPro` delegates here.
    nonisolated static var isProUnlocked: Bool {
        #if DEBUG
        // The blanket simulator unlock below makes the free tier untestable there — this launch
        // argument is the only way to exercise Pro-gated UI states in the simulator.
        if ProcessInfo.processInfo.arguments.contains("-UITEST_FORCE_FREE") {
            return false
        }
        #endif
        #if targetEnvironment(simulator)
        // Pro is always unlocked in the simulator so gated features are testable.
        return true
        #else
        if ScreenshotFixtures.isEnabled {
            return true
        }
        if let proExpirationDate = storedProExpirationDate {
            return proExpirationDate > .now
        }
        return false
        #endif
    }

    func subscribeToProMonthly() async throws {
        guard let proMonthlyProduct = products?.first(where: { $0.id == proSubscriptionMonthlyId }) else {
            throw PurchaseError.productNotFound
        }
        try await purchase(proMonthlyProduct)
    }

    // MARK: - Private Methods

    private func purchase(_ product: Product) async throws {
        let result = try await product.purchase()

        switch result {
        case let .success(.verified(transaction)):
            // Successful purchase
            await transaction.finish()
            await updateProExpirationDate()
        case let .success(.unverified(_, error)):
            throw error
        case .pending:
            // Transaction waiting on SCA (Strong Customer Authentication) or
            // approval from Ask to Buy
            break
        case .userCancelled:
            // ^^^
            break
        @unknown default:
            break
        }
    }

    private func updateProExpirationDate() async {
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result, transaction.revocationDate == nil else {
                continue
            }

            proExpirationDate = transaction.expirationDate
            return
        }
        proExpirationDate = nil
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) { [unowned self] in
            for await _ in Transaction.updates {
                await self.updateProExpirationDate()
            }
        }
    }

    /// Continues purchases started from the App Store (promoted in-app purchases) —
    /// the StoreKit 2 replacement for `SKPaymentTransactionObserver.paymentQueue(_:shouldAddStorePayment:for:)`.
    private func observePurchaseIntents() -> Task<Void, Never> {
        Task(priority: .background) { [unowned self] in
            for await intent in PurchaseIntent.intents {
                try? await self.purchase(intent.product)
            }
        }
    }
}
