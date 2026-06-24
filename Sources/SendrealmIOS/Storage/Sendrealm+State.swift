import Foundation

extension Sendrealm {
    func loadState() {
        let defaults = UserDefaults.standard
        appId = defaults.string(forKey: prefsKey("app_id"))
        baseUrl = defaults.string(forKey: prefsKey("base_url")) ?? defaultBaseUrl
        apiUrlSource = defaults.string(forKey: prefsKey("api_url_source")) ?? "default"
        deviceId = defaults.string(forKey: prefsKey("device_id"))
        externalUserId = defaults.string(forKey: prefsKey("external_user_id"))
        userEmail = defaults.string(forKey: prefsKey("user_email"))
        apnsToken = defaults.string(forKey: prefsKey("apns_token"))
        apnsEnvironment = defaults.string(forKey: prefsKey("apns_environment")) ?? defaultApnsEnvironment()
        lastPermissionStatus = defaults.string(forKey: prefsKey("permission_status")) ?? "not_determined"
        lastRegistrationFingerprint = defaults.string(forKey: prefsKey("registration_fingerprint"))
        subscribed = defaults.bool(forKey: prefsKey("subscribed"))
        suppressForegroundNotifications = defaults.bool(forKey: prefsKey("suppress_foreground_notifications"))
        foregroundBanner = foregroundBoolDefault("foreground_banner", defaultValue: true)
        foregroundList = foregroundBoolDefault("foreground_list", defaultValue: true)
        foregroundSound = foregroundBoolDefault("foreground_sound", defaultValue: true)
        foregroundBadge = foregroundBoolDefault("foreground_badge", defaultValue: true)
        initialized = !(appId ?? "").isEmpty
        lastInitResult = storedDictionary("last_init_result")
        lastRegisterResult = storedDictionary("last_register_result")
        lastSdkError = storedDictionary("last_sdk_error")
        lastNotificationPayload = storedDictionary("last_notification_payload") as NSDictionary?
        lastOpenPayload = storedDictionary("last_open_payload") as NSDictionary?
    }

    func persistState() {
        setDefaultString(appId, key: "app_id")
        setDefaultString(baseUrl, key: "base_url")
        setDefaultString(apiUrlSource, key: "api_url_source")
        setDefaultString(deviceId, key: "device_id")
        setDefaultString(externalUserId, key: "external_user_id")
        setDefaultString(userEmail, key: "user_email")
        setDefaultString(apnsToken, key: "apns_token")
        setDefaultString(apnsEnvironment, key: "apns_environment")
        setDefaultString(lastPermissionStatus, key: "permission_status")
        setDefaultString(lastRegistrationFingerprint, key: "registration_fingerprint")
        UserDefaults.standard.set(subscribed, forKey: prefsKey("subscribed"))
        UserDefaults.standard.set(suppressForegroundNotifications, forKey: prefsKey("suppress_foreground_notifications"))
        UserDefaults.standard.set(foregroundBanner, forKey: prefsKey("foreground_banner"))
        UserDefaults.standard.set(foregroundList, forKey: prefsKey("foreground_list"))
        UserDefaults.standard.set(foregroundSound, forKey: prefsKey("foreground_sound"))
        UserDefaults.standard.set(foregroundBadge, forKey: prefsKey("foreground_badge"))
        saveDictionary(lastInitResult, key: "last_init_result")
        saveDictionary(lastRegisterResult, key: "last_register_result")
        saveDictionary(lastSdkError, key: "last_sdk_error")
        saveDictionary(lastNotificationPayload as? [String: Any], key: "last_notification_payload")
        saveDictionary(lastOpenPayload as? [String: Any], key: "last_open_payload")
    }

    func setDefaultString(_ value: String?, key: String) {
        let defaultsKey = prefsKey(key)
        if let value, !value.isEmpty {
            UserDefaults.standard.set(value, forKey: defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }

    func prefsKey(_ key: String) -> String {
        "\(prefsName).\(key)"
    }

    func foregroundBoolDefault(_ key: String, defaultValue: Bool) -> Bool {
        let defaultsKey = prefsKey(key)
        guard UserDefaults.standard.object(forKey: defaultsKey) != nil else {
            return defaultValue
        }

        return UserDefaults.standard.bool(forKey: defaultsKey)
    }

    func storedDictionary(_ key: String) -> [String: Any]? {
        guard let data = UserDefaults.standard.data(forKey: prefsKey(key)),
              let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return dictionary
    }

    func saveDictionary(_ dictionary: [String: Any]?, key: String) {
        let defaultsKey = prefsKey(key)
        guard let dictionary, !dictionary.isEmpty else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return
        }

        UserDefaults.standard.set(try? JSONSerialization.data(withJSONObject: sanitizeJSON(dictionary)), forKey: defaultsKey)
    }

    func rememberInitResult(success: Bool, message: String? = nil) {
        lastInitResult = operationResult(success: success, message: message)
        if !success {
            setLastSdkError(code: "E_INIT_FAILED", message: message ?? "Failed to initialize device with push API")
        }
        persistState()
    }

    func rememberRegisterResult(success: Bool, message: String? = nil) {
        lastRegisterResult = operationResult(success: success, message: message)
        if !success {
            setLastSdkError(code: "E_REGISTER_FAILED", message: message ?? "Failed to register device with push API")
        }
        persistState()
    }

    func operationResult(success: Bool, message: String? = nil) -> [String: Any] {
        [
            "success": success,
            "message": message as Any? ?? NSNull(),
            "at": ISO8601DateFormatter().string(from: Date())
        ]
    }

    func setLastSdkError(code: String, message: String) {
        lastSdkError = [
            "code": code,
            "message": message,
            "at": ISO8601DateFormatter().string(from: Date())
        ]
        persistState()
    }

    func clearLastSdkError() {
        lastSdkError = nil
        persistState()
    }

    func defaultApnsEnvironment() -> String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
}
