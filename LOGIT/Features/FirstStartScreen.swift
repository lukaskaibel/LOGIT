//
//  FirstStartScreen.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 21.03.22.
//

import SwiftUI

struct FirstStartScreen: View {
    // MARK: - Environment
    
    @Environment(\.dismiss) var dismiss
    
    // MARK: - AppStorage

    @AppStorage("setupDone") var setupDone: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .foregroundStyle(.tertiary)
                .frame(width: 40, height: 5)
                .padding(.top, 8)
            
            ScrollView {
                VStack(spacing: SECTION_SPACING) {
                    // MARK: - Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("welcomeTo", comment: ""))
                            .font(.title2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("LOGIT")
                            .font(.system(size: 44, weight: .bold, design: .default))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 24)
                    
                    // MARK: - Feature Rows
                    VStack(alignment: .leading, spacing: 40) {
                        featureRow(
                            icon: "dumbbell.fill",
                            category: NSLocalizedString("track", comment: ""),
                            title: NSLocalizedString("workouts", comment: ""),
                            description: NSLocalizedString("welcomeWorkoutsDescription", comment: "")
                        )
                        
                        featureRow(
                            icon: "chart.line.uptrend.xyaxis",
                            category: NSLocalizedString("visualise", comment: ""),
                            title: NSLocalizedString("progress", comment: ""),
                            description: NSLocalizedString("welcomeProgressDescription", comment: "")
                        )
                        
                        featureRow(
                            icon: "list.bullet.rectangle.portrait",
                            category: NSLocalizedString("create", comment: ""),
                            title: NSLocalizedString("templates", comment: ""),
                            description: NSLocalizedString("welcomeTemplatesDescription", comment: "")
                        )
                        
                        featureRow(
                            icon: "target",
                            category: NSLocalizedString("set", comment: ""),
                            title: NSLocalizedString("goals", comment: ""),
                            description: NSLocalizedString("welcomeGoalsDescription", comment: "")
                        )
                    }
                    .padding(.top, 16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                Button {
                    setupDone = true
                    dismiss()
                } label: {
                    HStack {
                        Text(NSLocalizedString("getStarted", comment: ""))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .background {
                Rectangle()
                    .foregroundStyle(.ultraThinMaterial)
                    .ignoresSafeArea()
            }
        }
    }
    
    // MARK: - Feature Row
    
    private func featureRow(icon: String, category: String, title: String, description: String) -> some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(Color.accentColor)
                .frame(width: 50)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(category.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title3.weight(.bold))
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    Rectangle()
        .sheet(isPresented: .constant(true)) {
            FirstStartScreen()
                .preferredColorScheme(.dark)
        }
}
