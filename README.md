# Sendrealm iOS SDK

Native Swift SDK for Sendrealm mobile push notifications on iOS. The SDK registers APNs device tokens, tracks notification lifecycle events, exposes identity/tags/subscription APIs, and normalizes Sendrealm APNs payloads.

## Platform Support

- Minimum iOS: 13.4.
- Delivery provider: Apple Push Notification service.
- Supported package managers: Swift Package Manager and CocoaPods.
- APNs environments: `sandbox` and `production`.

## Quick Start

```swift
import SendrealmIOS

Sendrealm.configure()

Sendrealm.shared.initialize([
  "appId": "YOUR_SENDREALM_APP_ID",
  "baseUrl": "https://sdk-api.sendrealm.com",
  "apnsEnvironment": "sandbox",
  "autoRequestPermission": false
]) { result, error in
  print(result as Any, error as Any)
}
```

Forward APNs token callbacks:

```swift
func application(
  _ application: UIApplication,
  didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
  Sendrealm.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
}
```

Ask for permission:

```swift
Sendrealm.shared.requestPermission { granted, error in
  print(granted?.boolValue == true, error as Any)
}
```

## Main APIs

- `initialize(options, completion)`.
- `requestPermission(completion)`.
- `getPermissionStatus(completion)`.
- `openNotificationSettings(completion)`.
- `setBadgeCount(count, completion)` and `clearBadge(completion)`.
- `setForegroundPresentation(options, completion)`.
- `hasNotificationPermission(completion)`.
- `refreshRegistrationToken(forceRefresh, completion)`.
- `login(userId, email, completion)` and `logout(completion)`.
- `optIn(completion)` and `optOut(completion)`.
- `addTag`, `addTags`, and `removeTag`.
- `trackEvent(eventType, properties, completion)`.
- `getState(completion)`.
- `getDiagnostics(completion)`.
- `getInitialNotification(completion)`.

## Diagnostics And Reliability

`getDiagnostics` returns the app ID, API URL/source, SDK/app/OS version, device ID, token presence, permission status, subscribed state, APNs environment, queue counts, last init/register result, last SDK error, and last notification/open payload. The SDK persists failed register/subscription operations and retries them when the app returns to foreground.

Foreground presentation can be configured with:

```swift
Sendrealm.shared.setForegroundPresentation([
  "banner": true,
  "list": true,
  "sound": true,
  "badge": true
]) { success in
  print(success.boolValue)
}
```

Notification opens are deduplicated for tracking, and foreground, action, silent/background, delivery, open, click, and dismiss events are normalized before delegate forwarding.

## Source Layout

- `Core`: public SDK type, singleton, constants, and delegate protocol.
- `Public`: app-facing API methods that are exposed to Swift and the React Native Objective-C bridge.
- `Networking`: SDK API request construction and registration/event calls.
- `Notifications`: APNs callback handling, foreground/open events, payload normalization, deep-link opening, and rich notification helper.
- `Storage`: persisted SDK state and pending tag/event queues.
- `Utilities`: JSON, option normalization, version, and error helpers.
- `Tests`: XCTest-only helpers and unit tests. Test helpers should stay out of production sources.
- `Example`: native SwiftUI demo app for physical-device APNs testing.

SDK tags are client-sourced values for app-observed preferences, state, and
behavior. Keep authoritative account, billing, security, compliance, and
verified profile data on server-owned contact properties.

## Notes

- Use `sandbox` APNs environment for development builds and `production` for production-signed builds.
- APNs tokens cannot be deleted or force-regenerated like FCM tokens. Refresh asks iOS to register for remote notifications again and re-sends the latest token.
- Rich notification images require a Notification Service Extension. Use `SendrealmNotificationServiceHelper.enrich(...)` from the extension target.
- Silent pushes require the Remote notifications background mode and APNs `content-available`; delivery remains best effort under iOS power policy.
