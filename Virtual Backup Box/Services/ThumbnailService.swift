// ThumbnailService.swift
// Virtual Backup Box
//
// Generates and caches thumbnails for the file browser. Uses ImageIO for
// stills (CR3, JPG, HEIC, etc.) and AVFoundation for video (MP4, MOV).
// NSCache handles memory pressure automatically — no manual eviction.
//
// Cache access stays on MainActor. Heavy I/O (ImageIO, AVFoundation) runs
// in detached tasks off the main thread.

import UIKit
import ImageIO
import AVFoundation

class ThumbnailService {

    static let shared = ThumbnailService()

    private let cache = NSCache<NSString, UIImage>()

    // MARK: - Grid Thumbnail

    /// Returns a thumbnail for the given file, using the cache if available.
    /// Generates one in the background if not cached. Returns nil on failure.
    func thumbnail(for url: URL, maxDimension: CGFloat = 400) async -> UIImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let image = await Task.detached {
            Self.generateThumbnail(for: url, maxDimension: maxDimension)
        }.value

        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    // MARK: - Full-Screen Image

    /// Returns a high-resolution image for full-screen display. Not cached
    /// (too large for memory-efficient caching of many images).
    func fullImage(for url: URL, maxDimension: CGFloat = 3000) async -> UIImage? {
        await Task.detached {
            Self.generateThumbnail(for: url, maxDimension: maxDimension)
        }.value
    }

    // MARK: - Video Duration

    /// Returns the duration of a video file in seconds.
    func videoDuration(for url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite ? seconds : nil
        } catch {
            return nil
        }
    }

    // MARK: - Private: Image Generation

    /// Generates a thumbnail using ImageIO (stills) or AVFoundation (video).
    /// Runs off the main thread.
    nonisolated private static func generateThumbnail(
        for url: URL, maxDimension: CGFloat
    ) -> UIImage? {
        let ext = url.pathExtension.uppercased()
        if ["MP4", "MOV"].contains(ext) {
            return generateVideoThumbnail(for: url)
        }
        return generateImageThumbnail(for: url, maxDimension: maxDimension)
    }

    /// Extracts an embedded JPEG preview from a still image via ImageIO.
    /// Works for CR3, JPG, HEIC, RAF, ARW, NEF, DNG — ImageIO handles
    /// all common RAW formats on iOS. EXIF orientation is applied via
    /// kCGImageSourceCreateThumbnailWithTransform.
    nonisolated private static func generateImageThumbnail(
        for url: URL, maxDimension: CGFloat
    ) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// Generates a thumbnail from the first frame of a video file.
    nonisolated private static func generateVideoThumbnail(
        for url: URL
    ) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        var cgImage: CGImage?
        let semaphore = DispatchSemaphore(value: 0)
        generator.generateCGImagesAsynchronously(
            forTimes: [NSValue(time: .zero)]
        ) { _, image, _, _, _ in
            cgImage = image
            semaphore.signal()
        }
        semaphore.wait()
        guard let cgImage else { return nil }
        return UIImage(cgImage: cgImage)
    }

}
