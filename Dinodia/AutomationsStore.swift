import Foundation
import Combine

@MainActor
final class AutomationsStore: ObservableObject {
    @Published var automations: [AutomationSummary] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isSaving: Bool = false

    let mode: HaMode
    private let haConnection: HaConnection?

    init(mode: HaMode, haConnection: HaConnection?) {
        self.mode = mode
        self.haConnection = haConnection
        Task { await load() }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            automations = try await AutomationsService.list(mode: mode, haConnection: haConnection)
            errorMessage = nil
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    func reload() {
        Task { await load() }
    }

    func setEnabled(id: String, enabled: Bool) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await AutomationsService.setEnabled(id: id, enabled: enabled, mode: mode, haConnection: haConnection)
            await load()
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    func delete(id: String) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await AutomationsService.delete(id: id, mode: mode, haConnection: haConnection)
            automations.removeAll { $0.id == id }
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    func create(draft: AutomationDraft) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await AutomationsService.create(draft: draft, mode: mode, haConnection: haConnection)
            await load()
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    func update(id: String, draft: AutomationDraft) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await AutomationsService.update(id: id, draft: draft, mode: mode, haConnection: haConnection)
            await load()
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}
