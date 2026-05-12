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

    /// Pulldown of known cards (no button — the action button lives in
    /// the source zone's bottom row alongside "Select New" so the two
    /// source-selection actions sit side by side).
    ///
    /// Design rationale (Scott's 2026-05-12 UX direction): users will
    /// typically own multiple cards (one body, two cards; multiple bodies,
    /// many cards). A per-row "Choose Previous" button scales poorly past
    /// two cards. A single pulldown is cleaner. Defaults to the most-
    /// recently backed-up card (top of recentKnownCards) because that's
    /// what a returning user most likely wants.
    ///
    /// Layout history — what we tried and why this is the layout now:
    /// First version placed the "Select Previous" button beside the
    /// picker in an HStack. With a long card name like "Canon EOS R6
    /// Card-256Gb", the picker text wrapped across three lines and the
    /// helper text below it bled into the "Select Source" button beneath
    /// the section (screenshot 2026-05-12 15:24). Splitting picker and
    /// action button onto separate rows gives the picker the full row
    /// width and keeps long names on one line.
    @ViewBuilder
    func knownCardsPicker(knownCards: [KnownCard]) -> some View {
        let selected = currentlySelectedKnownCard(from: knownCards)
        let canSelect = canSelectPreviousCard(from: knownCards)

        VStack(alignment: .leading, spacing: 6) {
            Text("Known cards")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker(
                "Known card",
                selection: Binding(
                    get: { selected?.uuid ?? knownCards.first?.uuid ?? "" },
                    set: { selectedKnownCardUUID = $0 }
                )
            ) {
                ForEach(knownCards, id: \.uuid) { card in
                    Text(card.friendlyName).tag(card.uuid)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            if let card = selected, !canSelect {
                Text(helperText(for: card))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Bottom action row of the source zone: "Select Previous" (only
    /// shown when there are known cards other than the current source)
    /// and "Select New" (always shown). Plain tappable text — no
    /// .buttonStyle(.bordered), which on iOS 26 renders as large liquid-
    /// glass pills that overwhelm the source-zone card. Plain text
    /// buttons get the default borderless tinted style — blue and
    /// readable, with the icon as the visual anchor.
    ///
    /// Both taps log on entry so the iCloud debug log can tell us if a
    /// reported "button never becomes active" is a UI/hit-target issue
    /// (no log line means tap was never received) versus state
    /// propagation (log line fires but the sheet still doesn't appear).
    @ViewBuilder
    func sourceActionButtons(knownCards: [KnownCard]) -> some View {
        HStack(spacing: 20) {
            if !knownCards.isEmpty {
                let canSelect = canSelectPreviousCard(from: knownCards)
                Button {
                    DebugLogService.shared.log("[SelectPrevious] tapped")
                    if let card = currentlySelectedKnownCard(from: knownCards) {
                        chooseKnownCard(card)
                    }
                } label: {
                    Label("Select Previous", systemImage: "arrow.uturn.backward")
                        .font(.subheadline)
                }
                .disabled(!canSelect)
            }

            Button {
                DebugLogService.shared.log("[SelectNew] tapped — setting showingSourcePicker=true")
                viewModel.showingSourcePicker = true
            } label: {
                Label("Select New", systemImage: "folder")
                    .font(.subheadline)
            }

            Spacer()
        }
    }

    /// Returns the KnownCard the user has chosen in the pulldown, or the
    /// list's first entry when @State hasn't been set yet (initial render
    /// or the previously selected UUID is no longer in the filtered list).
    private func currentlySelectedKnownCard(
        from knownCards: [KnownCard]
    ) -> KnownCard? {
        if let uuid = selectedKnownCardUUID,
           let match = knownCards.first(where: { $0.uuid == uuid }) {
            return match
        }
        return knownCards.first
    }

    /// True when the currently-selected known card has a stored bookmark
    /// AND is mounted right now — the only state where Select Previous
    /// can succeed.
    private func canSelectPreviousCard(from knownCards: [KnownCard]) -> Bool {
        guard let card = currentlySelectedKnownCard(from: knownCards) else {
            return false
        }
        return card.bookmarkData != nil
            && mountedCardUUIDs.contains(card.uuid)
    }

    /// Plain-English explanation for why Select Previous is disabled for
    /// the given card. Two cases mapped to two iOS limitations.
    private func helperText(for card: KnownCard) -> String {
        if card.bookmarkData == nil {
            return "Pick \(card.friendlyName) once via Select New to enable quick-select"
        }
        return "\(card.friendlyName) is not plugged in"
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

            // Quick-select: known cards. The pulldown is hidden when the
            // only known card is the active source (nothing to re-pick),
            // but the action row is always shown so "Select New" is
            // always reachable.
            let knownCards = viewModel.recentKnownCards
                .filter { $0.uuid != viewModel.selectedCard?.uuid }
            if !knownCards.isEmpty {
                knownCardsPicker(knownCards: knownCards)
            }

            sourceActionButtons(knownCards: knownCards)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
