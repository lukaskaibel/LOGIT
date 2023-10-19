//
//  TemplateGenerationScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 04.08.23.
//

import Combine
import SwiftUI

struct TemplateGenerationScreen: View {

    // MARK: - Environment

    @Environment(\.dismiss) var dismiss

    // MARK: - Parameters

    @Binding var templateExtration: AnyCancellable?

    // MARK: - Body

    var body: some View {
        VStack {
            VStack(alignment: .leading) {
                Text(NSLocalizedString("generatingTemplate", comment: ""))
                    .font(.largeTitle.weight(.bold))
                Text(NSLocalizedString("FromPhoto", comment: ""))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .padding(.top, 20)

            Spacer()
            VStack(spacing: 30) {
                ProgressView()
                    .progressViewStyle(.circular)
                Text(NSLocalizedString("onlyFewSeconds", comment: ""))
                    .frame(maxWidth: 200)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button {
                templateExtration?.cancel()
                dismiss()
            } label: {
                Text(NSLocalizedString("cancel", comment: ""))
            }
            .buttonStyle(BigButtonStyle())
            .padding(.bottom, 50)
            .padding(.horizontal)
        }
    }
}

struct TemplateGenerationScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TemplateGenerationScreen(templateExtration: .constant(nil))
        }
    }
}
