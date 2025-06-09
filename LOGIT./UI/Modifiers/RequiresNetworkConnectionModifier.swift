//
//  RequiresNetworkConnectionModifier.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 19.10.23.
//

import SwiftUI

struct RequiresNetworkConnectionModifier: ViewModifier {
    @EnvironmentObject private var networkMonitor: NetworkMonitor

    @State private var isShowingNoConnectinoAlert = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        if !networkMonitor.isConnected {
                            isShowingNoConnectinoAlert = true
                        }
                    }
            )
            .alert(isPresented: $isShowingNoConnectinoAlert) {
                Alert(
                    title: Text("No Network Connection"),
                    message: Text("Please check your internet connection and try again."),
                    dismissButton: .default(Text("Ok"))
                )
            }
    }
}

extension View {
    func requiresNetworkConnection() -> some View {
        modifier(RequiresNetworkConnectionModifier())
    }
}
