# Security Checklist (Storage + Logout)

This checklist documents where sensitive state is stored and how it is cleared on logout/reset.

## Persistence surfaces

- `UserDefaults`
  - `dinodia_session_v1` (Session payload)
  - `tenant_selected_area_<userId>` (area selection)
  - `dinodia_devices_<userId>_<mode>` (device cache entries)
- `dinodia_device_id_v1` (device identity)
- Keychain
  - `PlatformTokenStore` (`com.dinodia.platform.token` / `platform_token`)
  - `HomeModeSecretsKeychain` (Dinodia Hub base URL + rotating token, per-user)
- In-memory caches
  - `HomeModeSecretsStore` (base URL + token; mirrors keychain for active user)
  - `DeviceCache` memory map
- Web data / cookies
  - `HTTPCookieStorage.shared`
  - `URLCredentialStorage.shared`
  - `URLCache.shared`
  - `WKWebsiteDataStore.default()` (RemoteAccessSetupView)

## Logout / reset clears

`SessionStore.resetApp()`:
- Invalidates verify timer
- Calls server logout (`AuthService.logoutRemote()`)
- Clears in-memory session state
- Removes `dinodia_session_v1`
- Clears `HomeModeSecretsStore`
- Clears `PlatformTokenStore` (keychain)
- Clears device caches via `DeviceStore.clearAll`
- Removes `tenant_selected_area_<userId>`
- Clears cookies, credentials, web data, and URL cache

## Background privacy

`DinodiaApp` shows a privacy cover when the app is inactive/backgrounded.
