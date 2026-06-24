import Foundation

#if canImport(ActivityKit)
@preconcurrency import ActivityKit
#endif

extension Sendrealm {
    func liveActivityDiagnostics() -> [String: Any] {
        [
            "status": liveActivityStatus,
            "enabled": liveActivityEnabled as Any? ?? NSNull(),
            "pushToStartObserverActive": liveActivityPushToStartTokenTask != nil,
            "customPushToStartObserverCount": liveActivityCustomPushToStartTokenTasks.count,
            "activityUpdatesObserverActive": liveActivityActivityUpdatesTask != nil,
            "customActivityUpdatesObserverCount": liveActivityCustomActivityUpdatesTasks.count,
            "updateTokenObserverCount": liveActivityUpdateTokenTasks.count,
            "stateObserverCount": liveActivityStateUpdateTasks.count,
            "contentObserverCount": liveActivityContentUpdateTasks.count,
            "pushToStartTokenObserved": liveActivityPushToStartObserved,
            "pendingTokenRegistrations": pendingLiveActivityTokenRegistrations.count,
            "registrationAttempts": liveActivityTokenRegistrationAttempts,
            "registrationSuccesses": liveActivityTokenRegistrationSuccesses,
            "registrationFailures": liveActivityTokenRegistrationFailures,
            "lastTokenType": liveActivityLastTokenType as Any? ?? NSNull(),
            "lastError": liveActivityLastError as Any? ?? NSNull()
        ]
    }

    func updateLiveActivityStatus(
        _ status: String,
        enabled: Bool? = nil,
        error: String? = nil
    ) {
        liveActivityStatus = status
        print("[Sendrealm] Live Activity status: \(status)")

        if let enabled {
            liveActivityEnabled = enabled
        }

        if let error {
            liveActivityLastError = error
            print("[Sendrealm] Live Activity error: \(error)")
        }
    }

    func trackLiveActivityDiagnosticsSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }

            self.trackDeviceEvent(
                "live_activity_diagnostics",
                properties: self.liveActivityDiagnostics(),
                enqueueOnFailure: true,
                completion: nil
            )
        }
    }

    func enqueuePendingLiveActivityTokenRegistration(
        token: String,
        activityId: String?,
        tokenType: String,
        activityType: String? = nil,
        attributesType: String? = nil,
        sendId: String? = nil
    ) {
        let registration = PendingLiveActivityTokenRegistration(
            token: token,
            activityId: activityId,
            tokenType: tokenType,
            activityType: activityType,
            attributesType: attributesType,
            sendId: sendId
        )

        guard !pendingLiveActivityTokenRegistrations.contains(where: { $0.key == registration.key }) else {
            return
        }

        pendingLiveActivityTokenRegistrations.append(registration)
        pendingLiveActivityTokenRegistrations = Array(
            pendingLiveActivityTokenRegistrations.suffix(queueLimit)
        )
    }

    func rememberLiveActivityTokenRegistration(
        token: String,
        activityId: String?,
        tokenType: String,
        activityType: String? = nil,
        attributesType: String? = nil,
        sendId: String? = nil
    ) {
        liveActivityRegisteredTokenKeys.insert(
            PendingLiveActivityTokenRegistration(
                token: token,
                activityId: activityId,
                tokenType: tokenType,
                activityType: activityType,
                attributesType: attributesType,
                sendId: sendId
            ).key
        )
    }

    func hasRegisteredLiveActivityToken(
        token: String,
        activityId: String?,
        tokenType: String,
        activityType: String? = nil,
        attributesType: String? = nil,
        sendId: String? = nil
    ) -> Bool {
        liveActivityRegisteredTokenKeys.contains(
            PendingLiveActivityTokenRegistration(
                token: token,
                activityId: activityId,
                tokenType: tokenType,
                activityType: activityType,
                attributesType: attributesType,
                sendId: sendId
            ).key
        )
    }

    func flushPendingLiveActivityTokenRegistrations() {
        guard deviceId != nil, !pendingLiveActivityTokenRegistrations.isEmpty else {
            return
        }

        let pending = pendingLiveActivityTokenRegistrations
        pendingLiveActivityTokenRegistrations = []

        pending.forEach { registration in
            registerLiveActivityToken(
                registration.token,
                activityId: registration.activityId,
                tokenType: registration.tokenType,
                activityType: registration.activityType,
                attributesType: registration.attributesType,
                sendId: registration.sendId
            ) { [weak self] success, _ in
                if success.boolValue {
                    return
                }

                self?.enqueuePendingLiveActivityTokenRegistration(
                    token: registration.token,
                    activityId: registration.activityId,
                    tokenType: registration.tokenType,
                    activityType: registration.activityType,
                    attributesType: registration.attributesType,
                    sendId: registration.sendId
                )
            }
        }
    }
}

