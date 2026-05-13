// MountedVolumeService.swift
// Virtual Backup Box
//
// Detects which known camera cards are currently mounted by resolving each
// KnownCard's saved security-scoped bookmark. Used by the main screen to
// decide which "Known cards" rows are one-tap selectable.
//
// History — why we don't use FileManager.mountedVolumeURLs:
// The first version of this service used FileManager.mountedVolumeURLs.
// That API returned an empty array on iOS even when a camera card was
// visibly mounted in the system Files app (debug dump 2026-05-12 showed
// count=0 while a card was actively picked via the picker). iOS does not
// surface external removable volumes to sandboxed third-party apps
// through that API — only the system Files app / UIDocumentPicker has
// visibility. The bookmark approach is the only sandbox-safe path.
//
// Why resolution is async with a retry loop (2026-05-12, round 3):
// iOS lazily wakes the "com.apple.filesystems.UserFS.FileProvider" that
// serves a mounted external volume. The first resolution attempt right
// after a refresh tick can throw NSFileProviderErrorDomain code -2001
// ("No valid file provider found …") even though the card is physically
// mounted and the bookmark itself is fine — confirmed by debug log
// 16:53:24 (threw) and 16:54:59 (same bookmark, succeeded). The provider
// is per-volume and goes to sleep independently when idle. Retrying with
// short async delays lets the provider wake up before we conclude the
// card is unplugged. Without this retry, the picker showed every card
// as "not plugged in" intermittently. We keep the retry budget tight
// (3 attempts × 200 ms) so the UI doesn't stall when a card really is
// gone — that case throws a different error and exits the loop early.

import Foundation
import SwiftData

@MainActor
enum MountedVolumeService {

    /// Result of resolving one card's bookmark. Carries both whether the
    /// card is reachable right now and (if so) the live URL so the caller
    /// can immediately use it without resolving the bookmark twice.
    struct Resolution {
        let isMounted: Bool
        let url: URL?
    }

    /// Returns the set of KnownCard UUIDs whose saved bookmark currently
    /// resolves to a reachable URL — i.e. cards plugged in *right now*.
    /// Cards without a bookmark, or whose bookmark fails after retries,
    /// are not included.
    static func mountedKnownCardUUIDs(in context: ModelContext) async -> Set<String> {
        let descriptor = FetchDescriptor<KnownCard>()
        guard let cards = try? context.fetch(descriptor) else { return [] }

        var mounted: Set<String> = []
        for card in cards {
            if await resolve(card: card).isMounted {
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
    /// Retry policy — on NSFileProviderErrorDomain -2001 ("file provider
    /// not found"), waits 200 ms and tries again, up to 3 attempts total.
    /// Any other error exits the loop immediately. This is the workaround
    /// for iOS's lazy UserFS provider wake-up (see file header).
    ///
    /// Does NOT clear the bookmark on failure. iOS reports the same error
    /// when (a) the card is physically unplugged and (b) the provider is
    /// merely asleep — we can't distinguish them at the API level, so
    /// keeping the bookmark gives the re-plug case a chance to recover.
    static func resolve(card: KnownCard) async -> Resolution {
        guard let data = card.bookmarkData else {
            DebugLogService.shared.log(
                "[MountedCards] \(card.friendlyName): bookmarkData is nil"
            )
            return Resolution(isMounted: false, url: nil)
        }

        var lastError: Error?
        var isStale = false

        for attempt in 1...3 {
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                return finishResolve(url: url, card: card, isStale: isStale)
            } catch {
                lastError = error
                let nserror = error as NSError
                let providerAsleep =
                    nserror.domain == "NSFileProviderErrorDomain"
                    && nserror.code == -2001
                if providerAsleep && attempt < 3 {
                    DebugLogService.shared.log(
                        "[MountedCards] \(card.friendlyName): FileProvider not ready (attempt \(attempt)/3) — retrying in 200ms"
                    )
                    try? await Task.sleep(for: .milliseconds(200))
                    continue
                }
                break
            }
        }

        DebugLogService.shared.log(
            "[MountedCards] \(card.friendlyName): bookmark did not resolve after retries — \(lastError.map { String(describing: $0) } ?? "no error")"
        )
        return Resolution(isMounted: false, url: nil)
    }

    /// Reachability probe + stale-refresh step. Split out of resolve()
    /// so the retry loop above stays readable.
    private static func finishResolve(
        url: URL,
        card: KnownCard,
        isStale: Bool
    ) -> Resolution {
        // Start scoped access for the reachability probe. Some iOS
        // versions return false on already-accessed URLs even though
        // access is granted, so we don't depend on the return value.
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }

        DebugLogService.shared.log(
            "[MountedCards] \(card.friendlyName): resolved to \(url.path) (isStale=\(isStale), accessStarted=\(started))"
        )

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
            let fmExists = FileManager.default.fileExists(atPath: url.path)
            DebugLogService.shared.log(
                "[MountedCards] \(card.friendlyName): not reachable (FileManager.fileExists=\(fmExists))"
            )
            return Resolution(isMounted: false, url: nil)
        }

        return Resolution(isMounted: true, url: url)
    }
}
