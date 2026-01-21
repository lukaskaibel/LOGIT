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
        if let url = Bundle.main.url(forResource: "logit_privacy_policy", withExtension: "md"),
           let data = try? Data(contentsOf: url),
           let markdown = String(data: data, encoding: .utf8)
        {
            return markdown
        }
        return "Failed to load privacy policy"
    }
}

#Preview {
    PrivacyPolicyScreen()
        .preferredColorScheme(.dark)
}
