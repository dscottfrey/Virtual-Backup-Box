// SelectionView+MountedCards.swift
// Virtual Backup Box
//
// Extension on SelectionView that handles the "is a known card mounted
// right now?" check. When a known card is mounted, the source zone shows
// it as a tappable "Choose Previous" line (instead of gray informational
// text), and tapping it opens the file picker pre-navigated to that
// card's volume root — saving the user a couple of taps inside the
// system picker.
//
// Why this is in its own file:
// SelectionView.swift is the screen's navigation coordinator and is
// already close to the §6.3 ~200-line cap. The mount-detection logic is
// orthogonal to navigation, so it lives here. The view's @State
// properties for `mountedCardUUIDs` and `preferredSourcePickerURL` must
// still be declared on the main struct (SwiftUI requires @State on the
// type itself, not extensions), but the supporting methods belong here.
//
// Why we don't fully skip the picker:
// iOS sandbox requires user consent via the picker for removable volume
// access. Detecting the mount and pre-navigating the picker is the most
// we can do without storing a security-scoped bookmark on each KnownCard.
// That follow-up (handoff.md item #15) would skip the picker entirely.

import SwiftUI

extension SelectionView {

    /// Refreshes the set of currently-mounted removable volume UUIDs.
    /// Called on first appearance and whenever the app becomes active
    /// again, so plugging in or ejecting a card while the screen is
    /// already showing immediately updates the UI.
    func refreshMountedCards() {
        mountedCardUUIDs = MountedVolumeService.mountedRemovableUUIDs()
        DebugLogService.shared.log(
            "[MountedCards] refreshed — \(mountedCardUUIDs.count) removable volume(s)"
        )
    }

    /// Handles a tap on a known card in the source zone. Looks up the
    /// card's current mount point and presents the picker pre-navigated
    /// to that volume root. The user still has to tap "Open" to grant
    /// sandbox access — that's an iOS constraint, not something we can
    /// work around without per-card bookmarks.
    func chooseKnownCard(_ card: KnownCard) {
        preferredSourcePickerURL = MountedVolumeService.mountedURL(
            forUUID: card.uuid
        )
        DebugLogService.shared.log(
            "[MountedCards] choosing known card \(card.friendlyName) — preferredURL=\(preferredSourcePickerURL?.path ?? "nil")"
        )
        viewModel.showingSourcePicker = true
    }
}
