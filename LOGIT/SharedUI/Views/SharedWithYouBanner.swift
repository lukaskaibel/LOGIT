//
//  SharedWithYouBanner.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 04.02.26.
//

import SwiftUI

/// A banner view that indicates content was shared with the user
/// Styled similarly to Apple's AirDrop received content UI
struct SharedWithYouBanner: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.title2)
                .foregroundStyle(Color.secondary)
                .symbolRenderingMode(.hierarchical)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        SharedWithYouBanner(
            title: "Shared Workout",
            subtitle: "Someone invited you to add this workout to your history"
        )
        
        SharedWithYouBanner(
            title: "Shared Template",
            subtitle: "Review and save this template to your collection"
        )
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}
