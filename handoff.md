# Virtual Backup Box — Handoff Notes

**Date:** 2026-04-22 (original) / 2026-09-08 (latest session below)
**From:** Desktop session → Laptop continuation
**Status:** All 7 modules built and tested on device. Core backup flow working. Source UI deliberately simplified to a single Choose Source button for core-functionality testing. Codebase passed a SwiftUI Pro skill review on 2026-05-20; tier-1 mechanical fixes landed, two riskier tiers deferred (see below).

---

## 2026-09-08 Session — TestFlight preparation

Goal: get the app ready to Archive and upload to TestFlight with Scott's developer signing. Read-only audit first, then four commits. **No Release build was compiled in this session** — the Claude Code sandbox blocks Xcode's build service from writing its build folder anywhere, so the first Archive in Xcode is also the first Release compile since 2026-05-20.

### What was already in place (verified, no change needed)
- Automatic signing on Debug and Release, team `B96HF9533R` (D. Scott Frey), bundle ID `com.scottfrey.Virtual-Backup-Box`. A development profile for this bundle ID exists on this Mac (expires 2027-05-12).
- This Mac has an App Store distribution profile for Scott's Codex Reader app (June 2026), so the paid membership and App Store Connect flow already work. The distribution certificate could not be checked (sandbox blocks keychain reads) — Xcode will create one automatically if missing.
- App icon: 1024 universal + dark + tinted. Version 1.0, build 1.
- No permission-prompting APIs (photos, camera, location), so no usage strings needed. No `print` calls, no `#if DEBUG`. DebugLogService is user opt-in in Settings — fine to ship.

### Commits
1. **`d680cde` — PrivacyInfo.xcprivacy.** Required by App Store Connect. Declares UserDefaults (CA92.1) and DiskSpace (E174.1), no tracking, no collected data. Folder-synced group picks it up automatically.
2. **`fb526f3` — `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`** on the app target (Debug + Release). SHA-256 hashing is exempt. **Verify after the first Archive** that the built Info.plist contains `ITSAppUsesNonExemptEncryption`; if not, fall back to a tiny Info.plist file with just that key.
3. **.gitignore + untrack** `.DS_Store`, `UserInterfaceState.xcuserstate`, `xcschememanagement.plist`.
4. Docs (this note + directive rev 3).

### Minimum OS decision
Project has been `IPHONEOS_DEPLOYMENT_TARGET = 26.4` since the initial commit while the directive said 17+. Scott first said iOS 18, then reversed to **26.4 — confirmed**. Directive updated to match.

**Correction to the 2026-05-20 note on `6cfc061`:** it claimed `ForEach` accepts `EnumeratedSequence` directly "on iOS 17+". That is wrong — the Collection conformance arrived in the Swift 6.2 standard library and is availability-gated to iOS 26. The four sites (`MediaGridView`, `FullScreenImageView`, `FullScreenVideoView`, `SessionResultsView`) compile only because the target is 26.4. If the target is ever lowered, wrap those four `enumerated()` calls in `Array(...)` again.

