import SwiftUI

struct AlexaSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    let onLinkStatusChanged: ((Bool) -> Void)?
    let initiallyLinked: Bool

    @State private var isLinked: Bool
    @State private var checking = false

    init(initiallyLinked: Bool = false, onLinkStatusChanged: ((Bool) -> Void)? = nil) {
        self.initiallyLinked = initiallyLinked
        self.onLinkStatusChanged = onLinkStatusChanged
        _isLinked = State(initialValue: initiallyLinked)
    }

var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemIndigo).opacity(0.18), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    statusRow
                    stepsSection
                    actionButtons
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("Connect Alexa")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await refreshLinkStatus() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await refreshLinkStatus() }
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 52, height: 52)
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Voice control, unlocked.")
                        .font(.headline)
                    Text("Enable the “Dinodia Smart Living” Alexa skill to run your home with voice.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            HStack {
                Label("Cloud Mode required", systemImage: "cloud.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
        )
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: isLinked ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(isLinked ? .green : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(isLinked ? "Linked to Alexa" : "Not linked yet")
                    .font(.headline)
                Text(isLinked ? "You can now control Dinodia from Alexa." : "Finish linking to control Dinodia from Alexa.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if checking {
                ProgressView().scaleEffect(0.85)
            } else {
                Button("Refresh") {
                    Task { await refreshLinkStatus() }
                }
                .font(.footnote.weight(.semibold))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 5)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isLinked)
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to link")
                .font(.headline)
            VStack(alignment: .leading, spacing: 14) {
                stepRow(number: 1, title: "Open the Alexa app", detail: "On your phone or tablet.")
                stepRow(number: 2, title: "Go to Skills & Games", detail: "Find it from the More tab.")
                stepRow(number: 3, title: "Search “Dinodia Smart Living”", detail: "Tap the Dinodia skill result.")
                stepRow(number: 4, title: "Enable & sign in", detail: "Use your Dinodia account to complete linking.")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
            )
        }
    }

    private func stepRow(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.2))
                .foregroundColor(.accentColor)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                openURL(EnvConfig.alexaSkillURL)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.right.square.fill")
                    Text("Open “Dinodia Smart Living” in Alexa")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
            .disabled(checking)

            if isLinked {
                Button(role: .destructive) {
                    showUnlinkConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "link.slash")
                        Text("Disconnect Alexa")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .disabled(checking || unlinking)
            }

            Button(role: .cancel) {
                dismiss()
            } label: {
                Text("Back to Dashboard")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .disabled(checking || unlinking)
        }
        .alert("Disconnect Alexa?", isPresented: $showUnlinkConfirm) {
            Button("Disconnect", role: .destructive) {
                Task { await handleUnlink() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will unlink your Dinodia account from Alexa. You can re-link anytime.")
        }
    }

    @MainActor
    private func applyLinkStatus(_ linked: Bool) {
        isLinked = linked
        onLinkStatusChanged?(linked)
    }

    private func refreshLinkStatus() async {
        checking = true
        let linked = await AlexaLinkService.checkLinked()
        await MainActor.run {
            applyLinkStatus(linked)
            checking = false
        }
    }

    @State private var unlinking = false
    @State private var showUnlinkConfirm = false

    private func handleUnlink() async {
        guard !unlinking else { return }
        unlinking = true
        do {
            try await AlexaLinkService.unlink()
            await MainActor.run {
                applyLinkStatus(false)
            }
        } catch {
            // Best-effort: keep UI consistent; we could show an alert if desired.
        }
        unlinking = false
    }
}
