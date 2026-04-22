// CurrentFileView.swift
// Virtual Backup Box
//
// Top region of the session progress screen. Shows what is happening right
// now: the phase (Copying or Verifying), the current filename, a per-file
// progress bar, the percentage complete, and the file size.
//
// For small files during verification (below verificationProgressThresholdBytes),
// shows an indeterminate spinner instead of a progress bar.
//
// This view contains no business logic — it reads from SessionViewModel only.

import SwiftUI

struct CurrentFileView: View {

    var viewModel: SessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch viewModel.currentPhase {
            case .copying(let name, let written, let total):
                phaseContent(
                    label: "Copying",
                    fileName: name,
                    bytesProgress: written,
                    totalBytes: total
                )

            case .verifying(let name, let bytesRead, let total):
                if total < Constants.verificationProgressThresholdBytes {
                    // Small file — spinner is more appropriate than a bar
                    // that fills instantly
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Verifying\u{2026}")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    Text(name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.body)
                } else {
                    phaseContent(
                        label: "Verifying",
                        fileName: name,
                        bytesProgress: bytesRead,
                        totalBytes: total
                    )
                }

            case .idle:
                EmptyView()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Shared layout for both copying and verifying phases when a progress
    /// bar is appropriate.
    private func phaseContent(
        label: String,
        fileName: String,
        bytesProgress: Int64,
        totalBytes: Int64
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(fileName)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)

            ProgressView(
                value: Double(bytesProgress),
                total: Double(max(totalBytes, 1))
            )

            HStack {
                Text("\(percentage(bytesProgress, totalBytes))%")
                Spacer()
                Text(ByteCountFormatter.string(
                    fromByteCount: totalBytes, countStyle: .file
                ))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private func percentage(_ current: Int64, _ total: Int64) -> Int {
        guard total > 0 else { return 0 }
        return Int(Double(current) / Double(total) * 100)
    }
}