### Outcome (2026-09-08, later the same day)
Correction to an earlier draft of this note: "built and installed, works" referred to a direct Xcode install, not TestFlight. The actual sequence:
- Scott archived 1.0 (1) in Xcode and uploaded via Organizer → **App Store Connect** (this Xcode labels the option "App Store Connect", not "TestFlight & App Store").
- App Store Connect already held a **build 1 from June 2026** (unknown to this session — it expires ~2026-09-14). Xcode's "manage version and build number" therefore uploaded today's archive as **1.0 (2)**. The project file was not touched by that bump; `CURRENT_PROJECT_VERSION` is now set to 2 in this commit so source matches what shipped. Xcode will keep auto-bumping on upload regardless.
- Build 2 went straight to **"Waiting for Review"** (external group) without stopping at "Missing Compliance", so the `ITSAppUsesNonExemptEncryption = NO` key works. No export-compliance question was asked.
- Release configuration compiles clean; privacy manifest passed the upload check; automatic signing created the distribution certificate/profile without manual steps.
- Tester groups: internal "Testers" (TE, Scott, installs immediately) and external "VBB external testers" (VE, needs Apple's Beta App Review, typically about a day). The Test Information form's pre-checked "Sign-in required" box must be **unchecked** — the app has no login.

### Scott's steps in Xcode / App Store Connect (not automatable from Claude Code)
1. App Store Connect → My Apps → **+** → New App. Platform iOS, name "Virtual Backup Box", bundle ID `com.scottfrey.Virtual-Backup-Box` (already registered by automatic signing), any SKU.
2. Xcode: destination **Any iOS Device (arm64)** → **Product ▸ Archive**.
3. Organizer → **Distribute App** → **TestFlight & App Store** (or App Store Connect ▸ Upload). Accept the automatic signing defaults.
4. App Store Connect → TestFlight tab → add yourself as an internal tester → install via the TestFlight app on the iPad.
5. If the upload emails an `ITMS-91053` privacy warning, the manifest is missing a category — add it to `PrivacyInfo.xcprivacy`.

---

## 2026-05-20 Session — SwiftUI Pro review + Safe & mechanical fixes

Ran the SwiftUI Pro skill against the whole codebase (Views + ViewModels + entry points). Eleven commits in two waves, build verified after each.

### Wave 1 — Safe & mechanical (6 commits)

1. **`a779ae1` — SessionProgressView: replace `UINotificationFeedbackGenerator` with `.sensoryFeedback`.** The UIKit haptic instance-and-call was swapped for SwiftUI's declarative `.sensoryFeedback(.success, trigger: viewModel.isSessionComplete)`. `.onChange(of: viewModel.isSessionComplete)` is retained but only calls `onSessionComplete()` now. Dropped the now-unused `import UIKit`.

2. **`6cfc061` — Drop redundant `Array(_:)` wrapper around `enumerated()` in four `ForEach` sites.** `MediaGridView:42`, `FullScreenImageView:40`, `FullScreenVideoView:38`, `SessionResultsView:124`. ForEach accepts `EnumeratedSequence` directly on iOS 17+; the `Array` materialization was unnecessary copy work.

3. **`8ba82d8` — SessionResultsView: Dynamic Type for outcome icons and headings.** `.font(.system(size: 48))` on the three outcome SF Symbols (checkmark/warning/x) → `.font(.largeTitle)`, so the icon scales with system text size. Three `.fontWeight(.semibold)` calls on the heading Text → `.bold()` per design.md (let the system pick weight).

4. **`4f60353` — ThumbnailCell: modernize placeholder fill, shape syntax, and duration formatting.** `Color(.systemGray5)` → `.quaternary` (hierarchical, no UIKit reference, adapts to mode/context). `RoundedRectangle(cornerRadius: 4)` inside `.background(in:)` → `.rect(cornerRadius: 4)`. `String(format: "%d:%02d", m, s)` → `Duration.seconds(Int(seconds)).formatted(.time(pattern: .minuteSecond))`.

5. **`2664223` — MediaGridView: drop scattered `.fontWeight(.medium)`.** Removed from the "N selected" Text in the multi-select toolbar; system default is already legible.

6. **`1c734ce` — Extract `ActivityViewWrapper` from `MediaGridView.swift` into its own file** at `Views/Browser/ActivityViewWrapper.swift`. MediaGridView is now 127 lines (was 142) and holds one top-level type, satisfying §6.3. No functional change — the share-sheet wrapper is byte-identical, just relocated.

### Wave 2 — `@MainActor` on all `@Observable` view models (5 commits)

SwiftUI Pro / data.md: "`@Observable` classes must be marked `@MainActor` unless the project has Main Actor default actor isolation." The project does not have that default set, so each annotation was needed.

7. **`4f7062c` — SessionViewModel.** Drives the running-backup UI; mutates `pendingFailureAlert` / `isSessionComplete` from UI callbacks; hands itself off to `BackupSessionService.runSession` (which works fine — Swift bridges MainActor instances to nonisolated async functions automatically).

8. **`4e3f260` — HistoryViewModel.** Touches `ModelContext`, mutates session/group/card arrays read by the history browser. `detectStaleSessions` hops out via `Task.detached` for I/O and back to MainActor for the state update — the explicit isolation makes that back-hop unambiguously safe.

9. **`64af42c` — ResultsViewModel.** Read exclusively from the post-session results screen.

10. **`5a52cea` — ScanViewModel.** Drives the inline scan card; hops to detached for the scan run, writes the result back on return.

11. **`9c3258f` — FileBrowserViewModel.** Owns card-mirror / media-tab / selection state for the file browser.

All five compile clean. **Untested on device** — no behavior should change, but if a caller turns out to be background-isolated in a way the type system didn't catch (unlikely given Swift 6 strict concurrency was already enabled), a hang or stutter could surface. If something feels off in the next on-device run, this is the first place to look.

### Memory note saved
A project memory was written stating that **VoiceOver fixes are deprioritized** for this app (photo-backup tool for sighted photographers). Dynamic Type stays at normal priority — older users / reading glasses / Pro Display Zoom still matter. This affects how future SwiftUI Pro reviews rank findings: VO-only items go to the bottom.

### Deferred — tier 2 & 3 fixes from the review

These were flagged by the review but **not landed** because each has a real failure mode that compile-clean doesn't catch. Sequence and reasoning here so a future session doesn't have to redo the analysis.

**Tier 2 — Needs build verification + manual exercise (do these before tier 3):**

- **`Binding(get:set:)` in `FailureAlertModifier.swift:50–55`.** Rewrite to use `.alert(_:isPresented:presenting:)` so the optional `pendingFailureAlert` is unwrapped natively. **High blast radius.** The binding gates a `CheckedContinuation` that pauses `BackupSessionService.runSession`'s copy loop. Wrong-paths could:
  - Hang the session forever (continuation never resumes).
  - Trap on double-resume of `CheckedContinuation`.
  - Swap Continue/Cancel semantics on swipe-to-dismiss (already burned us once — see the 2026-05-13 comment at line 14 of the file).
  - **Mitigation:** rewrite, then manually exercise pull-card-mid-session and tap each of Continue / Cancel / background-dismiss before committing.

- **`Task.detached` audit — narrow scope.** Convert the obvious cases in `HistoryViewModel:88` (just `FileManager.isReadableFile` over a Sendable array) and `SelectionViewModel+Targets:63` to plain `await` on a `nonisolated` helper. **Leave `ThumbnailService:29` and `:42` alone** — those are loading and decoding images, which is exactly the workload `Task.detached` exists for. Risk if done wrong: work ends up MainActor-isolated and freezes the UI during scanning. Reversible by single revert.

**Tier 3 — Structural, ask before starting:**

- **Extract `@ViewBuilder` helper properties in `SessionResultsView.swift` (4 helpers) and `InlineScanCard.swift` (5 helpers) into dedicated `View` structs in their own files.** Low semantic risk (state-ownership slip or missed `@Bindable` are the main traps) but touches a lot of code. Also helps the 200-line ceiling. Should be one struct at a time, build + render-preview between each.

- **`GeometryReader` → `containerRelativeFrame` in `MediaGridView:38`.** Visual regression risk: padding/safe-area differences mean cell width can shift a few points, may look wrong on iPad split-view / landscape / rotation. Needs `RenderPreview` and real-device check; not a compile-time concern.

**Won't touch (decided during the review):**

- VoiceOver items: icon-only toolbar buttons in `MediaGridView:114, 119`; `.onTapGesture` lacking `.accessibilityAddTraits(.isButton)` in `MediaGridView:50` and `ManageTargetsView:188`. Deprioritized per the saved memory.
- `String(format: "%02x", $0)` in `CopyEngine:131` and `VerificationEngine:165`. Hex encoding — no clean stdlib alternative.

### Deferred — architectural concerns from the model-layer review

The SwiftUI Pro pass touched Views/ViewModels but I also spot-read the models and the copy/verify engines. The following items are not Views/SwiftUI issues but are real and worth recording so they don't slip:

- **`VerificationEngine.hashFile` silently `break`s on `Task.isCancelled`** (line 146), returning a *partial* hash. In `verify()` this is self-correcting (the partial hash won't match the source hash, so the destination is deleted) — but in `verifyExisting()` (lines 90–119, the self-heal path) the partial hash is written straight into a new `FileRecord`. **A cancelled self-heal would persist a wrong hash to the database.** Fix: throw `CancellationError()` instead of `break`. Small, contained.

- **`KnownCard.sessions` cascade-deletes session history** when a card is deleted (KnownCard.swift:92). This contradicts the file header on `CopySession.swift` lines 13–16, which says target identity is kept by path string specifically to preserve history if the target goes away. The same logic should apply to cards — deleting a card from "Known Cards" management should not erase the historical record of those backups. Either drop the cascade or add a separate "Delete card AND its history" path.

- **No `@Attribute(.unique)` on `KnownCard.uuid`** even though the header comment calls UUID "the primary identifier." A race during card-naming could create two rows for the same UUID. Adding the attribute now is cheap; later it requires a migration.

- **No `@Attribute(.indexed)` / `@Index` on `FileRecord.relativeSourcePath`,** which is the lookup key for Module 2's incremental comparison. With thousands of FileRecords on a large library, the linear scan will start to bite. Cheap fix now, harder to retrofit later.

- **No `VersionedSchema` / migration plan.** SwiftData handles trivial additive migrations on its own, but a renamed or moved property will require a migration scaffolded before the change ships. Worth setting up the bones before the next model touch.

None of these are urgent for current testing, but each is the kind of thing that becomes a multi-hour rescue mission if discovered live on a real session. Add to the model-layer cleanup list when the user-facing items quiet down.

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
