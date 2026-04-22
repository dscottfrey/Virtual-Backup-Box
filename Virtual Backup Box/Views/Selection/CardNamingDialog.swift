// CardNamingDialog.swift
// Virtual Backup Box
//
// Modal sheet presented when the user selects a camera card that the app
// has not seen before (unknown UUID). The dialog collects a friendly name
// and confirms the camera model before creating a KnownCard record.
//
// This dialog cannot be dismissed by swiping — the user must tap Confirm.
// A card cannot be backed up without a name because the name drives the
// destination folder structure (YYYYMMDD_FriendlyName).

import SwiftUI

struct CardNamingDialog: View {

    var viewModel: SelectionViewModel

    /// The friendly name the user is editing. Pre-filled with the suggested
    /// name from the ViewModel (e.g. "Canon EOS R6 Mark III Card-1").
    @State private var friendlyName = ""

    /// The camera model string. Pre-filled from EXIF extraction; editable
    /// in case the extraction was wrong or the user wants to adjust it.
    @State private var cameraModel = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Card name", text: $friendlyName)
                } header: {
                    Text("Card Name")
                } footer: {
                    Text("This name will be used for the backup folder.")
                }

                Section {
                    TextField("Camera model", text: $cameraModel)
                } header: {
                    Text("Camera Model")
                } footer: {
                    Text("Read from the card. Edit if incorrect.")
                }
            }
            .navigationTitle("Name This Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        viewModel.confirmCardName(
                            friendlyName: friendlyName.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ),
                            cameraModel: cameraModel.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                        )
                    }
                    .disabled(friendlyName.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty)
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            friendlyName = viewModel.suggestedCardName
            cameraModel = viewModel.pendingCameraModel
        }
    }
}
