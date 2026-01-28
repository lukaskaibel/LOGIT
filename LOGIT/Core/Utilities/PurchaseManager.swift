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

    // MARK: - Init / Deinit

    override init() {
        super.init()
        updates = observeTransactionUpdates()
        SKPaymentQueue.default().add(self)
    }

    deinit {
        self.updates?.cancel()
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
            UserDefaults(suiteName: "com.lukaskbl.LOGIT")?.object(forKey: "com.lukaskbl.LOGIT.expirationDate") as? Date
        }
        set {
            UserDefaults(suiteName: "com.lukaskbl.LOGIT")?.set(newValue, forKey: "com.lukaskbl.LOGIT.expirationDate")
            objectWillChange.send()
        }
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
        #if DEBUG
            return false
        #else
            if let proExpirationDate = proExpirationDate {
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
}

extension PurchaseManager: SKPaymentTransactionObserver {
    func paymentQueue(_: SKPaymentQueue, updatedTransactions _: [SKPaymentTransaction]) {}

    func paymentQueue(_: SKPaymentQueue, shouldAddStorePayment _: SKPayment, for _: SKProduct) -> Bool {
        return true
    }
}
