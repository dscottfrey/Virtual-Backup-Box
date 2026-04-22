// SessionResultsView.swift
// Virtual Backup Box
//
// Post-session results screen shown immediately when a backup session ends.
// Displays one of three outcome states (success, partial, interrupted) with
// a clear, unambiguous account of what happened. This screen cannot be
// skipped — the user must tap "Done" to acknowledge the result.
//
// For 100% successful sessions with internal local storage as the source,
// includes the CleanupOfferView.

import SwiftUI

struct SessionResultsView: View {

    var viewModel: ResultsViewModel
    var onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                outcomeSection
                detailsSection

                if viewModel.showCleanupOffer {
                    CleanupOfferView(viewModel: viewModel)
                }

                if viewModel.cleanupCompleted {
                    Text(viewModel.cleanupMessage)
                        .font(.subheadline)
                        .foregroundStyle(.green)
                        .padding()
                }

                doneButton
            }
            .padding()
        }
        .navigationTitle("Results")
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Outcome Heading

    @ViewBuilder
    private var outcomeSection: some View {
        switch viewModel.session.status {
        case .success:
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Backup Complete")
                    .font(.title2).fontWeight(.semibold)
                Text("\(viewModel.session.filesCopied) files \u{2014} \(viewModel.formattedBytesCopied) \u{2014} all verified")
                    .foregroundStyle(.secondary)
            }

        case .partialSuccess:
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text("Backup Completed with Warnings")
                    .font(.title2).fontWeight(.semibold)
                Text("\(viewModel.session.filesCopied) of \(viewModel.session.totalFilesFound - viewModel.session.filesSkipped) files backed up \u{2014} \(viewModel.session.filesFailed) could not be copied")
                    .foregroundStyle(.secondary)
            }

        case .interrupted:
            VStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text("Backup Interrupted")
                    .font(.title2).fontWeight(.semibold)
                Text("\(viewModel.session.filesCopied) of \(viewModel.session.totalFilesFound - viewModel.session.filesSkipped) files backed up before the session stopped")
                    .foregroundStyle(.secondary)
            }

        case .inProgress:
            EmptyView()
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.session.filesSkipped > 0 {
                Text("\(viewModel.session.filesSkipped) files were already backed up and skipped")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Text("Backed up to: \(viewModel.destinationDisplay)")
                .font(.subheadline).foregroundStyle(.secondary)

            if !viewModel.sessionDuration.isEmpty {
                Text("Completed in \(viewModel.sessionDuration)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            // Failed file list (partial success only)
            if !viewModel.failedFiles.isEmpty {
                failedFilesSection
            }

            // Explanation for partial/interrupted
            if viewModel.session.status == .partialSuccess {
                explanationBox("These files were not backed up. The files that succeeded are safely stored. You may want to try running the backup again \u{2014} the app will attempt only the files that failed.")
            }
            if viewModel.session.status == .interrupted {
                explanationBox("Files that were successfully backed up before the interruption are safely stored. Run the backup again to continue \u{2014} the app will skip files that are already done.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var failedFilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Failed Files")
                .font(.headline)
            ForEach(Array(viewModel.failedFiles.enumerated()), id: \.offset) { _, file in
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.relativePath)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(file.reason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func explanationBox(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Done

    private var doneButton: some View {
        Button {
            onDone()
        } label: {
            Text("Done")
                .font(.title3).fontWeight(.semibold)
                .frame(maxWidth: .infinity).padding()
        }
        .buttonStyle(.borderedProminent)
    }
}
