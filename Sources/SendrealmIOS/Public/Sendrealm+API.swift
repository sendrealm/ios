import Foundation
import UIKit
import UserNotifications

public extension Sendrealm {
    @objc(handleOpenURL:)
    static func handleOpenURL(_ url: URL) -> Bool {
        shared.handleOpenURL(url)
    }

    @objc(handleOpenURL:)
    func handleOpenURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == "sendrealm",
              components.path == "/live-activity-action" || components.path == "/live-activity-open" else {
            return false
        }

        let queryItems = components.queryItems ?? []
        let queryValue: (String) -> String? = { name in
            self.normalizedString(queryItems.first { $0.name == name }?.value)
        }

        guard let targetURLString = queryValue("target_url"),
              let targetURL = URL(string: targetURLString) else {
            return false
        }

        let activityId = queryValue("activity_id")
        let sendId = queryValue("send_id")
        let actionId = queryValue("action_id")
        var properties: [String: Any] = [
            "launch_url": targetURL.absoluteString
        ]

        if let activityId {
            properties["activity_id"] = activityId
        }
        if let sendId {
            properties["send_id"] = sendId
        }
        if let actionId {
            properties["action_id"] = actionId
        }

        trackDeviceEvent(
            components.path == "/live-activity-action" ? "live_activity_action" : "live_activity_open",
            properties: properties,
            enqueueOnFailure: true,
            completion: nil
        )
        openLaunchUrl(targetURL.absoluteString)
        return true
    }

    @objc func initialize(_ options: NSDictionary, completion: @escaping (NSDictionary?, NSError?) -> Void) {
        guard let nextAppId = normalizedString(options["appId"]) else {
            completion(nil, error("E_INVALID_OPTIONS", "initialize() requires a non-empty appId"))
            return
        }

        appId = nextAppId
        let providedBaseUrl = normalizedString(options["baseUrl"])
        baseUrl = providedBaseUrl ?? baseUrl ?? defaultBaseUrl
        apiUrlSource = providedBaseUrl == nil ? (baseUrl == defaultBaseUrl ? "default" : "persisted") : "options"
        externalUserId = normalizedString(options["externalUserId"]) ?? externalUserId
        userEmail = normalizedString(options["userEmail"])?.lowercased()
        apnsEnvironment = normalizeApnsEnvironment(normalizedString(options["apnsEnvironment"]))
        environment = normalizePushEnvironment(normalizedString(options["environment"]))
        suppressForegroundNotifications = boolValue(options["suppressForegroundNotifications"]) ?? false
        applyForegroundPresentation(options["foregroundPresentation"] as? NSDictionary)
        initialized = true
        persistState()
        configure()
        updatePermissionStatusCache()

        let payload: [String: Any?] = baseDevicePayload(additional: [
            "device_id": deviceId as Any?,
            "environment": environment,
            "apns_environment": apnsEnvironment
        ])

        postJSON(path: "/v1/init", payload: payload) { [weak self] json, success in
            guard let self else { return }

            guard success else {
                let message = self.apiErrorMessage(
                    json,
                    fallback: "Failed to initialize device with push API"
                )
                self.rememberInitResult(success: false, message: message)
                completion(nil, self.error("E_INIT_FAILED", message))
                return
            }

            self.rememberInitResult(success: true)

            if
                let data = json?["data"] as? [String: Any],
                let nextDeviceId = self.normalizedString(data["device_id"] ?? data["deviceId"])
            {
                self.deviceId = nextDeviceId
                self.persistState()
                self.startLiveActivityTokenObserversIfAvailable()
                self.flushPendingLiveActivityTokenRegistrations()
            }

            if let token = self.apnsToken {
                self.registerAPNSToken(token, completion: nil)
            }

            let finish: (Bool) -> Void = { granted in
                completion([
                    "token": self.apnsToken as Any? ?? NSNull(),
                    "deviceId": self.deviceId as Any? ?? NSNull(),
                    "environment": self.environment,
                    "subscribed": self.subscribed,
                    "permissionGranted": granted
                ], nil)
            }

            if self.boolValue(options["autoRequestPermission"]) == true {
                self.requestPermission { granted, _ in
                    finish(granted?.boolValue ?? false)
                }
            } else {
                self.hasNotificationPermission { granted in
                    finish(granted)
                }
            }
        }
    }

    @objc func login(_ userId: String, email: String?, completion: @escaping (NSError?) -> Void) {
        guard let normalizedUserId = normalizedString(userId) else {
            completion(error("E_INVALID_USER_ID", "login() requires a non-empty userId"))
            return
        }

        externalUserId = normalizedUserId
        userEmail = normalizedString(email)?.lowercased()
        persistState()
        registerAPNSToken(apnsToken, completion: nil)
        completion(nil)
    }

    @objc func logout(_ completion: @escaping (NSError?) -> Void) {
        externalUserId = nil
        userEmail = nil
        persistState()
        registerAPNSToken(apnsToken, completion: nil)
        completion(nil)
    }

    @objc func requestPermission(_ completion: @escaping (NSNumber?, NSError?) -> Void) {
        if let status = notificationPermissionStatusForTesting {
            let granted = status == "authorized" || status == "provisional" || status == "ephemeral"
            lastPermissionStatus = status
            persistState()
            emitPermissionChanged(granted)
            trackDeviceEvent(granted ? "permission_granted" : "permission_denied", completion: nil)
            completion(NSNumber(value: granted), nil)
            return
        }

        let options: UNAuthorizationOptions = [.alert, .badge, .sound]
        let requestAuthorization =
            requestNotificationAuthorizationForTesting ??
            { options, completion in
                UNUserNotificationCenter.current().requestAuthorization(options: options, completionHandler: completion)
            }

        requestAuthorization(options) { [weak self] granted, requestError in
            guard let self else { return }

            if let requestError {
                DispatchQueue.main.async {
                    completion(nil, requestError as NSError)
                }
                return
            }

            DispatchQueue.main.async {
                if let registerForRemoteNotificationsForTesting = self.registerForRemoteNotificationsForTesting {
                    registerForRemoteNotificationsForTesting()
                } else {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }

            self.updatePermissionStatusCache()
            self.emitPermissionChanged(granted)
            self.trackDeviceEvent(granted ? "permission_granted" : "permission_denied", completion: nil)
            completion(NSNumber(value: granted), nil)
        }
    }

    @objc func getPermissionStatus(_ completion: @escaping (NSString) -> Void) {
        if let status = notificationPermissionStatusForTesting {
            lastPermissionStatus = status
            persistState()
            completion(status as NSString)
            return
        }

        if let notificationAuthorizationStatusForTesting {
            notificationAuthorizationStatusForTesting { [weak self] authorizationStatus in
                let status = self?.permissionStatusString(authorizationStatus) ?? "not_determined"
                self?.lastPermissionStatus = status
                self?.persistState()
                DispatchQueue.main.async {
                    completion(status as NSString)
                }
            }
            return
        }

        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let status = self?.permissionStatusString(settings.authorizationStatus) ?? "not_determined"
            self?.lastPermissionStatus = status
            self?.persistState()
            DispatchQueue.main.async {
                completion(status as NSString)
            }
        }
    }

    @objc func openNotificationSettings(_ completion: @escaping (NSNumber) -> Void) {
        if applicationIntegrationDisabledForTesting {
            completion(NSNumber(value: false))
            return
        }

        DispatchQueue.main.async {
            let url: URL?
            if #available(iOS 16.0, *) {
                url = URL(string: UIApplication.openNotificationSettingsURLString)
            } else {
                url = URL(string: UIApplication.openSettingsURLString)
            }

            guard let url else {
                completion(NSNumber(value: false))
                return
            }

            if let openURLForTesting = self.openURLForTesting {
                openURLForTesting(url) { opened in
                    completion(NSNumber(value: opened))
                }
                return
            }

            UIApplication.shared.open(url, options: [:]) { opened in
                completion(NSNumber(value: opened))
            }
        }
    }

    @objc func setBadgeCount(_ count: NSNumber, completion: @escaping (NSNumber) -> Void) {
        let nextCount = max(0, count.intValue)
        if applicationIntegrationDisabledForTesting {
            completion(NSNumber(value: nextCount >= 0))
            return
        }

        DispatchQueue.main.async {
            if let setBadgeCountForTesting = self.setBadgeCountForTesting {
                setBadgeCountForTesting(nextCount) { error in
                    DispatchQueue.main.async {
                        completion(NSNumber(value: error == nil))
                    }
                }
                return
            }

            if #available(iOS 16.0, *) {
                UNUserNotificationCenter.current().setBadgeCount(nextCount) { error in
                    DispatchQueue.main.async {
                        completion(NSNumber(value: error == nil))
                    }
                }
            } else {
                UIApplication.shared.applicationIconBadgeNumber = nextCount
                completion(NSNumber(value: true))
            }
        }
    }

    @objc func clearBadge(_ completion: @escaping (NSNumber) -> Void) {
        setBadgeCount(0, completion: completion)
    }

    @objc func setForegroundPresentation(_ options: NSDictionary, completion: @escaping (NSNumber) -> Void) {
        applyForegroundPresentation(options)
        persistState()
        completion(NSNumber(value: true))
    }

    @objc func hasNotificationPermission(_ completion: @escaping (Bool) -> Void) {
        if let status = notificationPermissionStatusForTesting {
            let granted = status == "authorized" || status == "provisional" || status == "ephemeral"
            lastPermissionStatus = status
            persistState()
            completion(granted)
            return
        }

        if let notificationAuthorizationStatusForTesting {
            notificationAuthorizationStatusForTesting { [weak self] authorizationStatus in
                var granted =
                    authorizationStatus == .authorized ||
                    authorizationStatus == .provisional

                if #available(iOS 14.0, *) {
                    granted = granted || authorizationStatus == .ephemeral
                }

                self?.lastPermissionStatus = self?.permissionStatusString(authorizationStatus) ?? "not_determined"
                self?.persistState()
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
            return
        }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            var granted =
                settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional

            if #available(iOS 14.0, *) {
                granted = granted || settings.authorizationStatus == .ephemeral
            }

            self.lastPermissionStatus = self.permissionStatusString(settings.authorizationStatus)
            self.persistState()
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    @objc func getDeviceId(_ completion: @escaping (NSString?) -> Void) {
        completion(deviceId as NSString?)
    }

    @objc func isSubscribed(_ completion: @escaping (NSNumber) -> Void) {
        completion(NSNumber(value: subscribed))
    }

    @objc func getState(_ completion: @escaping (NSDictionary) -> Void) {
        hasNotificationPermission { [weak self] granted in
            guard let self else { return }
            let registered = !(self.deviceId ?? "").isEmpty && !(self.apnsToken ?? "").isEmpty
            completion([
                "initialized": self.initialized,
                "registered": registered,
                "permissionGranted": granted,
                "subscribed": self.subscribed,
                "deviceId": self.deviceId as Any? ?? NSNull(),
                "registrationToken": self.apnsToken as Any? ?? NSNull(),
                "tokenStatus": registered ? (self.subscribed ? "registered" : "unsubscribed") : "missing",
                "externalUserId": self.externalUserId as Any? ?? NSNull(),
                "userEmail": self.userEmail as Any? ?? NSNull(),
                "platform": "ios",
                "sdkVersion": self.sdkVersion,
                "environment": self.environment,
                "apnsEnvironment": self.apnsEnvironment,
                "liveActivity": self.liveActivityDiagnostics()
            ])
        }
    }

    @objc func getDiagnostics(_ completion: @escaping (NSDictionary) -> Void) {
        getPermissionStatus { [weak self] status in
            guard let self else { return }
            completion([
                "appId": self.appId as Any? ?? NSNull(),
                "apiUrl": self.baseUrl as Any? ?? NSNull(),
                "apiUrlSource": self.apiUrlSource,
                "sdkVersion": self.sdkVersion,
                "platform": "ios",
                "environment": self.environment,
                "deviceId": self.deviceId as Any? ?? NSNull(),
                "registrationTokenPresent": !(self.apnsToken ?? "").isEmpty,
                "permissionStatus": status,
                "subscribed": self.subscribed,
                "apnsEnvironment": self.apnsEnvironment,
                "appVersion": self.appVersion() as Any? ?? NSNull(),
                "deviceModel": UIDevice.current.model,
                "osVersion": UIDevice.current.systemVersion,
                "locale": Locale.current.identifier,
                "timezone": TimeZone.current.identifier,
                "lastInitResult": self.lastInitResult as Any? ?? NSNull(),
                "lastRegisterResult": self.lastRegisterResult as Any? ?? NSNull(),
                "lastSdkError": self.lastSdkError as Any? ?? NSNull(),
                "queueCounts": self.queueCounts(),
                "liveActivity": self.liveActivityDiagnostics(),
                "lastNotificationPayload": self.lastNotificationPayload as Any? ?? NSNull(),
                "lastOpenPayload": self.lastOpenPayload as Any? ?? NSNull(),
                "foregroundPresentation": self.foregroundPresentationDiagnostics()
            ])
        }
    }

    @objc func refreshRegistrationToken(_ forceRefresh: Bool, completion: @escaping (NSString?) -> Void) {
        if !applicationIntegrationDisabledForTesting {
            DispatchQueue.main.async {
                if let registerForRemoteNotificationsForTesting = self.registerForRemoteNotificationsForTesting {
                    registerForRemoteNotificationsForTesting()
                } else {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }

        guard let token = apnsToken else {
            completion(nil)
            return
        }

        registerAPNSToken(token) { success in
            completion(success ? token as NSString : nil)
        }
    }

    @objc func setAPNSToken(_ token: String, completion: @escaping (NSString?, NSError?) -> Void) {
        guard let normalizedToken = normalizedString(token) else {
            completion(nil, error("E_INVALID_APNS_TOKEN", "setAPNSToken() requires a non-empty token"))
            return
        }

        handleAPNSToken(normalizedToken)
        completion(normalizedToken as NSString, nil)
    }

    @objc func optIn(_ completion: @escaping (NSNumber) -> Void) {
        subscribed = true
        persistState()

        if let token = apnsToken {
            registerAPNSToken(token) { [weak self] success in
                self?.emitSubscriptionChanged(true)
                completion(NSNumber(value: success))
            }
            return
        }

        updateSubscription(true) { [weak self] success in
            self?.emitSubscriptionChanged(true)
            completion(NSNumber(value: success))
        }
    }

    @objc func optOut(_ completion: @escaping (NSNumber) -> Void) {
        subscribed = false
        persistState()
        updateSubscription(false) { [weak self] success in
            self?.emitSubscriptionChanged(false)
            completion(NSNumber(value: success))
        }
    }

    @objc func addTag(_ key: String, value: Any?, completion: @escaping (NSNumber, NSError?) -> Void) {
        guard let normalizedKey = normalizedString(key) else {
            completion(NSNumber(value: false), error("E_INVALID_TAG", "addTag() requires a non-empty key"))
            return
        }

        addTags([normalizedKey: value ?? NSNull()], completion: completion)
    }

    @objc func addTags(_ tags: NSDictionary, completion: @escaping (NSNumber, NSError?) -> Void) {
        guard tags.count > 0 else {
            completion(NSNumber(value: false), nil)
            return
        }

        updateTags(tags as? [String: Any] ?? [:]) { [weak self] success in
            if !success {
                self?.enqueueTags(tags as? [String: Any] ?? [:])
            }

            completion(NSNumber(value: true), nil)
        }
    }

    @objc func removeTag(_ key: String, completion: @escaping (NSNumber) -> Void) {
        guard let normalizedKey = normalizedString(key) else {
            completion(NSNumber(value: false))
            return
        }

        addTags([normalizedKey: NSNull()]) { success, _ in
            completion(success)
        }
    }

    @objc func trackEvent(_ eventType: String, properties: NSDictionary?, completion: @escaping (NSNumber, NSError?) -> Void) {
        guard let normalizedEventType = normalizedString(eventType) else {
            completion(NSNumber(value: false), error("E_INVALID_EVENT_TYPE", "trackEvent() requires a non-empty eventType"))
            return
        }

        trackDeviceEvent(normalizedEventType, properties: properties as? [String: Any]) { [weak self] success in
            if !success {
                self?.enqueueEvent(eventType: normalizedEventType, properties: properties as? [String: Any])
            }

            completion(NSNumber(value: true), nil)
        }
    }

    @objc func registerLiveActivityToken(_ token: String, activityId: String?, tokenType: String?, completion: @escaping (NSNumber, NSError?) -> Void) {
        registerLiveActivityToken(
            token,
            activityId: activityId,
            tokenType: tokenType,
            activityType: nil,
            attributesType: nil,
            sendId: nil,
            completion: completion
        )
    }

    @objc func registerLiveActivityToken(_ token: String, activityId: String?, tokenType: String?, activityType: String?, attributesType: String?, completion: @escaping (NSNumber, NSError?) -> Void) {
        registerLiveActivityToken(
            token,
            activityId: activityId,
            tokenType: tokenType,
            activityType: activityType,
            attributesType: attributesType,
            sendId: nil,
            completion: completion
        )
    }

    func registerLiveActivityToken(
        _ token: String,
        activityId: String?,
        tokenType: String?,
        activityType: String? = nil,
        attributesType: String? = nil,
        sendId: String?,
        completion: @escaping (NSNumber, NSError?) -> Void
    ) {
        guard let normalizedToken = normalizedString(token) else {
            completion(NSNumber(value: false), error("E_INVALID_LIVE_ACTIVITY_TOKEN", "registerLiveActivityToken() requires a non-empty token"))
            return
        }

        let normalizedTokenType = normalizedString(tokenType) ?? "ios_update"
        let normalizedActivityId = normalizedString(activityId)
        let normalizedActivityType = normalizedString(activityType)
        let normalizedAttributesType =
            normalizedString(attributesType) ?? normalizedActivityType
        let normalizedSendId = normalizedString(sendId)

        guard let deviceId else {
            enqueuePendingLiveActivityTokenRegistration(
                token: normalizedToken,
                activityId: normalizedActivityId,
                tokenType: normalizedTokenType,
                activityType: normalizedActivityType,
                attributesType: normalizedAttributesType,
                sendId: normalizedSendId
            )
            completion(NSNumber(value: false), error("E_DEVICE_NOT_READY", "Device must be initialized before registering Live Activity tokens"))
            return
        }

        let payload = baseDevicePayload(additional: [
            "device_id": deviceId,
            "token": normalizedToken,
            "token_type": normalizedTokenType,
            "activity_id": normalizedActivityId as Any?,
            "activity_type": normalizedActivityType as Any?,
            "attributes_type": normalizedAttributesType as Any?,
            "send_id": normalizedSendId as Any?
        ])

        liveActivityLastTokenType = normalizedTokenType
        liveActivityTokenRegistrationAttempts += 1
        updateLiveActivityStatus("live_activity_token_registering")

        postJSON(path: "/v1/live-activities/tokens", payload: payload) { [weak self] json, success in
            if success {
                self?.liveActivityTokenRegistrationSuccesses += 1
                self?.updateLiveActivityStatus("live_activity_token_registered")
                self?.rememberLiveActivityTokenRegistration(
                    token: normalizedToken,
                    activityId: normalizedActivityId,
                    tokenType: normalizedTokenType,
                    activityType: normalizedActivityType,
                    attributesType: normalizedAttributesType,
                    sendId: normalizedSendId
                )
            } else {
                self?.liveActivityTokenRegistrationFailures += 1
                let message = self?.apiErrorMessage(
                    json,
                    fallback: "Failed to register Live Activity token"
                ) ?? "Failed to register Live Activity token"
                self?.updateLiveActivityStatus(
                    "live_activity_token_registration_failed",
                    error: message
                )
                self?.enqueueOperation(
                    name: "live_activity_token_\(normalizedTokenType)",
                    path: "/v1/live-activities/tokens",
                    payload: payload
                )
                self?.setLastSdkError(
                    code: "E_LIVE_ACTIVITY_TOKEN_SYNC_FAILED",
                    message: message
                )
            }

            completion(NSNumber(value: success), nil)
        }
    }

    @objc func deleteLiveActivityToken(_ token: String, activityId: String?, tokenType: String?, completion: @escaping (NSNumber, NSError?) -> Void) {
        deleteLiveActivityToken(
            token,
            activityId: activityId,
            tokenType: tokenType,
            activityType: nil,
            attributesType: nil,
            completion: completion
        )
    }

    @objc func deleteLiveActivityToken(_ token: String, activityId: String?, tokenType: String?, activityType: String?, attributesType: String?, completion: @escaping (NSNumber, NSError?) -> Void) {
        guard let normalizedToken = normalizedString(token) else {
            completion(NSNumber(value: false), error("E_INVALID_LIVE_ACTIVITY_TOKEN", "deleteLiveActivityToken() requires a non-empty token"))
            return
        }

        guard let deviceId else {
            completion(NSNumber(value: false), error("E_DEVICE_NOT_READY", "Device must be initialized before deleting Live Activity tokens"))
            return
        }

        let normalizedActivityType = normalizedString(activityType)
        let normalizedAttributesType =
            normalizedString(attributesType) ?? normalizedActivityType
        let payload = baseDevicePayload(additional: [
            "device_id": deviceId,
            "token": normalizedToken,
            "token_type": normalizedString(tokenType) ?? "ios_update",
            "activity_id": normalizedString(activityId) as Any?,
            "activity_type": normalizedActivityType as Any?,
            "attributes_type": normalizedAttributesType as Any?
        ])

        postJSON(path: "/v1/live-activities/tokens", payload: payload, method: "DELETE") { _, success in
            completion(NSNumber(value: success), nil)
        }
    }

    @objc func syncLiveActivityTokens(_ completion: @escaping (NSNumber) -> Void) {
        startLiveActivityTokenObserversIfAvailable()
        flushPendingLiveActivityTokenRegistrations()
        trackLiveActivityDiagnosticsSoon()
        completion(NSNumber(value: true))
    }

    @objc func getInitialNotification(_ completion: @escaping (NSDictionary?) -> Void) {
        let notification = initialNotification
        initialNotification = nil
        completion(notification)
    }

    func notificationEvent(from userInfo: NSDictionary) -> NSDictionary {
        notificationMap(from: userInfo, isForeground: UIApplication.shared.applicationState == .active)
    }
}
