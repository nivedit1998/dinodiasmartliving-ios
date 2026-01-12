import SwiftUI

enum NoticeKind {
    case error
    case info
    case success
    case warning

    var icon: String {
        switch self {
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        }
    }

    var foreground: Color {
        switch self {
        case .error: return .red
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        }
    }

    var background: Color {
        switch self {
        case .error: return Color.red.opacity(0.08)
        case .info: return Color.secondary.opacity(0.08)
        case .success: return Color.green.opacity(0.08)
        case .warning: return Color.orange.opacity(0.08)
        }
    }
}

struct NoticeView: View {
    let kind: NoticeKind
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: kind.icon)
                .font(.footnote)
                .foregroundColor(kind.foreground)
            Text(message)
                .font(.footnote)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.background)
        .cornerRadius(12)
    }
}
