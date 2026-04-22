// ScanProgressView.swift
// Virtual Backup Box
//
// Shown while the Module 2 source scan is running. Displays a spinner and
// a live count of files found so far. Transitions automatically to
// ScanSummaryView when the scan completes.
//
// This view contains no business logic — it reads from ScanViewModel only.

import SwiftUI

struct ScanProgressView: View {

    var viewModel: ScanViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text("Scanning\u{2026}")
                .font(.title2)
                .fontWeight(.medium)

            Text("\(viewModel.filesFound) files found")
                .font(.title3)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())

            Spacer()
        }
        .padding()
        .navigationTitle("Scanning Source")
        .navigationBarBackButtonHidden(true)
    }
}
