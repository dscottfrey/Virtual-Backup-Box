// MountedVolumeService.swift
// Virtual Backup Box
//
// Detects which known camera cards are currently mounted by resolving each
// KnownCard's saved security-scoped bookmark. Used by the main screen to
// decide which "Known cards" rows are one-tap selectable.
//
// History — why we don't use FileManager.mountedVolumeURLs:
// The first version of this service used FileManager.mountedVolumeURLs
// with a removable/ejectable filter. It returned an empty array on iOS
// even with a camera card visibly mounted in the system Files app
// (debug log dump on 2026-05-12 showed count=0 while a card was actively
// picked via the picker). iOS does not surface external removable volumes
// to a sandboxed third-party app through that API — only the system Files
// app / UIDocumentPicker has visibility. So that approach is dead. The
// bookmark approach is the only sandbox-safe way to know whether a
// previously-seen card is plugged in right now.
//
// How the bookmark resolution doubles as both detection AND access:
// A security-scoped bookmark stored at first-pick time both (a) survives
// app restarts and (b) when resolved, can be combined with
// startAccessingSecurityScopedResource() to regain sandbox access without
// re-presenting the picker. So a single bookmark resolution per card
// answers "is it mounted?" and "can I open it directly?" with one call.
//
// Limitation:
// A KnownCard that has never been picked since the bookmarkData property
// was introduced has no bookmark and cannot be detected. The UI shows
// those cards as "Not yet saved" and guides the user to do one normal
// "Select Source" pick to enable quick-select. After that, the card is
// one-tap forever (until the bookmark goes stale, which is auto-refreshed
// on each successful resolution).

import Foundation
import SwiftData

enum MountedVolumeService {

    /// Result of resolving one card's bookmark. Carries both whether the
    /// card is reachable right now and (if so) the live URL so the caller
    /// can immediately use it without resolving the bookmark twice.
    struct Resolution {
        let isMounted: Bool
        let url: URL?
    }

    /// Returns the set of KnownCard UUIDs whose saved bookmark resolves to
    /// a currently-reachable URL — i.e. cards that are plugged in *right
    /// now*. Cards without a bookmark, or whose bookmark fails to resolve,
    /// are not included.
    static func mountedKnownCardUUIDs(in context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<KnownCard>()
        guard let cards = try? context.fetch(descriptor) else { return [] }

        var mounted: Set<String> = []
        for card in cards {
            if resolve(card: card).isMounted {
                mounted.insert(card.uuid)
            }
        }
        DebugLogService.shared.log(
            "[MountedCards] resolved \(cards.count) known card(s), \(mounted.count) mounted"
        )
        return mounted
    }

    /// Resolves a single card's bookmark and returns whether it is mounted
    /// plus the live URL. Refreshes a stale bookmark in place.
    ///
    /// Important — does NOT clear the bookmark on failure. On iOS,
    /// URL(resolvingBookmarkData:) throws when the underlying external
    /// volume is unmounted, even though the bookmark itself is still
    /// good and will resolve again the next time the card is plugged in.
    /// An earlier version cleared on every throw and broke the "plug
    /// card back in while app is open" scenario (debug log 15:11:39).
    ///
    /// What changed 2026-05-12 (round 2): checkResourceIsReachable was
    /// returning false on a successfully-resolved URL even with the card
    /// visibly plugged in. Hypothesis under test: reachability on a
    /// security-scoped, bookmark-resolved URL requires
    /// startAccessingSecurityScopedResource() to be active first — the
    /// sandbox treats the URL as inaccessible otherwise. So we now start
    /// access for the reachability probe and stop it before returning.
    /// (The caller's own scope management is unaffected.) Every branch
    /// logs a distinct line so the next failure log identifies the cause.
    static func resolve(card: KnownCard) -> Resolution {
        guard let data = card.bookmarkData else {
            DebugLogService.shared.log(
                "[MountedCards] \(card.friendlyName): bookmarkData is nil"
            )
            return Resolution(isMounted: false, url: nil)
        }

        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            DebugLogService.shared.log(
                "[MountedCards] \(card.friendlyName): URL(resolvingBookmarkData:) threw — \(error)"
            )
            return Resolution(isMounted: false, url: nil)
        }

        // Start scoped access for the reachability probe, regardless of
        // whether the start-access call returns true (some iOS versions
        // return false on already-accessed URLs but still grant access).
        // Stop on every exit path via the deferred block.
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }

        DebugLogService.shared.log(
            "[MountedCards] \(card.friendlyName): resolved to \(url.path) (isStale=\(isStale), accessStarted=\(started))"
        )

        // Refresh stale bookmark silently so the next resolution is clean.
        if isStale {
            if let refreshed = try? url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                card.bookmarkData = refreshed
                DebugLogService.shared.log(
                    "[MountedCards] refreshed stale bookmark for \(card.friendlyName)"
                )
            }
        }

        // A bookmark can resolve to a URL even when the volume is gone —
        // the URL exists but the path is unreachable. checkResourceIsReachable
        // is the authoritative "is this here right now?" check.
        let reachable: Bool
        do {
            reachable = try url.checkResourceIsReachable()
        } catch {
            DebugLogService.shared.log(
                "[MountedCards] \(card.friendlyName): checkResourceIsReachable threw — \(error)"
            )
            return Resolution(isMounted: false, url: nil)
        }

        if !reachable {
            // Cross-check with FileManager so the log distinguishes
            // "sandbox can't see this path" from "path genuinely gone."
            let fmExists = FileManager.default.fileExists(atPath: url.path)
            DebugLogService.shared.log(
                "[MountedCards] \(card.friendlyName): not reachable (FileManager.fileExists=\(fmExists))"
            )
            return Resolution(isMounted: false, url: nil)
        }

        return Resolution(isMounted: true, url: url)
    }
}
