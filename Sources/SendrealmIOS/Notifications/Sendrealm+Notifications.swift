import Foundation
import UIKit
import UserNotifications

extension Sendrealm {
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        handleForegroundNotificationUserInfo(
            notification.request.content.userInfo as NSDictionary,
            isForeground: true,
            withCompletionHandler: completionHandler
        )
    }

    func handleForegroundNotificationUserInfo(
        _ userInfo: NSDictionary,
        isForeground: Bool,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let event = notificationMap(
            from: userInfo,
            isForeground: isForeground
        )
        lastNotificationPayload = event
        persistState()
        let notificationId = normalizedString(event["notificationId"])

        if let notificationId {
            trackDeviceEvent("delivery", notificationId: notificationId, enqueueOnFailure: true, completion: nil)
            trackDeviceEvent("foreground_display", notificationId: notificationId, enqueueOnFailure: true, completion: nil)
        }

        emitEvent(Sendrealm.eventForegroundNotification, body: event)

        if suppressForegroundNotifications || (!foregroundBanner && !foregroundList && !foregroundSound && !foregroundBadge) {
            completionHandler([])
            return
        }

        if #available(iOS 14.0, *) {
            var options: UNNotificationPresentationOptions = []
            if foregroundBanner {
                options.insert(.banner)
            }
            if foregroundList {
                options.insert(.list)
            }
            if foregroundSound {
                options.insert(.sound)
            }
            if foregroundBadge {
                options.insert(.badge)
            }
            completionHandler(options)
        } else {
            var options: UNNotificationPresentationOptions = []
            if foregroundBanner || foregroundList {
                options.insert(.alert)
            }
            if foregroundSound {
                options.insert(.sound)
            }
            if foregroundBadge {
                options.insert(.badge)
            }
            completionHandler(options)
        }
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleNotificationResponseUserInfo(
            response.notification.request.content.userInfo as NSDictionary,
            isForeground: UIApplication.shared.applicationState == .active,
            actionIdentifier: response.actionIdentifier,
            withCompletionHandler: completionHandler
        )
    }

    func handleNotificationResponseUserInfo(
        _ userInfo: NSDictionary,
        isForeground: Bool,
        actionIdentifier: String,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let event = notificationMap(
            from: userInfo,
            isForeground: isForeground,
            actionIdentifier: actionIdentifier
        )
        let notificationId = normalizedString(event["notificationId"])
        let launchUrl = normalizedString(event["launchUrl"])
        let actionIdentifier = normalizedString(event["actionIdentifier"])
        let isDismiss = actionIdentifier == UNNotificationDismissActionIdentifier
        let isDefault = actionIdentifier == UNNotificationDefaultActionIdentifier
        let isDuplicate = isDuplicateOpen(event)

        if let notificationId, !isDuplicate {
            trackDeviceEvent("open", notificationId: notificationId, enqueueOnFailure: true, completion: nil)
            if !isDismiss {
                let clickProperties: [String: Any]? = actionIdentifier.map { ["action_id": $0] }
                trackDeviceEvent("click", notificationId: notificationId, properties: clickProperties, enqueueOnFailure: true, completion: nil)
            }
            if isDismiss {
                trackDeviceEvent("dismiss", notificationId: notificationId, enqueueOnFailure: true, completion: nil)
            } else if !isDefault, actionIdentifier != nil {
                trackDeviceEvent("notification_action", properties: [
                    "notification_id": notificationId,
                    "action_id": actionIdentifier as Any
                ], enqueueOnFailure: true, completion: nil)
            }
        }

        if !isDuplicate,
           let payload = event["payload"] as? NSDictionary,
           let liveActivity = payload["liveActivity"] as? NSDictionary,
           let activityId = normalizedString(liveActivity["activityId"]) {
            var properties: [String: Any] = [
                "activity_id": activityId
            ]
            let metadata = payload["metadata"] as? NSDictionary
            let sendId =
                normalizedString(metadata?["sendId"]) ??
                normalizedString(metadata?["send_id"]) ??
                normalizedString(liveActivity["sendId"]) ??
                normalizedString(liveActivity["send_id"])

            if let actionIdentifier {
                properties["action_id"] = actionIdentifier
            }
            if let sendId {
                properties["send_id"] = sendId
            }

            let liveActivityEvent =
                isDismiss
                    ? "live_activity_dismiss"
                    : (isDefault ? "live_activity_open" : "live_activity_action")
            trackDeviceEvent(liveActivityEvent, properties: properties, enqueueOnFailure: true, completion: nil)
        }

        initialNotification = event
        lastOpenPayload = event
        persistState()
        emitEvent(Sendrealm.eventNotificationClicked, body: event)
        if !isDefault, !isDismiss {
            emitEvent(Sendrealm.eventNotificationAction, body: event)
        }
        openLaunchUrl(launchUrl)
        completionHandler()
    }

    func handleAPNSToken(_ token: String) {
        apnsToken = token
        subscribed = true
        persistState()
        emitEvent(Sendrealm.eventSubscriptionChanged, body: [
            "subscribed": true,
            "registrationToken": token
        ])
        registerAPNSToken(token, completion: nil)
    }

    func handleNotificationUserInfo(_ userInfo: NSDictionary, opened: Bool) {
        let event = notificationMap(
            from: userInfo,
            isForeground: UIApplication.shared.applicationState == .active
        )
        lastNotificationPayload = event
        persistState()
        let notificationId = normalizedString(event["notificationId"])

        if let notificationId {
            trackDeviceEvent(opened ? "open" : "delivery", notificationId: notificationId, enqueueOnFailure: true, completion: nil)
        }

        if isSilentPush(userInfo) && !opened {
            emitEvent(Sendrealm.eventSilentNotification, body: event)
            trackDeviceEvent("background_notification_received", properties: [
                "silent": true
            ], enqueueOnFailure: true, completion: nil)
            return
        }

        if opened {
            initialNotification = event
            lastOpenPayload = event
            persistState()
            emitEvent(Sendrealm.eventNotificationClicked, body: event)
        } else {
            emitEvent(Sendrealm.eventForegroundNotification, body: event)
        }
    }

    func notificationMap(
        from userInfo: NSDictionary,
        isForeground: Bool,
        actionIdentifier: String? = nil
    ) -> NSDictionary {
        let payload = normalizedPayload(from: userInfo)
        let metadata = payload["metadata"] as? [String: Any] ?? [:]
        let resolvedAction = notificationAction(
            from: payload,
            actionIdentifier: actionIdentifier
        )
        let resolvedActionIdentifier =
            normalizedString(resolvedAction?["id"]) ??
            normalizedString(actionIdentifier)
        let notificationId =
            normalizedString(metadata["notificationId"]) ??
            normalizedString(metadata["notification_id"]) ??
            normalizedString(userInfo["notification_id"]) ??
            normalizedString(userInfo["notificationId"])
        let deliveryId =
            normalizedString(metadata["deliveryId"]) ??
            normalizedString(metadata["delivery_id"]) ??
            normalizedString(userInfo["delivery_id"]) ??
            normalizedString(userInfo["deliveryId"])
        let clickId =
            normalizedString(metadata["clickId"]) ??
            normalizedString(metadata["click_id"]) ??
            normalizedString(userInfo["click_id"]) ??
            normalizedString(userInfo["clickId"])
        let launchUrl =
            normalizedString(resolvedAction?["launchUrl"]) ??
            normalizedString(resolvedAction?["launch_url"]) ??
            normalizedString(metadata["iosLaunchUrl"]) ??
            normalizedString(metadata["ios_launch_url"]) ??
            normalizedString(metadata["launch_url"]) ??
            normalizedString(userInfo["ios_launch_url"]) ??
            normalizedString(userInfo["launch_url"]) ??
            normalizedString(userInfo["url"])
        let rawPayload = jsonString(payload)

        return [
            "notificationId": notificationId as Any? ?? NSNull(),
            "deliveryId": deliveryId as Any? ?? NSNull(),
            "clickId": clickId as Any? ?? NSNull(),
            "launchUrl": launchUrl as Any? ?? NSNull(),
            "actionIdentifier": resolvedActionIdentifier as Any? ?? NSNull(),
            "rawActionIdentifier": actionIdentifier as Any? ?? NSNull(),
            "action": resolvedAction.map { sanitizeJSON($0) } as Any? ?? NSNull(),
            "rawPayload": rawPayload as Any? ?? NSNull(),
            "payload": sanitizeJSON(payload),
            "rawUserInfo": sanitizeJSON(userInfo as? [String: Any] ?? [:]),
            "isForeground": isForeground,
            "isSilent": isSilentPush(userInfo),
            "preventedDefault": suppressForegroundNotifications
        ]
    }

    func notificationAction(
        from payload: [String: Any],
        actionIdentifier: String?
    ) -> [String: Any]? {
        guard let actionIdentifier = normalizedString(actionIdentifier) else {
            return nil
        }

        let actions =
            (payload["actions"] as? [[String: Any]]) ??
            ((payload["liveActivity"] as? [String: Any])?["buttons"] as? [[String: Any]]) ??
            ((payload["live_activity"] as? [String: Any])?["buttons"] as? [[String: Any]]) ??
            []

        if let index = Self.defaultActionIdentifiers.firstIndex(of: actionIdentifier),
           actions.indices.contains(index) {
            return actions[index]
        }

        return actions.first { normalizedString($0["id"]) == actionIdentifier }
    }

    func normalizedActionPayloads(_ value: Any?) -> [[String: Any]]? {
        let actions: [[String: Any]]

        if let typedActions = value as? [[String: Any]] {
            actions = typedActions
        } else if let dictionaries = value as? [NSDictionary] {
            actions = dictionaries.compactMap { $0 as? [String: Any] }
        } else {
            return nil
        }

        return actions.map { action in
            var nextAction = action

            if let value = nextAction["launch_url"], nextAction["launchUrl"] == nil {
                nextAction["launchUrl"] = value
            }
            if let value = nextAction["text"], nextAction["title"] == nil {
                nextAction["title"] = value
            }

            return nextAction
        }
    }

    func normalizedPayload(from userInfo: NSDictionary) -> [String: Any] {
        let rawPayload = userInfo["sendrealm_v1"]
        var payload: [String: Any] = [:]

        if let rawPayload = rawPayload as? String,
           let data = rawPayload.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload = parsed
        } else if let rawPayload = rawPayload as? [String: Any] {
            payload = rawPayload
        } else {
            payload = userInfo as? [String: Any] ?? [:]
        }

        let aps = userInfo["aps"] as? [String: Any] ?? [:]
        let alert = aps["alert"]
        let alertDictionary = alert as? [String: Any]
        let alertTitle = normalizedString(alertDictionary?["title"])
        let alertBody =
            normalizedString(alertDictionary?["body"]) ??
            (alert as? String)

        var notification = payload["notification"] as? [String: Any] ?? [:]
        notification["title"] =
            normalizedString(notification["title"]) ??
            alertTitle ??
            ""
        notification["body"] =
            normalizedString(notification["body"]) ??
            alertBody ??
            ""

        var ios = notification["ios"] as? [String: Any] ?? [:]
        if ios["sound"] == nil, let sound = aps["sound"] {
            ios["sound"] = sound
        }
        if ios["badge"] == nil, let badge = aps["badge"] {
            ios["badge"] = badge
        }
        notification["ios"] = ios
        payload["notification"] = notification

        var metadata = payload["metadata"] as? [String: Any] ?? [:]
        if let value = metadata["notification_id"], metadata["notificationId"] == nil {
            metadata["notificationId"] = value
        }
        if let value = metadata["ios_launch_url"], metadata["iosLaunchUrl"] == nil {
            metadata["iosLaunchUrl"] = value
        }
        if let value = metadata["image_url"], metadata["imageUrl"] == nil {
            metadata["imageUrl"] = value
        }
        if let value = metadata["delivery_id"], metadata["deliveryId"] == nil {
            metadata["deliveryId"] = value
        }
        if let value = metadata["click_id"], metadata["clickId"] == nil {
            metadata["clickId"] = value
        }
        if let value = metadata["send_id"], metadata["sendId"] == nil {
            metadata["sendId"] = value
        }
        payload["metadata"] = metadata

        if let actions = normalizedActionPayloads(payload["actions"]) {
            payload["actions"] = actions
        }

        if let rawLiveActivity = payload["live_activity"] as? [String: Any] {
            var liveActivity = rawLiveActivity
            if let value = liveActivity["activity_id"], liveActivity["activityId"] == nil {
                liveActivity["activityId"] = value
            }
            if let value = liveActivity["image_url"], liveActivity["imageUrl"] == nil {
                liveActivity["imageUrl"] = value
            }
            if let value = liveActivity["accent_color"], liveActivity["accentColor"] == nil {
                liveActivity["accentColor"] = value
            }
            if let value = liveActivity["launch_url"], liveActivity["launchUrl"] == nil {
                liveActivity["launchUrl"] = value
            }
            if let value = liveActivity["send_id"], liveActivity["sendId"] == nil {
                liveActivity["sendId"] = value
            }
            if let buttons = normalizedActionPayloads(liveActivity["buttons"]) {
                liveActivity["buttons"] = buttons
            }
            payload["liveActivity"] = liveActivity
        }

        if payload["data"] == nil {
            payload["data"] = [:]
        }

        return payload
    }

    func openLaunchUrl(_ launchUrl: String?) {
        guard let launchUrl, let url = URL(string: launchUrl) else {
            return
        }

        guard !applicationIntegrationDisabledForTesting else {
            return
        }

        DispatchQueue.main.async {
            if let openURLForTesting = self.openURLForTesting {
                openURLForTesting(url) { _ in }
            } else {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }

    func emitPermissionChanged(_ granted: Bool) {
        emitEvent(Sendrealm.eventPermissionChanged, body: ["granted": granted])
    }

    func emitSubscriptionChanged(_ nextSubscribed: Bool) {
        emitEvent(Sendrealm.eventSubscriptionChanged, body: ["subscribed": nextSubscribed])
    }

    func emitEvent(_ name: String, body: NSDictionary) {
        delegate?.sendrealm(self, didReceiveEvent: name, body: body)
    }

    func emitEvent(_ name: String, body: [String: Any]) {
        emitEvent(name, body: body as NSDictionary)
    }

    func isSilentPush(_ userInfo: NSDictionary) -> Bool {
        guard let aps = userInfo["aps"] as? [String: Any] else {
            return false
        }

        let contentAvailableNumber = aps["content-available"] as? NSNumber
        let contentAvailableInt = aps["content-available"] as? Int
        return (contentAvailableNumber?.intValue == 1 || contentAvailableInt == 1) && aps["alert"] == nil
    }

    func isDuplicateOpen(_ event: NSDictionary) -> Bool {
        let key =
            normalizedString(event["clickId"]) ??
            normalizedString(event["notificationId"]) ??
            normalizedString(event["rawPayload"])

        guard let key else {
            return false
        }

        let now = Date().timeIntervalSince1970
        var recent = recentOpenKeys().filter { now - $0.value < 300 }

        if recent[key] != nil {
            saveRecentOpenKeys(recent)
            return true
        }

        recent[key] = now
        saveRecentOpenKeys(recent)
        return false
    }

    func recentOpenKeys() -> [String: Double] {
        guard let data = UserDefaults.standard.data(forKey: prefsKey("recent_open_keys")),
              let keys = try? JSONSerialization.jsonObject(with: data) as? [String: Double] else {
            return [:]
        }

        return keys
    }

    func saveRecentOpenKeys(_ keys: [String: Double]) {
        let trimmedPairs = Array(keys.sorted { $0.value > $1.value }.prefix(50))
        let trimmed = Dictionary(uniqueKeysWithValues: trimmedPairs)
        UserDefaults.standard.set(try? JSONSerialization.data(withJSONObject: trimmed), forKey: prefsKey("recent_open_keys"))
    }
}
