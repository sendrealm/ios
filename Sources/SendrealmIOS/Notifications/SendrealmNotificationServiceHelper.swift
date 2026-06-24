import Foundation
import UserNotifications

public enum SendrealmNotificationServiceHelper {
    private struct SendrealmAction {
        let identifier: String
        let title: String
    }

    private static let defaultActionCategory = "sendrealm_default_actions"
    private static let defaultActionCategoryPrefix = "sendrealm_default_actions_"
    private static let defaultActionIdentifiers = [
        "sendrealm_action_1",
        "sendrealm_action_2",
        "sendrealm_action_3"
    ]
    static var notificationCenterIntegrationDisabledForTesting = false
    static var imageDownloadForTesting: ((URL, @escaping (URL?) -> Void) -> Void)?

    public static func enrich(
        request: UNNotificationRequest,
        bestAttemptContent: UNMutableNotificationContent,
        completion: @escaping (UNMutableNotificationContent) -> Void
    ) {
        registerDynamicActionCategoryIfNeeded(
            for: bestAttemptContent,
            userInfo: request.content.userInfo
        ) {
            guard let imageUrl = imageURL(from: request.content.userInfo) else {
                completion(bestAttemptContent)
                return
            }

            let attachImage: (URL?) -> Void = { location in
                guard let location else {
                    completion(bestAttemptContent)
                    return
                }

                let temporaryUrl = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(imageUrl.pathExtension.isEmpty ? "jpg" : imageUrl.pathExtension)

                do {
                    try FileManager.default.moveItem(at: location, to: temporaryUrl)
                    let attachment = try UNNotificationAttachment(identifier: "sendrealm-image", url: temporaryUrl)
                    bestAttemptContent.attachments = [attachment]
                } catch {
                    // The main notification should still display when rich media fails.
                }

                completion(bestAttemptContent)
            }

            if let imageDownloadForTesting {
                imageDownloadForTesting(imageUrl, attachImage)
                return
            }

            URLSession.shared.downloadTask(with: imageUrl) { location, _, _ in
                attachImage(location)
            }.resume()
        }
    }

    static func testingActionDiagnostics(
        userInfo: [AnyHashable: Any],
        categoryIdentifier: String
    ) -> [String: Any] {
        let payload = sendrealmPayload(from: userInfo)
        let actions = actionPayloads(from: payload)

        return [
            "usesDefaultCategory": usesDefaultActionCategory(categoryIdentifier),
            "dynamicCategoryIdentifier": actions.isEmpty ? NSNull() : dynamicActionCategoryIdentifier(for: actions),
            "actions": actions.map { action in
                [
                    "identifier": action.identifier,
                    "title": action.title
                ]
            },
            "imageUrl": imageURL(from: userInfo)?.absoluteString as Any? ?? NSNull()
        ]
    }

    private static func registerDynamicActionCategoryIfNeeded(
        for content: UNMutableNotificationContent,
        userInfo: [AnyHashable: Any],
        completion: @escaping () -> Void
    ) {
        let payload = sendrealmPayload(from: userInfo)
        let actions = actionPayloads(from: payload)

        guard
            !actions.isEmpty,
            usesDefaultActionCategory(content.categoryIdentifier)
        else {
            completion()
            return
        }

        let categoryIdentifier = dynamicActionCategoryIdentifier(for: actions)
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: actions.map { action in
                UNNotificationAction(
                    identifier: action.identifier,
                    title: action.title,
                    options: [.foreground]
                )
            },
            intentIdentifiers: [],
            options: []
        )

        if notificationCenterIntegrationDisabledForTesting {
            content.categoryIdentifier = categoryIdentifier
            completion()
            return
        }

        UNUserNotificationCenter.current().getNotificationCategories { categories in
            var nextCategories = categories
            nextCategories.update(with: category)
            UNUserNotificationCenter.current().setNotificationCategories(nextCategories)
            content.categoryIdentifier = categoryIdentifier
            completion()
        }
    }

    private static func sendrealmPayload(from userInfo: [AnyHashable: Any]) -> [String: Any] {
        let payloadValue = userInfo["sendrealm_v1"]

        if let rawPayload = payloadValue as? String,
           let data = rawPayload.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return parsed
        } else if let parsed = payloadValue as? [String: Any] {
            return parsed
        } else {
            return userInfo as? [String: Any] ?? [:]
        }
    }

    private static func actionPayloads(from payload: [String: Any]) -> [SendrealmAction] {
        let actionValues =
            (payload["actions"] as? [[String: Any]]) ??
            ((payload["liveActivity"] as? [String: Any])?["buttons"] as? [[String: Any]]) ??
            ((payload["live_activity"] as? [String: Any])?["buttons"] as? [[String: Any]]) ??
            []

        return actionValues.prefix(defaultActionIdentifiers.count).enumerated().compactMap { index, action in
            guard
                let title = normalizedString(action["text"]) ?? normalizedString(action["title"])
            else {
                return nil
            }

            let fallbackIdentifier = defaultActionIdentifiers[index]
            let identifier = normalizedString(action["id"]) ?? fallbackIdentifier

            return SendrealmAction(identifier: identifier, title: title)
        }
    }

    private static func imageURL(from userInfo: [AnyHashable: Any]) -> URL? {
        let payload = sendrealmPayload(from: userInfo)
        let metadata = payload["metadata"] as? [String: Any] ?? [:]
        let rawUrl =
            metadata["image_url"] as? String ??
            metadata["imageUrl"] as? String ??
            userInfo["image_url"] as? String ??
            userInfo["imageUrl"] as? String

        guard let rawUrl, !rawUrl.isEmpty else {
            return nil
        }

        return URL(string: rawUrl)
    }

    private static func usesDefaultActionCategory(_ categoryIdentifier: String) -> Bool {
        categoryIdentifier == defaultActionCategory ||
            categoryIdentifier.hasPrefix(defaultActionCategoryPrefix)
    }

    private static func dynamicActionCategoryIdentifier(for actions: [SendrealmAction]) -> String {
        let signature = actions
            .map { "\($0.identifier)=\($0.title)" }
            .joined(separator: "|")
        var hash: UInt32 = 2166136261

        for scalar in signature.unicodeScalars {
            hash ^= UInt32(scalar.value)
            hash = hash &* 16777619
        }

        return "sendrealm_actions_\(actions.count)_\(String(format: "%08x", hash))"
    }

    private static func normalizedString(_ value: Any?) -> String? {
        guard let value else {
            return nil
        }

        let string = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return string.isEmpty ? nil : string
    }
}
