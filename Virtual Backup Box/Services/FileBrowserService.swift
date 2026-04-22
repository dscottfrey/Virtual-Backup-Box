// FileBrowserService.swift
// Virtual Backup Box
//
// Builds the list of browsable card mirrors on internal iPad storage and
// enumerates media files within them. Also handles file deletion for the
// browse-and-cull workflow. This module never touches the backup engine.
//
// Internal storage only: the volumeIsInternalKey check is enforced, not
// optional. External drive mirrors are not shown in the file browser.

import Foundation
import SwiftData

/// A card mirror folder found on internal iPad storage.
struct CardMirror: Identifiable, Sendable {
    let id: String
    let folderURL: URL
    let folderName: String
    let cardName: String?
    let cameraModel: String?
    var imageCount: Int
    var videoCount: Int
    var totalSizeBytes: Int64
}

/// A single media file in a card mirror.
struct MediaFile: Identifiable, Hashable, Sendable {
    let url: URL
    let fileName: String
    let fileSizeBytes: Int64
    var id: URL { url }
}

nonisolated enum FileBrowserService {

    /// Image file extensions supported in the browser.
    static let imageExtensions: Set<String> = [
        "CR3", "JPG", "JPEG", "HEIC", "RAF", "ARW", "NEF", "DNG"
    ]

    /// Video file extensions supported in the browser.
    static let videoExtensions: Set<String> = ["MP4", "MOV"]

    /// Finds all card mirror folders on internal iPad storage targets.
    /// Cross-references with KnownCard records for display names.
    static func findCardMirrors(context: ModelContext) -> [CardMirror] {
        let targetDescriptor = FetchDescriptor<KnownTarget>()
        let targets = (try? context.fetch(targetDescriptor)) ?? []

        let cardDescriptor = FetchDescriptor<KnownCard>()
        let cards = (try? context.fetch(cardDescriptor)) ?? []
        let cardsByFolder = Dictionary(
            uniqueKeysWithValues: cards.map { ($0.destinationFolderName, $0) }
        )

        var mirrors: [CardMirror] = []

        for target in targets {
            guard let resolved = BookmarkService.resolveBookmark(target.bookmarkData),
                  resolved.url.startAccessingSecurityScopedResource() else { continue }
            defer { resolved.url.stopAccessingSecurityScopedResource() }

            let values = try? resolved.url.resourceValues(
                forKeys: [.volumeIsInternalKey]
            )
            guard values?.volumeIsInternal == true else { continue }

            let contents = (try? FileManager.default.contentsOfDirectory(
                at: resolved.url,
                includingPropertiesForKeys: [.isDirectoryKey]
            )) ?? []

            for folderURL in contents {
                let isDir = (try? folderURL.resourceValues(
                    forKeys: [.isDirectoryKey]
                ))?.isDirectory ?? false
                guard isDir else { continue }

                let name = folderURL.lastPathComponent
                let card = cardsByFolder[name]
                let (images, videos, size) = countMedia(in: folderURL)

                guard images > 0 || videos > 0 else { continue }

                mirrors.append(CardMirror(
                    id: name,
                    folderURL: folderURL,
                    folderName: name,
                    cardName: card?.friendlyName,
                    cameraModel: card?.cameraModel,
                    imageCount: images,
                    videoCount: videos,
                    totalSizeBytes: size
                ))
            }
        }
        return mirrors.sorted { $0.folderName > $1.folderName }
    }

    /// Enumerates image files in a card mirror folder.
    static func imageFiles(in folderURL: URL) -> [MediaFile] {
        enumerateFiles(in: folderURL, extensions: imageExtensions)
    }

    /// Enumerates video files in a card mirror folder.
    static func videoFiles(in folderURL: URL) -> [MediaFile] {
        enumerateFiles(in: folderURL, extensions: videoExtensions)
    }

    // MARK: - Private

    private static func countMedia(
        in folderURL: URL
    ) -> (images: Int, videos: Int, totalBytes: Int64) {
        var images = 0, videos = 0, total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return (0, 0, 0) }

        while let url = enumerator.nextObject() as? URL {
            let ext = url.pathExtension.uppercased()
            let size = Int64((try? url.resourceValues(
                forKeys: [.fileSizeKey]
            ))?.fileSize ?? 0)
            if imageExtensions.contains(ext) { images += 1; total += size }
            else if videoExtensions.contains(ext) { videos += 1; total += size }
        }
        return (images, videos, total)
    }

    private static func enumerateFiles(
        in folderURL: URL, extensions: Set<String>
    ) -> [MediaFile] {
        var files: [MediaFile] = []
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        while let url = enumerator.nextObject() as? URL {
            let ext = url.pathExtension.uppercased()
            guard extensions.contains(ext) else { continue }
            let size = Int64((try? url.resourceValues(
                forKeys: [.fileSizeKey]
            ))?.fileSize ?? 0)
            files.append(MediaFile(
                url: url, fileName: url.lastPathComponent, fileSizeBytes: size
            ))
        }
        return files.sorted { $0.fileName < $1.fileName }
    }
}
