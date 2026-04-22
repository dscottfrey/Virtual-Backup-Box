// FolderPickerView.swift
// Virtual Backup Box
//
// UIViewControllerRepresentable wrapper around UIDocumentPickerViewController
// for folder selection. Supports setting an initial directory to control
// where the picker opens — set to "/" to start at the Locations level
// where connected drives and cards are visible.

import SwiftUI
import UniformTypeIdentifiers

struct FolderPickerView: UIViewControllerRepresentable {

    /// Initial directory for the picker. Set to "/" to open at the
    /// Locations level, or nil to use the picker's default (last location).
    let initialDirectory: URL?

    /// Called with the selected folder URL when the user confirms.
    let onPicked: (URL) -> Void

    /// Called when the user cancels the picker.
    let onCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancelled: onCancelled)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.folder]
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false

        if let dir = initialDirectory {
            picker.directoryURL = dir
        }

        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    // MARK: - Coordinator

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (URL) -> Void
        let onCancelled: () -> Void

        init(onPicked: @escaping (URL) -> Void,
             onCancelled: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancelled = onCancelled
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard let url = urls.first else { return }
            onPicked(url)
        }

        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
            onCancelled()
        }
    }
}
