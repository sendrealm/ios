import Foundation

extension Sendrealm {
    func enqueueOperation(name: String, path: String, payload: [String: Any?]) {
        guard !name.isEmpty, !path.isEmpty else {
            return
        }

        var operations = queuedOperations()
        var nextPayload = payload
        if nextPayload["idempotency_key"] == nil {
            nextPayload["idempotency_key"] = idempotencyKey(prefix: name)
        }

        operations.append([
            "name": name,
            "path": path,
            "payload": sanitizeJSON(nextPayload),
            "queuedAt": Date().timeIntervalSince1970,
            "retryCount": 0,
            "nextAttemptAt": Date().timeIntervalSince1970
        ])
        saveQueuedOperations(Array(operations.suffix(queueLimit)))
    }

    func enqueueEvent(eventType: String, notificationId: String? = nil, properties: [String: Any]? = nil) {
        guard !eventType.isEmpty else {
            return
        }

        var events = queuedEvents()
        events.append([
            "eventType": eventType,
            "notificationId": notificationId as Any? ?? "",
            "properties": properties as Any? ?? [:],
            "idempotencyKey": idempotencyKey(prefix: eventType),
            "queuedAt": Date().timeIntervalSince1970
        ])
        saveQueuedEvents(Array(events.suffix(queueLimit)))
    }

    func enqueueTags(_ tags: [String: Any]) {
        guard !tags.isEmpty else {
            return
        }

        var pendingTags = queuedTags()
        tags.forEach { key, value in
            pendingTags[key] = value
        }
        saveQueuedTags(pendingTags)
    }

    func flushPendingWork() {
        flushQueuedOperations()
        flushPendingLiveActivityTokenRegistrations()

        let pendingTags = queuedTags()
        if !pendingTags.isEmpty {
            updateTags(pendingTags) { [weak self] success in
                if success {
                    self?.saveQueuedTags([:])
                }
            }
        }

        let events = queuedEvents()
        guard !events.isEmpty else {
            return
        }

        var remaining: [[String: Any]] = []
        let group = DispatchGroup()

        events.forEach { event in
            guard let eventType = normalizedString(event["eventType"]) else {
                return
            }

            group.enter()
            trackDeviceEvent(
                eventType,
                notificationId: normalizedString(event["notificationId"]),
                properties: event["properties"] as? [String: Any]
            ) { success in
                if !success {
                    remaining.append(event)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.saveQueuedEvents(remaining)
        }
    }

    func flushQueuedOperations() {
        let now = Date().timeIntervalSince1970
        let operations = queuedOperations()
        guard !operations.isEmpty else {
            return
        }

        var remaining: [[String: Any]] = []
        let group = DispatchGroup()

        operations.forEach { operation in
            let nextAttemptAt = (operation["nextAttemptAt"] as? Double) ?? 0
            guard nextAttemptAt <= now else {
                remaining.append(operation)
                return
            }

            guard let path = normalizedString(operation["path"]),
                  let rawPayload = operation["payload"] as? [String: Any] else {
                return
            }

            var payload: [String: Any?] = [:]
            rawPayload.forEach { key, value in
                payload[key] = value
            }

            group.enter()
            postJSON(path: path, payload: payload) { successJSON, success in
                if !success {
                    var retryOperation = operation
                    let retryCount = (operation["retryCount"] as? Int) ?? 0
                    retryOperation["retryCount"] = retryCount + 1
                    retryOperation["nextAttemptAt"] = Date().timeIntervalSince1970 + self.retryDelay(for: retryCount + 1)
                    retryOperation["lastError"] = self.apiErrorMessage(successJSON, fallback: "Request failed")
                    remaining.append(retryOperation)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.saveQueuedOperations(Array(remaining.suffix(self?.queueLimit ?? 1000)))
        }
    }

    func queuedEvents() -> [[String: Any]] {
        guard let data = UserDefaults.standard.data(forKey: prefsKey("pending_events")),
              let events = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return events
    }

    func saveQueuedEvents(_ events: [[String: Any]]) {
        let key = prefsKey("pending_events")
        if events.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }

        UserDefaults.standard.set(try? JSONSerialization.data(withJSONObject: sanitizeJSON(events)), forKey: key)
    }

    func queuedTags() -> [String: Any] {
        guard let data = UserDefaults.standard.data(forKey: prefsKey("pending_tags")),
              let tags = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        return tags
    }

    func saveQueuedTags(_ tags: [String: Any]) {
        let key = prefsKey("pending_tags")
        if tags.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }

        UserDefaults.standard.set(try? JSONSerialization.data(withJSONObject: sanitizeJSON(tags)), forKey: key)
    }

    func queuedOperations() -> [[String: Any]] {
        guard let data = UserDefaults.standard.data(forKey: prefsKey("pending_operations")),
              let operations = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return operations
    }

    func saveQueuedOperations(_ operations: [[String: Any]]) {
        let key = prefsKey("pending_operations")
        if operations.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }

        UserDefaults.standard.set(try? JSONSerialization.data(withJSONObject: sanitizeJSON(operations)), forKey: key)
    }

    func queueCounts() -> [String: Int] {
        [
            "events": queuedEvents().count,
            "tags": queuedTags().count,
            "operations": queuedOperations().count,
            "liveActivityTokens": pendingLiveActivityTokenRegistrations.count
        ]
    }

    func retryDelay(for retryCount: Int) -> TimeInterval {
        min(pow(2.0, Double(max(retryCount, 1))), 300)
    }

    func idempotencyKey(prefix: String) -> String {
        "\(prefix)_\(UUID().uuidString.lowercased())"
    }
}
