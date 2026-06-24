import Foundation
import SendrealmIOS

struct DemoLogEntry: Identifiable {
    let id = UUID()
    let message: String
}

struct DemoAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class DemoViewModel: NSObject, ObservableObject, @preconcurrency SendrealmDelegate {
    @Published var appId = "YOUR_SENDREALM_APP_ID"
    @Published var baseUrl = "https://sdk-api.sendrealm.com"
    @Published var apnsEnvironment = "sandbox"
    @Published var externalUserId = "ios-demo-user"
    @Published var userEmail = "ios-demo@sendrealm.local"
    @Published var tagKey = "plan"
    @Published var tagValue = "pro"
    @Published var eventName = "demo_button_clicked"
    @Published var suppressForegroundNotifications = false

    @Published private(set) var deviceId = "Pending"
    @Published private(set) var tokenStatus = "Missing"
    @Published private(set) var permissionStatus = "Unknown"
    @Published private(set) var subscriptionStatus = "Unknown"
    @Published private(set) var liveActivityStatus = "Unknown"
    @Published private(set) var status = "Ready"
    @Published private(set) var lastNotification = "No notification activity yet."
    @Published private(set) var logs: [DemoLogEntry] = []
    @Published private(set) var notificationEvents: [DemoLogEntry] = []
    @Published private(set) var isInitializing = false
    @Published var activeAlert: DemoAlert?

    private let sdk = Sendrealm.shared
    private var logObserver: NSObjectProtocol?

    override init() {
        super.init()
        sdk.delegate = self
        sdk.configure()

        logObserver = NotificationCenter.default.addObserver(
            forName: .sendrealmDemoLog,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let message = notification.object as? String else {
                return
            }

            Task { @MainActor in
                self?.appendLog(message)
            }
        }

        loadInitialNotification()
        refreshState()
        syncLiveActivityTokens()
    }

    deinit {
        if let logObserver {
            NotificationCenter.default.removeObserver(logObserver)
        }
    }

    func initializeSdk() {
        guard !isInitializing else {
            appendLog("Initialize ignored because a request is already in progress")
            return
        }

        let trimmedAppId = appId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBaseUrl = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedAppId.isEmpty, trimmedAppId != "YOUR_SENDREALM_APP_ID" else {
            let message = "Replace YOUR_SENDREALM_APP_ID with the real Push App ID from the Sendrealm dashboard before initializing."
            status = "Missing Sendrealm App ID"
            appendLog(message)
            activeAlert = DemoAlert(title: "Missing App ID", message: message)
            return
        }

        guard URL(string: trimmedBaseUrl) != nil else {
            let message = "Enter a valid SDK API URL, for example https://sdk-api.sendrealm.com."
            status = "Invalid SDK API URL"
            appendLog(message)
            activeAlert = DemoAlert(title: "Invalid SDK API URL", message: message)
            return
        }

        let options: NSDictionary = [
            "appId": trimmedAppId,
            "baseUrl": trimmedBaseUrl,
            "apnsEnvironment": apnsEnvironment,
            "externalUserId": externalUserId.trimmingCharacters(in: .whitespacesAndNewlines),
            "userEmail": userEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            "suppressForegroundNotifications": suppressForegroundNotifications,
            "autoRequestPermission": false
        ]

        isInitializing = true
        status = "Initializing SDK..."
        appendLog("Initializing SDK")
        sdk.initialize(options) { [weak self] result, error in
            Task { @MainActor in
                self?.isInitializing = false

                if let error {
                    let message = error.localizedDescription
                    self?.status = "Initialize failed"
                    self?.appendLog("Initialize failed: \(message)")
                    self?.activeAlert = DemoAlert(
                        title: "Initialize failed",
                        message: "\(message)\n\nCheck that the SDK API is reachable, the app ID exists, and the iOS provider matches this bundle/environment."
                    )
                    return
                }

                self?.status = "Initialized"
                self?.appendLog("Initialize result: \(Self.describe(result))")
                self?.syncLiveActivityTokens()
                self?.refreshState()
            }
        }
    }

    func requestPermission() {
        appendLog("Requesting notification permission")
        sdk.requestPermission { [weak self] granted, error in
            Task { @MainActor in
                if let error {
                    self?.appendLog("Permission failed: \(error.localizedDescription)")
                    return
                }

                self?.permissionStatus = granted?.boolValue == true ? "Granted" : "Denied"
                self?.appendLog("Permission: \(self?.permissionStatus ?? "Unknown")")
                self?.refreshState()
            }
        }
    }

    func refreshRegistrationToken() {
        appendLog("Refreshing APNs registration")
        sdk.refreshRegistrationToken(true) { [weak self] token in
            Task { @MainActor in
                self?.appendLog(token == nil ? "APNs token not available yet" : "APNs token re-sent")
                self?.refreshState()
            }
        }
    }

    func syncLiveActivityTokens() {
        sdk.syncLiveActivityTokens { [weak self] success in
            Task { @MainActor in
                self?.appendLog(success.boolValue ? "Live Activity token sync started" : "Live Activity token sync unavailable")
                self?.refreshState()
            }
        }
    }

