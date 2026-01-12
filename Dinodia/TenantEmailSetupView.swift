import SwiftUI

struct TenantEmailSetupView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    let data: TenantSetupData

    @State private var email: String = ""
    @State private var confirmEmail: String = ""
    @State private var challengeId: String?
    @State private var challengeStatus: ChallengeStatus = .PENDING
    @State private var isLoading: Bool = false
    @State private var verifying: Bool = false
    @State private var infoMessage: String?
    @State private var errorMessage: String?
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Verify your email")
                    .font(.title2.weight(.semibold))
                Text("Add your email to secure new devices. We’ll trust this device after you finish.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .font(.subheadline)
            }

            if let errorMessage {
                NoticeView(kind: .error, message: errorMessage)
                    .multilineTextAlignment(.center)
            } else if let infoMessage {
                NoticeView(kind: .info, message: infoMessage)
                    .multilineTextAlignment(.center)
            }

            if challengeId == nil {
                formView
            } else {
                verificationView
            }

            Button("Back to login", role: .cancel) {
                pollTask?.cancel()
                dismiss()
            }
            .padding(.top, 8)
        }
        .padding()
        .navigationBarBackButtonHidden(true)
        .task {
            if let id = data.challengeId {
                challengeId = id
                startPolling(challengeId: id)
            }
        }
    }

    private var formView: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))

            TextField("Confirm email", text: $confirmEmail)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))

            Button {
                Task { await handleSubmit() }
            } label: {
                Text(isLoading ? "Sending…" : "Send verification email")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .disabled(isLoading)
            .foregroundColor(.white)
            .background(isLoading ? Color.accentColor.opacity(0.7) : Color.accentColor)
            .cornerRadius(14)
        }
    }

    private var verificationView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ProgressView()
                Text(statusLabel)
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
            if let cid = challengeId {
                Button {
                  Task { await handleResend(id: cid) }
                } label: {
                    Text("Resend email")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .disabled(verifying || isLoading)
            }
        }
    }

    private var statusLabel: String {
        if verifying { return "Finishing sign-in..." }
        switch challengeStatus {
        case .APPROVED: return "Approved. Completing sign-in..."
        case .PENDING: return "Waiting for verification..."
        case .EXPIRED: return "Verification expired."
        case .NOT_FOUND: return "Verification not found."
        case .CONSUMED: return "Verification already used."
        }
    }

    private func handleSubmit() async {
        guard !isLoading else { return }
        errorMessage = nil
        infoMessage = nil
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !confirmEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter and confirm your email to continue."
            return
        }
        guard email.trimmingCharacters(in: .whitespacesAndNewlines) ==
                confirmEmail.trimmingCharacters(in: .whitespacesAndNewlines) else {
            errorMessage = "Email addresses must match."
            return
        }

        isLoading = true
        do {
            let outcome = try await AuthService.login(
                username: data.username,
                password: data.password,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            switch outcome {
            case .challenge(let id):
                challengeId = id
                infoMessage = "We sent a verification link to your email. Tap the link to finish signing in."
                startPolling(challengeId: id)
            case .ok:
                try await session.finalizeLogin()
                dismiss()
            case .needsEmail:
                errorMessage = "We still need your email to continue."
            }
        } catch {
            errorMessage = friendlyError(for: error)
        }
        isLoading = false
    }

    private func startPolling(challengeId: String) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                do {
                    let status = try await AuthService.fetchChallengeStatus(id: challengeId)
                    await MainActor.run {
                        challengeStatus = status
                    }
                    if status == .APPROVED {
                        await MainActor.run { verifying = true }
                        do {
                            _ = try await AuthService.completeChallenge(id: challengeId)
                            try await session.finalizeLogin()
                            await MainActor.run { dismiss() }
                            return
                        } catch {
                            await MainActor.run {
                                errorMessage = friendlyError(for: error)
                                verifying = false
                            }
                            return
                        }
                    }
                    if status == .EXPIRED || status == .NOT_FOUND || status == .CONSUMED {
                        await MainActor.run {
                            errorMessage = statusLabel
                        }
                        return
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = friendlyError(for: error)
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func handleResend(id: String) async {
        do {
            try await AuthService.resendChallenge(id: id)
            await MainActor.run {
                infoMessage = "We sent a fresh verification email."
            }
        } catch {
            await MainActor.run {
                errorMessage = friendlyError(for: error)
            }
        }
    }

    private func friendlyError(for error: Error) -> String {
        if let authErr = error as? AuthServiceError {
            return authErr.localizedDescription
        }
        return error.localizedDescription
    }
}
