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

    /// Pulldown of known cards plus a "Select Previous" button.
    ///
    /// Design rationale (Scott's 2026-05-12 UX direction): users will
    /// typically own multiple cards (one body, two cards; multiple bodies,
    /// many cards). A per-row "Choose Previous" button scales poorly past
    /// two cards. A single pulldown + action button is cleaner and reads
    /// as "pick a card from history → confirm." The default selection is
    /// the most-recently backed-up card (already top of recentKnownCards)
    /// because that's the one a returning user most likely wants.
    ///
    /// Three states for the action button, mapped to what iOS will let us
    /// do with the currently-selected card:
    ///
    ///  1. Card mounted AND bookmark stored → button enabled (blue).
    ///     Tap resolves the bookmark and selects the card as source.
    ///     No file picker is presented.
    ///
    ///  2. Bookmark stored but card not plugged in → button disabled,
    ///     helper line below says "Not plugged in." User needs to plug
    ///     the card in (or pick a different one from the pulldown).
    ///
    ///  3. No bookmark on this card yet → button disabled, helper line
    ///     says "Pick once via Select Source to enable quick-select."
    ///     One normal pick captures the bookmark; future sessions are
    ///     one-tap.
    @ViewBuilder
    func knownCardsPicker(knownCards: [KnownCard]) -> some View {
        let selected = currentlySelectedKnownCard(from: knownCards)
        let hasBookmark = selected?.bookmarkData != nil
        let isMounted = selected.map { mountedCardUUIDs.contains($0.uuid) } ?? false
        let canSelect = hasBookmark && isMounted

        VStack(alignment: .leading, spacing: 6) {
            Text("Known cards")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
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

                Spacer()

                Button {
                    if let card = selected { chooseKnownCard(card) }
                } label: {
                    Label("Select Previous", systemImage: "arrow.uturn.backward")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .disabled(!canSelect)
            }

            if let card = selected, !canSelect {
                Text(
                    hasBookmark
                        ? "\(card.friendlyName) is not plugged in"
                        : "Pick \(card.friendlyName) once via Select Source to enable quick-select"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
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

            // Quick-select: known cards. Hidden when the only known card
            // is the active source — there's nothing to re-pick. Anticipates
            // a multi-card workflow (one user, two bodies, several SD cards).
            let knownCards = viewModel.recentKnownCards
                .filter { $0.uuid != viewModel.selectedCard?.uuid }
            if !knownCards.isEmpty {
                knownCardsPicker(knownCards: knownCards)
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
