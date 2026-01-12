import SwiftUI
import WebKit

private enum RemoteWizardStep: Int, CaseIterable {
    case intro = 0
    case homeCheck
    case emailVerify
    case connect
    case result
}

private enum RemoteResultState {
    case idle
    case saving
    case testing
    case success
    case failure(String)
}

struct RemoteAccessWizardView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var step: RemoteWizardStep = .intro
    @State private var homeReachable = false
    @State private var isCheckingHome = false
    @State private var alertMessage: String?

    // Verification / lease
    @State private var challengeId: String?
    @State private var leaseToken: String?
    @State private var leaseExpiresAt: String?
    @State private var haUsername: String = ""
    @State private var haPassword: String = ""
    @State private var baseUrl: String = ""
    @State private var stepUpApproved = false
    @State private var stepUpApprovedAt: Date?

    // Connect step
    @State private var showWeb = false
    @State private var webKey = 0
    @State private var allowedHosts: Set<String> = ["account.nabucasa.com", "auth.nabucasa.com", "cloud.nabucasa.com"]
    @State private var resultState: RemoteResultState = .idle
    @State private var verifyMessage: String?
    @State private var isFetchingCredsForWeb = false
    @State private var webHaUsername: String = ""
    @State private var webHaPassword: String = ""

    private var progressText: String {
        "Step \(step.rawValue + 1) of \(RemoteWizardStep.allCases.count)"
    }

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            bottomBar
        }
        .navigationTitle("Remote Access Setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DinodiaNavBarLogo()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Close") {
                    clearSensitive()
                    dismiss()
                }
            }
        }
        .alert("Dinodia", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .sheet(isPresented: $showWeb) {
            RemoteAccessWebView(
                key: webKey,
                baseUrl: baseUrl,
                accountUrl: accountUrl,
                allowedHosts: allowedHosts,
                haUsername: webHaUsername,
                haPassword: webHaPassword,
                onCapture: { url in
                    Task { await saveCaptured(url: url) }
                    showWeb = false
                },
                onClose: {
                    showWeb = false
                }
            )
        }
        .onAppear {
            Task { await loadBaseUrl() }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(titleForStep)
                    .font(.title3)
                    .bold()
                Text(subtitleForStep)
                    .font(.body)
                    .foregroundColor(.secondary)

                switch step {
                case .intro:
                    Link("Open Nabu Casa account page", destination: URL(string: "https://account.nabucasa.com/")!)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                case .homeCheck:
                    homeCheckView
                case .emailVerify:
                    emailVerifyView
                case .connect:
                    connectView
                case .result:
                    resultView
                }
            }
            .padding()
        }
    }

    private var homeCheckView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: homeReachable ? "wifi" : "wifi.slash")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(homeReachable ? .green : .orange)
                VStack(alignment: .leading) {
                    Text(homeReachable ? "Dinodia Hub reachable" : "Hub not reachable")
                        .font(.headline)
                    Text(homeReachable ? "Connected to home Wi‑Fi" : "Switch to home Wi‑Fi to continue.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if isCheckingHome {
                    ProgressView()
                }
            }
            Button {
                Task { await refreshHomeReachability() }
            } label: {
                Text("Recheck")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var emailVerifyView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("We’ll send a verification email. After you approve it, setup is unlocked for ~10 minutes.")
                .font(.footnote)
                .foregroundColor(.secondary)
            if challengeId == nil {
                Button {
                    Task { await sendStepUpAndMint() }
                } label: {
                    Text("Send verification email")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                ProgressView("Waiting for email verification…")
            }
            if let expiresText = leaseCountdownText {
                Text(expiresText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if stepUpApproved {
                Label("Email verified", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
            }
        }
    }

    private var connectView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1) Enter Nabu Casa login details\n2) Scroll down and unhide the remote access URL\n3) We’ll save it automatically")
                .font(.subheadline)
            Button {
                Task { await onConnectTapped() }
            } label: {
                Text("Login to Nabu Casa on Dinodia Hub")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if case .saving = resultState {
                HStack {
                    ProgressView()
                    Text("Saving remote access…")
                }
            }
        }
    }

    private var resultView: some View {
        VStack(alignment: .center, spacing: 16) {
            switch resultState {
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                Text("Remote access enabled")
                    .font(.headline)
                Text("Cloud mode should work now.")
                    .foregroundColor(.secondary)
            case .failure(let msg):
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.red)
                Text("Could not enable remote access")
                    .font(.headline)
                Text(msg)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            case .saving, .testing:
                ProgressView("Finalizing…")
            case .idle:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var bottomBar: some View {
        HStack {
            Button("Back") { goBack() }
                .disabled(step == .intro || step == .result)
            Spacer()
            Text(progressText)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button(nextLabel) { goNext() }
                .buttonStyle(.borderedProminent)
                .disabled(!canGoNext)
        }
        .padding()
        .background(Color(UIColor.systemBackground))
    }

    private var nextLabel: String {
        step == .result ? "Close" : "Next"
    }

    private var canGoNext: Bool {
        switch step {
        case .intro:
            return true
        case .homeCheck:
            return homeReachable
        case .emailVerify:
            return stepUpApproved && !baseUrl.isEmpty
        case .connect:
            if case .success = resultState { return true }
            return false
        case .result:
            return true
        }
    }

    private var titleForStep: String {
        switch step {
        case .intro: return "Have your Nabu Casa login details ready"
        case .homeCheck: return "Make sure you are at home"
        case .emailVerify: return "Verify your email to continue setup"
        case .connect: return "Login to Nabu Casa on Dinodia Hub"
        case .result: return "Remote access status"
        }
    }

    private var subtitleForStep: String {
        switch step {
        case .intro: return "You’ll need your Nabu Casa username and password to enable remote access."
        case .homeCheck: return "We need to reach your Dinodia Hub on home Wi‑Fi."
        case .emailVerify: return "This unlocks setup for about 10 minutes so we can securely fetch credentials."
        case .connect: return "Enter Nabu Casa, unhide the remote access URL, and we’ll save it automatically."
        case .result: return "See whether remote access was enabled successfully."
        }
    }

    private var leaseCountdownText: String? {
        if let expires = leaseExpiresAt, let ms = msUntil(expires), ms > 0 {
            let mins = Int(Double(ms) / 1000.0 / 60.0)
            return "Setup unlocked for ~\(mins) min"
        }
        if let approvedAt = stepUpApprovedAt {
            let msLeft = Int((approvedAt.addingTimeInterval(10 * 60).timeIntervalSinceNow) * 1000)
            if msLeft > 0 {
                let mins = Int(Double(msLeft) / 1000.0 / 60.0)
                return "Setup unlocked for ~\(mins) min"
            }
        }
        return nil
    }

    private var accountUrl: String {
        guard !baseUrl.isEmpty, var components = URLComponents(string: baseUrl) else { return baseUrl }
        components.port = 8123
        components.path = "/config/cloud/account"
        return (components.string ?? baseUrl).replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
    }

    // MARK: - Actions

    private func goBack() {
        switch step {
        case .intro:
            break
        case .homeCheck:
            step = .intro
        case .emailVerify:
            step = .homeCheck
        case .connect:
            step = .emailVerify
        case .result:
            clearSensitive()
            dismiss()
        }
    }

    private func goNext() {
        switch step {
        case .intro:
            step = .homeCheck
            Task { await refreshHomeReachability() }
        case .homeCheck:
            step = .emailVerify
        case .emailVerify:
            step = .connect
        case .connect:
            step = .result
        case .result:
            dismiss()
        }
    }

    private func refreshHomeReachability() async {
        isCheckingHome = true
        let reachable = await RemoteAccessService.checkHomeReachable()
        await MainActor.run {
            homeReachable = reachable
            isCheckingHome = false
        }
    }

    private func loadBaseUrl() async {
        if let cached = HomeModeSecretsStore.cached() {
            baseUrl = cached.baseUrl
            updateAllowedHosts()
            return
        }
        if let secrets = try? await HomeModeSecretsStore.fetch() {
            baseUrl = secrets.baseUrl
            updateAllowedHosts()
        }
    }

    private func sendStepUpAndMint() async {
        do {
            let cid = try await RemoteAccessService.startStepUp()
            await MainActor.run {
                challengeId = cid
                verifyMessage = nil
            }
            try await waitForChallenge(challengeId: cid)
            await MainActor.run {
                stepUpApproved = true
                stepUpApprovedAt = Date()
                challengeId = nil
                leaseToken = nil
                leaseExpiresAt = nil
                haUsername = ""
                haPassword = ""
            }
        } catch {
            await MainActor.run {
                alertMessage = error.localizedDescription
                challengeId = nil
                stepUpApproved = false
            }
        }
    }

    private func waitForChallenge(challengeId: String) async throws {
        while true {
            try Task.checkCancellation()
            let st = try await AuthService.fetchChallengeStatus(id: challengeId)
            switch st {
            case .APPROVED, .CONSUMED:
                // Ensure completion succeeds; retry a few times before failing.
                var attempts = 0
                while attempts < 3 {
                    do {
                        try await AuthService.completeStepUpChallenge(id: challengeId)
                        return
                    } catch {
                        attempts += 1
                        if attempts >= 3 { throw error }
                        try await Task.sleep(nanoseconds: 1_000_000_000) // 1s backoff
                    }
                }
            case .EXPIRED, .NOT_FOUND:
                throw AuthServiceError.custom("Verification expired. Please resend.")
            default:
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func mintLeaseAndFetch() async throws {
        let lease = try await RemoteAccessService.mintLease()
        guard let token = lease.leaseToken, !token.isEmpty else {
            throw AuthServiceError.custom(lease.error ?? "Email verification is required.")
        }
        await MainActor.run {
            leaseToken = token
            leaseExpiresAt = lease.expiresAt
        }
        let secrets = try await RemoteAccessService.fetchSecrets(leaseToken: token)
        let user = (secrets.haUsername ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pass = (secrets.haPassword ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !pass.isEmpty else {
            throw AuthServiceError.custom("Unable to load Dinodia Hub credentials.")
        }
        await MainActor.run {
            haUsername = user
            haPassword = pass
        }
    }

    private func saveCaptured(url: String) async {
        let normalized = normalizedCloudUrl(from: url)
        guard !normalized.isEmpty else {
            await MainActor.run {
                resultState = .failure("Invalid remote URL.")
                step = .result
            }
            return
        }
        guard let token = leaseToken, !token.isEmpty else {
            await MainActor.run {
                resultState = .failure("Lease expired. Please resend verification.")
                step = .emailVerify
            }
            return
        }
        await MainActor.run {
            resultState = .saving
            step = .connect
        }
        do {
            try await RemoteAccessService.saveCloudUrl(leaseToken: token, cloudUrl: normalized)
            await testCloudUrl(normalized)
        } catch {
            await MainActor.run {
                resultState = .failure(error.localizedDescription)
                step = .result
            }
        }
    }

    private func testCloudUrl(_ url: String) async {
        await MainActor.run {
            resultState = .testing
        }
        do {
            var req = URLRequest(url: URL(string: url)!)
            req.httpMethod = "GET"
            req.timeoutInterval = 5
            _ = try await URLSession.shared.data(for: req)
            await MainActor.run {
                resultState = .success
                verifyMessage = "Remote access enabled. Cloud mode should work now."
                step = .result
            }
        } catch {
            await MainActor.run {
                resultState = .success // Save succeeded even if test failed
                verifyMessage = "Saved, but we could not verify the URL right now."
                step = .result
            }
        }
    }

    private func onConnectTapped() async {
        guard stepUpApproved else {
            await MainActor.run { alertMessage = "Please verify your email to unlock setup." }
            return
        }
        guard !baseUrl.isEmpty else {
            await MainActor.run { alertMessage = "Dinodia Hub address is missing. Try again from Home Mode." }
            return
        }
        if isFetchingCredsForWeb { return }
        await MainActor.run { isFetchingCredsForWeb = true }
        do {
            try await ensureLeaseAndCredsForWeb()
            await MainActor.run {
                allowedHosts = buildAllowedHosts()
                webKey += 1
                webHaUsername = haUsername
                webHaPassword = haPassword
                showWeb = true
                // Clear in-app copies after handing to WebView.
                haUsername = ""
                haPassword = ""
            }
        } catch {
            await MainActor.run { alertMessage = error.localizedDescription }
        }
        await MainActor.run {
            isFetchingCredsForWeb = false
        }
    }

    private func ensureLeaseAndCredsForWeb() async throws {
        // Retry mint + fetch a few times to allow for slight backend lag after step-up.
        var attempt = 0
        while attempt < 3 {
            if let expires = leaseExpiresAt, let ms = msUntil(expires), ms > 0, !haUsername.isEmpty, !haPassword.isEmpty {
                return
            }
            do {
                try await mintLeaseAndFetch()
                return
            } catch {
                attempt += 1
                if attempt >= 3 { throw error }
                try await Task.sleep(nanoseconds: UInt64(500_000_000 * attempt)) // 0.5s, 1s backoff
            }
        }
    }

    // MARK: - Helpers

    private func msUntil(_ iso: String?) -> Int? {
        guard let iso else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: iso)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: iso)
        }
        guard let parsed = date else { return nil }
        return Int(parsed.timeIntervalSinceNow * 1000)
    }

    private func updateAllowedHosts() {
        var hosts: Set<String> = ["account.nabucasa.com", "auth.nabucasa.com", "cloud.nabucasa.com"]
        if let host = URL(string: hubUiBaseUrl)?.host {
            hosts.insert(host)
        }
        allowedHosts = hosts
    }

    private func clearSensitive() {
        leaseToken = nil
        leaseExpiresAt = nil
        haUsername = ""
        haPassword = ""
        webHaUsername = ""
        webHaPassword = ""
        challengeId = nil
        stepUpApproved = false
        stepUpApprovedAt = nil
        resultState = .idle
        verifyMessage = nil
        isFetchingCredsForWeb = false
        showWeb = false
        step = .intro
    }

    private var hubUiBaseUrl: String {
        guard var components = URLComponents(string: baseUrl) else { return baseUrl }
        components.port = 8123
        return components.string ?? baseUrl
    }

    private func normalizedCloudUrl(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme == "https" else { return "" }
        if let host = url.host, !host.lowercased().hasSuffix(".ui.nabu.casa") {
            return ""
        }
        var cleaned = url.absoluteString
        while cleaned.hasSuffix("/") { cleaned.removeLast() }
        return cleaned
    }

    private func buildAllowedHosts() -> Set<String> {
        var hosts = allowedHosts
        if let host = URL(string: hubUiBaseUrl)?.host {
            hosts.insert(host)
        }
        return hosts
    }
}

// MARK: - WebView (copied from existing setup view)

private struct RemoteAccessWebView: UIViewRepresentable {
    let key: Int
    let baseUrl: String
    let accountUrl: String
    let allowedHosts: Set<String>
    let haUsername: String
    let haPassword: String
    let onCapture: (String) -> Void
    let onClose: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.websiteDataStore = .nonPersistent()
        config.userContentController = WKUserContentController()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.userContentController.add(context.coordinator, name: "capture")

        let autoCaptureScript = """
          (function() {
            let posted = false;
            function isAllowedPath(path) {
              return path.startsWith("/config/cloud/account") ||
                     path.startsWith("/auth/login") ||
                     path.startsWith("/auth/authorize") ||
                     path.startsWith("/auth/flow");
            }
            function withinShadow(root, predicate) {
              try {
                if (!root) return null;
                const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT, null);
                let node = walker.currentNode;
                while (node) {
                  if (predicate(node)) return node;
                  if (node.shadowRoot) {
                    const found = withinShadow(node.shadowRoot, predicate);
                    if (found) return found;
                  }
                  node = walker.nextNode();
                }
              } catch (e) {}
              return null;
            }
            function findCloudInput() {
              const matcher = (el) => {
                const tag = (el.tagName || "").toLowerCase();
                if (tag !== "input" && tag !== "textarea") return false;
                const val = (el.value || "").toString();
                const type = (el.getAttribute && el.getAttribute("type"))?.toString().toLowerCase() || "";
                const hasMask = /[•\\*]/.test(val);
                return typeof val === "string" && val.includes(".ui.nabu.casa") && !hasMask && type !== "password";
              };
              return withinShadow(document, matcher);
            }
            function redact(el) {
              try {
                el.value = "Saved";
                el.type = "password";
                el.setAttribute("readonly", "true");
                el.style.opacity = "0.6";
              } catch (e) {}
            }
            function tick(attempt = 0) {
              if (posted) return;
              try {
                const path = (location.pathname || "");
                if (!isAllowedPath(path)) {
                  if (attempt < 200) setTimeout(() => tick(attempt + 1), 800);
                  return;
                }
                const input = findCloudInput();
                if (input) {
                  const raw = (input.value || "").toString().trim();
                  if (raw && raw.includes(".ui.nabu.casa") && !/[•\\*]/.test(raw)) {
                    posted = true;
                    redact(input);
                    window.webkit?.messageHandlers?.capture?.postMessage(raw);
                    return;
                  }
                }
              } catch (e) {}
              if (attempt < 200) setTimeout(() => tick(attempt + 1), 800);
            }
            setTimeout(() => tick(0), 200);
          })();
        """
        let userScript = WKUserScript(source: autoCaptureScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.uiDelegate = context.coordinator
        webView.customUserAgent = "Dinodia-iOS"
        context.coordinator.webView = webView
        loadInitial(webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastKey != key {
            context.coordinator.lastKey = key
            loadInitial(uiView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onCapture: onCapture,
            onClose: onClose,
            haUsername: haUsername,
            haPassword: haPassword,
            allowedHosts: allowedHosts,
            accountUrl: accountUrl
        )
    }

    private func loadInitial(_ webView: WKWebView) {
        guard let url = URL(string: accountUrl) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        webView.load(request)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var webView: WKWebView?
        var lastKey: Int = 0
        let onCapture: (String) -> Void
        let onClose: () -> Void
        let haUsername: String
        let haPassword: String
        let allowedHosts: Set<String>
        let accountUrl: String
        private var injected = false
        private var hasReachedAccount = false
        private var lastAllowedUrl: URL?

        init(
            onCapture: @escaping (String) -> Void,
            onClose: @escaping () -> Void,
            haUsername: String,
            haPassword: String,
            allowedHosts: Set<String>,
            accountUrl: String
        ) {
            self.onCapture = onCapture
            self.onClose = onClose
            self.haUsername = haUsername
            self.haPassword = haPassword
            self.allowedHosts = allowedHosts
            self.accountUrl = accountUrl
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if navigationAction.targetFrame?.isMainFrame == false {
                decisionHandler(.cancel)
                return
            }
            if let scheme = url.scheme?.lowercased(), scheme != "https" && scheme != "http" {
                decisionHandler(.cancel)
                return
            }
            let path = url.path
            let isAccountPath = path.hasPrefix("/config/cloud/account")
            let isAuthPath = path.hasPrefix("/auth/login") || path.hasPrefix("/auth/authorize") || path.hasPrefix("/auth/flow")
            let allowedPath = isAccountPath || (!hasReachedAccount && isAuthPath)
            if let host = url.host?.lowercased(), allowedHosts.contains(host), allowedPath {
                lastAllowedUrl = url
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            if let account = URL(string: accountUrl) {
                webView.load(URLRequest(url: account))
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let current = webView.url?.path, current.hasPrefix("/config/cloud/account") {
                hasReachedAccount = true
            }
            injectScripts(webView)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let url = navigationResponse.response.url {
                if let scheme = url.scheme?.lowercased(), scheme != "https" && scheme != "http" {
                    decisionHandler(.cancel)
                    return
                }
                let path = url.path
                let isAccountPath = path.hasPrefix("/config/cloud/account")
                let isAuthPath = path.hasPrefix("/auth/login") || path.hasPrefix("/auth/authorize") || path.hasPrefix("/auth/flow")
                let allowedPath = isAccountPath || (!hasReachedAccount && isAuthPath)
                if let host = url.host?.lowercased(), allowedHosts.contains(host), allowedPath {
                    lastAllowedUrl = url
                    decisionHandler(.allow)
                    return
                }
            }
            decisionHandler(.cancel)
            if let account = URL(string: accountUrl) {
                webView.load(URLRequest(url: account))
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Block popups/new windows outright.
            return nil
        }

        private func injectScripts(_ webView: WKWebView) {
            guard !injected else { return }
            injected = true
            let user = haUsername.replacingOccurrences(of: "\"", with: "\\\"")
            let pass = haPassword.replacingOccurrences(of: "\"", with: "\\\"")
            let account = accountUrl.replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
              (function() {
                const USERNAME="\(user)";
                const PASSWORD="\(pass)";
                const ACCOUNT="\(account)";
                let accountReached = false;
                function isAllowedPath(path) {
                  return path.startsWith("/config/cloud/account") ||
                         path.startsWith("/auth/login") ||
                         path.startsWith("/auth/authorize") ||
                         path.startsWith("/auth/flow");
                }
                function lockBackNavigation() {
                  try {
                    const goAccount = () => { if (location.pathname !== "/config/cloud/account") { location.replace(ACCOUNT); } };
                    window.addEventListener("popstate", goAccount, true);
                    history.back = function(){ goAccount(); return; };
                    history.go = function(){ goAccount(); return; };
                  } catch(e){}
                }
                function enforceLocation() {
                  const path = (location.pathname||"");
                  if (!isAllowedPath(path)) {
                    location.href = ACCOUNT;
                    return false;
                  }
                  return true;
                }
                function patchHistory() {
                  const origPush = history.pushState;
                  const origReplace = history.replaceState;
                  history.pushState = function(a,b,url){ if (typeof url === "string" && !isAllowedPath(new URL(url, location.origin).pathname)) { return; } return origPush.apply(this, arguments); };
                  history.replaceState = function(a,b,url){ if (typeof url === "string" && !isAllowedPath(new URL(url, location.origin).pathname)) { return; } return origReplace.apply(this, arguments); };
                  window.addEventListener("popstate", enforceLocation, true);
                }
                function blockBadClicks() {
                  document.addEventListener("click", function(e){
                    let el = e.target;
                    while (el && el.tagName && el.tagName.toLowerCase() !== "a") { el = el.parentElement; }
                    if (!el || !el.href) return;
                    try {
                      const url = new URL(el.href, location.href);
                      if (!isAllowedPath(url.pathname)) { e.preventDefault(); e.stopPropagation(); enforceLocation(); }
                    } catch (_) {}
                  }, true);
                }
                function q(sel){ try { return document.querySelector(sel); } catch(e){ return null; } }
                function withinShadow(root, sel) {
                  if (!root) return null;
                  const direct = root.querySelector?.(sel);
                  if (direct) return direct;
                  const shadowHosts = Array.from(root.querySelectorAll?.('*')||[]).filter(n => n.shadowRoot);
                  for (const host of shadowHosts) {
                    const found = withinShadow(host.shadowRoot, sel);
                    if (found) return found;
                  }
                  return null;
                }
                function isAuthPath() {
                  const p = (location.pathname||"");
                  return p.startsWith("/auth/authorize") || p.startsWith("/auth/login");
                }
                function clickSubmit() {
                  const btns = ['button[type="submit"]','ha-progress-button','ha-button','button'];
                  for (const sel of btns) {
                    const el = withinShadow(document, sel) || q(sel);
                    if (el && typeof el.click==="function") { el.click(); return true; }
                  }
                  return false;
                }
                function fillLogin() {
                  if (!isAuthPath()) return false;
                  const u = withinShadow(document,'input[type="email"]') || withinShadow(document,'input[name="username"]') || q('#username');
                  const p = withinShadow(document,'input[type="password"]') || q('#password');
                  if (!u || !p) return false;
                  u.value = USERNAME; p.value = PASSWORD;
                  ['input','change'].forEach(ev => { u.dispatchEvent(new Event(ev,{bubbles:true})); p.dispatchEvent(new Event(ev,{bubbles:true})); });
                  clickSubmit();
                  return true;
                }
                function findCloudUrl() {
                  const inputs = Array.from(document.querySelectorAll('input')).concat(Array.from(document.querySelectorAll('textarea')));
                  for (const el of inputs) {
                    const val = (el.value||"").toString();
                    const type = (el.getAttribute && el.getAttribute("type")) || "";
                    if (val.includes(".ui.nabu.casa") && !/[•\\*]/.test(val) && type !== "password") {
                      el.value = "Saved";
                      el.setAttribute("readonly","true");
                      window.webkit?.messageHandlers?.capture?.postMessage(val);
                      accountReached = true;
                      lockBackNavigation();
                      return true;
                    }
                  }
                  return false;
                }
                function tick(attempt=0) {
                  try {
                    enforceLocation();
                    if (findCloudUrl()) return;
                    if (!accountReached && fillLogin()) return;
                  } catch (e) {}
                  if (attempt < 60) setTimeout(() => tick(attempt+1), 800);
                }
                function watchUrlField() {
                  const obs = new MutationObserver(() => { findCloudUrl(); enforceLocation(); });
                  obs.observe(document.documentElement, { childList:true, subtree:true, attributes:true, attributeFilter:['value','type','style','class'] });
                  setTimeout(() => obs.disconnect(), 30000);
                }
                patchHistory();
                blockBadClicks();
                if (location.pathname.startsWith("/config/cloud/account")) { accountReached = true; lockBackNavigation(); }
                setTimeout(() => tick(0), 800);
                setTimeout(() => watchUrlField(), 500);
              })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}

extension RemoteAccessWebView.Coordinator: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "capture", let url = message.body as? String, !url.isEmpty {
            onCapture(url)
        }
    }
}
