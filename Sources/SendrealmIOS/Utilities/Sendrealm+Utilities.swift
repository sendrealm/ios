import Foundation
import UserNotifications

extension Sendrealm {
    func normalizedString(_ value: Any?) -> String? {
        guard let value = value as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func normalizeApnsEnvironment(_ value: String?) -> String {
        if value == "sandbox" || value == "development" {
            return "sandbox"
        }

        if value == "production" {
            return "production"
        }

        return defaultApnsEnvironment()
    }

    func permissionStatusString(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "not_determined"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        case .provisional:
            return "provisional"
        case .ephemeral:
            return "ephemeral"
        @unknown default:
            return "unknown"
        }
    }

    func updatePermissionStatusCache() {
        if let status = notificationPermissionStatusForTesting {
            lastPermissionStatus = status
            persistState()
            return
        }

        if let notificationAuthorizationStatusForTesting {
            notificationAuthorizationStatusForTesting { [weak self] authorizationStatus in
                guard let self else {
                    return
                }

                self.lastPermissionStatus = self.permissionStatusString(authorizationStatus)
                self.persistState()
            }
            return
        }

        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let self else {
                return
            }

            self.lastPermissionStatus = self.permissionStatusString(settings.authorizationStatus)
            self.persistState()
        }
    }

    func applyForegroundPresentation(_ options: NSDictionary?) {
        guard let options else {
            return
        }

        if boolValue(options["suppress"]) == true || boolValue(options["display"]) == false {
            suppressForegroundNotifications = true
            foregroundBanner = false
            foregroundList = false
            foregroundSound = false
            foregroundBadge = false
            return
        }

        suppressForegroundNotifications = false
        foregroundBanner = boolValue(options["banner"]) ?? foregroundBanner
        foregroundList = boolValue(options["list"]) ?? foregroundList
        foregroundSound = boolValue(options["sound"]) ?? foregroundSound
        foregroundBadge = boolValue(options["badge"]) ?? foregroundBadge
    }

    func foregroundPresentationDiagnostics() -> [String: Bool] {
        [
            "banner": foregroundBanner,
            "list": foregroundList,
            "sound": foregroundSound,
            "badge": foregroundBadge,
            "suppress": suppressForegroundNotifications
        ]
    }

    func registrationFingerprint() -> String {
        jsonString([
            "appId": appId as Any? ?? "",
            "token": apnsToken as Any? ?? "",
            "appVersion": appVersion() as Any? ?? "",
            "sdkVersion": sdkVersion,
            "externalUserId": externalUserId as Any? ?? "",
            "userEmail": userEmail as Any? ?? "",
            "apnsEnvironment": apnsEnvironment,
            "subscribed": subscribed,
            "permissionStatus": lastPermissionStatus
        ]) ?? UUID().uuidString
    }

    func reRegisterIfFingerprintChanged() {
        guard initialized, let apnsToken, !apnsToken.isEmpty else {
            return
        }

        let nextFingerprint = registrationFingerprint()
        guard nextFingerprint != lastRegistrationFingerprint else {
            return
        }

        registerAPNSToken(apnsToken, completion: nil)
    }

    func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }

        if let value = value as? NSNumber {
            return value.boolValue
        }

        return nil
    }

    func sanitizeJSON(_ value: Any?) -> Any {
        switch value {
        case nil:
            return NSNull()
        case let dictionary as [String: Any?]:
            var result: [String: Any] = [:]
            dictionary.forEach { key, value in
                guard let value else {
                    return
                }
                result[key] = sanitizeJSON(value)
            }
            return result
        case let dictionary as [String: Any]:
            var result: [String: Any] = [:]
            dictionary.forEach { key, value in
                result[key] = sanitizeJSON(value)
            }
            return result
        case let array as [Any?]:
            return array.map { sanitizeJSON($0) }
        case let array as [Any]:
            return array.map { sanitizeJSON($0) }
        case let value as NSString:
            return value
        case let value as NSNumber:
            return value
        case let value as NSNull:
            return value
        case let value as String:
            return value
        case let value as Bool:
            return value
        case let value as Int:
            return value
        case let value as Double:
            return value
        case let value as Float:
            return value
        default:
            return String(describing: value!)
        }
    }

    func jsonString(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(sanitizeJSON(value)),
              let data = try? JSONSerialization.data(withJSONObject: sanitizeJSON(value)),
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }

        return raw
    }

    func apiErrorMessage(_ json: [String: Any]?, fallback: String) -> String {
        guard let error = json?["error"] as? [String: Any] else {
            return fallback
        }

        var parts: [String] = []

        if let code = normalizedString(error["code"]) {
            parts.append(code)
        }

        if let message = normalizedString(error["message"]) {
            parts.append(message)
        }

        if
            let details = error["details"] as? [[String: Any]]
        {
            let detailMessage = details
                .compactMap { normalizedString($0["message"]) }
                .joined(separator: "; ")

            if !detailMessage.isEmpty {
                parts.append(detailMessage)
            }
        }

        return parts.isEmpty ? fallback : parts.joined(separator: " - ")
    }

    func appVersion() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    func error(_ code: String, _ message: String) -> NSError {
        NSError(
            domain: "Sendrealm",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: message,
                "code": code
            ]
        )
    }
}
