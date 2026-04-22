# Prompt for Claude Code (terminal, working in Xcode project)

Copy-paste everything below the horizontal rule into a fresh `claude` session inside your Xcode project directory.

---

## Task

I have an iOS backup app (Xcode, Swift/SwiftUI or UIKit — please detect which from the project). When the user taps "Pick camera card," the app presents a `UIDocumentPickerViewController` (or SwiftUI `.fileImporter` / `DocumentPicker` wrapper) so the user can select the DCIM folder on a camera's SD card mounted via the Lightning/USB-C adapter.

**The bug:** iOS's Files picker remembers the last-used location globally for my app. After the first successful pick, every subsequent present re-opens deep inside "On My iPhone" (internal storage). The user has to hit the back chevron four or five times, tap the "Browse" tab, tap "Locations," and only then can they tap the camera card. This happens every single time.

**Goal:** Fix the picker so it always lands in a useful place for a camera-card workflow — never buried inside internal storage. A permission re-prompt each launch is acceptable if needed.

**Constraints:**
- iOS 15+ (adjust if project deployment target differs — check `Info.plist` / project settings first).
- Do not break existing picker delegate / completion handlers.
- Keep backward compatibility with UIKit if the project is UIKit; use SwiftUI idioms if it is SwiftUI.
- Support both single-file pick and folder pick as the project already uses them.

## Research I've already done (so you don't repeat it)

Apple's default behavior: when `UIDocumentPickerViewController.directoryURL` is `nil`, the picker starts at the last directory the user browsed. That is the documented cause of the annoyance. (https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/directoryurl)

`directoryURL` accepts a URL the picker will *try* to open at. In practice:
1. It works reliably when the URL is security-scoped (from a bookmark or a prior picker callback).
2. It is ignored on Mac Catalyst.
3. It can be ignored with some content-type filters (e.g. `.pdf`) but is respected for `.folder`. See Apple Dev Forums thread 718369.
4. A URL that no longer resolves (stale bookmark, unmounted volume) makes the picker fall back to the Browse/Locations view — we can weaponize this.

## Strategy — implement all three, layered

### Layer 1 — Remember the camera card with a security-scoped bookmark (primary fix)

The *right* fix is not fighting the picker, it's making the default location actually be the camera card:

1. First run: present the picker with `UIDocumentPickerViewController(forOpeningContentTypes: [.folder])` so the user picks the camera card's root (or DCIM).
2. On `didPickDocumentsAt`, call `startAccessingSecurityScopedResource()`, create a bookmark with `.withSecurityScope` (or `.minimalBookmark` on iOS where `.withSecurityScope` is unavailable — iOS has been inconsistent here, test at runtime), and persist the bookmark `Data` to `UserDefaults` under a key like `cameraCardBookmark`.
3. On every subsequent present: resolve the bookmark, check `isStale`, check that the volume is still mounted (`FileManager.default.fileExists(atPath:)`), and if valid, set it as `picker.directoryURL`. The picker now opens directly inside the camera card — zero back-taps.
4. If the bookmark is stale or the volume is gone, fall through to Layer 2.

### Layer 2 — Force the Browse / Locations view when no bookmark applies

When there is no saved bookmark, or it's unusable, make the picker open to the sidebar/Locations view rather than "On My iPhone":

- Set `picker.directoryURL` to a deliberately non-resolving URL. In testing, pointing it at a file URL for a path that doesn't exist (e.g. `URL(fileURLWithPath: "/private/var/_force_browse_\(UUID().uuidString)")`) causes the picker to give up trying to open that path and drop the user on the Browse root with Locations visible. Document this clearly in a comment — it is an undocumented behavior and might regress.
- Alternative that's cleaner but less universal: try to use the iCloud Drive ubiquity root via `FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents")`. The picker opens at iCloud Drive root, which is one tap from the Locations sidebar. Only works if the user has iCloud Drive enabled.
- Never leave `directoryURL` as `nil` — that is explicitly what triggers the "last location" behavior we are trying to avoid.

### Layer 3 — Offer a "Pick default folder" setting

Add a one-line settings row (Settings tab, or whatever analogue exists in the project) that lets the user re-trigger the folder picker to update the stored bookmark if they change cameras/cards. Wipe the bookmark on any permission-denied error so the app self-heals.

## Concrete Swift reference implementation

Treat this as a starting point — adapt naming and file layout to the project:

