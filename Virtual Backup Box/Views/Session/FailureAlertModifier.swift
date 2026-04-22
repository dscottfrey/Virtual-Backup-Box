// FailureAlertModifier.swift
// Virtual Backup Box
//
// ViewModifier that watches SessionViewModel for a pending failure alert
// and presents a blocking dialog when one is posted. The user must tap
// "Continue Backup" to dismiss — the session is paused until they do.
//
// BackupSessionService sets pendingFailureAlert when a file fails after
// all retries. It then awaits waitForFailureDismissal(), which resumes
// when dismissFailureAlert() is called here.

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
            } message: {
                if let alert = viewModel.pendingFailureAlert {
                    Text("\(alert.relativeFilePath)\n\n\(alert.reason)")
                }
            }
    }

    /// Binding that is true when a failure alert is pending.
    /// Setting it to false dismisses the alert via the ViewModel.
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
