// SettingsView.swift
// Virtual Backup Box
//
// App settings screen accessible from the ellipsis menu. Currently
// contains debug logging configuration: enable/disable logging and
// select the iCloud Drive folder where log files are written.

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var isLoggingEnabled = DebugLogService.shared.isConfigured
    @State private var showingLogFolderPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Enable Debug Logging", isOn: $isLoggingEnabled)
                        .onChange(of: isLoggingEnabled) {
                            if isLoggingEnabled && !DebugLogService.shared.isConfigured {
                                showingLogFolderPicker = true
                            } else if !isLoggingEnabled {
                                DebugLogService.shared.clearLogFolder()
                            }
                        }

                    if DebugLogService.shared.isConfigured {
                        Text("Logs are written to VBB_Debug_Log.txt in your selected folder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Change Log Folder") {
                            showingLogFolderPicker = true
                        }
                    } else if isLoggingEnabled {
                        Text("Select a folder (e.g. iCloud Drive) where debug logs will be written.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Select Log Folder") {
                            showingLogFolderPicker = true
                        }
                    }
                } header: {
                    Text("Debug Logging")
                } footer: {
                    Text("Write debug logs to a file so you can review them when the USB port is used by the card reader. Use an iCloud Drive folder to read logs on your Mac.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingLogFolderPicker) {
                LogFolderPickerView { url in
                    DebugLogService.shared.setLogFolder(url: url)
                    isLoggingEnabled = true
                    showingLogFolderPicker = false
                } onCancelled: {
                    if !DebugLogService.shared.isConfigured {
                        isLoggingEnabled = false
                    }
                    showingLogFolderPicker = false
                }
            }
        }
    }
}

/// Folder picker specifically for selecting the debug log destination.
/// Separate from FolderPickerView because it doesn't use the source
/// bookmark logic — it just picks a folder and returns the URL.
private struct LogFolderPickerView: UIViewControllerRepresentable {
    let onPicked: (URL) -> Void
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
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (URL) -> Void
        let onCancelled: () -> Void

        init(onPicked: @escaping (URL) -> Void,
             onCancelled: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancelled = onCancelled
        }

        func documentPicker(_ c: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPicked(url)
        }

        func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) {
            onCancelled()
        }
    }
}
