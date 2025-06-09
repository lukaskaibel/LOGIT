//
//  NetworkMonitor.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 19.10.23.
//

import Foundation
import Network

class NetworkMonitor: ObservableObject {
    private var monitor: NWPathMonitor
    private var queue: DispatchQueue

    @Published var isConnected: Bool = false

    init() {
        monitor = NWPathMonitor()
        queue = DispatchQueue(label: "NetworkMonitor")
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}
