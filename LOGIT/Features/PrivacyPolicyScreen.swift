//
//  PrivacyPolicyScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 20.10.23.
//

import MarkdownUI
import SwiftUI

struct PrivacyPolicyScreen: View {
    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Storage

    @AppStorage("acceptedPrivacyPolicyVersion") var acceptedVersion: Int?

    // MARK: - Parameters

    var needsAcceptance = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            Markdown(getPrivacyPolicyMarkdown())
                .padding(.horizontal)
                .padding(.bottom, 200)
        }
        .navigationTitle(NSLocalizedString("privacyPolicy", comment: ""))
        .overlay {
            if needsAcceptance {
                Button {
                    acceptedVersion = privacyPolicyVersion
                    dismiss()
                } label: {
                    Text(NSLocalizedString("acceptPrivacyPolicy", comment: ""))
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding()
                .frame(maxWidth: .infinity)
                .background {
                    Rectangle()
                        .foregroundStyle(.thinMaterial)
                        .edgesIgnoringSafeArea(.bottom)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    // MARK: - Computed Properties

    private func getPrivacyPolicyMarkdown() -> String {
        if let markdown = LocalizedMarkdown.load(named: "logit_privacy_policy") {
            return markdown
        }

        return NSLocalizedString("failedToLoadPrivacyPolicy", comment: "")
    }
}

#Preview {
    PrivacyPolicyScreen()
        .preferredColorScheme(.dark)
}
