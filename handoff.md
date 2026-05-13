# Virtual Backup Box — Handoff Notes

**Date:** 2026-04-22 (original) / 2026-05-13 (latest session below)
**From:** Desktop session → Laptop continuation
**Status:** All 7 modules built and tested on device. Core backup flow working. Source UI deliberately simplified to a single Choose Source button for core-functionality testing.

---

## 2026-05-13 Session — Re-prioritization + on-device test fixes

Scott's overnight decision: shelve the auto-detect / quick-select rabbit hole and get back to battle-testing the core flow. The user-facing source experience is now one button. Three rounds of fixes followed from same-day on-device testing.

### Round 1 — initial simplification (commits 7807820 → 297c7df)

1. **`7807820` — Force folder picker to Browse/Locations root every time.** `FolderPickerView` no longer reads the saved last-pick bookmark to position the picker. It always uses the non-resolving `directoryURL` trick so the picker lands at the Files Browse view with Locations visible, regardless of where the last source/destination pick landed. Bookmark-saving code is preserved (saved but unread) so a future revival of quick-select doesn't have to re-grant permissions.

2. **`8ad7aaa` — Collapse source zone to a single Choose/Change Source button.** Removed the known-cards pulldown, Select Previous/New buttons, "On this device" internal-archives list, and the mounted-cards state plumbing from the UI. Label is "Choose Source" when nothing is picked, "Change Source" once something is. The `KnownCard.bookmarkData` capture in `SelectionViewModel.saveBookmark` still runs on every successful card pick — bookmarks accumulate behind the scenes for a future revival. `validateSourceStillValid()` still fires on scene-phase activation and at scan start, so card-pull / card-swap clears the source. Deleted `SelectionView+MountedCards.swift` (orphaned with the UI) and three orphaned ViewModel helpers (`internalArchives`, `recentKnownCards`, `selectInternalArchive`). Removed the "Forget Last Source" ellipsis menu item.

3. **`7b96e79` — Add Choose Folder entry to Browse view.** `CardPickerView` gains a "Choose Folder…" button in a Section at the bottom of the list (always visible, even when no card mirrors exist). Tap → folder picker → `FileBrowserViewModel.loadArbitraryFolder(url:)` synthesizes a minimal `CardMirror`, security scope is retained for the browse session and released `onDisappear` of the destination view.

4. **`297c7df` — Detect iCloud non-local files at scan time and block the session.** `SourceScannerService.enumerateSource` checks `URLResourceKey.ubiquitousItemDownloadingStatusKey` per file. Anything `.notDownloaded` is recorded on the new `ScanResult.cloudOnlyFiles` field and excluded from the copy pipeline. `InlineScanCard` shows a clear "N files aren't downloaded yet" warning with up to three example paths and instructions when `hasCloudOnlyBlock` is true, and omits the Start Copying button entirely.

### Round 2 — test-driven fixes from on-device session

Five commits during testing today:

