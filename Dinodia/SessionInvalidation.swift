import Foundation

enum SessionInvalidation {
    private static var handler: (() -> Void)?
    private static var triggered = false

    static func setHandler(_ newHandler: @escaping () -> Void) {
        handler = newHandler
        triggered = false
    }

    static func triggerOnce() {
        guard !triggered else { return }
        triggered = true
        handler?()
    }
}
