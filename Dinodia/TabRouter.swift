import Foundation
import Combine

enum AdminTab: Hashable {
    case dashboard
    case automations
    case homeSetup
    case settings
}

enum TenantTab: Hashable {
    case dashboard
    case automations
    case addDevices
    case settings
}

@MainActor
final class TabRouter: ObservableObject {
    @Published var adminTab: AdminTab = .dashboard
    @Published var tenantTab: TenantTab = .dashboard
}
