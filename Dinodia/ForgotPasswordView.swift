import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var identifier: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    var body: some View {
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
                        Text("Reset password")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Enter your username or email. If we find a match, we'll email a reset link.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Username or email")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("DINODIA or you@example.com", text: $identifier)
                                .textContentType(.username)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
                        }

                        if let errorMessage {
                            NoticeView(kind: .error, message: errorMessage)
                        }
                        if let infoMessage {
                            NoticeView(kind: .info, message: infoMessage)
                        }

                        Button(action: submit) {
                            HStack {
                                if isSubmitting { ProgressView().tint(.white) }
                                Text(isSubmitting ? "Sending..." : "Send reset link")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .disabled(isSubmitting)
                        .foregroundColor(.white)
                        .background(isSubmitting ? Color.accentColor.opacity(0.7) : Color.accentColor)
                        .cornerRadius(14)

                        Button("Back to login") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .buttonStyle(.bordered)
                        .disabled(isSubmitting)
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
    }

    private func submit() {
        guard !isSubmitting else { return }
        errorMessage = nil
        infoMessage = nil
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errorMessage = "Enter your username or email to continue."
            return
        }
        isSubmitting = true
        Task {
            do {
                try await AuthService.requestPasswordReset(identifier: trimmed)
                await MainActor.run {
                    infoMessage = "If an account exists for that username or email, we sent a reset link."
                }
            } catch {
                await MainActor.run { errorMessage = friendlyError(for: error) }
            }
            await MainActor.run { isSubmitting = false }
        }
    }

    private func friendlyError(for error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("too many") {
            return "Too many requests. Please wait and try again."
        }
        if raw.contains("http") || raw.isEmpty {
            return "We could not send a reset link right now. Please try again."
        }
        return error.localizedDescription
    }
}