    func login() {
        sdk.login(externalUserId, email: userEmail) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.appendLog("Login failed: \(error.localizedDescription)")
                    return
                }

                self?.appendLog("Logged in as \(self?.externalUserId ?? "")")
                self?.refreshState()
            }
        }
    }

    func logout() {
        sdk.logout { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.appendLog("Logout failed: \(error.localizedDescription)")
                    return
                }

                self?.appendLog("Logged out")
                self?.refreshState()
            }
        }
    }

    func optIn() {
        sdk.optIn { [weak self] success in
            Task { @MainActor in
                self?.appendLog(success.boolValue ? "Opt-in synced" : "Opt-in failed")
                self?.refreshState()
            }
        }
    }

    func optOut() {
        sdk.optOut { [weak self] success in
            Task { @MainActor in
                self?.appendLog(success.boolValue ? "Opt-out synced" : "Opt-out failed")
                self?.refreshState()
            }
        }
    }

    func addTag() {
        sdk.addTag(tagKey, value: tagValue) { [weak self] success, error in
            Task { @MainActor in
                if let error {
                    self?.appendLog("Tag failed: \(error.localizedDescription)")
                    return
                }

                self?.appendLog(success.boolValue ? "Tag synced: \(self?.tagKey ?? "")" : "Tag sync failed")
            }
        }
    }

    func trackEvent() {
        let properties: NSDictionary = [
            "source": "ios_demo",
            "sample_product_id": "sku_demo_123",
            "sample_price": 29.0
        ]

        sdk.trackEvent(eventName, properties: properties) { [weak self] success, error in
            Task { @MainActor in
                if let error {
                    self?.appendLog("Event failed: \(error.localizedDescription)")
                    return
                }

                self?.appendLog(success.boolValue ? "Tracked event: \(self?.eventName ?? "")" : "Event tracking failed")
            }
        }
    }

    func refreshState() {
        sdk.getState { [weak self] state in
            Task { @MainActor in
                self?.deviceId = Self.stringValue(state["deviceId"]) ?? "Pending"
                self?.tokenStatus = Self.stringValue(state["tokenStatus"]) ?? "Missing"
                self?.permissionStatus = (state["permissionGranted"] as? Bool) == true ? "Granted" : "Not granted"
                self?.subscriptionStatus = (state["subscribed"] as? Bool) == true ? "Subscribed" : "Not subscribed"
                self?.apnsEnvironment = Self.stringValue(state["apnsEnvironment"]) ?? self?.apnsEnvironment ?? "sandbox"
                if let liveActivity = state["liveActivity"] as? [String: Any] {
                    let status = Self.stringValue(liveActivity["status"]) ?? "unknown"
                    let enabled = liveActivity["enabled"] as? Bool
                    let observed = liveActivity["pushToStartTokenObserved"] as? Bool
                    let successes = liveActivity["registrationSuccesses"] as? Int ?? 0
                    let failures = liveActivity["registrationFailures"] as? Int ?? 0
                    let lastError = Self.stringValue(liveActivity["lastError"])

                    self?.liveActivityStatus = [
                        status,
                        enabled == nil ? nil : (enabled == true ? "enabled" : "disabled"),
                        observed == true ? "token seen" : "no token yet",
                        successes > 0 ? "registered \(successes)" : nil,
                        failures > 0 ? "failed \(failures)" : nil,
                        lastError
                    ]
                    .compactMap { $0 }
                    .joined(separator: " / ")
                }
                self?.status = "State refreshed"
            }
        }
    }

    func sendrealm(_ sdk: Sendrealm, didReceiveEvent name: String, body: NSDictionary) {
        let summary = "\(name): \(Self.describe(body))"

        Task { @MainActor in
            if name == Sendrealm.eventNotificationClicked ||
                name == Sendrealm.eventForegroundNotification {
                lastNotification = summary
                prepend(summary, to: &notificationEvents, limit: 20)
            }

            appendLog("SDK event: \(summary)")
            refreshState()
        }
    }

    private func loadInitialNotification() {
        sdk.getInitialNotification { [weak self] notification in
            Task { @MainActor in
                guard let notification else {
                    return
                }

                let summary = "Initial notification: \(Self.describe(notification))"
                self?.lastNotification = summary
                if let self {
                    self.prepend(summary, to: &self.notificationEvents, limit: 20)
                }
            }
        }
    }

    private func appendLog(_ message: String) {
        prepend("[\(Self.timestamp())] \(message)", to: &logs, limit: 50)
    }

    private func prepend(_ value: String, to array: inout [DemoLogEntry], limit: Int) {
        array.insert(DemoLogEntry(message: value), at: 0)
        if array.count > limit {
            array.removeLast(array.count - limit)
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String, !value.isEmpty {
            return value
        }

        return nil
    }

    private static func describe(_ value: Any?) -> String {
        guard let value else {
            return "nil"
        }

        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
           let raw = String(data: data, encoding: .utf8) {
            return raw
        }

        return String(describing: value)
    }
}
