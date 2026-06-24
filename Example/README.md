# Sendrealm iOS Native Demo

Native SwiftUI demo app for validating the Sendrealm iOS SDK on a real iPhone.

This mirrors the Android native demo at `../../android/app`: it initializes the SDK, requests notification permission, registers the APNs token, displays SDK state, listens for foreground/open notification events, and exercises login, tags, opt-in/out, and custom event tracking.

## Requirements

- Xcode with iOS SDK support.
- iOS 15.0 or newer for the demo app.
- A paid Apple Developer account.
- A physical iPhone.
- A bundle ID with the Push Notifications capability enabled.
- A configured Sendrealm iOS provider with the Apple APNs configuration file (`.p8` auth key), Key ID, Team ID, Bundle ID, and APNs Environment set to `sandbox` for development builds.
- An SDK API URL reachable by the iPhone. The demo defaults to `https://sdk-api.sendrealm.com`; use a LAN or tunnel URL for local API testing.

## Run

1. Open `SendrealmIOSDemo.xcodeproj` in Xcode.
2. Select the `SendrealmIOSDemo` target.
3. Set your signing team and confirm the bundle identifier is `com.sendrealm.demo.native`.
4. Confirm the Simulator/app icon name is `Sendrealm Native Demo`.
5. Confirm `Signing & Capabilities` includes Push Notifications.
6. Run on a physical iPhone.
7. In the app, set:
   - Sendrealm App ID
   - SDK API base URL. The default is `https://sdk-api.sendrealm.com`.
   - APNs Environment: `sandbox`
8. Tap `Initialize SDK`, then `Request Permission`.

## Simulator Testing

Current Xcode simulators support two push-testing paths:

- Real APNs Sandbox remote notifications on supported simulator setups: iOS 16 or newer simulator runtime on macOS 13 or newer, running on Apple silicon or a Mac with a T2 processor. The simulator produces a sandbox registration token, and the server sends through `api.sandbox.push.apple.com`.
- Local simulated remote notifications with `xcrun simctl push`. This does not go through APNs, but it is useful for testing foreground handling, payload parsing, opens, and deep links.

Use a physical iPhone for production APNs, real-device delivery checks, and final release validation.

Local simulation example:

```bash
xcrun simctl push booted com.sendrealm.demo.native payload.apns
```

The payload file must be a JSON object with an `aps` key.

## Local API URLs

Physical iPhones cannot use `localhost`, `127.0.0.1`, or Android emulator addresses like `10.0.2.2`. For local API testing, use a LAN URL such as `http://192.168.0.170:5506` or an HTTPS tunnel that is reachable from the phone.

For the full checklist, see:

- `../README.md`
- `../../react-native/docs/testing-ios-physical-device.md`
