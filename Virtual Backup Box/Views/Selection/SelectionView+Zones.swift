// SelectionView+Zones.swift
// Virtual Backup Box
//
// Extension on SelectionView containing the Target and Source zone sub-views.
// Split from the main view file to respect the ~200-line-per-file rule (§6.3).
//
// Source zone simplification (2026-05-13):
// The source zone has been reduced to a single Choose Source / Change Source
// button. Earlier iterations layered quick-select widgets (known-cards
// pulldown, Select Previous button, "On this device" internal archives list,
// mounted-card auto-detection) on top of the basic picker — none of which
// could be made reliable enough on iOS without fighting the framework
// (UserFS file-provider sleep, sandboxed app's lack of mountedVolumeURLs
// visibility into camera-card volumes). Scott's direction (2026-05-13):
// "I think the pre-selected source and destination rabbit hole is
// sidetracking us so I would like to push that whole mess down the list
// for after we get the full core functionality locked in." So: one button,
// one picker, no clever layers. The KnownCard.bookmarkData capture in
// SelectionViewModel remains untouched so a future revival of quick-select
// has the permission ground already laid.

import SwiftUI

extension SelectionView {

    // MARK: - Target Zone

    /// Shows the active backup destination, or a prompt to add one.
    /// The action button sits in the header row (right-justified) rather
    /// than below the content — same shape as the source zone, easier
    /// to reach. Tap opens the Manage Destinations sheet (replaces the
    /// older "Manage" header button AND the bottom "Add Destination"
    /// button; both routed there anyway).
    var targetZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Destination")
                    .font(.headline)
                Spacer()
                Button {
                    showingManageTargets = true
                } label: {
                    HStack(spacing: 4) {
                        Text(destinationButtonTitle)
                        Image(systemName: "folder")
                        Image(systemName: "externaldrive")
                    }
                    .font(.subheadline)
                }
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
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// "Choose" when nothing is active yet, "Change" once a destination
    /// is selected. Mirrors the Source zone's button-label logic so the
    /// two zones read the same.
    private var destinationButtonTitle: String {
        viewModel.activeTarget == nil ? "Choose" : "Change"
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

    /// Shows the selected source's display name (if any). The action
    /// button sits in the header row (right-justified) rather than
    /// below the content — Scott's 2026-05-13 layout request after
    /// noticing the destination zone already had a header-right
    /// "Manage" button and wanted the two zones to match.
    var sourceZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Source")
                    .font(.headline)
                Spacer()
                Button {
                    DebugLogService.shared.log(
                        "[ChooseSource] tapped — presenting picker"
                    )
                    viewModel.showingSourcePicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(sourceButtonTitle)
                        Image(systemName: "folder")
                        Image(systemName: "sdcard")
                    }
                    .font(.subheadline)
                }
            }

            sourceContent
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// "Choose" when nothing is picked yet, "Change" once a source is
    /// in place. Computed from viewModel.sourceURL so SwiftUI re-renders
    /// the label automatically when the source is cleared (by the user
    /// or by validateSourceStillValid).
    private var sourceButtonTitle: String {
        viewModel.sourceURL == nil ? "Choose" : "Change"
    }

    /// The current-source readout displayed above the button. Three states:
    /// reading-card spinner, recognised camera card with friendly name and
    /// last-backup date, or generic folder name. When nothing is picked yet
    /// the readout is omitted entirely so the card collapses to just the
    /// "Choose Source" button.
    @ViewBuilder
    private var sourceContent: some View {
        if viewModel.isReadingCard {
            HStack(spacing: 8) {
                ProgressView()
                Text("Reading card\u{2026}")
                    .foregroundStyle(.secondary)
            }
        } else if let card = viewModel.selectedCard {
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
    }
}