5. **`9249100` — Available-space fallback for external drives.** `BookmarkService.availableSpace` tries `volumeAvailableCapacityForImportantUsageKey` (directive §1's specified key, intended for the primary device volume) and falls back to `volumeAvailableCapacityKey` when the primary returns 0 or nil. External USB drives now report real available bytes instead of triggering the bogus "Zero KB available" warning.

6. **`062a783` — Cancel Session button on the per-file failure alert.** `FailureAlertModifier` gains a second button beside "Continue Backup". New `SessionViewModel.cancelFromFailureAlert()` atomically clears the alert, cancels the session task, and resumes the suspended continuation so the copy loop observes the cancellation. Pulling the source card mid-stream no longer requires cycling Continue → race-Cancel-during-retry.

7. **`64618b4` — Manage Destinations: refresh availability and dedup re-picks.** Three pieces: re-resolves targets on sheet appear and on scenePhase active; gray-row tap attempts a fresh resolve before deciding to do nothing; `handleTargetSelected` now returns a `TargetPickResult` enum so an already-known drive is activated silently instead of creating a duplicate KnownTarget. Pre-existing duplicates need manual swipe-delete.

8. **`36d59cb` — Categorised per-file failure causes.** New `FailureCause` enum (sourceNotMounted, destinationNotMounted, sourceReadError, destinationWriteError, verificationMismatch, unknown). `processFile` now returns the most recent `AttemptOutcome` alongside its bool; `determineFailureCause` checks mount state first (overrides per-file errors) then falls through to the outcome. Reason strings are phrased so the user can match cause to button: "Reconnect or Cancel Session" for mount issues, "Continue Backup will skip this file" for single-file errors.

9. **`096904d` — Show "Checking availability…" while resolving.** `resolveKnownTargets` now wraps each per-target bookmark resolution in `Task.detached` so the main thread doesn't freeze during the multi-second wait for iOS's UserFS file provider to wake. New `isResolvingTargets` flag drives a ProgressView + footer message in `ManageTargetsView`. Rows update one-by-one as resolution completes rather than all-at-once at the end.

### Round 2 test results (Scott on device)

- Step 1, 2, 3 (simplified UI, root-landing picker, pick card) — passed.
- Step 4 (add flash drive as destination) — first pass surfaced two issues now fixed: the "Zero KB available" warning (commit `9249100`) and the gray-known-drive selectability + duplicate-on-re-pick problem (commit `64618b4`).
- Step 5 (card → flash drive direct backup) — passed.
- Step 6 (pull card mid-stream) — passed, plus surfaced the missing Cancel button (now commit `062a783`) and the generic-reason problem (now commit `36d59cb`).
- Step 7 (pull flash drive mid-stream) — passed.
- Step 8 (pull flash drive mid-stream redo) — passed.
- Step 9 (Browse → Choose Folder) — passed.
- Step 10 (cloud-only block) — passed.
- Resolve-delay UX (the "Checking availability" indicator from commit `096904d`) — added in response to Scott's "took quite a while to turn green, we should have a warning" note. Not yet re-tested as of this writing.

### Deferred — "Select to Copy" partial-transfer flow

Scott (2026-05-13 evening): "After the verify step, change the button that says 'Start copying' to 'Backup All' and add a second button under that that says 'select to copy'. That button should lead to a selection picker (same as the select in the browser does) and then the copy operation will only copy the selected files. This is actually a convenience. For example, I only want to open one file off a card in Lightroom, I can do that from the standard select box and then just back out and abort. Or, I can only copy a selection of files to an iCloud drive location. This is really not a backup exactly. Hence the different wording."

Estimated scope when picked up: 1 new file (`FileSelectionSheet.swift`, multi-select list of `filesToCopy` with Select All toggle and "Copy [N] Selected" footer), 3 modified files (`InlineScanCard` for the two-button split, `SelectionView+SessionRoute` for plumbing the URL filter through, `BackupSessionService` to suppress the card's `lastBackupDate` update on partial copies). ~150 lines total, one commit.

Design notes from the discussion:
- Partial copy lands inside the card's regular `YYYYMMDD_friendlyname/` folder — a later Backup All will see those files as already verified and skip them. Correct behaviour.
- Card's `lastBackupDate` does NOT update on partial copies — the source-zone "Last backed up" should still reflect the last real backup.
- The session is still recorded in History (FileRecords are needed for incremental scan), but a future `CopySession.isPartialCopy` boolean would let the History row show a "partial" badge. Adding the field defaulted-to-false at the time we build the feature avoids a SwiftData migration later.
- One-off destination folders that aren't a KnownTarget are explicitly out of scope; if Scott finds himself wanting that, it's a separate shape (no card→folder convention, no security-scoped bookmark to persist).

Scott noted this is doable via the Files app today, just clunky — confirming "convenience" framing rather than core requirement.

### Deferred — picker no longer lands at root on source pick

Scott (2026-05-13 evening test):
> "since the last thing I did was choose an iCloud drive folder, that is where it took me to start, you 'on my iPad/iPhone' trigger is not working, note for later to work on it."

The non-resolving `directoryURL` trick in `FolderPickerView.makeUIViewController` (the `/private/var/_force_browse_<UUID>` path) is no longer reliably routing the source picker to the Browse/Locations root. The picker is instead opening at whatever folder was last picked across the system (source OR destination — the destination flow uses a different picker but the cross-process Files state seems to share recent-location memory).

Possible causes to investigate:
- iOS 17+ may have changed how unreachable `directoryURL` values are handled — perhaps quietly falling back to "most recent" instead of the Browse root.
- The fileImporter used for destinations vs the UIDocumentPicker used for sources may both feed a shared per-process Files state.
- The destination-picking flow could be saving its own bookmark that's overriding our intent.

Tonight's note for next session: this is the next picker-positioning challenge. Worth checking what iOS Files actually shows when the trick is invoked (does it briefly flash a Loading state? jump straight to a recent? error?), and whether a different `directoryURL` value (an empty URL, a documented but inaccessible system path) behaves differently. The picker's `shouldShowFileExtensions` or the use of `forOpeningContentTypes:` could also factor in.

### Today's test plan (card → flash drive direct)

1. Sideload the latest build (commit `297c7df`).
2. Plug in **both** a camera card reader and a USB flash drive at the same time (USB hub or split adapter).
3. Open the app. The Source zone should show a single "Choose Source" button. The Destination zone shows whatever target was last configured.
4. Tap **Choose Source**. The picker should land at the Files Browse/Locations view — sidebar visible, drives & card listed. Scroll to the camera card, pick its root, confirm.
5. In Manage Destinations, add the flash drive as a destination (if not already a known target). Make it the active destination.
6. Tap **Verify Backup Flow** → confirm inline scan summary shows files to copy → tap **Start Copying**.
7. **Mid-stream test #1 — pull the card.** Confirm the session ends, no false-positive alert, and any partial destination file is deleted (re-plug card → re-run → scan should resume cleanly via size-mismatch check).
8. **Mid-stream test #2 — pull the flash drive.** Confirm the session ends cleanly. Re-plug → re-run → any partial destination file is overwritten on the re-copy pass.
9. **Browse anywhere.** Open the Browse sheet (toolbar photo icon). Tap **Choose Folder…** at the bottom, pick any folder (an iCloud folder is a good test), confirm media files appear in the grid.
10. **Cloud-only block.** Add an iCloud Drive folder as a source where at least one file is **not** downloaded ("Remove Download" via Files first). Verify Backup Flow should report "N files aren't downloaded yet" with no Start Copying button.

### What was deliberately deferred (so it doesn't get lost)

- **Third-party file-provider non-local detection.** Dropbox, Synology, Box.com, etc. don't surface `ubiquitousItemDownloadingStatusKey`. Their non-local files will currently fall through to the copy engine's per-file retry-then-skip path (per §5c) with a less helpful error message. Need to research per-provider APIs or look for a provider-agnostic resource key (possibly `NSFileProvider*` keys in iOS 17+).
- **Quick-select / Select Previous UI resurrection.** All the underlying plumbing is intact (`KnownCard.bookmarkData` populated on every pick, `MountedVolumeService` still present, `validateSourceStillValid` still wired). Only the UI surface is gone. When core is battle-tested, this is where to dig back in — the FileProvider sleep retry hypothesis from `535263c` is still untested and may or may not be the fix.
- **Internal archives as quick-source.** The "On this device" list in the source zone was removed. VBB Internal Storage remains as a destination via the normal target machinery. If the user wants quick re-pick of a previously-staged card as a source, they can use the file picker (the folder is at `Documents/VBB Internal Storage/...` and shows in Files under "On My iPad").
- **Diagnostic logs around card-naming Confirm** (commit `7767bc7`). Still present in `SelectionViewModel.confirmCardName`. Remove after a few successful card namings confirm the freeze is gone.
- **Items #16, #17** below — still relevant but lower priority than core testing.

---

## 2026-05-12 End-of-Day State

**Latest commit:** `535263c` — "Retry bookmark resolution when iOS UserFS file provider is asleep" — **not yet sideloaded by Scott.** Ball is in Scott's court to build and test.

**Working hypothesis under test:** Quick-select via "Select Previous" never lit up because iOS lazily sleeps the per-volume `com.apple.filesystems.UserFS.FileProvider`. The first bookmark-resolution attempt after a refresh tick can throw `NSFileProviderErrorDomain -2001` even though the card is physically mounted — confirmed in the debug log (one bookmark, same card, threw at 16:53:24 and resolved successfully at 16:54:59 with nothing in between). The new code retries up to 3 times with 200 ms async delays on that specific error. Other errors fail fast.

**What got built today (2026-05-12 session, in order):**

1. `3ab9e83` — Inline scan summary (item #14 done).
2. `4e7d053` — Source-zone cosmetic cleanup.
3. `7767bc7` — Diagnostic logs around the card-naming Confirm freeze. **Logs still present.** Remove after a few successful card namings.
4. `07a0e14` — Reverse Source/Target order (Source on top), drop divider.
5. `02b2d02` / `67ff1e2` — First-attempt hybrid via `mountedVolumeURLs`. **Both effectively dead code now** — superseded by the bookmark approach. Could be reverted but harmless.
6. `2a88da4` — Per-`KnownCard` security-scoped bookmark stored on every successful pick. The "Select Previous" path resolves the bookmark and skips the picker entirely.
7. `e9dd597` — Don't clear bookmarks on resolution failure (was a real bug — clearing on unplug broke re-plug recovery).
8. `a2bf7f9` / `4eba748` / `d8a0222` — Pulldown UI for known cards, layout cleanup, plain text buttons (no liquid-glass pills). Renamed "Select Source" → "Select New". "Select Previous" sits to the left of "Select New".
9. `53a455a` — Validate source still valid (UUID match + reachability) on every refresh and at scan start. Catches card-swap-under-us scenarios.
10. `e2eb41c` — Diagnostic logging on every CopyEngine throw site (we had no visibility into "Could not be backed up after 3 attempts" before).
11. `2810c19` — Cancellation no longer surfaces the "File Could Not Be Backed Up" alert. Tap Cancel → session finalises as `.interrupted` cleanly.
12. `6e750c9` — Picker no longer filters out the currently-selected card, and default selection prefers a mounted+bookmarked card.
13. `4adafdb` — Reachability wrapped in `startAccessingSecurityScopedResource`, every resolve branch logs distinctly, refresh fires on `sourceURL` change.
14. `535263c` — **The current "this might be the fix" commit.** Async retry on UserFS file-provider sleep.

**Confirmed working before EOD:**

- Per-card bookmark capture (`[KnownCardBookmark] saved bookmark for …` in the log).
- "Select Previous" works **within the same plug-session** (log 15:11:24, 15:38:10).
- Card swap clears stale source via UUID mismatch detection.
- Cancel Backup no longer triggers the failure alert.
- Actual backup runs end-to-end (Scott confirmed earlier today before the cancel bug surfaced).

**Unverified — needs Scott to sideload and test:**

- Whether the retry-on-FileProvider-sleep actually solves "Select Previous never lights up" across plug-sessions (the main thing).
- Whether the Select Previous → Verify Backup Flow → real backup chain works end-to-end after the cancellation and validate fixes.

**Test plan for tomorrow** (re-stated here so it's not buried in chat):

1. Sideload commit `535263c` (the new build).
2. Plug in a previously-named card. Open the app.
3. Watch the picker: within ~1 second, the row for the plugged-in card should resolve and **Select Previous** should light up (blue, tappable).
4. Tap **Select Previous**. The source should switch to that card without the file picker appearing.
5. Tap **Verify Backup Flow** → review scan summary → **Start Copying**. Confirm the backup runs.
6. Cancel the backup mid-stream. Confirm no "File Could Not Be Backed Up" dialog appears (just session ends as interrupted).
7. Pull the card. Within a few seconds the picker row should go gray ("not plugged in"). Pull the card during a backup and confirm the source clears.
8. Plug in a *different* known card. The picker should switch its default selection to the now-plugged-in card and Select Previous should light up for it.

**What the log will say if the retry is the fix:** lines like
`[MountedCards] Card-1: FileProvider not ready (attempt 1/3) — retrying in 200ms`
immediately followed by
`[MountedCards] Card-1: resolved to /private/var/… (isStale=false, accessStarted=true)`.

If after 3 retries it still fails with `bookmark did not resolve after retries — NSFileProviderErrorDomain -2001`, the lazy wake-up takes longer than 600 ms and we'd need to either lengthen the budget or find a non-bookmark detection path.

**Open follow-ups** (numbered items below, plus):

- Items #15 (per-card bookmark) is **done**.
- Items #16 (scan wording for no-files case), **#17** (rename "On this device" entries to indicate they're backups), and the diagnostic logs from `7767bc7` are all small view/text cleanups worth doing in one batch when Select Previous is confirmed reliable.

---

## What's Working

- Card → iCloud Drive backup (tested, verified)
- Card → VBB Internal Storage backup (tested)
- Incremental scan correctly skips already-backed-up files across app restarts
- Verify-only mode self-heals database after reinstall
- Source picker remembers last-picked location via bookmark
- Source picker falls back to Browse/Locations on first run or when card is ejected
- Internal archives shown as one-tap source options on main screen
- Known cards listed as reference in source zone
- Debug logging to iCloud Drive folder (configured in Settings)
- Reset Database option in ellipsis menu
- File browser with thumbnails (ImageIO for stills, AVFoundation for video)
- Full-screen image viewer with pinch-to-zoom (ZoomableScrollView)
- Multi-select with share and delete in file browser
- Post-session results with three outcome states
- History browser with grouped sessions, stale detection, card management

## Outstanding Tasks / Known Issues

### Bugs to Investigate

1. **Full-size preview (black screen)** — ZoomableScrollView was rewritten with Auto Layout constraints to fix the zero-frame-on-first-render issue. Needs re-testing on device to confirm the fix works.

2. **Share to Lightroom** — Scott reported sharing to Lightroom did not appear to work. Deferred for later investigation. May be a UTType issue or Lightroom's file provider requirements.

### UX Improvements (Scott's Notes)

3. **Target management UX** — Scott noted: "we should treat all target sources with privileged bookmarks where possible. Probably warrants a dropdown list before it gets too long and a place to manage locations (manage, rename and delete bookmarks from list)." The current Manage Destinations view works but could be improved with a dropdown picker on the main screen for quick target switching.

4. **Terminology** — Scott noted: "the term bookmarks will confuse users." Anywhere the app surfaces "bookmark" language to the user, replace with something clearer (e.g. "saved location," "remembered drive"). *(2026-05-11: the one user-facing instance — the "Reset Source Bookmark" ellipsis-menu item — has been renamed to "Forget Last Source." If new user-facing "bookmark" wording appears, apply the same rule.)*

5. **Show log folder path in Settings** — When a debug log folder is selected, display the path to the folder in the Settings screen so the user can see where logs are being written. *(2026-05-11: done.)*

6. **Rename "Start Backup" button to "Verify Backup Flow"** — On the main screen where source and target are chosen, change the button label from "Start Backup" to "Verify Backup Flow." *(2026-05-11: done.)*

14. **Merge scan summary onto main screen** — Today, tapping the main-screen button navigates to a separate "Scan Complete" page that shows files-to-copy / already-backed-up / excluded / available space, with a second confirm button. Scott wants this summary to render inline on the main screen below the Source/Target zones, so the renamed "Verify Backup Flow" tap runs the scan in place; only after the user confirms with a second "Start Copying"-style button does navigation push to the session progress page. This eliminates the middle page and pairs naturally with the rename. Deferred from 2026-05-11 because Scott was out of time before sideloading. *(2026-05-12: done. New `InlineScanCard` view; old `ScanProgressView` and `ScanSummaryView` deleted; SelectionView wrapped in ScrollView with `.safeAreaInset` for the bottom button; scan card auto-clears when Source or Target changes.)*

17. **"On this device" archive names are confusing** — When a card has been backed up to VBB Internal Storage, the archive folder is named e.g. `20260512_Canon EOS R6 Card-256Gb` (date + card friendly name). That same string is then surfaced verbatim under the source-zone "On this device" list, which makes it visually indistinguishable from the live card itself. Scott (2026-05-12): "should prepend Backup to backed up cards, somehow." Two options: prepend "Backup of " in the display only (model unchanged) — cleanest — or render with an extra subtitle like "(previous backup)". The actual on-disk folder name should NOT change because that name is used by incremental scan comparisons (per §5d of the directive). Fix lives in the source-zone view layer where internalArchives is iterated.

16. **Scan summary wording for the no-files case** — When the scan finds zero files on the source, the summary currently reads "everything is backed up." That phrasing only makes sense when the source had files and they all already exist on the destination. For an empty source (no files at all) it should read "no files to back up" or similar. Surfaced by Scott on 2026-05-12 after the card-swap clear: source was effectively invalidated, scan saw 0 source files, summary read "everything is backed up" which was misleading. Fix lives in ScanViewModel summary text generation — branch on `totalSourceFiles == 0`.

15. **Per-KnownCard security-scoped bookmark (skip picker entirely)** — *(2026-05-12: done. The hybrid mount-detect via `mountedVolumeURLs` was confirmed dead — iOS doesn't surface external camera cards to a sandboxed app through that API; the dump returned count=0 even with the card actively picked via the picker. Replaced with bookmark-based detection: `KnownCard.bookmarkData` stores a security-scoped bookmark captured at every successful pick, and `MountedVolumeService` now resolves each bookmark to answer both "is it mounted?" and provide sandbox-ready URL access. "Choose Previous" tap path resolves the bookmark and feeds the URL straight into `handleSourceSelected` — no picker. Three row states with plain-English guidance: tappable blue when mounted+bookmarked, gray "Not plugged in" when bookmarked but unmounted, gray "Pick once via Select Source to enable quick-select" when no bookmark yet. Legacy cards have no bookmark; one more normal pick activates them.)*

### Technical Debt

7. **Orphaned print statements** — Some `print()` calls may remain in files other than FolderPickerView. Search for `print(` and replace with `DebugLogService.shared.log()` where appropriate. Remove any that are no longer useful.

8. **SelectionView size** — SelectionView.swift is the navigation coordinator for the entire app. At ~195 lines it's within limits but will grow as features are added. Consider extracting navigation logic into a dedicated coordinator if it exceeds ~200 again.

9. **SwiftData persistence verification** — Scott observed that the database may not persist across app reinstalls (expected) but the app should handle this gracefully. The verify-only mode now handles this case, but worth testing: kill app → relaunch → same card + target → should show "nothing to copy" or "X files to verify."

10. **Module 7 File Browser** — Built but lightly tested. Needs device testing with actual CR3 files. The spec notes that the simulator may not support CR3 — test on real hardware. If ImageIO doesn't produce thumbnails, there's a byte-offset fallback described in the Module 7 spec.

### Features Not Yet Built

11. **Camera Settings Restore (§9.1)** — Stretch goal. The architecture supports it (KnownCard stores cameraModel, FileRecord has isSettingsFile flag, SettingsFilePatterns lookup table exists). Not implemented.

12. **Deep Verify** — Future feature noted in Module 4. Re-hash all destination files and compare against stored FileRecord hashes to confirm nothing has changed on the target drive. VerificationEngine's interface was deliberately kept clean to support this.

13. **Pause/Resume** — Only cancel is implemented for v1. Pause deferred to v2.

## File Count

47 Swift files, ~5,200 lines of code across:
- 6 Models
- 10 Services
- 7 ViewModels
- 24 Views

## Git Log (recent)

```
43f2ca5 Rename iPad to local storage everywhere, fix cleanup dialog trigger
eb80f1e Add file-based debug logging to iCloud Drive for untethered testing
d806cbc Fix source picker: bookmark last-picked folder, force Browse on first run
e9f66dc Add Reset Database option to main screen menu
60a7abe Add verify-only mode: hash existing destination files to self-heal database
f8c37a0 Fix incremental scan to check destination filesystem, not just database
c1aef7e Add git commit directive to CLAUDE.md
962889b Implement all 7 modules of Virtual Backup Box
9c0a523 Initial Commit
```
