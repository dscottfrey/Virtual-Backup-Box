// SessionDetailView.swift
// Virtual Backup Box
//
// Full detail view for a single past backup session. Shows all summary
// information, session duration, and file lists. Successful files are
// collapsed by default; failed file count is always visible.
//
// For sessions where source files were deleted after backup, a note
// indicates this.

import SwiftUI

struct SessionDetailView: View {

    let session: CopySession
    @State private var showSuccessfulFiles = false

    var body: some View {
        List {
            // Summary section
            Section("Summary") {
                labelRow("Status", value: statusText)
                labelRow("Date", value: session.startDate.formatted(
                    .dateTime.month().day().year().hour().minute()
                ))
                labelRow("Duration", value: durationText)
                labelRow("Source", value: session.sourceCard?.friendlyName
                    ?? URL(fileURLWithPath: session.sourcePath).lastPathComponent)
                labelRow("Destination", value: session.sessionFolderName)
                labelRow("Files Copied", value: "\(session.filesCopied)")
                labelRow("Files Skipped", value: "\(session.filesSkipped)")
                if session.filesFailed > 0 {
                    labelRow("Files Failed", value: "\(session.filesFailed)")
                }
            }

            // Source deleted note
            if session.sourceFilesDeleted {
                Section {
                    Label(
                        "Source files were removed from local storage after this backup.",
                        systemImage: "trash"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            // Successful files (collapsed by default)
            Section {
                DisclosureGroup(
                    "\(session.fileRecords.count) verified files",
                    isExpanded: $showSuccessfulFiles
                ) {
                    ForEach(session.fileRecords.sorted(
                        by: { $0.relativeSourcePath < $1.relativeSourcePath }
                    )) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.relativeSourcePath)
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(ByteCountFormatter.string(
                                fromByteCount: record.fileSizeBytes,
                                countStyle: .file
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Session Detail")
    }

    // MARK: - Helpers

    private var statusText: String {
        switch session.status {
        case .success: return "Success"
        case .partialSuccess: return "Partial Success"
        case .interrupted: return "Interrupted"
        case .inProgress: return "In Progress"
        }
    }

    private var durationText: String {
        guard let end = session.endDate else { return "In progress" }
        let seconds = Int(end.timeIntervalSince(session.startDate))
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes == 0 { return "\(secs)s" }
        return "\(minutes)m \(secs)s"
    }

    private func labelRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
    }
}
