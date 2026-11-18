//
//  NoticeBanner.swift
//  DailyReadings
//
//  Created for DailyReadings Catholic Daily Readings App.
//  iOS 17+ | Swift 6+
//

import SwiftUI

/// A short message above the readings with a Retry button: a failed load, or readings shown in a
/// different translation from the one chosen.
struct NoticeBanner: View {
    let message: String
    let accentColor: Color
    let retry: () async -> Void
    /// While a retry runs the button is replaced by a spinner, so repeated taps cannot start more.
    @State private var isRetrying = false

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
                .accessibilityHidden(true)

            Text(message)
                .font(.scaled(size: 14))
                .foregroundStyle(Color.primary)

            Spacer()

            if isRetrying {
                ProgressView()
                    .accessibilityLabel("Retrying")
            } else {
                Button("Retry") {
                    isRetrying = true
                    Task {
                        await retry()
                        isRetrying = false
                    }
                }
                .font(.scaled(size: 13, weight: .semibold))
                .foregroundStyle(accentColor)
            }
        }
        .padding(AppTheme.Spacing.medium)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
    }
}
