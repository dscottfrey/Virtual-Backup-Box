# Module 7 — File Browser

**Status:** Scoped, ready to build
**Depends on:** Module 1 (KnownCard, KnownTarget, BookmarkService), Module 6 (history — for card list)
**Blocks:** Nothing
**Last Updated:** 2026-04-21

> Before building this module, read `00_OVERALL_DIRECTIVE.md` and `00_DATA_MODELS.md`.
> This module operates on files already in internal iPad storage. It does not copy,
> verify, or interact with the backup engine.

---

## What This Module Does

The File Browser lets the user look at card mirrors stored on internal iPad storage,
browse images and videos as thumbnails, view them full-screen, share individual or
multiple files with other apps (Lightroom, Photos, etc.), and delete unwanted files
(bad exposures, missed focus) to reclaim space.

It is a read-and-cull tool. It has nothing to do with the backup process.

---

## What the File Browser Is NOT

- Not a general file browser. It only shows card mirrors the app knows about on
  internal iPad storage. It does not navigate arbitrary folders.
- Not available for external drive targets in v1. Files on external SSDs or camera
  cards cannot be browsed here. Internal staging storage only.
- Not automated in any way. Every deletion is individually user-confirmed or batch-
  confirmed. The app never decides what to delete.

---

## CR3 Thumbnail Strategy (Verified from Sample Card)

Canon CR3 files contain three embedded JPEG previews at fixed offsets:

| Preview | Size | Dimensions | Use |
|---------|------|------------|-----|
| Small | 14 KB | 160×120 | Skip — too small for grid |
| Medium | 204 KB | 1620×1080 | **Grid thumbnails** |
| Full | 2.1 MB | 6960×4640 | **Full-screen view** |

No RAW decoding is required. `ImageIO` via `CGImageSourceCreateThumbnailAtIndex`
extracts the appropriate embedded JPEG. The full-resolution preview (2.1 MB JPEG)
is indistinguishable from decoding the RAW in typical use.

**iOS API:**
```swift
// For grid thumbnails — request a max dimension, ImageIO picks the right preview
let options: [CFString: Any] = [
    kCGImageSourceThumbnailMaxPixelSize: 400,
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true   // respect EXIF orientation
]
let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil)
let thumbnail = CGImageSourceCreateThumbnailAtIndex(source!, 0, options as CFDictionary)
```

For full-screen, request max dimension matching the display (e.g. 3000 px on a
large iPad). ImageIO will select the full embedded JPEG automatically.

**JPEG and other stills:** `ImageIO` handles these natively — same API, no special cases.

**Video thumbnails (MP4):** Use `AVFoundation`:
```swift
let asset = AVAsset(url: fileURL)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
let thumbnail = try generator.copyCGImage(at: .zero, actualTime: nil)
// .zero = first frame; acceptable for a thumbnail
```

---

## Navigation Flow

```
Main Screen (Module 1)
    └── "Browse Files" button (shown only if internal storage targets have card folders)
            ↓
        Card Picker
            └── [card list — YYYYMMDD_Name folders on internal storage]
                    ↓ tap a card
                Images | Videos  (segmented control)
                    ↓
                Thumbnail Grid
                    ├── tap thumbnail → Full Screen Viewer
                    └── tap Select → Multi-Select Mode
                                        ├── Share button → system share sheet
                                        └── Delete button → confirmation → delete
```

---

## Card Picker

Lists all card mirrors available on internal iPad storage.

**How the list is built:**
1. Fetch all `KnownTarget` records whose bookmark resolves to internal iPad storage.
   Detection: the resolved URL's volume is the device's internal storage
   (`URLResourceKey.volumeIsInternalKey == true`).
2. For each such target, list subdirectories matching the `YYYYMMDD_*` naming pattern.
3. Cross-reference with `KnownCard.destinationFolderName` to get the friendly card name
   and camera model for display.
4. If a folder exists on disk but has no matching `KnownCard` record (edge case —
   manually placed folder), show the folder name as-is with no camera model.

Each card row shows:
- Card friendly name (e.g. "EOS R6 Mark III Card-1")
- Camera model
- Date of first backup (from folder name prefix)
- Image count + video count (enumerated at list-build time, cached)
- Total size on disk

If no card mirrors exist on internal storage: show an empty state explaining that
backed-up cards will appear here once files are copied to iPad storage.

---

## Thumbnail Grid

Two tabs: **Images** and **Videos** (segmented control at top).

**Images tab:** Shows all image files in the card's `DCIM/` subfolders.
Supported extensions: `.CR3`, `.JPG`, `.JPEG`, `.HEIC`, `.RAF`, `.ARW`, `.NEF`, `.DNG`
(common RAW and JPEG formats — add as needed, but CR3 + JPG covers the primary case).

