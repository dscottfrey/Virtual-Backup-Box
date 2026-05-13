// SelectionView+MountedCards.swift
// Virtual Backup Box
//
// Extension on SelectionView that detects which known cards are mounted
// right now and handles the one-tap "Choose Previous" action.
//
// How detection works (and what failed first):
// First attempt used FileManager.mountedVolumeURLs to enumerate plugged-in
// removable volumes. That returned an empty array on iOS even when a card
// was visibly mounted in the system Files app (debug dump on 2026-05-12,
// see commit 67ff1e2). iOS does not expose external camera-card volumes
// to a sandboxed app via that API — only the system Files app /
// UIDocumentPicker has visibility. So detection had to move elsewhere.
//
// The current approach: each KnownCard stores a security-scoped bookmark
// captured the last time the user picked that card via the file picker.
// On screen appear (and on scenePhase → .active), we resolve each
// bookmark; a successful resolution with checkResourceIsReachable() == true
// means the card is plugged in *and* we have sandbox access to use. That
// answers both questions ("is it mounted?" and "can I open it?") in one
// call — which is what powers one-tap re-selection.
//
// Why this is in its own file:
// SelectionView.swift is the screen's navigation coordinator and is
// already close to the §6.3 ~200-line cap. Mount-detection is orthogonal
// to navigation, so it lives here. The @State properties for the mounted
// set must still be declared on the main struct (SwiftUI requires @State
// on the type itself, not extensions); the supporting methods belong here.

import SwiftUI

extension SelectionView {

    /// Refreshes the set of mounted-known-card UUIDs by resolving every
    /// KnownCard's stored bookmark. Async because the resolution loop can
    /// retry through iOS's UserFS file-provider wake-up (see
    /// MountedVolumeService). The Task lets SwiftUI keep painting while
    /// the retries run; mountedCardUUIDs updates when the work finishes.
    ///
    /// Also validates the currently-selected source still points at the
    /// right card. If the user pulled the card and inserted a different
    /// one, the source URL would still reference the old mount path and
    /// the scan would attribute new files to the old card's destination.
    /// validateSourceStillValid() catches that and clears the source.
    func refreshMountedCards() {
        Task {
            let mounted = await MountedVolumeService.mountedKnownCardUUIDs(
                in: modelContext
            )
            mountedCardUUIDs = mounted
            viewModel.validateSourceStillValid()
        }
    }

    /// Handles a tap on a "Choose Previous" row. Resolves the card's
    /// security-scoped bookmark and feeds the resulting URL straight into
    /// the normal source-selection pipeline — no picker is presented.
    ///
    /// If the bookmark fails to resolve at the moment of the tap (e.g.
    /// the card was unplugged between the screen rendering and the tap,
    /// or the FileProvider has gone to sleep and didn't wake within the
    /// retry budget), we fall back to the normal picker so the user is
    /// never stranded.
    func chooseKnownCard(_ card: KnownCard) {
        Task {
            let resolution = await MountedVolumeService.resolve(card: card)
            guard let url = resolution.url, resolution.isMounted else {
                DebugLogService.shared.log(
                    "[MountedCards] choose \(card.friendlyName) — bookmark stale at tap time; falling back to picker"
                )
                mountedCardUUIDs.remove(card.uuid)
                viewModel.showingSourcePicker = true
                return
            }
            DebugLogService.shared.log(
                "[MountedCards] choose \(card.friendlyName) — skipping picker, using bookmark URL"
            )
            await viewModel.handleSourceSelected(url: url)
        }
    }
}
