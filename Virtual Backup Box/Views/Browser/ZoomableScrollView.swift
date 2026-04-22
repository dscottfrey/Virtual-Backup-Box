// ZoomableScrollView.swift
// Virtual Backup Box
//
// UIViewRepresentable wrapping UIScrollView for pinch-to-zoom on images.
// This wrapper is necessary because SwiftUI's ScrollView does not support
// pinch-to-zoom as of iOS 17. This is NOT fighting the framework — it is
// using UIKit via Apple's supported UIViewRepresentable bridge.
//
// Uses Auto Layout constraints to correctly size the image to the scroll
// view's frame — manual frame setting fails because scrollView.bounds is
// zero on the first layout pass.

import SwiftUI
import UIKit

struct ZoomableScrollView: UIViewRepresentable {

    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delegate = context.coordinator

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)

        // Pin the imageView to the scroll view's content guide (for scrolling)
        // and constrain its size to the scroll view's frame guide (for display).
        // This ensures the image fills the visible area and zoom works correctly.
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        context.coordinator.imageView = imageView
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
        scrollView.zoomScale = 1.0
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        /// Tells the scroll view which subview to zoom.
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }
    }
}