**Videos tab:** Shows all video files in the card's `XFVC/` subfolders (Canon) and
any other video files found in DCIM or root. Supported extensions: `.MP4`, `.MOV`.

**Grid layout:**
- iPad: 4 columns in portrait, 6 columns in landscape
- iPhone: 3 columns in portrait, 4 columns in landscape
- Square cells with no gaps between them (like iOS Photos app)
- Cell size computed from available width / column count

**Thumbnail loading:**
- Load thumbnails asynchronously on background Tasks
- Display a neutral grey placeholder while loading
- Cache loaded thumbnails in an `NSCache<NSString, UIImage>` keyed by file path
  `NSCache` handles memory pressure automatically — do not implement a custom cache
- Do not load all thumbnails at once — use lazy loading as cells scroll into view
  (`LazyVGrid` in SwiftUI handles this correctly)

**Video cells:** Show the thumbnail with a play icon overlay and duration label
(bottom trailing). Duration from `AVAsset.duration`.

**Sort order:** By filename (which for Canon files encodes capture sequence).
Do not sort by modification date — filesystem dates are unreliable after a copy.

---

## Full Screen Viewer

Tapping a thumbnail pushes (or sheets) to the full-screen viewer.

**Images:**
- Load the full embedded JPEG preview via `ImageIO` (max dimension ~3000px)
- Pinch to zoom, double-tap to zoom to 100%
- Swipe left/right to navigate to the next/previous file in the grid
- Show filename and capture date (from EXIF) in an overlay that auto-hides after 3s
- Share button (top trailing): opens system share sheet for the current file
- Trash button (top trailing): delete with confirmation (single file)

**Videos:**
- Use `VideoPlayer` from `AVKit` — the correct Apple framework for this
- Swipe left/right to navigate between videos
- Share and trash buttons same as images

**SwiftUI zoom:** `ScrollView` with a `ZoomableImageView` wrapper. Implementing
pinch-to-zoom in SwiftUI requires a `UIViewRepresentable` wrapping `UIScrollView`
configured for zoom. This is a known pattern — flag it to Scott before building
using the exact language: "This approach requires a UIViewRepresentable wrapper."
It is not fighting the framework — it is using UIKit via the supported bridge.
Apple's `ScrollView` does not natively support pinch-to-zoom in SwiftUI as of iOS 17.

---

## Multi-Select Mode

Activated by a "Select" button in the grid toolbar.

In multi-select mode:
- A circular selection indicator appears on each cell (empty circle / filled checkmark)
- Tapping a cell toggles its selection
- The toolbar shows: "X selected", Share button, Delete button, Cancel button
- "Select All" option in the toolbar

**Share (Open In...):**
- Collect the URLs of all selected files
- Present `UIActivityViewController` via a `UIViewRepresentable` wrapper
  (ShareLink in SwiftUI does not support bulk sharing of file URLs as of iOS 17 —
  flag this to Scott as requiring a UIViewRepresentable. Not fighting the framework —
  this is the documented Apple approach for multi-file sharing.)
- Compatible apps (Lightroom Mobile, Photos, etc.) appear automatically based on
  file type. No hardcoding of app names.
- After sharing, selection mode remains active (the user may want to then delete
  the same files they just exported)

**Delete:**
- Confirmation sheet: "Delete [X] files? This cannot be undone."
  List the filenames if X ≤ 5; show count only if X > 5.
- On confirm: delete files via `FileManager.removeItem`.
- Update the grid immediately (remove deleted cells with animation).
- Do not update any `FileRecord` entries in the database — those records represent
  verified copies on external targets and remain valid after source deletion.
- Add the required exception comment at every deletion callsite:

```swift
// DELIBERATE EXCEPTION to read-only source rule (§2 of overall directive).
// Files being deleted here are on internal iPad storage (staging area only).
// Verified copies exist on external targets per FileRecord entries in the database.
// Deletion is triggered only by explicit user confirmation.
```

---

## Files To Build

