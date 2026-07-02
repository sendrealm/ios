import Foundation
import UIKit
import UserNotifications

struct PendingLiveActivityTokenRegistration {
    let token: String
    let activityId: String?
    let tokenType: String
    let activityType: String?
    let attributesType: String?
    let sendId: String?

    var key: String {
        "\(tokenType):\(activityId ?? ""):\(activityType ?? ""):\(attributesType ?? ""):\(sendId ?? ""):\(token)"
    }
}

@objc public final class Sendrealm: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    @objc public static let shared = Sendrealm()

    public static let eventNotificationClicked = "Sendrealm:notification_clicked"
    public static let eventForegroundNotification = "Sendrealm:foreground_notification"
    public static let eventNotificationAction = "Sendrealm:notification_action"
    public static let eventSilentNotification = "Sendrealm:silent_notification"
    public static let eventPermissionChanged = "Sendrealm:permission_changed"
    public static let eventSubscriptionChanged = "Sendrealm:subscription_changed"
    public static let defaultActionCategory = "sendrealm_default_actions"
    public static let defaultActionCategoryPrefix = "sendrealm_default_actions_"
    public static let defaultActionIdentifiers = [
        "sendrealm_action_1",
        "sendrealm_action_2",
        "sendrealm_action_3"
    ]

    let prefsName = "com.sendrealm.iospush"
    let defaultBaseUrl = "https://sdk-api.sendrealm.com"
    let sdkVersion = "0.1.2"
    let queueLimit = 1000

    @objc public weak var delegate: SendrealmDelegate?

    var initialized = false
    var subscribed = false
    var suppressForegroundNotifications = false
    var foregroundBanner = true
    var foregroundList = true
    var foregroundSound = true
    var foregroundBadge = true
    var appId: String?
    var baseUrl: String?
    var apiUrlSource = "default"
    var deviceId: String?
    var externalUserId: String?
    var userEmail: String?
    var apnsToken: String?
    var apnsEnvironment = "production"
    var environment = "production"
    var lastPermissionStatus = "not_determined"
    var lastRegistrationFingerprint: String?
    var lastInitResult: [String: Any]?
    var lastRegisterResult: [String: Any]?
    var lastSdkError: [String: Any]?
    var lastNotificationPayload: NSDictionary?
    var lastOpenPayload: NSDictionary?
    var initialNotification: NSDictionary?
    var foregroundObserverRegistered = false
    var pendingLiveActivityTokenRegistrations: [PendingLiveActivityTokenRegistration] = []
    var liveActivityRegisteredTokenKeys = Set<String>()
    var liveActivityPushToStartTokenTask: Task<Void, Never>?
    var liveActivityCustomPushToStartTokenTasks: [String: Task<Void, Never>] = [:]
    var liveActivityCustomActivityUpdatesTasks: [String: Task<Void, Never>] = [:]
    var liveActivityActivityUpdatesTask: Task<Void, Never>?
    var liveActivityUpdateTokenTasks: [String: Task<Void, Never>] = [:]
    var liveActivityStateUpdateTasks: [String: Task<Void, Never>] = [:]
    var liveActivityContentUpdateTasks: [String: Task<Void, Never>] = [:]
    var liveActivityTrackedReceiptActivityIds = Set<String>()
    var liveActivityTrackedUpdateSendIds = Set<String>()
    var liveActivityStatus = "not_started"
    var liveActivityEnabled: Bool?
    var liveActivityPushToStartObserved = false
    var liveActivityTokenRegistrationAttempts = 0
    var liveActivityTokenRegistrationSuccesses = 0
    var liveActivityTokenRegistrationFailures = 0
    var liveActivityLastError: String?
    var liveActivityLastTokenType: String?
    var notificationCenterIntegrationDisabledForTesting = false
    var applicationIntegrationDisabledForTesting = false
    var notificationPermissionStatusForTesting: String?
    var requestNotificationAuthorizationForTesting: ((UNAuthorizationOptions, @escaping (Bool, Error?) -> Void) -> Void)?
    var notificationAuthorizationStatusForTesting: ((@escaping (UNAuthorizationStatus) -> Void) -> Void)?
    var registerForRemoteNotificationsForTesting: (() -> Void)?
    var openURLForTesting: ((URL, @escaping (Bool) -> Void) -> Void)?
    var setBadgeCountForTesting: ((Int, @escaping (Error?) -> Void) -> Void)?
    var registerNotificationCategoriesForTesting: ((Set<UNNotificationCategory>) -> Void)?
    var liveActivityActivitiesEnabledForTesting: Bool?

    private override init() {
        super.init()
        loadState()
    }

    public static func hexString(forDeviceToken deviceToken: Data) -> String {
        deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    @objc public func configure() {
        guard !notificationCenterIntegrationDisabledForTesting else {
            return
        }

        let installDelegate = {
            self.installNotificationCenterDelegate()
            self.registerDefaultNotificationCategories()
            self.registerForegroundObserverIfNeeded()
            self.startLiveActivityTokenObserversIfAvailable()
        }

        if Thread.isMainThread {
            installDelegate()
        } else {
            DispatchQueue.main.async(execute: installDelegate)
        }
    }

    @objc public static func configure() {
        shared.configure()
    }

    @objc(didRegisterForRemoteNotificationsWithDeviceToken:)
    public static func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        shared.handleAPNSToken(hexString(forDeviceToken: deviceToken))
    }

    @objc public static func didReceiveRemoteNotification(_ userInfo: NSDictionary) {
        shared.handleNotificationUserInfo(userInfo, opened: false)
    }

    @objc(didReceive:)
    public static func didReceive(_ response: UNNotificationResponse) {
        shared.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: response,
            withCompletionHandler: {}
        )
    }

    func registerForegroundObserverIfNeeded() {
        guard !foregroundObserverRegistered else {
            return
        }

        foregroundObserverRegistered = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    func registerDefaultNotificationCategories() {
        let categoriesForRegistration = defaultNotificationCategories()

        if let registerNotificationCategoriesForTesting {
            registerNotificationCategoriesForTesting(categoriesForRegistration)
            return
        }

        UNUserNotificationCenter.current().getNotificationCategories { categories in
            var nextCategories = categories
            categoriesForRegistration.forEach { category in
                nextCategories.update(with: category)
            }
            UNUserNotificationCenter.current().setNotificationCategories(nextCategories)
        }
    }

    func defaultNotificationCategories() -> Set<UNNotificationCategory> {
        let makeAction: (Int, String) -> UNNotificationAction = { index, identifier in
            UNNotificationAction(
                identifier: identifier,
                title: "Action \(index + 1)",
                options: [.foreground]
            )
        }
        let legacyCategory = UNNotificationCategory(
            identifier: Self.defaultActionCategory,
            actions: Self.defaultActionIdentifiers.enumerated().map { index, identifier in
                makeAction(index, identifier)
            },
            intentIdentifiers: [],
            options: []
        )
        let countSpecificCategories = (1...Self.defaultActionIdentifiers.count).map { count in
            UNNotificationCategory(
                identifier: "\(Self.defaultActionCategoryPrefix)\(count)",
                actions: Self.defaultActionIdentifiers
                    .prefix(count)
                    .enumerated()
                    .map { index, identifier in
                        makeAction(index, identifier)
                    },
                intentIdentifiers: [],
                options: []
            )
        }

        return Set([legacyCategory] + countSpecificCategories)
    }

    @objc func handleAppWillEnterForeground() {
        installNotificationCenterDelegate()
        updatePermissionStatusCache()
        flushPendingWork()
        reRegisterIfFingerprintChanged()
    }

    func installNotificationCenterDelegate() {
        guard !notificationCenterIntegrationDisabledForTesting else {
            return
        }

        UNUserNotificationCenter.current().delegate = self
    }
}
