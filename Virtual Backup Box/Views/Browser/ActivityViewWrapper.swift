// ActivityViewWrapper.swift
// Virtual Backup Box
//
// UIViewControllerRepresentable wrapping UIActivityViewController for
// multi-file sharing from the media grid. SwiftUI's ShareLink does not
// support bulk file-URL sharing as of iOS 17 — this wrapper uses the
// documented Apple approach via the UIKit activity view controller.
//
// Extracted from MediaGridView.swift to satisfy the project's
// "one file, one job" rule (§6.3).

import SwiftUI
import UIKit

struct ActivityViewWrapper: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