```
VirtualBackupBox/
├── Services/
│   ├── ThumbnailService.swift        ← generates and caches thumbnails;
│   │                                    CR3/JPG via ImageIO, MP4 via AVFoundation;
│   │                                    NSCache for memory management
│   └── FileBrowserService.swift      ← builds card list from KnownTarget + KnownCard
│                                        records; enumerates media files per card;
│                                        handles deletion
├── ViewModels/
│   └── FileBrowserViewModel.swift    ← card list state, selected card, current tab
│                                        (images/videos), file list, selection state,
│                                        thumbnail request coordination
└── Views/
    └── Browser/
        ├── FileBrowserView.swift         ← entry point; shows card picker or grid
        │                                    if only one card; hosts navigation
        ├── CardPickerView.swift          ← list of card mirrors with metadata
        ├── MediaGridView.swift           ← LazyVGrid of thumbnails; Images/Videos tabs;
        │                                    select mode toolbar
        ├── ThumbnailCell.swift           ← single grid cell: image/video thumbnail,
        │                                    selection indicator, video duration overlay
        ├── FullScreenImageView.swift     ← zoomable image viewer with swipe navigation;
        │                                    UIViewRepresentable for pinch-to-zoom
        ├── FullScreenVideoView.swift     ← AVKit VideoPlayer with swipe navigation
        └── ZoomableScrollView.swift      ← UIViewRepresentable wrapping UIScrollView
                                             for pinch-to-zoom; used by FullScreenImageView
```

---

## Key Constraints & Cautions

**This module never touches the backup engine.** No calls to `CopyEngine`,
`VerificationEngine`, `BackupSessionService`, or any Module 3/4 service. If you
find yourself reaching for those, stop — the design has gone wrong.

**Internal storage only.** Do not show card mirrors on external drives. The
`volumeIsInternalKey` check in `FileBrowserService` must be enforced, not optional.

**Thumbnail generation is expensive for large grids.** Use `LazyVGrid` — SwiftUI
will only render visible cells. Do not pre-generate all thumbnails at grid load.
`ThumbnailService` should generate on demand and cache aggressively.

**CR3 thumbnail extraction uses ImageIO — test on a real device.** The simulator
may not support CR3. The sample card file is available at:
`Sample Camera Card/DCIM/100EOSR6/_MG_1530.CR3`
Test thumbnail extraction early in the build — before building the rest of the grid.
If ImageIO does not produce a thumbnail on the target device, fall back to the
embedded JPEG extraction by byte offset (offsets are known from analysis:
thumbnail at 110,096 bytes, full preview at 319,488 bytes).

**EXIF orientation must be respected.** Pass `kCGImageSourceCreateThumbnailWithTransform: true`
in all `ImageIO` thumbnail requests. Failing to do this produces sideways thumbnails
for portrait-orientation shots.

**Deletion updates the grid, not the database.** After deleting files, remove them
from the ViewModel's file list and let SwiftUI animate the grid update. Do not touch
`FileRecord`, `CopySession`, `KnownCard`, or `KnownTarget` records.

---

## Open Questions for This Module

| # | Question | Status |
|---|----------|--------|
| 1 | Should Videos tab show both standard and open-gate video, or separate them? | ❓ Show all together in v1. Both are in XFVC/ anyway. User can distinguish by file size if needed. |
| 2 | Should the file browser be available for external drive targets in a future version? | ❓ Possible v2 feature. Architecture should not prevent it — keep FileBrowserService generic enough to accept any accessible URL, not just internal storage. |
| 3 | RAW formats beyond Canon CR3? | ❓ ImageIO handles most common RAW formats on iOS (RAF, ARW, NEF, DNG). Add extensions to the supported list as they are tested. Start with CR3 and JPG. |

---

## Definition of Done

Module 7 is complete when:
- [ ] Card picker lists card mirrors on internal iPad storage with correct metadata.
      Empty state shown if no internal card mirrors exist.
- [ ] Images tab shows all image files from the selected card's DCIM subfolders.
      CR3 thumbnails load correctly using ImageIO embedded preview extraction.
      EXIF orientation is applied (no sideways thumbnails).
- [ ] Videos tab shows all MP4/MOV files with first-frame thumbnail and duration.
- [ ] Thumbnails load lazily (only visible cells), cached in NSCache.
- [ ] Tapping a thumbnail opens full-screen viewer. Pinch-to-zoom works for images.
      Swipe left/right navigates between files.
- [ ] `VideoPlayer` plays MP4 files correctly in full-screen.
- [ ] Multi-select mode: tap to select, select all, share sheet opens with correct files.
- [ ] Delete: confirmation sheet names files (up to 5), deletes on confirm, grid
      updates with animation. Database is not modified.
- [ ] All deletion callsites have the required §2 exception comment.
- [ ] Tested with the sample CR3 file — thumbnail renders correctly.
- [ ] Tested on iPad (primary) and iPhone (secondary).
- [ ] No file exceeds ~200 lines. `ZoomableScrollView` and `UIActivityViewController`
      wrappers are documented with comments explaining why UIViewRepresentable is used.
