// ThumbnailCell.swift
// Virtual Backup Box
//
// A single cell in the media grid. Shows a thumbnail image loaded
// asynchronously via ThumbnailService. For videos, overlays a play
// icon and duration label. In selection mode, shows a selection indicator.

import SwiftUI

struct ThumbnailCell: View {

    let file: MediaFile
    let isVideo: Bool
    let isSelecting: Bool
    let isSelected: Bool
    let size: CGFloat

    @State private var thumbnail: UIImage?
    @State private var duration: TimeInterval?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Thumbnail or placeholder
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: size, height: size)
            }

            // Video overlay: play icon and duration
            if isVideo {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                    if let duration {
                        Text(formatDuration(duration))
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.white)
                .padding(4)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                .padding(4)
            }

            // Selection indicator
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .white)
                    .shadow(radius: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(6)
            }
        }
        .task {
            thumbnail = await ThumbnailService.shared.thumbnail(for: file.url)
            if isVideo {
                duration = await ThumbnailService.shared.videoDuration(for: file.url)
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
