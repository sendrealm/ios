import Foundation
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
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

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var downloadTask: URLSessionDownloadTask?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent else {
            finish(request.content)
            return
        }

        registerDynamicActionCategoryIfNeeded(
            for: bestAttemptContent,
            userInfo: request.content.userInfo
        ) { [weak self] in
            guard let self else {
                contentHandler(bestAttemptContent)
                return
            }

            guard let url = self.imageURL(from: request.content.userInfo) else {
                self.finish(bestAttemptContent)
                return
            }

            self.downloadTask = URLSession.shared.downloadTask(with: url) { [weak self] location, _, _ in
                guard let self else { return }

                if let location {
                    do {
                        let attachmentURL = try self.copyAttachment(from: location, originalURL: url)
                        let attachment = try UNNotificationAttachment(
                            identifier: "sendrealm-rich-media",
                            url: attachmentURL,
                            options: nil
                        )
                        bestAttemptContent.attachments = [attachment]
                    } catch {
                        // The main notification should still display when rich media fails.
                    }
                }

                self.finish(bestAttemptContent)
            }
            self.downloadTask?.resume()
        }
    }

    override func serviceExtensionTimeWillExpire() {
        downloadTask?.cancel()

        if let bestAttemptContent {
            finish(bestAttemptContent)
        }
    }

    private func finish(_ content: UNNotificationContent) {
        contentHandler?(content)
        contentHandler = nil
    }

    private func registerDynamicActionCategoryIfNeeded(
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

        UNUserNotificationCenter.current().getNotificationCategories { categories in
            var nextCategories = categories
            nextCategories.update(with: category)
            UNUserNotificationCenter.current().setNotificationCategories(nextCategories)
            content.categoryIdentifier = categoryIdentifier
            completion()
        }
    }

    private func sendrealmPayload(from userInfo: [AnyHashable: Any]) -> [String: Any] {
        if
            let rawPayload = userInfo["sendrealm_v1"] as? String,
            let data = rawPayload.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            return parsed
        } else if let parsed = userInfo["sendrealm_v1"] as? [String: Any] {
            return parsed
        } else {
            return userInfo as? [String: Any] ?? [:]
        }
    }

    private func actionPayloads(from payload: [String: Any]) -> [SendrealmAction] {
        let actionValues =
            (payload["actions"] as? [[String: Any]]) ??
            ((payload["liveActivity"] as? [String: Any])?["buttons"] as? [[String: Any]]) ??
            ((payload["live_activity"] as? [String: Any])?["buttons"] as? [[String: Any]]) ??
            []

        return actionValues.prefix(Self.defaultActionIdentifiers.count).enumerated().compactMap { index, action in
            guard let title = normalizedString(action["text"]) ?? normalizedString(action["title"]) else {
                return nil
            }

            let identifier = normalizedString(action["id"]) ?? Self.defaultActionIdentifiers[index]
            return SendrealmAction(identifier: identifier, title: title)
        }
    }

    private func imageURL(from userInfo: [AnyHashable: Any]) -> URL? {
        let sendrealmPayload = sendrealmPayload(from: userInfo)
        let metadata = sendrealmPayload["metadata"] as? [String: Any] ?? [:]
        let rawURL =
            metadata["image_url"] as? String ??
            metadata["imageUrl"] as? String ??
            userInfo["image_url"] as? String ??
            userInfo["imageUrl"] as? String

        if
            let rawURL,
            let url = URL(string: rawURL),
            ["http", "https"].contains(url.scheme?.lowercased())
        {
            return url
        }

        return nil
    }

    private func copyAttachment(from location: URL, originalURL: URL) throws -> URL {
        let fileExtension = originalURL.pathExtension.isEmpty ? "jpg" : originalURL.pathExtension
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let attachmentURL = temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)

        if FileManager.default.fileExists(atPath: attachmentURL.path) {
            try FileManager.default.removeItem(at: attachmentURL)
        }

        try FileManager.default.copyItem(at: location, to: attachmentURL)
        return attachmentURL
    }

    private func usesDefaultActionCategory(_ categoryIdentifier: String) -> Bool {
        categoryIdentifier == Self.defaultActionCategory ||
            categoryIdentifier.hasPrefix(Self.defaultActionCategoryPrefix)
    }

    private func dynamicActionCategoryIdentifier(for actions: [SendrealmAction]) -> String {
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

    private func normalizedString(_ value: Any?) -> String? {
        guard let value else {
            return nil
        }

        let string = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return string.isEmpty ? nil : string
    }
}
