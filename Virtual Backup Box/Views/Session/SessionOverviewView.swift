// SessionOverviewView.swift
// Virtual Backup Box
//
// Bottom region of the session progress screen. Shows the overall session
// status: file count fraction, overall progress bar, bytes transferred,
// elapsed time, estimated time remaining, skipped file count, and the
// cancel button.
//
// Elapsed time and time remaining are driven by a TimelineView that ticks
// every second — no Timer is used.
//
// This view contains no business logic — it reads from SessionViewModel only.

import SwiftUI

struct SessionOverviewView: View {

    var viewModel: SessionViewModel
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Large file count
            Text("\(viewModel.filesCompleted) of \(viewModel.totalFiles) files")
                .font(.title)
                .fontWeight(.semibold)
                .contentTransition(.numericText())

            // Overall progress bar
            ProgressView(
                value: Double(viewModel.filesCompleted),
                total: Double(max(viewModel.totalFiles, 1))
            )

            // Bytes transferred
            Text("\(formattedBytes(viewModel.totalBytesWritten)) of \(formattedBytes(viewModel.totalBytesToProcess))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Elapsed time and estimated remaining (ticks every second)
            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                timeSection(now: context.date)
            }

            // Files skipped from previous sessions
            if viewModel.filesSkipped > 0 {
                Text("\(viewModel.filesSkipped) already backed up \u{2014} skipped")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Failures so far
            if viewModel.filesFailed > 0 {
                Text("\(viewModel.filesFailed) failed")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            Spacer()

            // Cancel button
            HStack {
                Spacer()
                Button("Cancel Backup", role: .destructive) {
                    onCancel()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Time Display

    /// Shows elapsed time and estimated time remaining.
    private func timeSection(now: Date) -> some View {
        let elapsed = now.timeIntervalSince(viewModel.sessionStartDate)

        return HStack {
            Text("Elapsed: \(formatDuration(elapsed))")
            Spacer()
            Text(estimatedRemaining(elapsed: elapsed))
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    /// Computes estimated time remaining from the overall average transfer
    /// rate. Shows "Calculating..." for the first 5 seconds.
    private func estimatedRemaining(elapsed: TimeInterval) -> String {
        guard elapsed >= 5 else { return "Calculating\u{2026}" }

        let bytesWritten = viewModel.totalBytesWritten
        guard bytesWritten > 0 else { return "\u{2014}" }

        let rate = Double(bytesWritten) / elapsed
        let remaining = viewModel.totalBytesToProcess - bytesWritten
        guard remaining > 0 else { return "< 1 minute" }

        let seconds = Double(remaining) / rate
        return formatDuration(seconds) + " remaining"
    }

    // MARK: - Formatting

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Formats a duration in seconds to a human-readable string.
    /// Over a minute: no seconds precision (avoids flicker).
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        if total < 60 { return "< 1 minute" }

        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m \(secs)s"
    }
}
