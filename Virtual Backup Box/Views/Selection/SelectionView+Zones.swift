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

    /// One row in the "Known cards" list. Mounted cards render as a blue
    /// tappable Button (label: "Choose Previous"); not-mounted cards
    /// render as gray text. See the source-zone comment for why we keep
    /// the non-actionable row instead of hiding it.
    @ViewBuilder
    func knownCardRow(for card: KnownCard) -> some View {
        if mountedCardUUIDs.contains(card.uuid) {
            Button {
                chooseKnownCard(card)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sdcard")
                    Text(card.friendlyName)
                    Spacer()
                    Text("Choose Previous")
                        .fontWeight(.medium)
                }
                .font(.subheadline)
                .contentShape(Rectangle())
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "sdcard")
                    .foregroundStyle(.secondary)
                Text(card.friendlyName)
                if let date = card.lastBackupDate {
                    Spacer()
                    Text(date, format: .dateTime.month().day())
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
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
                // Card icon sits with the title so the visual cue lives
                // on the most prominent line. The camera-model subhead
                // and the "Known cards" duplicate entry for this same
                // card were dropped — the friendly name already includes
                // the camera model in the suggested format.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "sdcard")
                            .foregroundStyle(.secondary)
                        Text(card.friendlyName).font(.title3)
                    }
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

            // Quick-select: known cards. Hide the currently-selected card
            // (already shown above as the active source).
            //
            // Two states per row:
            //  • Mounted right now → blue "Choose Previous" button. Tap
            //    opens the picker pre-navigated to that card's volume
            //    root, so the user just hits Open.
            //  • Not mounted → gray informational text. Communicates
            //    "we know this card exists, but it isn't plugged in."
            //
            // Why we can't make the not-mounted line actionable: iOS
            // won't grant sandbox access to a volume that isn't there.
            // The not-mounted row exists so the user understands what
            // the app remembers — it isn't a bug that the row is inert.
            let knownCards = viewModel.recentKnownCards
                .filter { $0.uuid != viewModel.selectedCard?.uuid }
            if !knownCards.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Known cards")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(knownCards, id: \.uuid) { card in
                        knownCardRow(for: card)
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
