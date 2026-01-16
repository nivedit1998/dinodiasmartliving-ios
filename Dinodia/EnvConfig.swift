import Foundation

enum EnvConfig {
    // Dinodia Platform base URL (matches kiosk ENV.DINODIA_PLATFORM_API)
    static let dinodiaPlatformAPI = URL(string: "https://app.dinodiasmartliving.com")!
    // Alexa skill store URL (direct open)
    static let alexaSkillURL = URL(string: "https://www.amazon.co.uk/gp/product/B0GGCC4BDS?nodl=0")!
}
