// CardDetectionService.swift
// Virtual Backup Box
//
// Handles camera card detection: checks for a DCIM folder, reads the volume
// UUID, and extracts the camera model string from EXIF metadata in media files.
//
// Card detection is triggered by Module 1 when the user selects a source
// folder. If the folder contains DCIM/ at its root, it is treated as a
// camera card and the full detection flow runs.
//
// Camera model extraction reads EXIF from stills (via ImageIO) or video
// metadata (via AVFoundation). It must run on a background task because
// file I/O on a camera card over USB can be slow.

import Foundation
import ImageIO
import AVFoundation

enum CardDetectionService {

    /// Checks whether the given folder looks like a camera card by checking
    /// for a DCIM subfolder at its root. DCIM is the universal directory
    /// standard used by all digital cameras.
    static func isCameraCard(at url: URL) -> Bool {
        let dcimURL = url.appendingPathComponent("DCIM")
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: dcimURL.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }

    /// Reads the filesystem volume UUID from the given URL.
    ///
    /// Returns the UUID string, or nil if it cannot be read. Some FAT32
    /// volumes may not report a UUID — the caller falls back to generic
    /// folder treatment in that case.
    static func readVolumeUUID(from url: URL) -> String? {
        let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey])
        return values?.volumeUUIDString
    }

    /// Extracts the camera model string from the first media file found on
    /// the card.
    ///
    /// Tries stills first (CR3 or JPG in DCIM/), then video (MP4 in XFVC/).
    /// Returns the EXIF Model field (e.g. "Canon EOS R6 Mark III"), or nil
    /// if no media files are found or none contain a model string.
    ///
    /// Must be called from a background task — it performs file I/O.
    static func extractCameraModel(from sourceURL: URL) async -> String? {
        if let model = extractModelFromStills(in: sourceURL) {
            return model
        }
        return await extractModelFromVideo(in: sourceURL)
    }

    // MARK: - Private: Still Image Model Extraction

    /// Searches DCIM/ for the first CR3 or JPG file and reads its EXIF Model
    /// field. Uses ImageIO, which reads only the metadata header — it does
    /// not decode the full image.
    private static func extractModelFromStills(in sourceURL: URL) -> String? {
        let dcimURL = sourceURL.appendingPathComponent("DCIM")
        guard let enumerator = FileManager.default.enumerator(
            at: dcimURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let stillExtensions: Set<String> = ["CR3", "JPG", "JPEG"]

        while let fileURL = enumerator.nextObject() as? URL {
            guard stillExtensions.contains(fileURL.pathExtension.uppercased()) else {
                continue
            }
            if let model = readModelWithImageIO(from: fileURL) {
                return model
            }
        }
        return nil
    }

    /// Reads the TIFF Model field from an image file using ImageIO.
    /// Returns nil if the file cannot be read or contains no model metadata.
    private static func readModelWithImageIO(from url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source, 0, nil
              ) as? [String: Any] else {
            return nil
        }

        let tiffKey = kCGImagePropertyTIFFDictionary as String
        let modelKey = kCGImagePropertyTIFFModel as String

        guard let tiff = properties[tiffKey] as? [String: Any] else {
            return nil
        }
        return tiff[modelKey] as? String
    }

    // MARK: - Private: Video Model Extraction

    /// Searches XFVC/ for the first MP4 file and reads its metadata Model
    /// field. Uses AVFoundation's async metadata loading API.
    private static func extractModelFromVideo(
        in sourceURL: URL
    ) async -> String? {
        let xfvcURL = sourceURL.appendingPathComponent("XFVC")
        guard let enumerator = FileManager.default.enumerator(
            at: xfvcURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension.uppercased() == "MP4" else { continue }

            let asset = AVURLAsset(url: fileURL)
            do {
                let metadata = try await asset.load(.commonMetadata)
                let items = AVMetadataItem.metadataItems(
                    from: metadata,
                    filteredByIdentifier: .commonIdentifierModel
                )
                if let item = items.first,
                   let model = try await item.load(.stringValue) {
                    return model
                }
            } catch {
                // Could not read this file's metadata — try the next one
                continue
            }
        }
        return nil
    }
}
