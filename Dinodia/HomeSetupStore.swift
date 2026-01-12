import Foundation
import Combine

@MainActor
final class HomeSetupStore: ObservableObject {
    @Published var tenants: [TenantRecord] = []
    @Published var isLoadingTenants = false
    @Published var tenantError: String?

    @Published var sellingTargets: SellingTargets?
    @Published var sellingError: String?
    @Published var sellingLoading = false
    @Published var claimCode: String?

    @Published var remoteStatus: RemoteAccessStatus = .checking
    @Published var homeReachable: Bool = true

    func loadTenants() async {
        isLoadingTenants = true
        tenantError = nil
        defer { isLoadingTenants = false }
        do {
            tenants = try await AdminService.fetchTenants()
        } catch {
            if error.isCancellation { return }
            tenantError = error.localizedDescription
        }
    }

    func addTenant(username: String, password: String, areas: [String]) async {
        do {
            try await AdminService.createTenant(username: username, password: password, areas: areas)
            await loadTenants()
        } catch {
            if error.isCancellation { return }
            tenantError = error.localizedDescription
        }
    }

    func updateAreas(for tenantId: Int, areas: [String]) async {
        do {
            let updated = try await AdminService.updateTenantAreas(id: tenantId, areas: areas)
            tenants = tenants.map { $0.id == updated.id ? updated : $0 }
        } catch {
            if error.isCancellation { return }
            tenantError = error.localizedDescription
        }
    }

    func deleteTenant(id: Int) async {
        do {
            try await AdminService.deleteTenant(id: id)
            tenants.removeAll { $0.id == id }
        } catch {
            if error.isCancellation { return }
            tenantError = error.localizedDescription
        }
    }

    func refreshRemoteAccess() async {
        remoteStatus = .checking
        let enabled = await RemoteAccessService.checkRemoteAccessEnabled()
        remoteStatus = enabled ? .enabled : .locked
    }

    func refreshHomeReachability() async {
        homeReachable = await RemoteAccessService.checkHomeReachable()
    }

    func loadSellingTargets(mode: HaMode) async {
        sellingLoading = true
        sellingError = nil
        defer { sellingLoading = false }
        do {
            let platformTargets = try await AdminService.fetchSellingTargets()
            if platformTargets.deviceIds.isEmpty && platformTargets.entityIds.isEmpty && platformTargets.automationIds.isEmpty {
                // Cloud mode: stay platform-only; Home mode: attempt local inspection as a fallback.
                if mode == .home, let secrets = try? await HomeModeSecretsStore.fetch() {
                    let ha = HaConnectionLike(baseUrl: secrets.baseUrl, longLivedToken: secrets.longLivedToken)
                    let devices = (try? await HAService.listDeviceRegistryIds(ha)) ?? []
                    let entities = (try? await HAService.listEntityRegistryIds(ha)) ?? []
                    let automations = (try? await HAService.listAutomationEntityIds(ha)) ?? []
                    sellingTargets = SellingTargets(deviceIds: devices, entityIds: entities, automationIds: automations)
                } else {
                    sellingTargets = platformTargets
                }
            } else {
                sellingTargets = platformTargets
            }
        } catch {
            if error.isCancellation { return }
            if error.isCancellation { return }
            sellingError = error.localizedDescription
        }
    }

    func resetProperty(mode: String, cleanup: String?, haMode: HaMode) async {
        sellingLoading = true
        sellingError = nil
        claimCode = nil
        defer { sellingLoading = false }
        do {
            // Cloud mode: never run local cleanup; force platform-only.
            let effectiveCleanup: String?
            if haMode == .cloud {
                effectiveCleanup = cleanup == "device" ? "platform" : cleanup
            } else {
                effectiveCleanup = cleanup
            }

            if haMode == .home, effectiveCleanup == "device" {
                try await runLocalCleanup()
            }
            // Try platform cleanup with requested mode; if remote access is required, fall back to a platform-only cleanup.
            let serverCleanup = effectiveCleanup
            do {
                claimCode = try await AdminService.deregisterProperty(mode: mode, cleanup: serverCleanup)
            } catch {
                let message = error.localizedDescription.lowercased()
                if effectiveCleanup == "device",
                   message.contains("remote access") || message.contains("not trusted") || message.contains("trusted") {
                    claimCode = try await AdminService.deregisterProperty(mode: mode, cleanup: "platform")
                } else {
                    throw error
                }
            }
        } catch {
            if error.isCancellation { return }
            sellingError = error.localizedDescription
        }
    }

    private func runLocalCleanup() async throws {
        let secrets = try await HomeModeSecretsStore.fetch()
        let ha = HaConnectionLike(baseUrl: secrets.baseUrl, longLivedToken: secrets.longLivedToken)
        let targets = try await AdminService.fetchSellingTargets()
        let automationIds = targets.automationIds
        let entityIds = targets.entityIds
        let deviceIds = targets.deviceIds

        for id in automationIds {
            try? await HAService.deleteAutomation(ha, entityId: id)
        }
        for entityId in entityIds {
            try? await HAService.removeEntity(ha, entityId: entityId)
        }
        for deviceId in deviceIds {
            try? await HAService.removeDevice(ha, deviceId: deviceId)
        }
        try? await HAService.callHaService(ha, domain: "cloud", service: "logout", data: [:], timeout: 4.0)
    }
}
