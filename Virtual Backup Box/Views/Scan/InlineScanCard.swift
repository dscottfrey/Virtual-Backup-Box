// InlineScanCard.swift
// Virtual Backup Box
//
// Renders the Module 2 scan inline on the main screen, below the Source
// and Target zones. Replaces the older two-screen flow (ScanProgressView
// pushed onto the navigation stack, then ScanSummaryView with its own
// "Start Backup" button on a separate "Scan Complete" page).
//
// Why inline: tapping "Verify Backup Flow" should feel like running a
// quick check in place — not navigating away to a separate page and back.
// The user sees the result without losing sight of which Source and Target
// it relates to. A second tap on "Start Copying" inside this card pushes
// to the live session page.
//
// Two visual states:
//   1. Scanning   — spinner + running file count
//   2. Complete   — summary sections + Start Copying / Done / Cancel buttons
//
// This view contains no business logic. It reads from ScanViewModel
// and calls back to its parent for the start-copy / dismiss actions.

import SwiftUI

struct InlineScanCard: View {

    var viewModel: ScanViewModel

    /// Called when the user taps "Start Copying" in the summary state.
    var onStartCopying: () -> Void

    /// Called when the user dismisses the card (Done after fully-backed-up,
    /// or Cancel after a normal summary). Parent should clear its
    /// ScanViewModel reference so the card disappears.
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let result = viewModel.scanResult {
                summaryContent(result: result)
            } else {
                scanningContent
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Scanning State

    /// Shown while the scan runs. Mirrors the old ScanProgressView but
    /// inline and without navigation chrome.
    private var scanningContent: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text("Scanning\u{2026}")
                    .font(.headline)
                Text("\(viewModel.filesFound) files found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
        }
    }

    // MARK: - Summary State

    /// Shown once scanResult is set. Lays out the summary sections then
    /// the action buttons. The "all backed up" case collapses to a single
    /// reassuring row plus a Done button. Cloud-only files take precedence
    /// over everything else: when present, the whole session is blocked
    /// until the user downloads them — see cloudOnlyBlock.
    @ViewBuilder
    private func summaryContent(result: ScanResult) -> some View {
        if result.hasCloudOnlyBlock {
            cloudOnlyBlock(result: result)
            doneButton
        } else if result.isFullyBackedUp {
            allBackedUpRow
            doneButton
        } else {
            if !result.filesToCopy.isEmpty {
                filesToCopyRow(result: result)
            }
            if !result.filesToVerifyOnly.isEmpty {
                verifyOnlyRow(result: result)
            }
            if !result.filesToSkip.isEmpty {
                alreadyBackedUpRow(result: result)
            }
            if result.excludedCount > 0 {
                excludedRow(count: result.excludedCount)
            }
            if let space = viewModel.availableSpaceBytes {
                spaceRow(bytes: space)
            }

            startCopyingButton
            cancelButton
        }
    }

    /// The hard-fail warning shown when the scan finds iCloud files in
    /// the source that haven't been downloaded to this device. Names up
    /// to three example file paths so the user can find them in Files.
    /// The Start Copying button is omitted — Done is the only way out.
    private func cloudOnlyBlock(result: ScanResult) -> some View {
        let examples = result.cloudOnlyFiles.prefix(3).joined(separator: "\n")
        let more = result.cloudOnlyFiles.count > 3
            ? "\n\u{2026} and \(result.cloudOnlyFiles.count - 3) more"
            : ""

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "icloud.slash")
                    .font(.title)
                    .foregroundStyle(.orange)
                Text("\(result.cloudOnlyFiles.count) files aren\u{2019}t downloaded yet")
                    .font(.headline)
            }
            Text("These files live in iCloud and haven\u{2019}t been copied to this device. Open the source in Files, set the files (or the whole folder) to \u{201C}Keep on This Device,\u{201D} wait for the downloads to finish, then tap Verify Backup Flow again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(examples)\(more)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    // MARK: - Summary Rows

    private var allBackedUpRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(.green)
            Text("Everything is already backed up")
                .font(.headline)
            Spacer()
        }
    }

    private func filesToCopyRow(result: ScanResult) -> some View {
        summaryRow(
            title: "Files to copy",
            detail: "\(result.filesToCopy.count) files \u{2014} \(formattedBytes(result.totalBytesToCopy))"
        )
    }

    private func verifyOnlyRow(result: ScanResult) -> some View {
        summaryRow(
            title: "Already at destination",
            detail: "\(result.filesToVerifyOnly.count) files \u{2014} \(formattedBytes(result.totalBytesToVerify)) \u{2014} will verify and record"
        )
    }

    private func alreadyBackedUpRow(result: ScanResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Already backed up").font(.subheadline).fontWeight(.medium)
                Text("\(result.filesToSkip.count) files \u{2014} skipping")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func excludedRow(count: Int) -> some View {
        Text("\(count) system files excluded")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func spaceRow(bytes: Int64) -> some View {
        let isLow = bytes < Constants.minimumWarningSpaceBytes
        if isLow {
            Label(
                "\(formattedBytes(bytes)) available on target",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
        } else {
            Text("\(formattedBytes(bytes)) available on target")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Shared layout for the headline + secondary-detail rows.
    private func summaryRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline).fontWeight(.medium)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Buttons

    private var startCopyingButton: some View {
        Button(action: onStartCopying) {
            Text("Start Copying")
                .font(.title3)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .padding(.top, 4)
    }

    private var doneButton: some View {
        Button(action: onDismiss) {
            Text("Done")
                .font(.title3)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .padding(.top, 4)
    }

    private var cancelButton: some View {
        Button("Cancel", role: .cancel, action: onDismiss)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
