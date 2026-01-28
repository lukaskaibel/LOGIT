//
//  TermsAndConditionsScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 28.01.26.
//

import MarkdownUI
import SwiftUI

struct TermsAndConditionsScreen: View {
    var body: some View {
        ScrollView {
            Markdown(getTermsMarkdown())
                .padding(.horizontal)
                .padding(.bottom, 200)
        }
        .navigationTitle(NSLocalizedString("termsAndConditions", comment: ""))
    }

    private func getTermsMarkdown() -> String {
        if let url = Bundle.main.url(forResource: "logit_terms_and_conditions", withExtension: "md"),
           let data = try? Data(contentsOf: url),
           let markdown = String(data: data, encoding: .utf8)
        {
            return markdown
        }
        return "Failed to load terms and conditions"
    }
}

#Preview {
    NavigationStack {
        TermsAndConditionsScreen()
    }
    .preferredColorScheme(.dark)
}
