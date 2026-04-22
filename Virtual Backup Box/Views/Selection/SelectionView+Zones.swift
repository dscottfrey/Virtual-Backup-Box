// SelectionView+Zones.swift
// Virtual Backup Box
//
// Extension on SelectionView containing the Target and Source zone sub-views.
// Split from the main view file to respect the ~200-line-per-file rule (§6.3).

import SwiftUI

extension SelectionView {

    // MARK: - Target Zone

    /// Shows the active backup destination, or a prompt to add one.
    var targetZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Destination")
                    .font(.headline)
                Spacer()
                Button("Manage") { showingManageTargets = true }
                    .font(.subheadline)
            }

            if let target = viewModel.activeTarget {
                HStack(spacing: 8) {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(target.friendlyName)
                        .font(.title3)
                }

                if let space = viewModel.availableSpaceBytes {
                    spaceLabel(bytes: space)
                }
            } else {
                Text("No destination connected.")
                    .foregroundStyle(.secondary)
                Button {
                    showingManageTargets = true
                } label: {
                    Label("Add Destination", systemImage: "folder.badge.plus")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Shows available space with a warning if below threshold.
    func spaceLabel(bytes: Int64) -> some View {
        let text = ByteCountFormatter.string(
            fromByteCount: bytes, countStyle: .file
        ) + " available"

        return Group {
            if viewModel.showLowSpaceWarning {
                Label(text, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Text(text)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    // MARK: - Source Zone

    /// Shows the selected source folder or camera card, with a button to
    /// select or change it. If a camera card is auto-detected on a mounted
    /// volume, shows it as a one-tap option.
    var sourceZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Source")
                .font(.headline)

            if viewModel.isReadingCard {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Reading card\u{2026}")
                        .foregroundStyle(.secondary)
                }
            } else if let card = viewModel.selectedCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.friendlyName).font(.title3)
                    Text(card.cameraModel)
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    if let lastBackup = card.lastBackupDate {
                        Text("Last backed up: \(lastBackup, format: .dateTime.month().day().hour().minute())")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            } else if viewModel.sourceURL != nil {
                Text(viewModel.sourceDisplayName).font(.title3)
            }

            // Quick-select: internal archives (one-tap, no picker needed)
            let archives = viewModel.internalArchives
            if !archives.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("On this device")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(archives, id: \.url) { archive in
                        Button {
                            viewModel.selectInternalArchive(
                                url: archive.url, name: archive.name
                            )
                        } label: {
                            Label(archive.name, systemImage: "internaldrive")
                        }
                        .font(.subheadline)
                    }
                }
            }

            // Quick-select: known cards (need picker for iOS access)
            let knownCards = viewModel.recentKnownCards
            if !knownCards.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Known cards (select via picker)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(knownCards, id: \.uuid) { card in
                        HStack(spacing: 6) {
                            Image(systemName: "sdcard")
                                .foregroundStyle(.secondary)
                            Text(card.friendlyName)
                            if let date = card.lastBackupDate {
                                Spacer()
                                Text(date, format: .dateTime.month().day())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                viewModel.showingSourcePicker = true
            } label: {
                Label(
                    viewModel.sourceURL == nil ? "Select Source" : "Change Source",
                    systemImage: "folder"
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