#if canImport(ActivityKit)
extension Sendrealm {
    private var defaultLiveActivityAttributesType: String {
        "SendrealmLiveActivityAttributes"
    }

    @available(iOS 16.1, *)
    public func observeLiveActivityType<Attributes: ActivityAttributes>(
        _ attributesType: Attributes.Type,
        attributesTypeName: String? = nil,
        activityId: @escaping @Sendable (Attributes) -> String?,
        attributesSendId: @escaping @Sendable (Attributes) -> String? = { _ in nil },
        contentStateSendId: @escaping @Sendable (Attributes.ContentState) -> String? = { _ in nil }
    ) {
        let typeKey = normalizedString(attributesTypeName) ?? String(reflecting: attributesType)
        updateLiveActivityStatus("custom_activity_type_observer_starting")

        observeExistingLiveActivityUpdateTokens(
            for: attributesType,
            typeKey: typeKey,
            activityId: activityId,
            attributesSendId: attributesSendId,
            contentStateSendId: contentStateSendId
        )
        observeLiveActivityUpdates(
            for: attributesType,
            typeKey: typeKey,
            activityId: activityId,
            attributesSendId: attributesSendId,
            contentStateSendId: contentStateSendId
        )

        if #available(iOS 17.2, *) {
            observePushToStartTokens(for: attributesType, typeKey: typeKey)
        }
    }

    func startLiveActivityTokenObserversIfAvailable() {
        guard #available(iOS 16.1, *) else {
            updateLiveActivityStatus("unavailable_ios_version")
            return
        }

        let activitiesEnabled = liveActivityActivitiesEnabledForTesting ??
            ActivityAuthorizationInfo().areActivitiesEnabled
        updateLiveActivityStatus(
            activitiesEnabled ? "observer_starting" : "activities_disabled_observer_starting",
            enabled: activitiesEnabled
        )

        observeExistingLiveActivityUpdateTokens()
        observeLiveActivityUpdates()

        if #available(iOS 17.2, *) {
            observePushToStartTokens()
        } else {
            updateLiveActivityStatus(
                activitiesEnabled ? "push_to_start_requires_ios_17_2" : "activities_disabled_push_to_start_requires_ios_17_2",
                enabled: activitiesEnabled
            )
        }
    }

    func liveActivityMainObserverTask<Updates: AsyncSequence>(
        _ updates: Updates,
        handleUpdate: @escaping (Updates.Element) -> Void
    ) -> Task<Void, Never> {
        Task {
            do {
                for try await update in updates {
                    DispatchQueue.main.async {
                        handleUpdate(update)
                    }
                }
            } catch {
                return
            }
        }
    }

    @available(iOS 17.2, *)
    private func observePushToStartTokens() {
        guard liveActivityPushToStartTokenTask == nil else {
            return
        }

        updateLiveActivityStatus("push_to_start_observer_active")
        liveActivityPushToStartTokenTask = liveActivityMainObserverTask(
            Activity<SendrealmLiveActivityAttributes>.pushToStartTokenUpdates
        ) { [weak self] tokenData in
            guard let self else { return }
            self.observeLiveActivityPushToStartToken(
                tokenData,
                status: "push_to_start_token_observed",
                activityType: self.defaultLiveActivityAttributesType,
                attributesType: self.defaultLiveActivityAttributesType
            )
        }
    }

    @available(iOS 16.1, *)
    private func observeDefaultLiveActivity(
        _ activity: Activity<SendrealmLiveActivityAttributes>
    ) {
        observeUpdateTokens(for: activity)
        observeStateUpdates(for: activity)
        observeContentUpdates(for: activity)
        trackLiveActivityReceiptIfNeeded(
            activityId: activity.attributes.activity_id,
            sendId: sendId(for: activity),
            attributesType: defaultLiveActivityAttributesType
        )
    }

    @available(iOS 16.1, *)
    private func observeCustomLiveActivity<Attributes: ActivityAttributes>(
        _ activity: Activity<Attributes>,
        typeKey: String,
        activityId: @escaping @Sendable (Attributes) -> String?,
        attributesSendId: @escaping @Sendable (Attributes) -> String?,
        contentStateSendId: @escaping @Sendable (Attributes.ContentState) -> String?
    ) {
        observeUpdateTokens(for: activity, typeKey: typeKey, activityId: activityId, attributesSendId: attributesSendId)
        observeStateUpdates(for: activity, typeKey: typeKey, activityId: activityId, attributesSendId: attributesSendId)
        observeContentUpdates(
            for: activity,
            typeKey: typeKey,
            activityId: activityId,
            attributesSendId: attributesSendId,
            contentStateSendId: contentStateSendId
        )

        if let activityId = customActivityId(for: activity, activityId: activityId) {
            trackLiveActivityReceiptIfNeeded(
                activityId: activityId,
                sendId: customSendId(for: activity, attributesSendId: attributesSendId),
                attributesType: typeKey
            )
        }
    }

    @available(iOS 16.1, *)
    private func observeLiveActivityStateUpdate(
        _ state: ActivityState,
        activityId: String?,
        sendId: String?,
        attributesType: String?
    ) {
        guard
            let activityId,
            let activityState = liveActivityStateName(state)
        else {
            return
        }

        trackLiveActivityStateChange(
            activityId: activityId,
            sendId: sendId,
            activityState: activityState,
            attributesType: attributesType
        )
    }

    private func observeLiveActivityContentSendId(
        activityId: String?,
        sendId: String?,
        startSendId: String?,
        attributesType: String?
    ) {
        handleObservedLiveActivityContentUpdate(
            activityId: activityId,
            sendId: sendId,
            startSendId: startSendId,
            attributesType: attributesType
        )
    }

    private func observeLiveActivityUpdateToken(
        _ tokenData: Data,
        activityId: String?,
        activityType: String?,
        attributesType: String?,
        sendId: String?
    ) {
        handleObservedLiveActivityUpdateToken(
            tokenData,
            activityId: activityId,
            activityType: activityType,
            attributesType: attributesType,
            sendId: sendId
        )
    }

    private func observeLiveActivityPushToStartToken(
        _ tokenData: Data,
        status: String,
        activityType: String?,
        attributesType: String?
    ) {
        handleObservedPushToStartToken(
            tokenData,
            status: status,
            activityType: activityType,
            attributesType: attributesType
        )
    }

    @available(iOS 17.2, *)
    private func observePushToStartTokens<Attributes: ActivityAttributes>(
        for attributesType: Attributes.Type,
        typeKey: String
    ) {
        guard liveActivityCustomPushToStartTokenTasks[typeKey] == nil else {
            return
        }

        liveActivityCustomPushToStartTokenTasks[typeKey] = liveActivityMainObserverTask(
            Activity<Attributes>.pushToStartTokenUpdates
        ) { [weak self] tokenData in
            self?.observeLiveActivityPushToStartToken(
                tokenData,
                status: "custom_push_to_start_token_observed",
                activityType: typeKey,
                attributesType: typeKey
            )
        }
    }

    @available(iOS 16.1, *)
    private func sendId(
        for activity: Activity<SendrealmLiveActivityAttributes>
    ) -> String? {
        if #available(iOS 16.2, *) {
            return normalizedString(activity.content.state.send_id) ??
                normalizedString(activity.attributes.send_id)
        }

        return normalizedString(activity.attributes.send_id)
    }

    @available(iOS 16.1, *)
    private func customActivityId<Attributes: ActivityAttributes>(
        for activity: Activity<Attributes>,
        activityId: (Attributes) -> String?
    ) -> String? {
        normalizedString(activityId(activity.attributes))
    }

    @available(iOS 16.1, *)
    private func customSendId<Attributes: ActivityAttributes>(
        for activity: Activity<Attributes>,
        attributesSendId: (Attributes) -> String?
    ) -> String? {
        normalizedString(attributesSendId(activity.attributes))
    }

    @available(iOS 16.1, *)
    private func observeExistingLiveActivityUpdateTokens() {
        Activity<SendrealmLiveActivityAttributes>.activities.forEach(observeDefaultLiveActivity)
    }

    @available(iOS 16.1, *)
    private func observeExistingLiveActivityUpdateTokens<Attributes: ActivityAttributes>(
        for attributesType: Attributes.Type,
        typeKey: String,
        activityId: @escaping @Sendable (Attributes) -> String?,
        attributesSendId: @escaping @Sendable (Attributes) -> String?,
        contentStateSendId: @escaping @Sendable (Attributes.ContentState) -> String?
    ) {
        Activity<Attributes>.activities.forEach { activity in
            observeCustomLiveActivity(
                activity,
                typeKey: typeKey,
                activityId: activityId,
                attributesSendId: attributesSendId,
                contentStateSendId: contentStateSendId
            )
        }
    }

    @available(iOS 16.1, *)
    private func observeLiveActivityUpdates() {
        guard liveActivityActivityUpdatesTask == nil else {
            return
        }

        updateLiveActivityStatus("activity_updates_observer_active")
        liveActivityActivityUpdatesTask = liveActivityMainObserverTask(
            Activity<SendrealmLiveActivityAttributes>.activityUpdates
        ) { [weak self] activity in
            self?.observeDefaultLiveActivity(activity)
        }
    }

    @available(iOS 16.1, *)
    private func observeLiveActivityUpdates<Attributes: ActivityAttributes>(
        for attributesType: Attributes.Type,
        typeKey: String,
        activityId: @escaping @Sendable (Attributes) -> String?,
        attributesSendId: @escaping @Sendable (Attributes) -> String?,
        contentStateSendId: @escaping @Sendable (Attributes.ContentState) -> String?
    ) {
        guard liveActivityCustomActivityUpdatesTasks[typeKey] == nil else {
            return
        }

        liveActivityCustomActivityUpdatesTasks[typeKey] = liveActivityMainObserverTask(
            Activity<Attributes>.activityUpdates
        ) { [weak self] activity in
            self?.observeCustomLiveActivity(
                activity,
                typeKey: typeKey,
                activityId: activityId,
                attributesSendId: attributesSendId,
                contentStateSendId: contentStateSendId
            )
        }
    }

    @available(iOS 16.1, *)
    private func observeContentUpdates(
        for activity: Activity<SendrealmLiveActivityAttributes>
    ) {
        guard #available(iOS 16.2, *) else {
            return
        }

        let observerKey = activity.id
        let activityId = activity.attributes.activity_id
        let startSendId = normalizedString(activity.attributes.send_id)

        guard liveActivityContentUpdateTasks[observerKey] == nil else {
            return
        }

        liveActivityContentUpdateTasks[observerKey] = liveActivityMainObserverTask(
            activity.contentUpdates
        ) { [weak self] content in
            self?.observeLiveActivityContentSendId(
                activityId: activityId,
                sendId: self?.normalizedString(content.state.send_id),
                startSendId: startSendId,
                attributesType: self?.defaultLiveActivityAttributesType
            )
        }
    }

    @available(iOS 16.1, *)
    private func observeContentUpdates<Attributes: ActivityAttributes>(
        for activity: Activity<Attributes>,
        typeKey: String,
        activityId: @escaping @Sendable (Attributes) -> String?,
        attributesSendId: @escaping @Sendable (Attributes) -> String?,
        contentStateSendId: @escaping @Sendable (Attributes.ContentState) -> String?
    ) {
        guard #available(iOS 16.2, *) else {
            return
        }

        let observerKey = "\(typeKey):\(activity.id)"
        let startSendId = customSendId(
            for: activity,
            attributesSendId: attributesSendId
        )

        guard liveActivityContentUpdateTasks[observerKey] == nil else {
            return
        }

        liveActivityContentUpdateTasks[observerKey] = liveActivityMainObserverTask(
            activity.contentUpdates
        ) { [weak self] content in
            self?.observeLiveActivityContentSendId(
                activityId: self?.normalizedString(activityId(activity.attributes)),
                sendId: self?.normalizedString(contentStateSendId(content.state)),
                startSendId: startSendId,
                attributesType: typeKey
            )
        }
    }

    @available(iOS 16.1, *)
    private func observeUpdateTokens(
        for activity: Activity<SendrealmLiveActivityAttributes>
    ) {
        let observerKey = activity.id
        let activityId = activity.attributes.activity_id
        let sendId = sendId(for: activity)

        guard liveActivityUpdateTokenTasks[observerKey] == nil else {
            return
        }

        liveActivityUpdateTokenTasks[observerKey] = liveActivityMainObserverTask(
            activity.pushTokenUpdates
        ) { [weak self] tokenData in
            self?.observeLiveActivityUpdateToken(
                tokenData,
                activityId: activityId,
                activityType: self?.defaultLiveActivityAttributesType,
                attributesType: self?.defaultLiveActivityAttributesType,
                sendId: sendId
            )
        }
    }

    @available(iOS 16.1, *)
    private func observeUpdateTokens<Attributes: ActivityAttributes>(
        for activity: Activity<Attributes>,
        typeKey: String,
        activityId: @escaping @Sendable (Attributes) -> String?,
        attributesSendId: @escaping @Sendable (Attributes) -> String?
    ) {
        let observerKey = "\(typeKey):\(activity.id)"
        let resolvedActivityId = customActivityId(for: activity, activityId: activityId)
        let sendId = customSendId(
            for: activity,
            attributesSendId: attributesSendId
        )

        guard let resolvedActivityId else {
            updateLiveActivityStatus(
                "custom_live_activity_missing_activity_id",
                error: "Custom Live Activity observer could not extract activity_id for \(typeKey)"
            )
            return
        }

        guard liveActivityUpdateTokenTasks[observerKey] == nil else {
            return
        }

        liveActivityUpdateTokenTasks[observerKey] = liveActivityMainObserverTask(
            activity.pushTokenUpdates
        ) { [weak self] tokenData in
            self?.observeLiveActivityUpdateToken(
                tokenData,
                activityId: resolvedActivityId,
                activityType: typeKey,
                attributesType: typeKey,
                sendId: sendId
            )
        }
    }

    @available(iOS 16.1, *)
    private func observeStateUpdates(
        for activity: Activity<SendrealmLiveActivityAttributes>
    ) {
        let observerKey = activity.id
        let activityId = activity.attributes.activity_id

        guard liveActivityStateUpdateTasks[observerKey] == nil else {
            return
        }

        liveActivityStateUpdateTasks[observerKey] = liveActivityMainObserverTask(
            activity.activityStateUpdates
        ) { [weak self] state in
            self?.observeLiveActivityStateUpdate(
                state,
                activityId: activityId,
                sendId: self?.sendId(for: activity),
                attributesType: self?.defaultLiveActivityAttributesType
            )
        }
    }

    @available(iOS 16.1, *)
    private func observeStateUpdates<Attributes: ActivityAttributes>(
        for activity: Activity<Attributes>,
        typeKey: String,
        activityId: @escaping @Sendable (Attributes) -> String?,
        attributesSendId: @escaping @Sendable (Attributes) -> String?
    ) {
        let observerKey = "\(typeKey):\(activity.id)"

        guard liveActivityStateUpdateTasks[observerKey] == nil else {
            return
        }

        liveActivityStateUpdateTasks[observerKey] = liveActivityMainObserverTask(
            activity.activityStateUpdates
        ) { [weak self] state in
            self?.observeLiveActivityStateUpdate(
                state,
                activityId: self?.customActivityId(for: activity, activityId: activityId),
                sendId: self?.customSendId(for: activity, attributesSendId: attributesSendId),
                attributesType: typeKey
            )
        }
    }

    private func handleObservedPushToStartToken(
        _ tokenData: Data,
        status: String,
        activityType: String?,
        attributesType: String?
    ) {
        liveActivityPushToStartObserved = true
        updateLiveActivityStatus(status)
        registerObservedLiveActivityToken(
            Sendrealm.hexString(forDeviceToken: tokenData),
            activityId: nil,
            tokenType: "ios_push_to_start",
            activityType: activityType,
            attributesType: attributesType
        )
    }

    private func handleObservedLiveActivityUpdateToken(
        _ tokenData: Data,
        activityId: String?,
        activityType: String?,
        attributesType: String?,
        sendId: String?
    ) {
        registerObservedLiveActivityToken(
            Sendrealm.hexString(forDeviceToken: tokenData),
            activityId: activityId,
            tokenType: "ios_update",
            activityType: activityType,
            attributesType: attributesType,
            sendId: sendId
        )
    }

    private func handleObservedLiveActivityContentUpdate(
        activityId: String?,
        sendId: String?,
        startSendId: String?,
        attributesType: String?
    ) {
        guard let activityId = normalizedString(activityId) else {
            return
        }

        trackLiveActivityUpdateReceiptIfNeeded(
            activityId: activityId,
            sendId: sendId,
            startSendId: startSendId,
            attributesType: attributesType
        )
    }

    @available(iOS 16.1, *)
    private func liveActivityStateName(_ state: ActivityState) -> String? {
        switch state {
        case .pending:
            return "pending"
        case .active:
            return "active"
        case .stale:
            return "stale"
        case .ended:
            return "ended"
        case .dismissed:
            return "dismissed"
        @unknown default:
            return nil
        }
    }

    private func liveActivityEventProperties(
        activityId: String,
        sendId: String?,
        activityState: String? = nil,
        attributesType: String? = nil
    ) -> [String: Any] {
        var properties: [String: Any] = [
            "activity_id": activityId
        ]

        if let sendId = normalizedString(sendId) {
            properties["send_id"] = sendId
        }
        if let activityState {
            properties["activity_state"] = activityState
        }
        if let attributesType = normalizedString(attributesType) {
            properties["attributes_type"] = attributesType
            properties["activity_type"] = attributesType
        }

        return properties
    }

    private func trackLiveActivityStateChange(
        activityId: String,
        sendId: String?,
        activityState: String,
        attributesType: String? = nil
    ) {
        switch activityState {
        case "pending", "stale":
            trackDeviceEvent(
                "live_activity_update",
                properties: liveActivityEventProperties(
                    activityId: activityId,
                    sendId: sendId,
                    activityState: activityState,
                    attributesType: attributesType
                ),
                enqueueOnFailure: true,
                completion: nil
            )
        case "active":
            trackLiveActivityReceiptIfNeeded(
                activityId: activityId,
                sendId: sendId,
                attributesType: attributesType
            )
        case "ended":
            trackDeviceEvent(
                "live_activity_end",
                properties: liveActivityEventProperties(
                    activityId: activityId,
                    sendId: sendId,
                    activityState: activityState,
                    attributesType: attributesType
                ),
                enqueueOnFailure: true,
                completion: nil
            )
        case "dismissed":
            trackDeviceEvent(
                "live_activity_dismiss",
                properties: liveActivityEventProperties(
                    activityId: activityId,
                    sendId: sendId,
                    activityState: activityState,
                    attributesType: attributesType
                ),
                enqueueOnFailure: true,
                completion: nil
            )
        default:
            return
        }
    }

    private func trackLiveActivityReceiptIfNeeded(
        activityId: String,
        sendId: String?,
        attributesType: String? = nil
    ) {
        guard !activityId.isEmpty else {
            return
        }

        let receiptKey = "\(normalizedString(attributesType) ?? ""):\(activityId):\(normalizedString(sendId) ?? "")"

        guard !liveActivityTrackedReceiptActivityIds.contains(receiptKey) else {
            return
        }

        liveActivityTrackedReceiptActivityIds.insert(receiptKey)
        trackDeviceEvent(
            "live_activity_start",
            properties: {
                var properties = liveActivityEventProperties(
                    activityId: activityId,
                    sendId: sendId,
                    attributesType: attributesType
                )
                properties["confirmation_source"] = "activitykit_activity_observed"
                return properties
            }(),
            enqueueOnFailure: true,
            completion: nil
        )
    }

    private func trackLiveActivityUpdateReceiptIfNeeded(
        activityId: String,
        sendId: String?,
        startSendId: String?,
        attributesType: String? = nil
    ) {
        guard !activityId.isEmpty, let sendId = normalizedString(sendId) else {
            return
        }

        if sendId == normalizedString(startSendId) {
            return
        }

        let receiptKey = "\(normalizedString(attributesType) ?? ""):\(activityId):\(sendId)"

        guard !liveActivityTrackedUpdateSendIds.contains(receiptKey) else {
            return
        }

        liveActivityTrackedUpdateSendIds.insert(receiptKey)
        trackDeviceEvent(
            "live_activity_update",
            properties: {
                var properties = liveActivityEventProperties(
                    activityId: activityId,
                    sendId: sendId,
                    attributesType: attributesType
                )
                properties["confirmation_source"] = "activitykit_content_observed"
                return properties
            }(),
            enqueueOnFailure: true,
            completion: nil
        )
    }

    private func registerObservedLiveActivityToken(
        _ token: String,
        activityId: String?,
        tokenType: String,
        activityType: String? = nil,
        attributesType: String? = nil,
        sendId: String? = nil
    ) {
        liveActivityLastTokenType = tokenType

        guard !hasRegisteredLiveActivityToken(
            token: token,
            activityId: activityId,
            tokenType: tokenType,
            activityType: activityType,
            attributesType: attributesType,
            sendId: sendId
        ) else {
            updateLiveActivityStatus("live_activity_token_already_registered")
            return
        }

        updateLiveActivityStatus("live_activity_token_registering")
        registerLiveActivityToken(
            token,
            activityId: activityId,
            tokenType: tokenType,
            activityType: activityType,
            attributesType: attributesType,
            sendId: sendId
        ) { [weak self] success, _ in
            if success.boolValue {
                self?.rememberLiveActivityTokenRegistration(
                    token: token,
                    activityId: activityId,
                    tokenType: tokenType,
                    activityType: activityType,
                    attributesType: attributesType,
                    sendId: sendId
                )
            }
        }
    }

    func testingLiveActivityEventProperties(
        activityId: String,
        sendId: String?,
        activityState: String? = nil,
        attributesType: String? = nil
    ) -> [String: Any] {
        liveActivityEventProperties(
            activityId: activityId,
            sendId: sendId,
            activityState: activityState,
            attributesType: attributesType
        )
    }

    func testingTrackLiveActivityReceiptIfNeeded(
        activityId: String,
        sendId: String?,
        attributesType: String? = nil
    ) {
        trackLiveActivityReceiptIfNeeded(
            activityId: activityId,
            sendId: sendId,
            attributesType: attributesType
        )
    }

    func testingTrackLiveActivityUpdateReceiptIfNeeded(
        activityId: String,
        sendId: String?,
        startSendId: String?,
        attributesType: String? = nil
    ) {
        trackLiveActivityUpdateReceiptIfNeeded(
            activityId: activityId,
            sendId: sendId,
            startSendId: startSendId,
            attributesType: attributesType
        )
    }

    func testingTrackLiveActivityStateChange(
        activityId: String,
        sendId: String?,
        activityState: String,
        attributesType: String? = nil
    ) {
        trackLiveActivityStateChange(
            activityId: activityId,
            sendId: sendId,
            activityState: activityState,
            attributesType: attributesType
        )
    }

    func testingHandleObservedPushToStartToken(
        _ tokenData: Data,
        status: String,
        activityType: String?,
        attributesType: String?
    ) {
        observeLiveActivityPushToStartToken(
            tokenData,
            status: status,
            activityType: activityType,
            attributesType: attributesType
        )
    }

    func testingHandleObservedLiveActivityUpdateToken(
        _ tokenData: Data,
        activityId: String?,
        activityType: String?,
        attributesType: String?,
        sendId: String?
    ) {
        observeLiveActivityUpdateToken(
            tokenData,
            activityId: activityId,
            activityType: activityType,
            attributesType: attributesType,
            sendId: sendId
        )
    }

    func testingHandleObservedLiveActivityContentUpdate(
        activityId: String?,
        sendId: String?,
        startSendId: String?,
        attributesType: String?
    ) {
        observeLiveActivityContentSendId(
            activityId: activityId,
            sendId: sendId,
            startSendId: startSendId,
            attributesType: attributesType
        )
    }

    @available(iOS 16.1, *)
    func testingObserveLiveActivityStateUpdate(
        _ state: ActivityState,
        activityId: String?,
        sendId: String?,
        attributesType: String?
    ) {
        observeLiveActivityStateUpdate(
            state,
            activityId: activityId,
            sendId: sendId,
            attributesType: attributesType
        )
    }

    @available(iOS 16.1, *)
    func testingLiveActivityStateName(_ state: ActivityState) -> String? {
        liveActivityStateName(state)
    }

    func testingDefaultLiveActivityAttributesType() -> String {
        defaultLiveActivityAttributesType
    }

    func testingRegisterObservedLiveActivityToken(
        _ token: String,
        activityId: String?,
        tokenType: String,
        activityType: String? = nil,
        attributesType: String? = nil,
        sendId: String? = nil
    ) {
        registerObservedLiveActivityToken(
            token,
            activityId: activityId,
            tokenType: tokenType,
            activityType: activityType,
            attributesType: attributesType,
            sendId: sendId
        )
    }
}
#else
extension Sendrealm {
    func startLiveActivityTokenObserversIfAvailable() {
        updateLiveActivityStatus("activitykit_unavailable")
    }
}
#endif
