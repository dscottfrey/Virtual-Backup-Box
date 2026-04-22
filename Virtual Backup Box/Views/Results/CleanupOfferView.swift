// CleanupOfferView.swift
// Virtual Backup Box
//
// The "Remove from iPad storage?" section shown on the results screen
// after a 100% successful backup session where the source was internal
// iPad storage. Offers to delete the source files to free space.
//
// Source deletion is the ONLY time the app writes to the source in the
// entire codebase. Every deletion callsite has the required §2 exception
// comment. The deletion requires explicit user confirmation via a
// confirmation sheet — it is never automatic.

import SwiftUI

struct CleanupOfferView: View {

    @Bindable var viewModel: ResultsViewModel

    var body: some View {
        VStack(spacing: 12) {
            Text("Remove from iPad storage?")
                .font(.headline)

            Text("All \(viewModel.session.filesCopied) files have been verified on \(viewModel.targetName.isEmpty ? "the target" : viewModel.targetName). You can remove them from iPad storage to free up space.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                // DELIBERATE EXCEPTION to read-only source rule (§2 of overall
                // directive). This button initiates source file deletion, which
                // only proceeds after the confirmation sheet below.
                Button("Remove from iPad") {
                    viewModel.showCleanupConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Button("Keep on iPad") {
                    viewModel.cleanupCompleted = true
                    viewModel.cleanupMessage = "Files kept on iPad."
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .confirmationDialog(
            "Delete Source Files",
            isPresented: $viewModel.showCleanupConfirmation,
            titleVisibility: .visible
        ) {
            // DELIBERATE EXCEPTION to read-only source rule (§2 of overall
            // directive). This deletion is triggered only by explicit user
            // confirmation after a 100% successful backup session.
            Button("Delete Files", role: .destructive) {
                viewModel.performSourceCleanup()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete \(viewModel.session.filesCopied) files (\(viewModel.formattedBytesCopied)) from your iPad. This cannot be undone. The files are safely stored on \(viewModel.targetName.isEmpty ? "the target" : viewModel.targetName).")
        }
    }
}
