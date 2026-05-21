// SessionProgressView.swift
// Virtual Backup Box
//
// The main progress screen shown during a running backup session. Composes
// CurrentFileView (what is happening right now) and SessionOverviewView
// (overall session status). Applies the FailureAlertModifier for blocking
// failure dialogs.
//
// When the session completes, fires a single haptic notification. The app
// then transitions to the results screen (Module 6).
//
// This view contains no business logic — it reads from SessionViewModel
// and delegates actions to it.

import SwiftUI

struct SessionProgressView: View {

    var viewModel: SessionViewModel

    /// Called when the session ends and the user should see results.
    var onSessionComplete: () -> Void

    /// Called when the user taps Cancel and confirms.
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            CurrentFileView(viewModel: viewModel)

            SessionOverviewView(viewModel: viewModel) {
                viewModel.cancelSession()
            }
        }
        .padding()
        .navigationTitle("Backing Up")
        .navigationBarBackButtonHidden(true)
        .failureAlert(viewModel: viewModel)
        // Modern haptic API: .sensoryFeedback fires whenever the trigger
        // value changes to a truthy state, replacing the older
        // UINotificationFeedbackGenerator instance-and-call pattern.
        .sensoryFeedback(.success, trigger: viewModel.isSessionComplete)
        .onChange(of: viewModel.isSessionComplete) {
            if viewModel.isSessionComplete {
                onSessionComplete()
            }
        }
    }
}
