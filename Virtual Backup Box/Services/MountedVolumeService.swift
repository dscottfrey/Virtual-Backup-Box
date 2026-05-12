// MountedVolumeService.swift
// Virtual Backup Box
//
// Reports which removable volumes are currently mounted, keyed by their
// filesystem UUID. Used by the main screen to detect that a previously
// seen camera card is plugged in *right now*, so the "Known cards" list
// entry for it can become a tappable "Choose Previous" action instead of
// gray informational text.
//
// Why this is needed:
// On iOS, the file picker is the only path to actually open a folder on a
// removable volume — security-scoped bookmarks aside, the user must consent
// via the system picker. So even when we know a card is mounted, we still
// have to bounce through the picker. But we can absolutely *detect* that
// it's mounted, and that lets us:
//   1. Color the "Known cards" line as actionable instead of gray
//   2. Pre-navigate the picker to that card's volume root, so the user
//      just taps "Open"
// (The full "skip the picker entirely" version requires a per-card
// security-scoped bookmark stored on KnownCard — see handoff.md item #15.)
//
// Implementation notes — what failed first and why this approach works:
// First attempt was FileManager.default.mountedVolumeURLs(...) with no
// options. That returns *all* mounted volumes including iCloud Drive,
// On My iPhone, and synthetic Apple containers. We filter with
// .skipHiddenVolumes and additionally require the volume to be marked as
// removable or ejectable via URLResourceKey, because camera cards always
// report at least one of those keys as true. iCloud Drive / On My iPhone
// do not. This filter matches what the Files app surfaces under "Locations
// > External."

import Foundation

enum MountedVolumeService {

    /// Returns the set of filesystem UUIDs for all currently-mounted
    /// removable volumes (camera cards, USB sticks, SD readers, etc.).
    /// Excludes iCloud Drive, On My iPhone, and other built-in providers.
    ///
    /// Safe to call from any thread. Returns an empty set if iOS denies
    /// access to volume enumeration (extremely unlikely in our sandbox).
    static func mountedRemovableUUIDs() -> Set<String> {
        // Dump *every* mounted volume the API returns, before any filter,
        // so we can see in the iCloud debug log exactly what iOS exposes
        // to the sandbox. The original filter (volumeIsRemovable /
        // volumeIsEjectable) may be rejecting the card on iOS even though
        // the Files app shows it — this log will confirm or rule that out.
        dumpAllMountedVolumes()

        let urls = mountedRemovableURLs()
        var uuids: Set<String> = []
        for url in urls {
            if let values = try? url.resourceValues(
                forKeys: [.volumeUUIDStringKey]
            ), let uuid = values.volumeUUIDString {
                uuids.insert(uuid)
            }
        }
        return uuids
    }

    /// Returns the URL of the mounted volume root for a given UUID, or nil
    /// if no removable volume with that UUID is currently mounted. Used by
    /// the picker pre-navigation path.
    static func mountedURL(forUUID uuid: String) -> URL? {
        for url in mountedRemovableURLs() {
            if let values = try? url.resourceValues(
                forKeys: [.volumeUUIDStringKey]
            ), values.volumeUUIDString == uuid {
                return url
            }
        }
        return nil
    }

    // MARK: - Private

    /// Logs every mounted volume the API returns, with the resource-key
    /// values we care about. Temporary diagnostic — used to confirm
    /// whether iOS surfaces external camera cards to a sandboxed app via
    /// mountedVolumeURLs at all. Remove once we know the answer.
    private static func dumpAllMountedVolumes() {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeUUIDStringKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsLocalKey,
            .volumeIsInternalKey,
            .volumeIsBrowsableKey
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: []
        ) ?? []
        DebugLogService.shared.log(
            "[MountedCards] === volume dump (count=\(urls.count)) ==="
        )
        for url in urls {
            let v = try? url.resourceValues(forKeys: Set(keys))
            DebugLogService.shared.log(
                "[MountedCards]   path=\(url.path) name=\(v?.volumeName ?? "?") uuid=\(v?.volumeUUIDString ?? "nil") removable=\(v?.volumeIsRemovable ?? false) ejectable=\(v?.volumeIsEjectable ?? false) local=\(v?.volumeIsLocal ?? false) internal=\(v?.volumeIsInternal ?? false) browsable=\(v?.volumeIsBrowsable ?? false)"
            )
        }
        DebugLogService.shared.log("[MountedCards] === end dump ===")
    }

    /// Enumerates mounted volumes and keeps only the removable/ejectable
    /// ones. See the file header for why this filter exists.
    private static func mountedRemovableURLs() -> [URL] {
        let keys: [URLResourceKey] = [
            .volumeUUIDStringKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }
        return urls.filter { url in
            guard let values = try? url.resourceValues(
                forKeys: [.volumeIsRemovableKey, .volumeIsEjectableKey]
            ) else {
                return false
            }
            return (values.volumeIsRemovable ?? false)
                || (values.volumeIsEjectable ?? false)
        }
    }
}
