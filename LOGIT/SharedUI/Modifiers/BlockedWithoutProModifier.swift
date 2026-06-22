//
//  BlockedWithoutProModifier.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 27.09.23.
//

import SwiftUI

struct BlockedWithoutProModifier: ViewModifier {
    /// How the upsell button renders: `.regular` is the full "Available with LOGIT Pro" capsule;
    /// `.compact` is a crown-only capsule for surfaces too narrow to fit the text (the half-width
    /// exercise-detail tiles).
    enum Style {
        case regular, compact
    }

    @EnvironmentObject private var purchaseManager: PurchaseManager

    let blocked: Bool
    var style: Style = .regular

    @State private var isShowingUpgradeToProScreen = false

    func body(content: Content) -> some View {
        if !purchaseManager.hasUnlockedPro && blocked {
            content
                .overlay {
                    Color.black.opacity(0.3)
                        .edgesIgnoringSafeArea(.bottom)
                }
                .blur(radius: 8)
                .allowsHitTesting(false)
                .overlay {
                    Button {
                        isShowingUpgradeToProScreen = true
                    } label: {
                        HStack {
                            Image(systemName: "crown.fill")
                            if style == .regular {
                                Text(NSLocalizedString("availableWith", comment: ""))
                                LogitProLogo()
                                    .environment(\.colorScheme, .light)
                            }
                        }
                    }
                    .buttonStyle(CapsuleButtonStyle(color: .white))
                    .shadow(radius: 15)
                }
                .sheet(isPresented: $isShowingUpgradeToProScreen) {
                    NavigationStack {
                        UpgradeToProScreen()
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    func isBlockedWithoutPro(
        _ blocked: Bool = true,
        style: BlockedWithoutProModifier.Style = .regular
    ) -> some View {
        modifier(BlockedWithoutProModifier(blocked: blocked, style: style))
    }
}
