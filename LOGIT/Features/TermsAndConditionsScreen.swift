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
        if let markdown = LocalizedMarkdown.load(named: "logit_terms_and_conditions") {
            return markdown
        }

        return NSLocalizedString("failedToLoadTermsAndConditions", comment: "")
    }
}

#Preview {
    NavigationStack {
        TermsAndConditionsScreen()
    }
    .preferredColorScheme(.dark)
}
