import SwiftUI

struct ClaimHomeView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var step: Int = 1
    @State private var claimCode: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var email: String = ""
    @State private var confirmEmail: String = ""
    @State private var showPassword: Bool = false

    @State private var isLoading = false
    @State private var infoMessage: String?
    @State private var errorMessage: String?

    @State private var challengeId: String?
    @State private var challengeStatus: ChallengeStatus = .PENDING
    @State private var verifying = false
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                card
            }
            .padding()
        }
        .navigationTitle("Claim a home")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { pollTask?.cancel() }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Dinodia")
                .font(.system(size: 32, weight: .bold))
            Text("Use your claim code to become the new homeowner.")
                .foregroundColor(.secondary)
                .font(.subheadline)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let errorMessage {
                NoticeView(kind: .error, message: errorMessage)
            }
            if let infoMessage {
                NoticeView(kind: .info, message: infoMessage)
            }

            if challengeId != nil {
                verificationView
            } else if step == 1 {
                claimForm
            } else {
                adminForm
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
        )
    }

    private var claimForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter the claim code from the previous owner.")
                .font(.headline)
            TextField("Claim code", text: $claimCode)
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
            Button(action: validateClaim) {
                Text(isLoading ? "Checking claim code..." : "Continue")
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

    private var adminForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create your homeowner account")
                .font(.headline)
            TextField("Set Username", text: $username)
                .textInputAutocapitalization(.none)
                .disableAutocorrection(true)
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
            HStack {
                Group {
                    if showPassword {
                        TextField("Set Password", text: $password)
                    } else {
                        SecureField("Set Password", text: $password)
                    }
                }
                .textInputAutocapitalization(.none)
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
            HStack {
                Group {
                    if showPassword {
                        TextField("Confirm Password", text: $confirmPassword)
                    } else {
                        SecureField("Confirm Password", text: $confirmPassword)
                    }
                }
                .textInputAutocapitalization(.none)
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
            TextField("Homeowner email", text: $email)
                .textInputAutocapitalization(.none)
                .keyboardType(.emailAddress)
                .disableAutocorrection(true)
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
            TextField("Confirm email", text: $confirmEmail)
                .textInputAutocapitalization(.none)
                .keyboardType(.emailAddress)
                .disableAutocorrection(true)
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))

            Button(action: startClaim) {
                Text(isLoading ? "Starting claim..." : "Verify and claim home")
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProgressView()
                Text(statusLabel)
                    .foregroundColor(.secondary)
            }
            Button {
                if let id = challengeId {
                    Task { await handleResend(id: id) }
                }
            } label: {
                Text("Resend email")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .disabled(verifying || isLoading)

            Button {
                resetVerification()
                step = 1
            } label: {
                Text("Back to claim code")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .disabled(verifying || isLoading)
        }
    }

    private func validateClaim() {
        guard !isLoading else { return }
        errorMessage = nil
        infoMessage = nil
        let code = normalizedClaimCode(claimCode)
        claimCode = code
        if code.isEmpty {
            errorMessage = "Enter the claim code from the previous owner."
            return
        }
        isLoading = true
        Task {
            do {
                try await OnboardingService.claimValidate(code: code)
                await MainActor.run {
                    step = 2
                    infoMessage = "Claim code accepted. Create your homeowner account."
                }
            } catch {
                if error.isCancellation { return }
                await MainActor.run { errorMessage = friendlyError(error) }
            }
            await MainActor.run { isLoading = false }
        }
    }

    private func startClaim() {
        guard !isLoading else { return }
        errorMessage = nil
        infoMessage = nil
        let code = normalizedClaimCode(claimCode)
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.isEmpty {
            errorMessage = "Enter the claim code from the previous owner."
            return
        }
        if trimmedUser.isEmpty || password.isEmpty || confirmPassword.isEmpty {
            errorMessage = "Create and confirm a password to continue."
            return
        }
        if password != confirmPassword {
            errorMessage = "Passwords must match."
            return
        }
        if trimmedEmail.isEmpty || confirmEmail.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedEmail {
            errorMessage = "Emails must match."
            return
        }
        isLoading = true
        Task {
            do {
                let id = try await OnboardingService.claimStart(
                    code: code,
                    username: trimmedUser,
                    password: password,
                    email: trimmedEmail
                )
                await MainActor.run {
                    challengeId = id
                    challengeStatus = .PENDING
                    infoMessage = "Check your email to verify and finish setup."
                    startPolling(challengeId: id)
                }
            } catch {
                if error.isCancellation { return }
                await MainActor.run { errorMessage = friendlyError(error) }
            }
            await MainActor.run { isLoading = false }
        }
    }

    private func startPolling(challengeId: String) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                do {
                    let status = try await AuthService.fetchChallengeStatus(id: challengeId)
                    await MainActor.run { challengeStatus = status }
                    if status == .APPROVED {
                        await MainActor.run { verifying = true }
                        do {
                            _ = try await AuthService.completeChallenge(id: challengeId)
                            try await session.finalizeLogin()
                            await MainActor.run {
                                resetVerification()
                                dismiss()
                            }
                            return
                        } catch {
                            await MainActor.run {
                                errorMessage = friendlyError(error)
                                verifying = false
                                resetVerification()
                            }
                            return
                        }
                    }
                    if status == .EXPIRED || status == .NOT_FOUND || status == .CONSUMED {
                        let message: String
                        switch status {
                        case .EXPIRED: message = "Verification expired. Please start again."
                        case .NOT_FOUND: message = "Verification not found. Please start again."
                        case .CONSUMED: message = "Verification already used. Please start again."
                        default: message = "Verification expired. Please start again."
                        }
                        await MainActor.run {
                            errorMessage = message
                            resetVerification()
                        }
                        return
                    }
                } catch {
                    if error.isCancellation { return }
                    await MainActor.run {
                        errorMessage = friendlyError(error)
                        resetVerification()
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
            await MainActor.run { infoMessage = "We sent a fresh verification email." }
        } catch {
            await MainActor.run { errorMessage = friendlyError(error) }
        }
    }

    private func resetVerification() {
        challengeId = nil
        challengeStatus = .PENDING
        verifying = false
        pollTask?.cancel()
        pollTask = nil
    }

    private var statusLabel: String {
        switch challengeStatus {
        case .APPROVED:
            return "Approved. Completing sign-in..."
        case .CONSUMED:
            return "Verification already used."
        case .EXPIRED:
            return "Verification expired."
        case .NOT_FOUND:
            return "Verification not found."
        case .PENDING:
            fallthrough
        default:
            return verifying ? "Finishing sign-in..." : "Waiting for verification..."
        }
    }

    private func friendlyError(_ error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("{\"error\"") || raw.hasPrefix("{") {
            return "That claim code isn’t valid. Please check it and try again."
        }
        if raw.contains("claim") && (raw.contains("invalid") || raw.contains("not found")) {
            return "That claim code isn’t valid. Please check it and try again."
        }
        if raw.contains("expired") {
            return "That claim code has expired. Please request a new one."
        }
        if raw.contains("http") || raw.contains("network") {
            return "We could not reach Dinodia right now. Please try again."
        }
        return error.localizedDescription.isEmpty
            ? "We could not complete the claim. Please try again."
            : error.localizedDescription
    }
}

private func normalizedClaimCode(_ input: String) -> String {
    let raw = input.uppercased().replacingOccurrences(of: "[^A-Z0-9]", with: "", options: .regularExpression)
    let parts = [0, 3, 7, 11].map { idx -> String in
        let start = raw.index(raw.startIndex, offsetBy: min(idx, raw.count))
        let end = raw.index(raw.startIndex, offsetBy: min(idx + (idx == 0 ? 3 : 4), raw.count))
        return String(raw[start..<end])
    }.filter { !$0.isEmpty }
    return parts.joined(separator: "-")
}
