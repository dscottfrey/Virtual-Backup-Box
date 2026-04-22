# Virtual Backup Box — Handoff Notes

**Date:** 2026-04-22
**From:** Desktop session → Laptop continuation
**Status:** All 7 modules built and tested on device. Core backup flow working.

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

4. **Terminology** — Scott noted: "the term bookmarks will confuse users." Anywhere the app surfaces "bookmark" language to the user, replace with something clearer (e.g. "saved location," "remembered drive").

### Technical Debt

5. **Orphaned print statements** — Some `print()` calls may remain in files other than FolderPickerView. Search for `print(` and replace with `DebugLogService.shared.log()` where appropriate. Remove any that are no longer useful.

6. **SelectionView size** — SelectionView.swift is the navigation coordinator for the entire app. At ~195 lines it's within limits but will grow as features are added. Consider extracting navigation logic into a dedicated coordinator if it exceeds ~200 again.

7. **SwiftData persistence verification** — Scott observed that the database may not persist across app reinstalls (expected) but the app should handle this gracefully. The verify-only mode now handles this case, but worth testing: kill app → relaunch → same card + target → should show "nothing to copy" or "X files to verify."

8. **Module 7 File Browser** — Built but lightly tested. Needs device testing with actual CR3 files. The spec notes that the simulator may not support CR3 — test on real hardware. If ImageIO doesn't produce thumbnails, there's a byte-offset fallback described in the Module 7 spec.

### Features Not Yet Built

9. **Camera Settings Restore (§9.1)** — Stretch goal. The architecture supports it (KnownCard stores cameraModel, FileRecord has isSettingsFile flag, SettingsFilePatterns lookup table exists). Not implemented.

10. **Deep Verify** — Future feature noted in Module 4. Re-hash all destination files and compare against stored FileRecord hashes to confirm nothing has changed on the target drive. VerificationEngine's interface was deliberately kept clean to support this.

11. **Pause/Resume** — Only cancel is implemented for v1. Pause deferred to v2.

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
