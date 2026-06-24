import Foundation
import UIKit

extension Sendrealm {
    func registerAPNSToken(_ token: String?, completion: ((Bool) -> Void)?) {
        guard
            let appId,
            let deviceId,
            let token,
            !appId.isEmpty,
            !deviceId.isEmpty,
            !token.isEmpty
        else {
            completion?(false)
            return
        }

        let payload = baseDevicePayload(additional: [
            "device_id": deviceId,
            "registration_id": token,
            "apns_device_token": token,
            "apns_environment": apnsEnvironment,
            "permission_status": lastPermissionStatus,
            "subscribed": subscribed,
            "user_external_id": externalUserId as Any?,
            "user_email": userEmail as Any?
        ])

        postJSON(path: "/v1/register", payload: payload) { [weak self] json, success in
            if success {
                self?.subscribed = true
                self?.lastRegistrationFingerprint = self?.registrationFingerprint()
                self?.rememberRegisterResult(success: true)
                self?.persistState()
                self?.flushPendingWork()
                self?.flushPendingLiveActivityTokenRegistrations()
            } else {
                let message = self?.apiErrorMessage(json, fallback: "Failed to register APNs token")
                self?.rememberRegisterResult(success: false, message: message)
                self?.enqueueOperation(name: "register", path: "/v1/register", payload: payload)
            }

            completion?(success)
        }
    }

    func updateSubscription(_ nextSubscribed: Bool, completion: @escaping (Bool) -> Void) {
        guard let deviceId else {
            completion(false)
            return
        }

        let payload = baseDevicePayload(additional: [
            "device_id": deviceId,
            "subscribed": nextSubscribed,
            "registration_id": nextSubscribed ? apnsToken as Any? : nil,
            "apns_device_token": nextSubscribed ? apnsToken as Any? : nil,
            "apns_environment": apnsEnvironment,
            "permission_status": lastPermissionStatus
        ])

        postJSON(path: "/v1/subscription", payload: payload) { [weak self] json, success in
            if !success {
                self?.setLastSdkError(
                    code: "E_SUBSCRIPTION_SYNC_FAILED",
                    message: self?.apiErrorMessage(json, fallback: "Failed to update subscription state") ?? "Failed to update subscription state"
                )
                self?.enqueueOperation(name: nextSubscribed ? "opt_in" : "opt_out", path: "/v1/subscription", payload: payload)
            }
            completion(success)
        }
    }

    func updateTags(_ tags: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let appId, let deviceId, !appId.isEmpty, !deviceId.isEmpty else {
            completion(false)
            return
        }

        postJSON(path: "/v1/tags", payload: [
            "app_id": appId,
            "device_id": deviceId,
            "platform": "ios",
            "idempotency_key": idempotencyKey(prefix: "tags"),
            "tags": tags
        ]) { _, success in
            completion(success)
        }
    }

    func trackDeviceEvent(
        _ eventType: String,
        notificationId: String? = nil,
        properties: [String: Any]? = nil,
        enqueueOnFailure: Bool = false,
        completion: ((Bool) -> Void)?
    ) {
        guard let appId, let deviceId, !appId.isEmpty, !deviceId.isEmpty, !eventType.isEmpty else {
            completion?(false)
            return
        }

        let payload = baseDevicePayload(additional: [
            "device_id": deviceId,
            "event_type": eventType,
            "notification_id": notificationId as Any?,
            "idempotency_key": idempotencyKey(prefix: eventType),
            "properties": properties as Any?
        ])

        postJSON(path: "/v1/track", payload: payload) { [weak self] _, success in
            if !success && enqueueOnFailure {
                self?.enqueueOperation(
                    name: "track_\(eventType)",
                    path: "/v1/track",
                    payload: payload
                )
            }

            completion?(success)
        }
    }

    func baseDevicePayload(additional: [String: Any?] = [:]) -> [String: Any?] {
        var payload: [String: Any?] = [
            "app_id": appId,
            "platform": "ios",
            "app_version": appVersion(),
            "device_model": UIDevice.current.model,
            "sdk_version": sdkVersion,
            "os_version": UIDevice.current.systemVersion,
            "device_locale": Locale.current.identifier,
            "timezone": TimeZone.current.identifier,
            "api_url_source": apiUrlSource,
            "permission_status": lastPermissionStatus,
            "subscribed": subscribed
        ]

        additional.forEach { key, value in
            payload[key] = value
        }

        return payload
    }

    func postJSON(path: String, payload: [String: Any?], method: String = "POST", completion: @escaping ([String: Any]?, Bool) -> Void) {
        guard
            let baseUrl = normalizedString(baseUrl)?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            let url = URL(string: "\(baseUrl)\(path)")
        else {
            DispatchQueue.main.async {
                completion(nil, false)
            }
            return
        }

        let bodyObject = sanitizeJSON(payload)

        guard JSONSerialization.isValidJSONObject(bodyObject),
              let body = try? JSONSerialization.data(withJSONObject: bodyObject)
        else {
            DispatchQueue.main.async {
                completion(nil, false)
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let success = error == nil && (200..<300).contains(statusCode)
            var json: [String: Any]?

            if let data, !data.isEmpty {
                json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }

            DispatchQueue.main.async {
                completion(json, success)
            }
        }.resume()
    }
}
