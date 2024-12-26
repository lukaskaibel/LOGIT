//
//  InfoView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 26.12.24.
//

import SwiftUI

struct InfoView: View {
    
    let title: String
    let infoText: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: "info.circle")
                .fontWeight(.bold)
            Text(infoText)
        }
        .frame(width: 300)
        .padding()
        .presentationCompactAdaptation(.none)
    }
}

#Preview {
    InfoView(title: "Info View", infoText: "This view gives information about what something is or how it can be used.")
}
