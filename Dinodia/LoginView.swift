import SwiftUI

struct TenantSetupData: Identifiable, Hashable {
    let id = UUID()
    let username: String
    let password: String
    let challengeId: String?
}

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var email: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var needsEmail: Bool = false
    @State private var showPassword: Bool = false
    @State private var challengeId: String?
    @State private var challengeStatus: ChallengeStatus = .PENDING
    @State private var verifying: Bool = false
    @State private var pollTask: Task<Void, Never>?
    @State private var showSetupHome = false
    @State private var showClaimHome = false
    @State private var tenantSetup: TenantSetupData?
    @State private var showForgotPassword = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(.systemGray6), Color(.systemBackground)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 6) {
                            Image("DinodiaLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 96, height: 96)
                                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                            Text("Dinodia")
                                .font(.system(size: 34, weight: .bold))
                            Text("Smart Living. Quietly confident.")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            Text(challengeId == nil ? "Welcome back" : "Verify this device")
                                .font(.title2)
                                .fontWeight(.semibold)
                            if challengeId == nil {
                                Text("Sign in to open the home view.")
                                    .foregroundColor(.secondary)
                            } else {
                                Text("We sent a verification link to your email. Tap the link to finish signing in.")
                                    .foregroundColor(.secondary)
                            }

                            if challengeId == nil {
                                inputFields
                                loginButtons
                            } else {
                                verificationBlock
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color(.systemBackground))
                                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
                        )
                    }
                    .padding()
                }
            }
            .navigationDestination(isPresented: $showSetupHome) {
                SetupHomeOnboardingView()
                    .environmentObject(session)
            }
            .navigationDestination(isPresented: $showClaimHome) {
                ClaimHomeView()
                    .environmentObject(session)
            }
            .navigationDestination(item: $tenantSetup) { setup in
                TenantEmailSetupView(data: setup)
                    .environmentObject(session)
            }
            .navigationDestination(isPresented: $showForgotPassword) {
                ForgotPasswordView()
            }
        }
        .onDisappear { pollTask?.cancel() }
    }

    private var inputFields: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Username")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("DINODIA", text: $username)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Password")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Group {
                        if showPassword {
                            TextField("••••••••", text: $password)
                        } else {
                            SecureField("••••••••", text: $password)
                        }
                    }
                    .textContentType(.password)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
            }

            if needsEmail {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Email")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("you@example.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
                }
            }

            if let errorMessage {
                NoticeView(kind: .error, message: errorMessage)
            }
            if let infoMessage {
                NoticeView(kind: .info, message: infoMessage)
            }
        }
    }

    private var loginButtons: some View {
        VStack(spacing: 10) {
            Button(action: handleLogin) {
                Text(isLoading || verifying ? "Logging in..." : "Login")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .disabled(isLoading || verifying)
            .foregroundColor(.white)
            .background((isLoading || verifying) ? Color.accentColor.opacity(0.7) : Color.accentColor)
            .cornerRadius(14)

            Button {
                showSetupHome = true
            } label: {
                Text("First time here? Set up this home")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .disabled(isLoading || verifying)

            Button {
                showClaimHome = true
            } label: {
                Text("Claim a home (have a code?)")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .disabled(isLoading || verifying)

            Button {
                showForgotPassword = true
            } label: {
                Text("Forgot password?")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .disabled(isLoading || verifying)
            .buttonStyle(.plain)
        }
    }

    private var verificationBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProgressView()
                Text(statusLabel)
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
            if let errorMessage {
                NoticeView(kind: .error, message: errorMessage)
            } else if let infoMessage {
                NoticeView(kind: .info, message: infoMessage)
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
                resetChallengeState()
            } label: {
                Text("Back to login")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .disabled(verifying || isLoading)
        }
    }

    private func handleLogin() {
        guard !isLoading, !verifying else { return }
        errorMessage = nil
        infoMessage = nil
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUser.isEmpty || password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Enter both username and password to sign in."
            return
        }
        if needsEmail && email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Please enter your email address to continue."
            return
        }
        isLoading = true

        Task {
            do {
                let outcome = try await session.login(username: trimmedUser, password: password, email: needsEmail ? email : nil)
                switch outcome {
                case .success:
                    resetChallengeState()
                case .needsEmail:
                    needsEmail = false
                    tenantSetup = TenantSetupData(username: trimmedUser, password: password, challengeId: nil)
                    infoMessage = nil
                    errorMessage = nil
                case .challenge(let id):
                    needsEmail = false
                    tenantSetup = TenantSetupData(username: trimmedUser, password: password, challengeId: id)
                    infoMessage = nil
                    errorMessage = nil
                }
            } catch {
                errorMessage = friendlyError(for: error)
            }
            isLoading = false
        }
    }

    private func startPolling(challengeId: String) {
        self.challengeId = challengeId
        challengeStatus = .PENDING
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
                            await MainActor.run { resetChallengeState() }
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
                        let message: String
                        switch status {
                        case .EXPIRED:
                            message = "Verification expired. Please log in again."
                        case .NOT_FOUND:
                            message = "Verification not found. Please log in again."
                        case .CONSUMED:
                            message = "Verification already used. Please log in again."
                        default:
                            message = "Verification expired. Please log in again."
                        }
                        await MainActor.run {
                            resetChallengeState()
                            errorMessage = message
                        }
                        return
                    }
                } catch {
                    let message = friendlyError(for: error)
                    await MainActor.run {
                        resetChallengeState()
                        errorMessage = message
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
            await MainActor.run { errorMessage = friendlyError(for: error) }
        }
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

    private func resetChallengeState() {
        challengeId = nil
        needsEmail = false
        email = ""
        challengeStatus = .PENDING
        pollTask?.cancel()
        pollTask = nil
        verifying = false
        infoMessage = nil
        errorMessage = nil
    }

    private func friendlyError(for error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("{\"error\"") || raw.hasPrefix("{") {
            return "We could not log you in. Please try again."
        }
        if raw.contains("invalid credentials") || raw.contains("could not find that username") {
            return "We could not log you in. Check your username and password and try again."
        }
        if raw.contains("username and password are required") {
            return "Enter both username and password to sign in."
        }
        if raw.contains("device information is required") {
            return "This device could not be verified. Please try again."
        }
        if raw.contains("valid email") {
            return "Please enter a valid email address to continue."
        }
        if raw.contains("endpoint is not configured") || raw.contains("login is not available") {
            return "Login is not available right now. Please try again in a moment."
        }
        if raw.contains("http") || raw.contains("network") {
            return "We could not reach Dinodia right now. Please try again."
        }
        if let authError = error as? AuthServiceError, let description = authError.errorDescription {
            return description
        }
        if let fetchError = error as? PlatformFetchError, let description = fetchError.errorDescription {
            return description
        }
        return error.localizedDescription.isEmpty
            ? "We could not log you in right now. Please try again."
            : error.localizedDescription
    }
}
