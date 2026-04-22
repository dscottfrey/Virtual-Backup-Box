// ScanSummaryView.swift
// Virtual Backup Box
//
// Shown after the Module 2 scan completes. Presents a summary of what
// was found: files to copy, files already backed up, excluded system files,
// and available space on the target. The user confirms before copying begins.
//
// If everything is already backed up, shows a reassuring "all done" message
// instead of a Start Backup button.
//
// This view contains no business logic — it reads from ScanResult only.

import SwiftUI

struct ScanSummaryView: View {

    let result: ScanResult
    let availableSpaceBytes: Int64?

    /// Called when the user taps "Start Backup" to proceed to Module 3.
    var onStartBackup: () -> Void

    /// Called when the user taps "Cancel" to return to source selection.
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            if result.isFullyBackedUp {
                allBackedUpSection
            } else {
                filesToCopySection
            }

            alreadyBackedUpSection
            excludedSection
            spaceSection

            Spacer()

            buttonSection
        }
        .padding()
        .navigationTitle("Scan Complete")
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - All Backed Up

    /// Reassuring message when there is nothing new to copy.
    private var allBackedUpSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Everything is already backed up")
                .font(.title3)
                .fontWeight(.medium)
        }
        .padding(.vertical)
    }

    // MARK: - Files to Copy

    private var filesToCopySection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Files to copy")
                    .font(.headline)
                Text("\(result.filesToCopy.count) files \u{2014} \(formattedBytes(result.totalBytesToCopy))")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Already Backed Up

    @ViewBuilder
    private var alreadyBackedUpSection: some View {
        if !result.filesToSkip.isEmpty {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Already backed up")
                        .font(.headline)
                    Text("\(result.filesToSkip.count) files \u{2014} skipping")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Excluded

    @ViewBuilder
    private var excludedSection: some View {
        if result.excludedCount > 0 {
            HStack {
                Text("\(result.excludedCount) system files excluded")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Available Space

    @ViewBuilder
    private var spaceSection: some View {
        if let space = availableSpaceBytes {
            let isLow = space < Constants.minimumWarningSpaceBytes
            HStack {
                if isLow {
                    Label(
                        "\(formattedBytes(space)) available on target",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                } else {
                    Text("\(formattedBytes(space)) available on target")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.subheadline)
            .padding(.horizontal)
        }
    }

    // MARK: - Buttons

    private var buttonSection: some View {
        VStack(spacing: 12) {
            if result.isFullyBackedUp {
                Button {
                    onCancel()
                } label: {
                    Text("Done")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    onStartBackup()
                } label: {
                    Text("Start Backup")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)

                Button("Cancel", role: .cancel) {
                    onCancel()
                }
            }
        }
    }

    // MARK: - Helpers

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
