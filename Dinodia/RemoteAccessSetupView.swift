import SwiftUI
import WebKit

private enum RemoteAccessFlowState: Equatable {
    case idle
    case blocked(String)
    case sending
    case waiting
    case leasing
    case fetching
    case webview
    case saving
    case testing
    case done(String?)
    case error(String)
}

@MainActor
struct RemoteAccessSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: SessionStore

    @State private var challengeId: String?
    @State private var challengeError: String?
    @State private var leaseToken: String?
    @State private var leaseExpiresAt: String?
    @State private var cloudUrl: String = ""
    @State private var verifyMessage: String?
    @State private var verifyState: RemoteAccessStatus = .checking
    @State private var pollingTask: Task<Void, Never>?
    @State private var haUsername: String = ""
    @State private var haPassword: String = ""
    @State private var baseUrl: String = ""
    @State private var allowedHosts: Set<String> = []
    @State private var webKey: Int = 0
    @State private var showWeb: Bool = false
    @State private var alertMessage: String?
    @State private var homeReachable: Bool = false
    @State private var leaseExpiryTask: Task<Void, Never>?
    @State private var mintInFlight: Bool = false
    @State private var reachabilityTask: Task<Void, Never>?
    @State private var flowState: RemoteAccessFlowState = .idle
    @State private var isRunningFlow: Bool = false

    private var isHomeMode: Bool { session.haMode == .home }
    private var hasLeasedCreds: Bool { !haUsername.isEmpty && !haPassword.isEmpty }

    private var leaseActive: Bool {
        guard let token = leaseToken, !token.isEmpty else { return false }
        // If we cannot parse expires, treat as active to avoid re-mint spam; expiry task will clear when possible.
        guard let expires = leaseExpiresAt, let ms = msUntil(expires) else { return true }
        return ms > 0
    }

    private var hubUiBaseUrl: String {
        guard var components = URLComponents(string: baseUrl) else { return baseUrl }
        components.port = 8123
        return components.string ?? baseUrl
    }

    private var accountUrl: String {
        guard !hubUiBaseUrl.isEmpty else { return "" }
        var trimmed = hubUiBaseUrl
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        // Try the newer HA path; fallback is handled in the WebView script by redirect logic.
        return trimmed + "/config/cloud/account"
    }

    private var isHttpsBase: Bool {
        guard let url = URL(string: hubUiBaseUrl) else { return false }
        return url.scheme?.lowercased() == "https"
    }

    private var canLaunchWeb: Bool {
        leaseActive && homeReachable && !baseUrl.isEmpty && hasLeasedCreds
    }

    var body: some View {
        Form {
            if !isHomeMode || !homeReachable {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Unable to reach your Dinodia Hub")
                        .font(.headline)
                    Text("Connect to your Home Wi‑Fi to enable Remote Access, or switch to Cloud Mode.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button {
                        session.setHaMode(.cloud)
                    } label: {
                        HStack {
                            Image(systemName: "cloud")
                            Text("Switch to Cloud Mode")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 8)
            } else {
                Text("To enable remote access you must be on your Home Wi‑Fi")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                connectionSection
                remoteAccessSection
                tipsSection
            }
        }
        .navigationTitle("Remote Access Setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                ModeSwitchPrompt(
                    targetMode: session.haMode == .home ? .cloud : .home,
                    userId: session.user?.id,
                    onSwitched: { Task { await refreshHomeReachability() } }
                )
                .environmentObject(session)
            }
            ToolbarItem(placement: .principal) {
                DinodiaNavBarLogo()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Logout", role: .destructive) {
                    session.logout()
                }
            }
        }
        .refreshable {
            await refreshHomeReachability()
        }
        .onDisappear {
            pollingTask?.cancel()
            leaseExpiryTask?.cancel()
            reachabilityTask?.cancel()
            clearSensitive()
        }
        .task {
            if !isHomeMode { session.setHaMode(.home) }
            await loadBaseUrl()
            await refreshHomeReachability()
            startReachabilityPolling()
        }
        .sheet(isPresented: $showWeb) {
            RemoteAccessWebView(
                key: webKey,
                baseUrl: baseUrl,
                accountUrl: accountUrl,
                allowedHosts: allowedHosts,
                haUsername: haUsername,
                haPassword: haPassword,
                onCapture: { url in
                    cloudUrl = url
                    Task { await saveCaptured(url: url) }
                    showWeb = false
                },
                onClose: {
                    showWeb = false
                    haUsername = ""
                    haPassword = ""
                    flowState = .webview
                }
            )
        }
        .alert("Dinodia", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .onChange(of: session.user?.id) { _, newValue in
            if newValue == nil {
                showWeb = false
                alertMessage = nil
                clearSensitive()
            }
        }
        .onChange(of: leaseExpiresAt) { _, newValue in
            scheduleLeaseExpiryClear(expiresAt: newValue)
        }
        .onAppear {
            scheduleLeaseExpiryClear(expiresAt: leaseExpiresAt)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                showWeb = false
                clearSensitive()
            }
        }
    }

    private var connectionSection: some View {
        Section("Connection") {
            HStack {
                Text(isHomeMode ? "Home Mode" : "Cloud Mode")
                Spacer()
                Text(isHomeMode ? "Required" : "Switch to Home")
                    .font(.caption)
                    .foregroundColor(isHomeMode ? .green : .orange)
            }
            HStack {
                Image(systemName: homeReachable ? "wifi" : "wifi.exclamationmark")
                    .foregroundColor(homeReachable ? .green : .orange)
                Text(homeReachable ? "Dinodia Hub reachable" : "Hub not reachable")
                    .foregroundColor(.secondary)
            }
            if !isHomeMode {
                Button("Switch to Home Mode") {
                    session.setHaMode(.home)
                }
            } else if !homeReachable {
            Text("Home Mode must be online and reachable (checks your Dinodia Hub address).")
                .font(.caption)
                .foregroundColor(.orange)
            }
        }
    }

    private var remoteAccessSection: some View {
        Section("Remote access") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(statusText.title)
                        .foregroundColor(statusText.color)
                }
                if let leaseText = leaseCountdownText {
                    Text(leaseText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let message = statusMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(statusText.color)
                }
                if !isHttpsBase && !baseUrl.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Installer-only: this uses HTTP on your local network. Proceed only on trusted home Wi‑Fi.", systemImage: "exclamationmark.triangle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundColor(.orange)
                        if let host = URL(string: baseUrl)?.host {
                            Text("Hub: \(host)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Button {
                    startOrResumeFlow()
                } label: {
                    Text(primaryButtonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(primaryButtonDisabled)

                if (flowState == .webview || leaseActive) && !showWeb {
                    Button("Open WebView") {
                        startOrResumeFlow()
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                if case .waiting = flowState {
                    Button("Resend verification email") {
                        Task { await resendChallenge() }
                    }
                    .font(.caption)
                }

                Button("Cancel setup") {
                    cancelFlow()
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }

    private var tipsSection: some View {
        Section("Tips") {
            Text("1. Verify email")
            Text("2. Click Enable remote access")
            Text("3. Enter Nabu Casa login details")
            Text("4. Scroll down and unhide the remote access URL")
        }
    }

    // MARK: - Actions

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

    private func startOrResumeFlow() {
        guard !isRunningFlow else { return }
        Task { await runFlow() }
    }

    private func runFlow() async {
        await MainActor.run {
            challengeError = nil
            verifyMessage = nil
        }
        guard isHomeMode else {
            await MainActor.run {
                alertMessage = "Switch to Home Mode on your home Wi‑Fi to set up remote access."
                flowState = .blocked("Home Mode is required.")
                session.setHaMode(.home)
            }
            return
        }
        guard homeReachable else {
            await MainActor.run { flowState = .blocked("Home hub is not reachable. Connect to home Wi‑Fi and retry.") }
            return
        }

        isRunningFlow = true
        defer { isRunningFlow = false }

        do {
            if leaseActive {
                try await fetchCredsAndOpen()
                return
            }
            do {
                try await mintLeaseAndFetch()
            } catch {
                if isStepUpRequired(error) {
                    try await sendStepUpAndWait()
                    try await mintLeaseAndFetch()
                } else {
                    throw error
                }
            }
        } catch {
            if error.isCancellation { return }
            await MainActor.run { flowState = .error(error.localizedDescription) }
        }
    }

    private func sendStepUpAndWait() async throws {
        await MainActor.run {
            flowState = .sending
            challengeError = nil
        }
        let cid = try await RemoteAccessService.startStepUp()
        await MainActor.run {
            challengeId = cid
            flowState = .waiting
        }

        while true {
            try Task.checkCancellation()
            let st = try await AuthService.fetchChallengeStatus(id: cid)
            log("[poll] challengeId=\(cid) status=\(st.rawValue)")
            switch st {
            case .APPROVED, .CONSUMED:
                try? await AuthService.completeStepUpChallenge(id: cid)
                return
            case .EXPIRED, .NOT_FOUND:
                throw AuthServiceError.custom("Verification expired. Please resend.")
            default:
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func mintLeaseAndFetch() async throws {
        await MainActor.run { flowState = .leasing }
        let result = try await RemoteAccessService.mintLease()
        guard let token = result.leaseToken, !token.isEmpty else {
            throw AuthServiceError.custom(result.error ?? "Email verification is required.")
        }
        await MainActor.run {
            leaseToken = token
            leaseExpiresAt = result.expiresAt
            challengeId = nil
            scheduleLeaseExpiryClear(expiresAt: result.expiresAt)
        }
        try await fetchCredsAndOpen()
    }

    private func fetchCredsAndOpen() async throws {
        guard let token = leaseToken, !token.isEmpty else {
            throw AuthServiceError.custom("Lease is missing. Please retry.")
        }
        await MainActor.run { flowState = .fetching }
        let secrets = try await RemoteAccessService.fetchSecrets(leaseToken: token)
        let user = (secrets.haUsername ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pass = (secrets.haPassword ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !pass.isEmpty else {
            throw AuthServiceError.custom("Unable to load Dinodia Hub credentials.")
        }
        await MainActor.run {
            haUsername = user
            haPassword = pass
            webKey += 1
            showWeb = true
            flowState = .webview
        }
    }

    private func saveCaptured(url: String) async {
        let normalized = normalizedCloudUrl(from: url)
        guard !normalized.isEmpty else {
            challengeError = "Invalid remote URL."
            return
        }
        cloudUrl = normalized
        verifyMessage = nil
        do {
            try await ensureLeaseForSave()
        } catch {
            await MainActor.run {
                if error.isCancellation { return }
                flowState = .error(error.localizedDescription)
                challengeError = error.localizedDescription
            }
            return
        }
        await MainActor.run { flowState = .saving }
        do {
            try await RemoteAccessService.saveCloudUrl(leaseToken: leaseToken ?? "", cloudUrl: normalized)
            await testCloudUrl()
        } catch {
            await MainActor.run {
                if error.isCancellation { return }
                flowState = .error(error.localizedDescription)
                challengeError = error.localizedDescription
            }
        }
    }

    private func updateAllowedHosts() {
        var hosts: Set<String> = ["account.nabucasa.com", "auth.nabucasa.com", "cloud.nabucasa.com"]
        if let host = URL(string: hubUiBaseUrl)?.host {
            hosts.insert(host)
        }
        allowedHosts = hosts
        log("[baseUrl] \(baseUrl.isEmpty ? "missing" : baseUrl)")
    }

    private func refreshHomeReachability() async {
        homeReachable = await RemoteAccessService.checkHomeReachable()
    }

    private func startReachabilityPolling() {
        reachabilityTask?.cancel()
        reachabilityTask = Task { @MainActor in
            while !Task.isCancelled {
                await refreshHomeReachability()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func clearSensitive() {
        haUsername = ""
        haPassword = ""
        leaseToken = nil
        leaseExpiresAt = nil
        pollingTask?.cancel()
        leaseExpiryTask?.cancel()
    }

    private func scheduleLeaseExpiryClear(expiresAt: String?) {
        leaseExpiryTask?.cancel()
        guard let expiresAt, let ms = msUntil(expiresAt), ms > 0 else { return }
        let waitMs = ms
        leaseExpiryTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(waitMs) * 1_000_000)
            clearSensitive()
            flowState = .idle
            log("[lease] expired, cleared")
        }
    }

    private func resendChallenge() async {
        guard let cid = challengeId else { return }
        try? await AuthService.resendChallenge(id: cid)
    }

    private func ensureLeaseForSave() async throws {
        if leaseActive { return }
        await MainActor.run { flowState = .leasing }
        let result = try await RemoteAccessService.mintLease()
        guard let token = result.leaseToken, !token.isEmpty else {
            throw AuthServiceError.custom(result.error ?? "Email verification is required.")
        }
        await MainActor.run {
            leaseToken = token
            leaseExpiresAt = result.expiresAt
            scheduleLeaseExpiryClear(expiresAt: result.expiresAt)
        }
    }

    private func isStepUpRequired(_ error: Error) -> Bool {
        if let err = error as? PlatformFetchError {
            switch err {
            case .http(_, let message):
                return message.contains("Email verification is required")
            case .network(let message):
                return message.contains("Email verification is required")
            default:
                return false
            }
        }
        return error.localizedDescription.contains("Email verification is required")
    }

    private func cancelFlow() {
        pollingTask?.cancel()
        leaseExpiryTask?.cancel()
        reachabilityTask?.cancel()
        showWeb = false
        clearSensitive()
        flowState = .idle
        isRunningFlow = false
    }

    private func testCloudUrl() async {
        let target = normalizedCloudUrl(from: cloudUrl)
        log("[test] target=\(target)")
        guard let url = URL(string: target) else { return }
        await MainActor.run {
            flowState = .testing
            verifyMessage = nil
        }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 5
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode > 0 {
                await MainActor.run {
                    verifyMessage = "Remote access enabled. Cloud mode should work now."
                    flowState = .done(verifyMessage)
                }
            } else {
                await MainActor.run {
                    verifyMessage = "Saved, but we could not verify the URL right now."
                    flowState = .done(verifyMessage)
                }
            }
        } catch {
            await MainActor.run {
                verifyMessage = "Saved, but we could not verify the URL right now."
                flowState = .done(verifyMessage)
            }
            log("[test] error=\(error.localizedDescription)")
        }
    }
    // MARK: - Helpers

    private func log(_ message: String) {
        // Logs disabled per request
    }

    private var statusText: (title: String, color: Color) {
        switch flowState {
        case .idle:
            return ("Not started", .primary)
        case .blocked:
            return ("Blocked", .orange)
        case .sending:
            return ("Sending verification…", .primary)
        case .waiting:
            return ("Waiting for approval", .orange)
        case .leasing:
            return ("Verifying device…", .primary)
        case .fetching:
            return ("Fetching credentials…", .primary)
        case .webview:
            return ("Continue in Dinodia Hub", .primary)
        case .saving:
            return ("Saving…", .primary)
        case .testing:
            return ("Testing…", .primary)
        case .done:
            return ("Done", .green)
        case .error:
            return ("Error", .red)
        }
    }

    private var statusMessage: String? {
        switch flowState {
        case .blocked(let msg):
            return msg
        case .done(let msg):
            return msg ?? verifyMessage
        case .error(let msg):
            return msg
        default:
            return verifyMessage ?? challengeError
        }
    }

    private var primaryButtonTitle: String {
        switch flowState {
        case .sending:
            return "Sending…"
        case .waiting:
            return "Refresh status"
        case .leasing, .fetching:
            return "Preparing…"
        case .webview:
            return "WebView open"
        case .saving, .testing:
            return "Working…"
        case .done:
            return "Enable remote access again"
        default:
            return "Enable remote access"
        }
    }

    private var primaryButtonDisabled: Bool {
        switch flowState {
        case .webview, .saving, .testing:
            return true
        case .sending, .leasing, .fetching:
            return true
        default:
            return isRunningFlow || showWeb
        }
    }

    private var leaseCountdownText: String? {
        guard leaseActive, let expires = leaseExpiresAt, let ms = msUntil(expires), ms > 0 else { return nil }
        let mins = Int(Double(ms) / 1000.0 / 60.0)
        return "Lease valid for ~\(mins) min"
    }

    private func msUntil(_ iso: String?) -> Int? {
        guard let iso else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: iso)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: iso)
        }
        guard let parsed = date else {
            log("[date] unable to parse expiresAt=\(iso)")
            return nil
        }
        return Int(parsed.timeIntervalSinceNow * 1000)
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

}

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
