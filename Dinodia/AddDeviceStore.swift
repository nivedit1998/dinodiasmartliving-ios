import Foundation
import Combine

@MainActor
final class AddDeviceStore: ObservableObject {
    @Published var flows: [DiscoveryFlow] = []
    @Published var isLoading: Bool = false
    @Published var isWorking: Bool = false
    @Published var errorMessage: String?
    @Published var warnings: [String] = []
    @Published var activeSession: CommissionSession?

    @Published var areas: [String] = []
    @Published var userInput: [String: String] = [:]

    private let userId: Int

    init(userId: Int) {
        self.userId = userId
    }

    func loadFlows() async {
        isLoading = true
        defer { isLoading = false }
        do {
            flows = try await DeviceOnboardingService.listFlows()
            errorMessage = nil
        } catch {
            flows = []
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadAreas() async {
        do {
            let (relations, _) = try await DinodiaService.getUserWithHaConnection(userId: userId)
            let unique = Set(relations.accessRules.map { $0.area })
            areas = unique.sorted()
        } catch {
            areas = []
        }
    }

    func start(flowId: String, area: String, name: String?, haLabelId: String?, dinodiaType: String?, pairingCode: String?) async {
        isWorking = true
        warnings = []
        defer { isWorking = false }
        do {
            let response = try await DeviceOnboardingService.startSession(
                flowId: flowId,
                area: area,
                name: name,
                haLabelId: haLabelId,
                dinodiaType: dinodiaType,
                pairingCode: pairingCode
            )
            if let err = response.error { errorMessage = err; return }
            activeSession = response.session
            warnings = response.warnings ?? []
            errorMessage = nil
            syncUserInput(from: response.session)
            if let sessionId = response.session?.id, response.session?.isFinal != true {
                await step(sessionId: sessionId)
            }
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    func step(sessionId: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await DeviceOnboardingService.step(sessionId: sessionId, userInput: userInput)
            if let err = response.error { errorMessage = err }
            activeSession = response.session ?? activeSession
            warnings = response.warnings ?? warnings
            syncUserInput(from: response.session)
            if response.session?.status == .succeeded {
                await DeviceStore.clearAll(for: userId)
            }
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    func cancel(sessionId: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await DeviceOnboardingService.cancel(sessionId: sessionId)
            if let err = response.error { errorMessage = err }
            activeSession = response.session
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    func resetSession() {
        activeSession = nil
        warnings = []
        userInput = [:]
    }

    private func syncUserInput(from session: CommissionSession?) {
        guard let fields = session?.lastHaStep?.dataSchema else { return }
        var next: [String: String] = userInput
        for field in fields {
            if next[field.name] == nil {
                next[field.name] = ""
            }
        }
        userInput = next
    }
}
