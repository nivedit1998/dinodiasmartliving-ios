import SwiftUI

struct ModeSwitchResult {
    let available: Bool
    let message: String
}

struct ModeSwitchPrompt: View {
    @EnvironmentObject private var session: SessionStore
    let targetMode: HaMode
    let userId: Int?
    let onSwitched: (() -> Void)?

    @State private var checking = false
    @State private var result: ModeSwitchResult?
    @State private var showAlert = false

    var body: some View {
        Button {
            Task { await handleTap() }
        } label: {
            pill
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .alert(alertTitle, isPresented: $showAlert) {
            if result?.available == true {
                Button("Switch") { Task { await applySwitch() } }
            }
            Button("OK", role: .cancel) {}
        } message: {
            if let result {
                HStack {
                    Image(systemName: result.available ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundColor(result.available ? .green : .red)
                    Text(result.message)
                }
            }
        }
    }

    private var alertTitle: String {
        targetMode == .home ? "Move to Home Mode?" : "Move to Cloud Mode?"
    }

    private var pill: some View {
        let isHome = session.haMode == .home
        let text = isHome ? "Home Mode" : "Cloud Mode"
        let color = isHome ? Color.green.opacity(0.18) : Color.purple.opacity(0.18)
        let fg = isHome ? Color.green : Color.purple
        return HStack(spacing: 8) {
            if checking { ProgressView().scaleEffect(0.7) }
            Text(text)
                .font(.callout)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(color)
        .foregroundColor(fg)
        .cornerRadius(14)
        .fixedSize()
    }

    private func handleTap() async {
        checking = true
        defer { checking = false }
        let available = await ModeSwitchPrompt.checkAvailability(targetMode: targetMode, session: session)
        result = available
        showAlert = true
    }

    private func applySwitch() async {
        await ModeSwitchPrompt.performSwitch(
            targetMode: targetMode,
            userId: userId,
            session: session
        )
        onSwitched?()
    }

    // MARK: - Shared helpers

    static func checkAvailability(targetMode: HaMode, session: SessionStore) async -> ModeSwitchResult {
        if targetMode == .cloud {
            let hasCloud = session.haConnection?.cloudEnabled == true
            return ModeSwitchResult(
                available: hasCloud,
                message: hasCloud ? "Cloud Mode Available" : "Cloud Mode Unavailable"
            )
        } else {
            let ok = await RemoteAccessService.checkHomeReachable()
            return ModeSwitchResult(
                available: ok,
                message: ok ? "Home Mode Available" : "Home Mode Unavailable"
            )
        }
    }

    static func performSwitch(targetMode: HaMode, userId: Int?, session: SessionStore) async {
        guard let userId else { return }
        let next = targetMode
        if next == .cloud {
            let hasCloud = session.haConnection?.cloudEnabled == true
            guard hasCloud else { return }
        } else {
            let ok = await RemoteAccessService.checkHomeReachable()
            guard ok else { return }
        }
        await DeviceStore.clearCache(for: userId, mode: next)
        session.setHaMode(next)
    }
}
