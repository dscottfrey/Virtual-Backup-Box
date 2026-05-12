// SelectionView+SessionRoute.swift
// Virtual Backup Box
//
// Extension on SelectionView that handles the hand-off from a completed
// scan into a live backup session: building the SessionViewModel, pushing
// the SessionProgressView onto the navigation stack, and swapping in the
// SessionResultsView once the session finishes. Split from the main view
// file to respect the ~200-line-per-file rule (§6.3).

import SwiftUI

extension SelectionView {

    // MARK: - Start Copying

    /// Hands a completed scan result off to a new SessionViewModel and
    /// pushes the session progress page. Called by InlineScanCard's
    /// "Start Copying" button.
    func startCopying(scanVM: ScanViewModel) {
        guard let result = scanVM.scanResult else { return }
        let sessionVM = SessionViewModel()
        sessionVM.targetName = viewModel.activeTarget?.friendlyName ?? ""
        sessionVM.startSession(
            scanResult: result,
            selectedCard: scanVM.selectedCard,
            modelContext: modelContext
        )
        sessionViewModel = sessionVM
        navigateToSession = true
    }

    // MARK: - Session Destination

    /// The view shown by the navigationDestination tied to
    /// navigateToSession. Switches between the live progress UI and the
    /// post-session results UI based on whether the session has finished.
    @ViewBuilder
    var sessionDestinationView: some View {
        if let sessionVM = sessionViewModel {
            if sessionVM.isSessionComplete,
               let session = sessionVM.completedSession {
                SessionResultsView(
                    viewModel: ResultsViewModel(
                        session: session,
                        failedFiles: sessionVM.failedFiles,
                        targetName: sessionVM.targetName,
                        modelContext: modelContext
                    ),
                    onDone: {
                        navigateToSession = false
                        scanViewModel = nil
                    }
                )
            } else {
                SessionProgressView(
                    viewModel: sessionVM,
                    onSessionComplete: { },
                    onCancel: {
                        navigateToSession = false
                        scanViewModel = nil
                    }
                )
            }
        }
    }
}
