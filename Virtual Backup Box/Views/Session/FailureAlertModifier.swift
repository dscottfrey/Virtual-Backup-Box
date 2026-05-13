// FailureAlertModifier.swift
// Virtual Backup Box
//
// ViewModifier that watches SessionViewModel for a pending failure alert
// and presents a blocking dialog when one is posted. The user has two
// choices — Continue Backup (move on to the next file) or Cancel Session
// (stop the whole run). The session is paused until one is chosen.
//
// BackupSessionService sets pendingFailureAlert when a file fails after
// all retries. It then awaits waitForFailureDismissal(), which resumes
// when either dismissFailureAlert() or cancelFromFailureAlert() is
// called here.
//
// Why a Cancel button (added 2026-05-13): when the user pulls the source
// card mid-session, every remaining file fails the 3-retry cycle and
// posts its own dialog. Without a Cancel option the user had to tap
// Continue, then race to hit Cancel during the next retry window —
// brutally bad UX. Cancel from the dialog is the natural exit and
// matches what the user is already trying to do.

import SwiftUI

struct FailureAlertModifier: ViewModifier {

    var viewModel: SessionViewModel

    func body(content: Content) -> some View {
        content
            .alert(
                "File Could Not Be Backed Up",
                isPresented: alertBinding
            ) {
                Button("Continue Backup") {
                    viewModel.dismissFailureAlert()
                }
                Button("Cancel Session", role: .cancel) {
                    viewModel.cancelFromFailureAlert()
                }
            } message: {
                if let alert = viewModel.pendingFailureAlert {
                    Text("\(alert.relativeFilePath)\n\n\(alert.reason)")
                }
            }
    }

    /// Binding that is true when a failure alert is pending.
    /// Setting it to false dismisses the alert via the ViewModel as
    /// a Continue (the safer default — if the user dismisses via a
    /// gesture or some non-button path, we resume rather than cancel).
    private var alertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingFailureAlert != nil },
            set: { if !$0 { viewModel.dismissFailureAlert() } }
        )
    }
}

extension View {
    /// Applies the failure alert modifier, watching the given ViewModel
    /// for pending failure alerts.
    func failureAlert(viewModel: SessionViewModel) -> some View {
        modifier(FailureAlertModifier(viewModel: viewModel))
    }
}
