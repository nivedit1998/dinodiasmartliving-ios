import SwiftUI

private struct HubDetails {
    var dinodiaSerial: String = ""
    var bootstrapSecret: String = ""
}

struct SetupHomeOnboardingView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var email: String = ""
    @State private var confirmEmail: String = ""
    @State private var showPassword: Bool = false
    @State private var hub = HubDetails()
    @State private var scanning = false
    @State private var showScanner = false
    @State private var scanError: String?
    @State private var showSetupSuccessAlert = false

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
        .navigationTitle("Set up this home")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { pollTask?.cancel() }
        .alert("Home Created Successfully", isPresented: $showSetupSuccessAlert) {
            Button("OK") {
                resetVerification()
                dismiss()
            }
        } message: {
            Text("Please login again.")
        }
        .onChange(of: session.user?.id) { _, newValue in
            guard newValue == nil else { return }
            showScanner = false
            scanning = false
            scanError = nil
            infoMessage = nil
            errorMessage = nil
            challengeId = nil
            challengeStatus = .PENDING
            verifying = false
            pollTask?.cancel()
            pollTask = nil
        }
        .sheet(isPresented: $showScanner) {
            NavigationStack {
                ZStack {
                    QRScannerView { code in
                        handleScanResult(code)
                        showScanner = false
                    }
                    VStack {
                        HStack {
                            Button("Close") { showScanner = false }
                                .padding()
                            Spacer()
                        }
                        Spacer()
                        Text("Scan the Dinodia Hub QR code to auto-fill hub details.")
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .padding(.bottom, 24)
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Dinodia")
                .font(.system(size: 32, weight: .bold))
            Text("New home setup")
                .foregroundColor(.secondary)
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

            if challengeId == nil {
                adminForm
                hubForm
                Button(action: submit) {
                    Text(isLoading ? "Connecting Dinodia Hub..." : "Connect your Dinodia Hub")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .disabled(isLoading)
                .foregroundColor(.white)
                .background(isLoading ? Color.accentColor.opacity(0.7) : Color.accentColor)
                .cornerRadius(14)
            } else {
                verificationView
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
        )
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
        }
    }

    private var hubForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dinodia Hub connection")
                .font(.headline)
            Text(hub.dinodiaSerial.isEmpty ? "Scan the Dinodia Hub QR code to capture hub details." : "Hub details captured.")
                .font(.caption)
                .foregroundColor(.secondary)
            Button {
                scanError = nil
                showScanner = true
            } label: {
                Label(hub.dinodiaSerial.isEmpty ? "Scan Dinodia Hub QR code" : "Rescan Hub QR code", systemImage: "qrcode.viewfinder")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(scanning)

            if let scanError {
                NoticeView(kind: .warning, message: scanError)
            }
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
            } label: {
                Text("Back to setup")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .disabled(verifying || isLoading)
        }
    }

    private func submit() {
        guard !isLoading else { return }
        errorMessage = nil
        infoMessage = nil
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
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
        if hub.dinodiaSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            hub.bootstrapSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Scan the Dinodia Hub QR code to continue."
            return
        }

        isLoading = true
        Task {
            do {
                let id = try await OnboardingService.registerAdmin(
                    username: trimmedUser,
                    password: password,
                    email: trimmedEmail,
                    dinodiaSerial: hub.dinodiaSerial,
                    bootstrapSecret: hub.bootstrapSecret
                )
                await MainActor.run {
                    challengeId = id
                    challengeStatus = .PENDING
                    infoMessage = "Check your email to verify and finish setup."
                    startPolling(challengeId: id)
                    // Clear sensitive hub details after submission.
                    hub = HubDetails()
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
                            await session.resetApp()
                            await MainActor.run {
                                resetVerification()
                                showSetupSuccessAlert = true
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
            return "We could not complete setup. Please try again."
        }
        if raw.contains("invalid") || raw.contains("unauthorized") {
            return "We could not verify those details. Please try again."
        }
        if raw.contains("expired") {
            return "That link expired. Please resend and try again."
        }
        if raw.contains("http") || raw.contains("network") {
            return "We could not reach Dinodia right now. Please try again."
        }
        return error.localizedDescription.isEmpty
            ? "We could not complete setup. Please try again."
            : error.localizedDescription
    }

    private func handleScanResult(_ code: String) {
        let parsed = parseHubQrPayload(code)
        guard let parsed else {
            scanError = "QR code not recognized. Please scan the Dinodia Hub QR."
            return
        }
        hub.dinodiaSerial = parsed.dinodiaSerial
        hub.bootstrapSecret = parsed.bootstrapSecret
    }
}

private func parseHubQrPayload(_ raw: String) -> HubDetails? {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return nil }

    if text.lowercased().hasPrefix("dinodia://") {
        if let parsed = URL(string: text) {
            let serial = parsed.queryItems("s") ?? parsed.queryItems("serial")
            let bootstrap = parsed.queryItems("bs") ?? parsed.queryItems("bootstrapSecret")
            let version = parsed.queryItems("v") ?? parsed.queryItems("version")
            if let version, version != "3" { return nil }
            return HubDetails(
                dinodiaSerial: serial ?? "",
                bootstrapSecret: bootstrap ?? ""
            )
        }
    }

    if let data = text.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        let serial = json["serial"] as? String ?? json["s"] as? String
        let bootstrap = json["bootstrapSecret"] as? String ?? json["bs"] as? String
        return HubDetails(
            dinodiaSerial: serial ?? "",
            bootstrapSecret: bootstrap ?? ""
        )
    }

    return nil
}

private extension URL {
    func queryItems(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name.lowercased() == name.lowercased() })?
            .value
    }
}