```swift
import UIKit
import UniformTypeIdentifiers

final class CameraCardPickerCoordinator: NSObject, UIDocumentPickerDelegate {

    private static let bookmarkKey = "cameraCardBookmark.v1"
    private let contentTypes: [UTType]
    private var completion: ((Result<URL, Error>) -> Void)?
    private var accessedURL: URL?

    init(contentTypes: [UTType] = [.folder]) {
        self.contentTypes = contentTypes
    }

    func present(from presenter: UIViewController,
                 completion: @escaping (Result<URL, Error>) -> Void) {
        self.completion = completion

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true

        picker.directoryURL = resolvedStartDirectory()

        presenter.present(picker, animated: true)
    }

    /// Layer 1 if we have a valid bookmark, Layer 2 otherwise.
    private func resolvedStartDirectory() -> URL {
        if let url = resolveSavedBookmark() {
            // Start accessing so the picker can open inside the security scope.
            if url.startAccessingSecurityScopedResource() {
                accessedURL = url
            }
            return url
        }
        // Layer 2: force Browse/Locations view by pointing at a non-resolving URL.
        return URL(fileURLWithPath: "/private/var/_force_browse_\(UUID().uuidString)")
    }

    private func resolveSavedBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        // iOS accepts .withSecurityScope since iOS 14; on older OSes this is a no-op flag.
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else {
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
            return nil
        }
        if stale {
            // Try to refresh silently; if that fails, drop it.
            if let refreshed = try? url.bookmarkData(options: [],
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) {
                UserDefaults.standard.set(refreshed, forKey: Self.bookmarkKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
                return nil
            }
        }
        // Sanity check the volume is actually mounted right now.
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func saveBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(options: [],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        } catch {
            // Non-fatal: bookmark will just not persist.
        }
    }

    // MARK: UIDocumentPickerDelegate

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        defer {
            accessedURL?.stopAccessingSecurityScopedResource()
            accessedURL = nil
        }
        guard let url = urls.first else {
            completion?(.failure(CocoaError(.fileReadUnknown)))
            return
        }
        let gotScope = url.startAccessingSecurityScopedResource()
        defer { if gotScope { url.stopAccessingSecurityScopedResource() } }

        saveBookmark(for: url)
        completion?(.success(url))
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
        completion?(.failure(CocoaError(.userCancelled)))
    }
}
```

SwiftUI equivalent — wrap the above in a `UIViewControllerRepresentable` **or**, if the project uses `.fileImporter`, file-importer does not expose `directoryURL` directly. Bridge via a tiny UIKit wrapper exposed as a `UIViewControllerRepresentable`; do not try to hack `.fileImporter` because it doesn't take a starting URL.

A "Reset camera card" menu item should call:

```swift
UserDefaults.standard.removeObject(forKey: "cameraCardBookmark.v1")
```

## What I want you to do, step by step

1. Open the project and identify the existing picker entry point(s). Likely candidates: anything referencing `UIDocumentPickerViewController`, `.fileImporter`, `DocumentPicker`, or a coordinator/delegate file.
2. Note the deployment target in the project settings and confirm the UTTypes currently requested.
3. Drop in `CameraCardPickerCoordinator` (or adapt into the existing coordinator). Preserve existing completion semantics.
4. Wire the settings screen's existing "default folder" row (create one if it doesn't exist) to clear the bookmark key.
5. Add unit-ish tests or at minimum a debug-only log line that prints whether the picker opened from a resolved bookmark, a forced-browse fallback, or `nil` — so I can verify behavior on device.
6. Build. Run on a physical device with an SD card reader — the simulator cannot mount a camera card. Confirm the three cases manually:
   a. First run, no bookmark → picker opens at Browse/Locations view, not inside internal storage.
   b. After picking the card once → picker opens directly inside the card.
   c. After unplugging the card and re-presenting → picker falls back to Browse/Locations view and the stored bookmark is cleared.

## Things to explicitly check / push back on

- If the deployment target is < iOS 14, `forOpeningContentTypes:` is unavailable — fall back to `documentTypes:` with UTI strings.
- If the project is Catalyst, `directoryURL` is ignored; note that in the PR description.
- If the existing picker uses `asCopy: true`, keep that — it changes permission semantics and our bookmark logic still applies.
- If `UserDefaults` is already used for settings, use the existing suite/`UserDefaults(suiteName:)`; don't create a second store.

Report back with: list of files changed, the resolved deployment target, any edge case where my three-case acceptance test failed, and the exact log output from a real-device run.

---

## Notes and caveats (for you, Scott — not for terminal Claude)

- The "non-resolving URL forces Browse view" trick in Layer 2 is undocumented. It has worked in testing for other devs, but Apple could change it in any iOS release. That's why Layer 1 (the bookmark) is the real fix — Layer 2 is just cosmetic for first-run.
- `directoryURL` is documented as ignored on Mac Catalyst. If this backup app is cross-platform, Catalyst users will keep hitting the old behavior.
- Third-party file providers (Dropbox, Google Drive, etc.) sometimes show as greyed out in the folder picker — Apple considers that "working as designed." Camera cards mount as "On My iPhone" style locations, not third-party providers, so this should not affect you.
- An even cleaner long-term answer is `UIDocumentBrowserViewController`, which is designed to be the app's main file browser rather than a modal picker. Overkill for a single "pick card" button, but worth knowing.

Sources:
- [UIDocumentPickerViewController | Apple Developer Documentation](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller)
- [directoryURL | Apple Developer Documentation](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/directoryurl)
- [Providing Access to Directories in iOS with Bookmarks — Adam Garrett-Harris](https://adam.garrett-harris.com/2021-08-21-providing-access-to-directories-in-ios-with-bookmarks/)
- [Security-scoped bookmarks for URL access — SwiftLee](https://www.avanderlee.com/swift/security-scoped-bookmarks-for-url-access/)
- [Accessing Security Scoped Files — Use Your Loaf](https://useyourloaf.com/blog/accessing-security-scoped-files/)
- [UIDocumentPickerViewController ignoring directoryURL — Apple Developer Forums](https://developer.apple.com/forums/thread/718369)
- [UIDocumentPickerViewController — j… — Apple Developer Forums](https://developer.apple.com/forums/thread/710710)
- [How to let user select file from Files — Filip Němeček](https://nemecek.be/blog/155/how-to-let-user-select-file-from-files)
- [Providing access to directories | Apple Developer Documentation](https://developer.apple.com/documentation/uikit/providing-access-to-directories)
- [What's New in File Management and Quick Look — WWDC19 Session 719](https://developer.apple.com/videos/play/wwdc2019/719/)
