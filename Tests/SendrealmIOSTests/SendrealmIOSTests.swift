import UserNotifications
import XCTest
@testable import SendrealmIOS

#if canImport(ActivityKit)
import ActivityKit
#endif

final class SendrealmIOSTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
        MockURLProtocol.requestHandler = nil
        Sendrealm.shared.testingResetState()
    }

    override func tearDown() {
        Sendrealm.shared.testingResetState()
        MockURLProtocol.requestHandler = nil
        URLProtocol.unregisterClass(MockURLProtocol.self)
        super.tearDown()
    }

    func testAPNSTokenHexEncoding() {
        let token = Data([0x00, 0x1a, 0xff, 0x7c])

        XCTAssertEqual(Sendrealm.hexString(forDeviceToken: token), "001aff7c")
    }

    func testBaseDevicePayloadContainsIOSFields() {
        let sdk = Sendrealm.shared
        sdk.testingSetState(
            appId: "app_123",
            baseUrl: "https://push.example.com",
            deviceId: "device_123",
            externalUserId: "user_123",
            userEmail: "person@example.com",
            apnsToken: "abc123",
            environment: "development",
            apnsEnvironment: "sandbox",
            subscribed: true,
            initialized: true
        )

        let payload = sdk.testingBaseDevicePayload(additional: [
            "device_id": "device_123",
            "registration_id": "abc123",
            "environment": "development",
            "apns_environment": "sandbox"
        ])

        XCTAssertEqual(payload["app_id"] as? String, "app_123")
        XCTAssertEqual(payload["platform"] as? String, "ios")
        XCTAssertEqual(payload["environment"] as? String, "development")
        XCTAssertEqual(payload["device_id"] as? String, "device_123")
        XCTAssertEqual(payload["registration_id"] as? String, "abc123")
        XCTAssertEqual(payload["apns_environment"] as? String, "sandbox")
        XCTAssertEqual(payload["sdk_version"] as? String, "0.1.2")
    }

    func testSanitizeJSONOmitsNilDictionaryValuesButKeepsExplicitNulls() {
        let payload: [String: Any?] = [
            "device_id": nil,
            "platform": "ios",
            "removed_tag": NSNull()
        ]

        let sanitized = Sendrealm.shared.testingSanitizeJSON(payload)

        XCTAssertNil(sanitized["device_id"])
        XCTAssertEqual(sanitized["platform"] as? String, "ios")
        XCTAssertTrue(sanitized["removed_tag"] is NSNull)
    }

    func testAPIErrorMessageIncludesValidationDetails() {
        let json: [String: Any] = [
            "error": [
                "code": "ValidationError",
                "message": "Validation Error",
                "details": [
                    [
                        "message": "\"device_id\" must be a string"
                    ]
                ]
            ]
        ]

        let message = Sendrealm.shared.testingAPIErrorMessage(json)

        XCTAssertEqual(
            message,
            "ValidationError - Validation Error - \"device_id\" must be a string"
        )
    }

    func testStatePersistenceRoundTrip() {
        let sdk = Sendrealm.shared
        sdk.testingSetState(
            appId: "app_123",
            baseUrl: "https://push.example.com",
            deviceId: "device_123",
            externalUserId: "user_123",
            userEmail: "person@example.com",
            apnsToken: "abc123",
            apnsEnvironment: "sandbox",
            subscribed: true,
            initialized: true
        )
        sdk.testingClearMemoryState()
        sdk.testingReloadState()

        let snapshot = sdk.testingStateSnapshot()
        XCTAssertEqual(snapshot["appId"] as? String, "app_123")
        XCTAssertEqual(snapshot["baseUrl"] as? String, "https://push.example.com")
        XCTAssertEqual(snapshot["deviceId"] as? String, "device_123")
        XCTAssertEqual(snapshot["externalUserId"] as? String, "user_123")
        XCTAssertEqual(snapshot["userEmail"] as? String, "person@example.com")
        XCTAssertEqual(snapshot["apnsToken"] as? String, "abc123")
        XCTAssertEqual(snapshot["apnsEnvironment"] as? String, "sandbox")
        XCTAssertEqual(snapshot["subscribed"] as? Bool, true)
        XCTAssertEqual(snapshot["initialized"] as? Bool, true)
    }

    func testPendingQueuesPersistEventsAndTags() {
        let sdk = Sendrealm.shared

        sdk.testingEnqueueEvent(
            eventType: "checkout_completed",
            notificationId: "notification_123",
            properties: ["order_id": "order_123"]
        )
        sdk.testingEnqueueTags([
            "plan": "pro",
            "signed_in": true
        ])

        let events = sdk.testingQueuedEvents()
        let tags = sdk.testingQueuedTags()

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0]["eventType"] as? String, "checkout_completed")
        XCTAssertEqual(events[0]["notificationId"] as? String, "notification_123")
        XCTAssertEqual((events[0]["properties"] as? [String: Any])?["order_id"] as? String, "order_123")
        XCTAssertEqual(tags["plan"] as? String, "pro")
        XCTAssertEqual(tags["signed_in"] as? Bool, true)
    }

    func testPendingOperationQueueAddsIdempotencyKeyAndCounts() {
        let sdk = Sendrealm.shared

        sdk.testingEnqueueOperation(
            name: "register",
            path: "/v1/register",
            payload: [
                "app_id": "app_123",
                "device_id": "device_123"
            ]
        )

        let operations = sdk.testingQueuedOperations()
        let payload = operations.first?["payload"] as? [String: Any]

        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?["name"] as? String, "register")
        XCTAssertEqual(operations.first?["path"] as? String, "/v1/register")
        XCTAssertNotNil(payload?["idempotency_key"] as? String)
        XCTAssertEqual(sdk.testingQueueCounts()["operations"], 1)
    }

    func testForegroundPresentationOptionsCanSuppressDisplay() {
        let sdk = Sendrealm.shared

        sdk.testingApplyForegroundPresentation([
            "display": false
        ])

        let diagnostics = sdk.testingForegroundPresentationDiagnostics()
        XCTAssertEqual(diagnostics["suppress"], true)
        XCTAssertEqual(diagnostics["banner"], false)
        XCTAssertEqual(diagnostics["list"], false)
        XCTAssertEqual(diagnostics["sound"], false)
        XCTAssertEqual(diagnostics["badge"], false)
    }

    func testAPNSPayloadWithOnlyMetadataIsNormalized() {
        let payload: NSDictionary = [
            "aps": [
                "alert": [
                    "title": "Hello",
                    "body": "World"
                ],
                "sound": "default",
                "badge": 3
            ],
            "sendrealm_v1": [
                "metadata": [
                    "notification_id": "notification-1",
                    "ios_launch_url": "myapp://orders/1",
                    "image_url": "https://example.com/image.jpg"
                ],
                "data": [
                    "order_id": "1"
                ]
            ]
        ]

        let event = Sendrealm.shared.notificationEvent(from: payload)
        let normalizedPayload = event["payload"] as? [String: Any]
        let notification = normalizedPayload?["notification"] as? [String: Any]
        let metadata = normalizedPayload?["metadata"] as? [String: Any]

        XCTAssertEqual(event["notificationId"] as? String, "notification-1")
        XCTAssertEqual(event["launchUrl"] as? String, "myapp://orders/1")
        XCTAssertEqual(notification?["title"] as? String, "Hello")
        XCTAssertEqual(notification?["body"] as? String, "World")
        XCTAssertEqual(metadata?["imageUrl"] as? String, "https://example.com/image.jpg")
    }

    func testNotificationMapIncludesDeliveryClickAndActionFields() {
        let payload: NSDictionary = [
            "aps": [
                "alert": [
                    "title": "Hello",
                    "body": "World"
                ]
            ],
            "sendrealm_v1": [
                "metadata": [
                    "notification_id": "notification-1",
                    "delivery_id": "delivery-1",
                    "click_id": "click-1",
                    "ios_launch_url": "myapp://orders/1"
                ]
            ]
        ]

        let event = Sendrealm.shared.notificationMap(
            from: payload,
            isForeground: false,
            actionIdentifier: "reply"
        )

        XCTAssertEqual(event["notificationId"] as? String, "notification-1")
        XCTAssertEqual(event["deliveryId"] as? String, "delivery-1")
        XCTAssertEqual(event["clickId"] as? String, "click-1")
        XCTAssertEqual(event["actionIdentifier"] as? String, "reply")
        XCTAssertEqual(event["isSilent"] as? Bool, false)
    }

    func testRegistrationFingerprintChangesWhenIdentityChanges() {
        let sdk = Sendrealm.shared
        sdk.testingSetState(
            appId: "app_123",
            baseUrl: "https://push.example.com",
            deviceId: "device_123",
            externalUserId: "user_123",
            userEmail: "person@example.com",
            apnsToken: "abc123",
            apnsEnvironment: "sandbox",
            subscribed: true,
            initialized: true
        )

        let first = sdk.testingRegistrationFingerprint()
        sdk.userEmail = "next@example.com"
        let second = sdk.testingRegistrationFingerprint()

        XCTAssertNotEqual(first, second)
    }

    func testPostJSONSendsSanitizedBodyAndReportsSuccess() throws {
        let sdk = Sendrealm.shared
        let expectation = expectation(description: "postJSON completes")
        var capturedRequest: URLRequest?
        var capturedBody: [String: Any]?
        sdk.testingSetState(
            appId: "app_123",
            baseUrl: "https://push.example.com///",
            deviceId: "device_123",
            externalUserId: nil,
            userEmail: nil,
            apnsToken: nil,
            apnsEnvironment: "production",
            subscribed: false,
            initialized: true
        )

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            capturedBody = try request.testingJSONBody()
            return try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 201,
                body: [
                    "ok": true
                ]
            )
        }

        sdk.postJSON(
            path: "/v1/tags",
            payload: [
                "app_id": "app_123",
                "device_id": nil,
                "tags": [
                    "plan": "pro",
                    "removed": NSNull()
                ]
            ],
            method: "PATCH"
        ) { json, success in
            XCTAssertTrue(success)
            XCTAssertEqual(json?["ok"] as? Bool, true)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2)

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://push.example.com/v1/tags")
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(capturedBody)
        XCTAssertEqual(body["app_id"] as? String, "app_123")
        XCTAssertNil(body["device_id"])
        XCTAssertEqual((body["tags"] as? [String: Any])?["plan"] as? String, "pro")
        XCTAssertTrue((body["tags"] as? [String: Any])?["removed"] is NSNull)
    }

    func testPostJSONReportsHTTPFailureAndParsesErrorBody() {
        let sdk = Sendrealm.shared
        let expectation = expectation(description: "postJSON completes")
        sdk.testingSetState(
            appId: "app_123",
            baseUrl: "https://push.example.com",
            deviceId: "device_123",
            externalUserId: nil,
            userEmail: nil,
            apnsToken: nil,
            apnsEnvironment: "production",
            subscribed: false,
            initialized: true
        )

        MockURLProtocol.requestHandler = { request in
            try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 422,
                body: [
                    "error": [
                        "code": "ValidationError",
                        "message": "Validation Error"
                    ]
                ]
            )
        }

        sdk.postJSON(path: "/v1/init", payload: ["app_id": "app_123"]) { json, success in
            XCTAssertFalse(success)
            let error = json?["error"] as? [String: Any]
            XCTAssertEqual(error?["code"] as? String, "ValidationError")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2)
    }

    func testRegisterAPNSTokenPostsExpectedPayloadAndUpdatesStateOnSuccess() throws {
        let sdk = Sendrealm.shared
        let expectation = expectation(description: "registerAPNSToken completes")
        var capturedRequest: URLRequest?
        var capturedBody: [String: Any]?
        sdk.testingSetState(
            appId: "app_123",
            baseUrl: "https://push.example.com",
            deviceId: "device_123",
            externalUserId: "user_123",
            userEmail: "person@example.com",
            apnsToken: nil,
            apnsEnvironment: "sandbox",
            subscribed: false,
            initialized: true
        )

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            capturedBody = try request.testingJSONBody()
            return try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 200,
                body: [
                    "status": 200,
                    "data": [
                        "app_id": "app_123",
                        "device_id": "device_123",
                        "registration_id": "apns-token"
                    ]
                ]
            )
        }

        sdk.registerAPNSToken("apns-token") { success in
            XCTAssertTrue(success)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2)

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.path, "/v1/register")
        XCTAssertEqual(request.httpMethod, "POST")

        let body = try XCTUnwrap(capturedBody)
        XCTAssertEqual(body["app_id"] as? String, "app_123")
        XCTAssertEqual(body["device_id"] as? String, "device_123")
        XCTAssertEqual(body["registration_id"] as? String, "apns-token")
        XCTAssertEqual(body["apns_device_token"] as? String, "apns-token")
        XCTAssertEqual(body["environment"] as? String, "production")
        XCTAssertEqual(body["apns_environment"] as? String, "sandbox")
        XCTAssertEqual(body["user_external_id"] as? String, "user_123")
        XCTAssertEqual(body["user_email"] as? String, "person@example.com")
        XCTAssertEqual(body["platform"] as? String, "ios")
        XCTAssertEqual(body["sdk_version"] as? String, "0.1.2")
        XCTAssertEqual(sdk.testingStateSnapshot()["subscribed"] as? Bool, true)
        XCTAssertEqual((sdk.lastRegisterResult?["success"] as? Bool), true)
        XCTAssertNotNil(sdk.testingRegistrationFingerprint())
    }

    func testRegisterAPNSTokenQueuesOperationAndStoresDiagnosticsOnFailure() {
        let sdk = Sendrealm.shared
        let expectation = expectation(description: "registerAPNSToken completes")
        sdk.testingSetState(
            appId: "app_123",
            baseUrl: "https://push.example.com",
            deviceId: "device_123",
            externalUserId: nil,
            userEmail: nil,
            apnsToken: nil,
            apnsEnvironment: "production",
            subscribed: false,
            initialized: true
        )

        MockURLProtocol.requestHandler = { request in
            try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 500,
                body: [
                    "error": [
                        "message": "Push API unavailable"
                    ]
                ]
            )
        }

        sdk.registerAPNSToken("apns-token") { success in
            XCTAssertFalse(success)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2)

        let operations = sdk.testingQueuedOperations()
        let queuedPayload = operations.first?["payload"] as? [String: Any]

        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?["name"] as? String, "register")
        XCTAssertEqual(operations.first?["path"] as? String, "/v1/register")
        XCTAssertEqual(queuedPayload?["registration_id"] as? String, "apns-token")
        XCTAssertEqual(sdk.lastRegisterResult?["success"] as? Bool, false)
        XCTAssertEqual(sdk.lastSdkError?["code"] as? String, "E_REGISTER_FAILED")
    }

    func testFlushQueuedOperationsRetriesThenClearsOnSuccess() throws {
        let sdk = Sendrealm.shared
        var capturedBodies: [[String: Any]] = []
        sdk.testingSetState(
            appId: "app_123",
            baseUrl: "https://push.example.com",
            deviceId: "device_123",
            externalUserId: nil,
            userEmail: nil,
            apnsToken: nil,
            apnsEnvironment: "production",
            subscribed: true,
            initialized: true
        )
        sdk.testingEnqueueOperation(
            name: "track_event",
            path: "/v1/track",
            payload: [
                "app_id": "app_123",
                "device_id": "device_123",
                "event_type": "checkout_completed"
            ]
        )
        let originalKey = try XCTUnwrap(
            (sdk.testingQueuedOperations().first?["payload"] as? [String: Any])?["idempotency_key"] as? String
        )

        MockURLProtocol.requestHandler = { request in
            capturedBodies.append(try request.testingJSONBody())
            return try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 503,
                body: ["error": ["message": "unavailable"]]
            )
        }

        sdk.flushQueuedOperations()
        waitUntil("operation retry is persisted") {
            (sdk.testingQueuedOperations().first?["retryCount"] as? Int) == 1
        }

        let retried = try XCTUnwrap(sdk.testingQueuedOperations().first)
        let retriedPayload = try XCTUnwrap(retried["payload"] as? [String: Any])
        XCTAssertEqual(retriedPayload["idempotency_key"] as? String, originalKey)
        XCTAssertEqual(capturedBodies.first?["idempotency_key"] as? String, originalKey)
        XCTAssertEqual(retried["lastError"] as? String, "unavailable")
        sdk.testingMakeQueuedOperationsReady()

        MockURLProtocol.requestHandler = { request in
            capturedBodies.append(try request.testingJSONBody())
            return try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 200,
                body: ["ok": true]
            )
        }

        sdk.flushQueuedOperations()
        waitUntil("operation queue is cleared") {
            sdk.testingQueuedOperations().isEmpty
        }

        XCTAssertEqual(capturedBodies.count, 2)
        XCTAssertEqual(capturedBodies.last?["idempotency_key"] as? String, originalKey)
    }

    func testPublicMutationsQueueTagsEventsAndSubscriptionsOnFailure() {
        let sdk = Sendrealm.shared
        let removeTagExpectation = expectation(description: "removeTag completes")
        let trackEventExpectation = expectation(description: "trackEvent completes")
        let optOutExpectation = expectation(description: "optOut completes")
        sdk.testingSetState(
            appId: "app_123",
            baseUrl: "https://push.example.com",
            deviceId: "device_123",
            externalUserId: nil,
            userEmail: nil,
            apnsToken: "apns-token",
            apnsEnvironment: "production",
            subscribed: true,
            initialized: true
        )

        MockURLProtocol.requestHandler = { request in
            try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 500,
                body: ["error": ["message": "offline"]]
            )
        }

        sdk.removeTag("plan") { success in
            XCTAssertEqual(success.boolValue, true)
            removeTagExpectation.fulfill()
        }
        wait(for: [removeTagExpectation], timeout: 2)

        sdk.trackEvent("checkout_completed", properties: ["order_id": "order_123"]) { success, error in
            XCTAssertNil(error)
            XCTAssertEqual(success.boolValue, true)
            trackEventExpectation.fulfill()
        }
        wait(for: [trackEventExpectation], timeout: 2)

        sdk.optOut { success in
            XCTAssertEqual(success.boolValue, false)
            optOutExpectation.fulfill()
        }
        wait(for: [optOutExpectation], timeout: 2)

        XCTAssertTrue(sdk.testingQueuedTags()["plan"] is NSNull)
        XCTAssertEqual(sdk.testingQueuedEvents().first?["eventType"] as? String, "checkout_completed")
        XCTAssertEqual(sdk.testingQueuedOperations().first?["name"] as? String, "opt_out")
        XCTAssertEqual(sdk.testingQueueCounts()["tags"], 1)
        XCTAssertEqual(sdk.testingQueueCounts()["events"], 1)
        XCTAssertEqual(sdk.testingQueueCounts()["operations"], 1)
    }

    func testLiveActivityTokenQueuesUntilDeviceIsReadyThenFlushes() throws {
        let sdk = Sendrealm.shared
        let queuedExpectation = expectation(description: "live activity token queues")
        var capturedBody: [String: Any]?
        sdk.testingSetState(
            appId: "app_123",
            baseUrl: "https://push.example.com",
            deviceId: nil,
            externalUserId: nil,
            userEmail: nil,
            apnsToken: nil,
            apnsEnvironment: "production",
            subscribed: false,
            initialized: true
        )

        sdk.registerLiveActivityToken(
            "activity-token",
            activityId: "activity_123",
            tokenType: "ios_update",
            activityType: "DeliveryActivity",
            attributesType: "DeliveryAttributes"
        ) { success, error in
            XCTAssertEqual(success.boolValue, false)
            XCTAssertEqual(error?.userInfo["code"] as? String, "E_DEVICE_NOT_READY")
            queuedExpectation.fulfill()
        }
        wait(for: [queuedExpectation], timeout: 2)
        XCTAssertEqual(sdk.testingQueueCounts()["liveActivityTokens"], 1)

        sdk.testingSetState(
            appId: "app_123",
            baseUrl: "https://push.example.com",
            deviceId: "device_123",
            externalUserId: nil,
            userEmail: nil,
            apnsToken: nil,
            apnsEnvironment: "production",
            subscribed: false,
            initialized: true
        )
        MockURLProtocol.requestHandler = { request in
            capturedBody = try request.testingJSONBody()
            return try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 200,
                body: ["ok": true]
            )
        }

        sdk.flushPendingLiveActivityTokenRegistrations()
        waitUntil("live activity token queue clears") {
            sdk.testingQueueCounts()["liveActivityTokens"] == 0 &&
                (sdk.liveActivityDiagnostics()["registrationSuccesses"] as? Int) == 1
        }

        let body = try XCTUnwrap(capturedBody)
        XCTAssertEqual(body["token"] as? String, "activity-token")
        XCTAssertEqual(body["token_type"] as? String, "ios_update")
        XCTAssertEqual(body["activity_id"] as? String, "activity_123")
        XCTAssertEqual(body["activity_type"] as? String, "DeliveryActivity")
        XCTAssertEqual(body["attributes_type"] as? String, "DeliveryAttributes")
    }

    func testNotificationActionFallbackIdentifiersAndLaunchUrlPrecedence() {
        let payload: NSDictionary = [
            "aps": [
                "alert": [
                    "title": "Order ready",
                    "body": "Tap to view"
                ]
            ],
            "sendrealm_v1": [
                "metadata": [
                    "notification_id": "notification-1",
                    "ios_launch_url": "myapp://notification"
                ],
                "actions": [
                    [
                        "id": "view",
                        "text": "View",
                        "launch_url": "myapp://action"
                    ]
                ]
            ]
        ]

        let event = Sendrealm.shared.notificationMap(
            from: payload,
            isForeground: false,
            actionIdentifier: Sendrealm.defaultActionIdentifiers[0]
        )
        let action = event["action"] as? [String: Any]
        let normalizedPayload = event["payload"] as? [String: Any]
        let actions = normalizedPayload?["actions"] as? [[String: Any]]

        XCTAssertEqual(event["actionIdentifier"] as? String, "view")
        XCTAssertEqual(event["launchUrl"] as? String, "myapp://action")
        XCTAssertEqual(action?["title"] as? String, "View")
        XCTAssertEqual((actions?.first)?["launchUrl"] as? String, "myapp://action")
    }

    func testNotificationUserInfoEmitsEventsAndQueuesDeliveryAndOpenTracking() throws {
        let sdk = Sendrealm.shared
        let delegate = CapturingSendrealmDelegate()
        sdk.delegate = delegate
        sdk.testingSetState(
            appId: "app_123",
            baseUrl: "https://push.example.com",
            deviceId: "device_123",
            externalUserId: nil,
            userEmail: nil,
            apnsToken: "apns-token",
            apnsEnvironment: "production",
            subscribed: true,
            initialized: true
        )
        MockURLProtocol.requestHandler = { request in
            try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: request.url?.path == "/v1/track" ? 500 : 200,
                body: ["ok": false]
            )
        }
        let userInfo: NSDictionary = [
            "aps": [
                "alert": [
                    "title": "Order ready",
                    "body": "Tap to view"
                ]
            ],
            "sendrealm_v1": [
                "metadata": [
                    "notification_id": "notif_ios_1",
                    "delivery_id": "delivery_ios_1",
                    "click_id": "click_ios_1",
                    "ios_launch_url": "myapp://ios-order",
                    "launch_url": "https://example.com/orders/1",
                    "image_url": "https://cdn.example.com/order.png"
                ],
                "actions": [
                    [
                        "id": "view",
                        "text": "View",
                        "launch_url": "myapp://action"
                    ]
                ]
            ]
        ]

        sdk.handleNotificationUserInfo(userInfo, opened: false)

        waitUntil("delivery tracking operation queues") {
            sdk.testingQueuedOperations()
                .contains { $0["name"] as? String == "track_delivery" }
        }

        sdk.handleNotificationUserInfo(userInfo, opened: true)

        waitUntil("open tracking operation queues") {
            sdk.testingQueuedOperations()
                .contains { $0["name"] as? String == "track_open" }
        }

        XCTAssertEqual(
            delegate.events.map(\.name),
            [
                Sendrealm.eventForegroundNotification,
                Sendrealm.eventNotificationClicked
            ]
        )
        let foregroundEvent = try XCTUnwrap(delegate.events.first?.body)
        let foregroundPayload = try XCTUnwrap(foregroundEvent["payload"] as? [String: Any])
        let foregroundMetadata = try XCTUnwrap(foregroundPayload["metadata"] as? [String: Any])
        XCTAssertEqual(foregroundEvent["notificationId"] as? String, "notif_ios_1")
        XCTAssertEqual(foregroundEvent["deliveryId"] as? String, "delivery_ios_1")
        XCTAssertEqual(foregroundEvent["clickId"] as? String, "click_ios_1")
        XCTAssertEqual(foregroundEvent["launchUrl"] as? String, "myapp://ios-order")
        XCTAssertEqual(foregroundMetadata["imageUrl"] as? String, "https://cdn.example.com/order.png")

        let openEvent = try XCTUnwrap(delegate.events.last?.body)
        XCTAssertEqual(openEvent["notificationId"] as? String, "notif_ios_1")
        XCTAssertEqual(openEvent["launchUrl"] as? String, "myapp://ios-order")

        let operations = sdk.testingQueuedOperations()
        let deliveryOperation = try XCTUnwrap(
            operations.first { $0["name"] as? String == "track_delivery" }
        )
        let deliveryPayload = try XCTUnwrap(deliveryOperation["payload"] as? [String: Any])
        XCTAssertEqual(deliveryPayload["event_type"] as? String, "delivery")
        XCTAssertEqual(deliveryPayload["notification_id"] as? String, "notif_ios_1")

        let openOperation = try XCTUnwrap(
            operations.first { $0["name"] as? String == "track_open" }
        )
        let openPayload = try XCTUnwrap(openOperation["payload"] as? [String: Any])
        XCTAssertEqual(openPayload["event_type"] as? String, "open")
        XCTAssertEqual(openPayload["notification_id"] as? String, "notif_ios_1")
    }

    func testPublicInitializeStateLoginLogoutAndTokenWrappers() throws {
        let sdk = Sendrealm.shared
        let initializeExpectation = expectation(description: "initialize completes")
        let setTokenExpectation = expectation(description: "set token completes")
        let loginExpectation = expectation(description: "login completes")
        let logoutExpectation = expectation(description: "logout completes")
        let stateExpectation = expectation(description: "state completes")
        let diagnosticsExpectation = expectation(description: "diagnostics completes")
        var capturedBodies: [[String: Any]] = []
        sdk.notificationCenterIntegrationDisabledForTesting = true
        sdk.notificationPermissionStatusForTesting = "authorized"
        sdk.testingSetState(
            appId: nil,
            baseUrl: nil,
            deviceId: nil,
            externalUserId: nil,
            userEmail: nil,
            apnsToken: nil,
            apnsEnvironment: "production",
            subscribed: false,
            initialized: false
        )
        MockURLProtocol.requestHandler = { request in
            capturedBodies.append(try request.testingJSONBody())
            let body: [String: Any]
            if request.url?.path == "/v1/init" {
                body = [
                    "status": 200,
                    "data": [
                        "device_id": "device_public_1"
                    ]
                ]
            } else {
                body = [
                    "status": 200,
                    "data": [
                        "device_id": "device_public_1",
                        "registration_id": "apns-token-public"
                    ]
                ]
            }
            return try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 200,
                body: body
            )
        }

        sdk.initialize([
            "appId": "app_public",
            "baseUrl": "https://push.example.com///",
            "externalUserId": "User_Public",
            "userEmail": "PUBLIC@EXAMPLE.COM",
            "apnsEnvironment": "development",
            "autoRequestPermission": false,
            "foregroundPresentation": [
                "banner": false,
                "list": true,
                "sound": false,
                "badge": true
            ]
        ]) { result, error in
            XCTAssertNil(error)
            XCTAssertEqual(result?["deviceId"] as? String, "device_public_1")
            initializeExpectation.fulfill()
        }
        wait(for: [initializeExpectation], timeout: 2)

        sdk.setAPNSToken(" apns-token-public ") { token, error in
            XCTAssertNil(error)
            XCTAssertEqual(token as String?, "apns-token-public")
            setTokenExpectation.fulfill()
        }
        wait(for: [setTokenExpectation], timeout: 2)
        waitUntil("apns token registration posts") {
            capturedBodies.contains {
                $0["registration_id"] as? String == "apns-token-public"
            }
        }

        sdk.login(" next_user ", email: "NEXT@EXAMPLE.COM") { error in
            XCTAssertNil(error)
            loginExpectation.fulfill()
        }
        wait(for: [loginExpectation], timeout: 2)

        sdk.logout { error in
            XCTAssertNil(error)
            logoutExpectation.fulfill()
        }
        wait(for: [logoutExpectation], timeout: 2)

        sdk.getState { state in
            XCTAssertEqual(state["initialized"] as? Bool, true)
            XCTAssertEqual(state["registered"] as? Bool, true)
            XCTAssertEqual(state["deviceId"] as? String, "device_public_1")
            XCTAssertEqual(state["registrationToken"] as? String, "apns-token-public")
            XCTAssertEqual(state["platform"] as? String, "ios")
            XCTAssertEqual(state["environment"] as? String, "production")
            XCTAssertEqual(state["apnsEnvironment"] as? String, "sandbox")
            XCTAssertTrue(state["liveActivity"] is [String: Any])
            stateExpectation.fulfill()
        }
        wait(for: [stateExpectation], timeout: 2)

        sdk.getDiagnostics { diagnostics in
            XCTAssertEqual(diagnostics["appId"] as? String, "app_public")
            XCTAssertEqual(diagnostics["apiUrl"] as? String, "https://push.example.com///")
            XCTAssertEqual(diagnostics["apiUrlSource"] as? String, "options")
            XCTAssertEqual(diagnostics["platform"] as? String, "ios")
            XCTAssertEqual(diagnostics["registrationTokenPresent"] as? Bool, true)
            XCTAssertTrue(diagnostics["foregroundPresentation"] is [String: Bool])
            diagnosticsExpectation.fulfill()
        }
        wait(for: [diagnosticsExpectation], timeout: 2)

        XCTAssertEqual(capturedBodies.first?["app_id"] as? String, "app_public")
        XCTAssertEqual(sdk.testingStateSnapshot()["externalUserId"] as? String, nil)
        XCTAssertEqual(sdk.testingStateSnapshot()["userEmail"] as? String, nil)
    }

    func testLiveActivityTrackingHelpersQueueAndDeduplicateEvents() throws {
        let sdk = Sendrealm.shared
        sdk.testingSetState(
            appId: "app_123",
            baseUrl: "https://push.example.com",
            deviceId: "device_123",
            externalUserId: nil,
            userEmail: nil,
            apnsToken: "apns-token",
            apnsEnvironment: "production",
            subscribed: true,
            initialized: true
        )
        MockURLProtocol.requestHandler = { request in
            let statusCode = request.url?.path == "/v1/live-activities/tokens" ? 200 : 500
            return try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: statusCode,
                body: ["ok": statusCode == 200]
            )
        }

        let properties = sdk.testingLiveActivityEventProperties(
            activityId: "activity_123",
            sendId: "send_123",
            activityState: "active",
            attributesType: "DeliveryAttributes"
        )
        XCTAssertEqual(properties["activity_id"] as? String, "activity_123")
        XCTAssertEqual(properties["send_id"] as? String, "send_123")
        XCTAssertEqual(properties["activity_state"] as? String, "active")
        XCTAssertEqual(properties["activity_type"] as? String, "DeliveryAttributes")

        sdk.testingTrackLiveActivityReceiptIfNeeded(activityId: "", sendId: "ignored")
        sdk.testingTrackLiveActivityReceiptIfNeeded(
            activityId: "activity_123",
            sendId: "send_123",
            attributesType: "DeliveryAttributes"
        )
        sdk.testingTrackLiveActivityReceiptIfNeeded(
            activityId: "activity_123",
            sendId: "send_123",
            attributesType: "DeliveryAttributes"
        )
        sdk.testingTrackLiveActivityUpdateReceiptIfNeeded(
            activityId: "activity_123",
            sendId: "send_123",
            startSendId: "send_123",
            attributesType: "DeliveryAttributes"
        )
        sdk.testingTrackLiveActivityUpdateReceiptIfNeeded(
            activityId: "activity_123",
            sendId: nil,
            startSendId: "send_123",
            attributesType: "DeliveryAttributes"
        )
        sdk.testingTrackLiveActivityUpdateReceiptIfNeeded(
            activityId: "activity_123",
            sendId: "send_456",
            startSendId: "send_123",
            attributesType: "DeliveryAttributes"
        )
        sdk.testingTrackLiveActivityUpdateReceiptIfNeeded(
            activityId: "activity_123",
            sendId: "send_456",
            startSendId: "send_123",
            attributesType: "DeliveryAttributes"
        )

        waitUntil("live activity tracking operations queue") {
            let names = sdk.testingQueuedOperations().compactMap { $0["name"] as? String }
            return names.contains("track_live_activity_start") &&
                names.contains("track_live_activity_update")
        }
        let operationNames = sdk.testingQueuedOperations().compactMap { $0["name"] as? String }
        XCTAssertEqual(operationNames.filter { $0 == "track_live_activity_start" }.count, 1)
        XCTAssertEqual(operationNames.filter { $0 == "track_live_activity_update" }.count, 1)

        sdk.testingRegisterObservedLiveActivityToken(
            "observed-token",
            activityId: "activity_123",
            tokenType: "ios_update",
            activityType: "DeliveryActivity",
            attributesType: "DeliveryAttributes",
            sendId: "send_123"
        )
        waitUntil("observed live activity token registers") {
            (sdk.liveActivityDiagnostics()["registrationSuccesses"] as? Int) == 1
        }
        sdk.testingRegisterObservedLiveActivityToken(
            "observed-token",
            activityId: "activity_123",
            tokenType: "ios_update",
            activityType: "DeliveryActivity",
            attributesType: "DeliveryAttributes",
            sendId: "send_123"
        )
        XCTAssertEqual(sdk.liveActivityDiagnostics()["status"] as? String, "live_activity_token_already_registered")
    }

    func testDuplicateOpenKeysAreRememberedAndSuppressed() {
        let event: NSDictionary = [
            "clickId": "click_123",
            "notificationId": "notification_123"
        ]

        XCTAssertFalse(Sendrealm.shared.isDuplicateOpen(event))
        XCTAssertTrue(Sendrealm.shared.isDuplicateOpen(event))
    }

    func testNotificationServiceHelperNormalizesDynamicActionsAndImageUrl() {
        let diagnostics = SendrealmNotificationServiceHelper.testingActionDiagnostics(
            userInfo: [
                "sendrealm_v1": [
                    "metadata": [
                        "image_url": "https://example.com/image.jpg"
                    ],
                    "actions": [
                        [
                            "id": "view",
                            "text": "View"
                        ],
                        [
                            "title": "Track"
                        ]
                    ]
                ]
            ],
            categoryIdentifier: Sendrealm.defaultActionCategory
        )
        let actions = diagnostics["actions"] as? [[String: String]]

        XCTAssertEqual(diagnostics["usesDefaultCategory"] as? Bool, true)
        XCTAssertTrue((diagnostics["dynamicCategoryIdentifier"] as? String)?.hasPrefix("sendrealm_actions_2_") == true)
        XCTAssertEqual(diagnostics["imageUrl"] as? String, "https://example.com/image.jpg")
        XCTAssertEqual((actions?.first)?["identifier"], "view")
        XCTAssertEqual((actions?.first)?["title"], "View")
        XCTAssertEqual((actions?.last)?["identifier"], "sendrealm_action_2")
        XCTAssertEqual((actions?.last)?["title"], "Track")

        let malformed = SendrealmNotificationServiceHelper.testingActionDiagnostics(
            userInfo: [
                "sendrealm_v1": "{malformed-json",
                "imageUrl": ""
            ],
            categoryIdentifier: "custom"
        )

        XCTAssertEqual(malformed["usesDefaultCategory"] as? Bool, false)
        XCTAssertTrue(malformed["dynamicCategoryIdentifier"] is NSNull)
        XCTAssertTrue(malformed["imageUrl"] is NSNull)
    }

    func testPublicValidationPermissionBadgeAndTokenRefreshPaths() {
        let sdk = Sendrealm.shared
        sdk.applicationIntegrationDisabledForTesting = true
        sdk.notificationPermissionStatusForTesting = "denied"
        sdk.testingSetState(
            appId: "app_public",
            baseUrl: "https://push.example.com",
            deviceId: "device_public",
            externalUserId: nil,
            userEmail: nil,
            apnsToken: "token_public",
            apnsEnvironment: "production",
            subscribed: false,
            initialized: true
        )

        let initializeExpectation = expectation(description: "invalid initialize completes")
        sdk.initialize([:]) { result, error in
            XCTAssertNil(result)
            XCTAssertEqual(error?.userInfo["code"] as? String, "E_INVALID_OPTIONS")
            initializeExpectation.fulfill()
        }
        wait(for: [initializeExpectation], timeout: 2)

        let loginExpectation = expectation(description: "invalid login completes")
        sdk.login("   ", email: nil) { error in
            XCTAssertEqual(error?.userInfo["code"] as? String, "E_INVALID_USER_ID")
            loginExpectation.fulfill()
        }
        wait(for: [loginExpectation], timeout: 2)

        let tokenExpectation = expectation(description: "invalid token completes")
        sdk.setAPNSToken(" ") { token, error in
            XCTAssertNil(token)
            XCTAssertEqual(error?.userInfo["code"] as? String, "E_INVALID_APNS_TOKEN")
            tokenExpectation.fulfill()
        }
        wait(for: [tokenExpectation], timeout: 2)

        let requestPermissionExpectation = expectation(description: "request permission override completes")
        sdk.requestPermission { granted, error in
            XCTAssertNil(error)
            XCTAssertEqual(granted?.boolValue, false)
            requestPermissionExpectation.fulfill()
        }
        wait(for: [requestPermissionExpectation], timeout: 2)

        let permissionStatusExpectation = expectation(description: "permission status override completes")
        sdk.getPermissionStatus { status in
            XCTAssertEqual(status as String, "denied")
            permissionStatusExpectation.fulfill()
        }
        wait(for: [permissionStatusExpectation], timeout: 2)

        let hasPermissionExpectation = expectation(description: "has permission override completes")
        sdk.hasNotificationPermission { granted in
            XCTAssertFalse(granted)
            hasPermissionExpectation.fulfill()
        }
        wait(for: [hasPermissionExpectation], timeout: 2)

        let addTagExpectation = expectation(description: "invalid add tag completes")
        sdk.addTag(" ", value: "ignored") { success, error in
            XCTAssertFalse(success.boolValue)
            XCTAssertEqual(error?.userInfo["code"] as? String, "E_INVALID_TAG")
            addTagExpectation.fulfill()
        }
        wait(for: [addTagExpectation], timeout: 2)

        let emptyTagsExpectation = expectation(description: "empty add tags completes")
        sdk.addTags([:]) { success, error in
            XCTAssertNil(error)
            XCTAssertFalse(success.boolValue)
            emptyTagsExpectation.fulfill()
        }
        wait(for: [emptyTagsExpectation], timeout: 2)

        let removeTagExpectation = expectation(description: "invalid remove tag completes")
        sdk.removeTag(" ") { success in
            XCTAssertFalse(success.boolValue)
            removeTagExpectation.fulfill()
        }
        wait(for: [removeTagExpectation], timeout: 2)

        let eventExpectation = expectation(description: "invalid event completes")
        sdk.trackEvent(" ", properties: nil) { success, error in
            XCTAssertFalse(success.boolValue)
            XCTAssertEqual(error?.userInfo["code"] as? String, "E_INVALID_EVENT_TYPE")
            eventExpectation.fulfill()
        }
        wait(for: [eventExpectation], timeout: 2)

        let foregroundExpectation = expectation(description: "foreground presentation completes")
        sdk.setForegroundPresentation(["display": false]) { success in
            XCTAssertTrue(success.boolValue)
            foregroundExpectation.fulfill()
        }
        wait(for: [foregroundExpectation], timeout: 2)
        XCTAssertEqual(sdk.foregroundPresentationDiagnostics()["suppress"], true)

        let deviceExpectation = expectation(description: "device id completes")
        sdk.getDeviceId { deviceId in
            XCTAssertEqual(deviceId as String?, "device_public")
            deviceExpectation.fulfill()
        }
        wait(for: [deviceExpectation], timeout: 2)

        let subscribedExpectation = expectation(description: "subscribed completes")
        sdk.isSubscribed { subscribed in
            XCTAssertFalse(subscribed.boolValue)
            subscribedExpectation.fulfill()
        }
        wait(for: [subscribedExpectation], timeout: 2)

        let badgeExpectation = expectation(description: "badge completes")
        sdk.setBadgeCount(-3) { success in
            XCTAssertTrue(success.boolValue)
            badgeExpectation.fulfill()
        }
        wait(for: [badgeExpectation], timeout: 2)

        let clearBadgeExpectation = expectation(description: "clear badge completes")
        sdk.clearBadge { success in
            XCTAssertTrue(success.boolValue)
            clearBadgeExpectation.fulfill()
        }
        wait(for: [clearBadgeExpectation], timeout: 2)

        let settingsExpectation = expectation(description: "settings completes")
        sdk.openNotificationSettings { opened in
            XCTAssertFalse(opened.boolValue)
            settingsExpectation.fulfill()
        }
        wait(for: [settingsExpectation], timeout: 2)

        MockURLProtocol.requestHandler = { request in
            try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 200,
                body: ["ok": true]
            )
        }
        let refreshExpectation = expectation(description: "refresh token completes")
        sdk.refreshRegistrationToken(true) { token in
            XCTAssertEqual(token as String?, "token_public")
            refreshExpectation.fulfill()
        }
        wait(for: [refreshExpectation], timeout: 2)

        sdk.apnsToken = nil
        let missingRefreshExpectation = expectation(description: "missing refresh token completes")
        sdk.refreshRegistrationToken(false) { token in
            XCTAssertNil(token)
            missingRefreshExpectation.fulfill()
        }
        wait(for: [missingRefreshExpectation], timeout: 2)
    }

    func testPublicLiveActivityDeleteSyncAndDeepLinks() {
        let sdk = Sendrealm.shared
        sdk.applicationIntegrationDisabledForTesting = true
        sdk.testingSetState(
            appId: "app_live",
            baseUrl: "https://push.example.com",
            deviceId: nil,
            externalUserId: nil,
            userEmail: nil,
            apnsToken: "apns-token",
            apnsEnvironment: "production",
            subscribed: true,
            initialized: true
        )

        let invalidRegisterExpectation = expectation(description: "invalid live token completes")
        sdk.registerLiveActivityToken(" ", activityId: nil, tokenType: nil) { success, error in
            XCTAssertFalse(success.boolValue)
            XCTAssertEqual(error?.userInfo["code"] as? String, "E_INVALID_LIVE_ACTIVITY_TOKEN")
            invalidRegisterExpectation.fulfill()
        }
        wait(for: [invalidRegisterExpectation], timeout: 2)

        let missingDeleteExpectation = expectation(description: "missing device delete completes")
        sdk.deleteLiveActivityToken("token-delete", activityId: "activity_1", tokenType: "ios_update") { success, error in
            XCTAssertFalse(success.boolValue)
            XCTAssertEqual(error?.userInfo["code"] as? String, "E_DEVICE_NOT_READY")
            missingDeleteExpectation.fulfill()
        }
        wait(for: [missingDeleteExpectation], timeout: 2)

        sdk.testingSetState(
            appId: "app_live",
            baseUrl: "https://push.example.com",
            deviceId: "device_live",
            externalUserId: nil,
            userEmail: nil,
            apnsToken: "apns-token",
            apnsEnvironment: "production",
            subscribed: true,
            initialized: true
        )
        var capturedMethods: [String] = []
        var capturedBodies: [[String: Any]] = []
        MockURLProtocol.requestHandler = { request in
            capturedMethods.append(request.httpMethod ?? "")
            capturedBodies.append(try request.testingJSONBody())
            let statusCode = request.url?.path == "/v1/live-activities/tokens" ? 200 : 500
            return try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: statusCode,
                body: ["ok": statusCode == 200]
            )
        }

        let deleteExpectation = expectation(description: "delete live token completes")
        sdk.deleteLiveActivityToken(
            "token-delete",
            activityId: "activity_1",
            tokenType: nil,
            activityType: "DeliveryActivity",
            attributesType: nil
        ) { success, error in
            XCTAssertNil(error)
            XCTAssertTrue(success.boolValue)
            deleteExpectation.fulfill()
        }
        wait(for: [deleteExpectation], timeout: 2)
        XCTAssertEqual(capturedMethods.last, "DELETE")
        XCTAssertEqual(capturedBodies.last?["token_type"] as? String, "ios_update")
        XCTAssertEqual(capturedBodies.last?["activity_type"] as? String, "DeliveryActivity")
        XCTAssertEqual(capturedBodies.last?["attributes_type"] as? String, "DeliveryActivity")

        let syncExpectation = expectation(description: "sync live activity completes")
        sdk.syncLiveActivityTokens { success in
            XCTAssertTrue(success.boolValue)
            syncExpectation.fulfill()
        }
        wait(for: [syncExpectation], timeout: 2)
        XCTAssertNotNil(sdk.liveActivityDiagnostics()["status"])

        MockURLProtocol.requestHandler = { request in
            capturedBodies.append(try request.testingJSONBody())
            return try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 500,
                body: ["error": ["message": "offline"]]
            )
        }
        XCTAssertFalse(sdk.handleOpenURL(URL(string: "myapp://other/live-activity-action?target_url=myapp%3A%2F%2Forders%2F1")!))
        XCTAssertFalse(sdk.handleOpenURL(URL(string: "myapp://sendrealm/live-activity-action")!))
        XCTAssertTrue(
            sdk.handleOpenURL(
                URL(string: "myapp://sendrealm/live-activity-action?target_url=myapp%3A%2F%2Forders%2F1&activity_id=activity_1&send_id=send_1&action_id=confirm")!
            )
        )
        XCTAssertTrue(
            Sendrealm.handleOpenURL(
                URL(string: "myapp://sendrealm/live-activity-open?target_url=myapp%3A%2F%2Forders%2F2&activity_id=activity_2")!
            )
        )
        waitUntil("deep link events queue") {
            let names = sdk.testingQueuedOperations().compactMap { $0["name"] as? String }
            return names.contains("track_live_activity_action") &&
                names.contains("track_live_activity_open")
        }
    }

    func testPublicInitializeFailureOptInOutSuccessAndNetworkGuards() {
        let sdk = Sendrealm.shared
        sdk.notificationCenterIntegrationDisabledForTesting = true
        sdk.notificationPermissionStatusForTesting = "authorized"
        sdk.applicationIntegrationDisabledForTesting = true
        MockURLProtocol.requestHandler = { request in
            try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 500,
                body: ["error": ["code": "InitFailed", "message": "offline"]]
            )
        }

        let failedInitializeExpectation = expectation(description: "failed initialize completes")
        sdk.initialize([
            "appId": "app_failure",
            "baseUrl": "https://push.example.com",
            "autoRequestPermission": false
        ]) { result, error in
            XCTAssertNil(result)
            XCTAssertEqual(error?.userInfo["code"] as? String, "E_INIT_FAILED")
            XCTAssertEqual(error?.localizedDescription, "InitFailed - offline")
            failedInitializeExpectation.fulfill()
        }
        wait(for: [failedInitializeExpectation], timeout: 2)
        XCTAssertEqual(sdk.lastInitResult?["success"] as? Bool, false)
        XCTAssertEqual(sdk.lastSdkError?["code"] as? String, "E_INIT_FAILED")

        sdk.testingResetState()
        sdk.applicationIntegrationDisabledForTesting = true
        sdk.testingSetState(
            appId: "app_subscribe",
            baseUrl: "https://push.example.com",
            deviceId: "device_subscribe",
            externalUserId: nil,
            userEmail: nil,
            apnsToken: "apns-token",
            apnsEnvironment: "production",
            subscribed: false,
            initialized: true
        )
        MockURLProtocol.requestHandler = { request in
            try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 200,
                body: ["ok": true]
            )
        }

        let optInTokenExpectation = expectation(description: "opt in with token completes")
        sdk.optIn { success in
            XCTAssertTrue(success.boolValue)
            optInTokenExpectation.fulfill()
        }
        wait(for: [optInTokenExpectation], timeout: 2)
        XCTAssertTrue(sdk.subscribed)

        sdk.apnsToken = nil
        let optOutExpectation = expectation(description: "opt out completes")
        sdk.optOut { success in
            XCTAssertTrue(success.boolValue)
            optOutExpectation.fulfill()
        }
        wait(for: [optOutExpectation], timeout: 2)
        XCTAssertFalse(sdk.subscribed)

        let optInNoTokenExpectation = expectation(description: "opt in without token completes")
        sdk.optIn { success in
            XCTAssertTrue(success.boolValue)
            optInNoTokenExpectation.fulfill()
        }
        wait(for: [optInNoTokenExpectation], timeout: 2)
        XCTAssertTrue(sdk.subscribed)

        sdk.testingResetState()
        let registerMissingExpectation = expectation(description: "register missing fields completes")
        sdk.registerAPNSToken(nil) { success in
            XCTAssertFalse(success)
            registerMissingExpectation.fulfill()
        }
        wait(for: [registerMissingExpectation], timeout: 2)

        let subscriptionMissingExpectation = expectation(description: "subscription missing device completes")
        sdk.updateSubscription(true) { success in
            XCTAssertFalse(success)
            subscriptionMissingExpectation.fulfill()
        }
        wait(for: [subscriptionMissingExpectation], timeout: 2)

        let tagsMissingExpectation = expectation(description: "tags missing device completes")
        sdk.updateTags(["plan": "pro"]) { success in
            XCTAssertFalse(success)
            tagsMissingExpectation.fulfill()
        }
        wait(for: [tagsMissingExpectation], timeout: 2)

        let eventMissingExpectation = expectation(description: "event missing device completes")
        sdk.trackDeviceEvent("checkout_completed", completion: { success in
            XCTAssertFalse(success)
            eventMissingExpectation.fulfill()
        })
        wait(for: [eventMissingExpectation], timeout: 2)

        sdk.baseUrl = nil
        let missingBaseExpectation = expectation(description: "post missing base completes")
        sdk.postJSON(path: "/v1/test", payload: [:]) { _, success in
            XCTAssertFalse(success)
            missingBaseExpectation.fulfill()
        }
        wait(for: [missingBaseExpectation], timeout: 2)

        sdk.baseUrl = "https://push.example.com"
        let invalidBodyExpectation = expectation(description: "post invalid body completes")
        sdk.postJSON(path: "/v1/test", payload: ["bad": Double.nan]) { _, success in
            XCTAssertFalse(success)
            invalidBodyExpectation.fulfill()
        }
        wait(for: [invalidBodyExpectation], timeout: 2)
    }

    func testNotificationPayloadVariantsSilentEventsAndRecentOpenStorage() throws {
        let sdk = Sendrealm.shared
        let delegate = CapturingSendrealmDelegate()
        sdk.delegate = delegate
        sdk.applicationIntegrationDisabledForTesting = true
        sdk.testingSetState(
            appId: "app_notifications",
            baseUrl: "https://push.example.com",
            deviceId: "device_notifications",
            externalUserId: nil,
            userEmail: nil,
            apnsToken: "apns-token",
            apnsEnvironment: "production",
            subscribed: true,
            initialized: true
        )
        MockURLProtocol.requestHandler = { request in
            try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 500,
                body: ["error": ["message": "offline"]]
            )
        }

        let jsonPayload =
            """
            {
              "metadata": {
                "notification_id": "notification_json",
                "delivery_id": "delivery_json",
                "click_id": "click_json",
                "launch_url": "myapp://payload",
                "send_id": "send_json"
              },
              "live_activity": {
                "activity_id": "activity_json",
                "image_url": "https://cdn.example.com/live.png",
                "accent_color": "#ffcc00",
                "launch_url": "myapp://live",
                "buttons": [
                  { "text": "Confirm", "launch_url": "myapp://confirm" }
                ]
              }
            }
            """
        let payload: NSDictionary = [
            "aps": [
                "alert": "String alert",
                "badge": 8
            ],
            "sendrealm_v1": jsonPayload
        ]

        let event = sdk.notificationMap(
            from: payload,
            isForeground: true,
            actionIdentifier: Sendrealm.defaultActionIdentifiers[0]
        )
        let normalizedPayload = try XCTUnwrap(event["payload"] as? [String: Any])
        let liveActivity = try XCTUnwrap(normalizedPayload["liveActivity"] as? [String: Any])
        let action = try XCTUnwrap(event["action"] as? [String: Any])

        XCTAssertEqual(event["notificationId"] as? String, "notification_json")
        XCTAssertEqual(event["deliveryId"] as? String, "delivery_json")
        XCTAssertEqual(event["clickId"] as? String, "click_json")
        XCTAssertEqual(event["launchUrl"] as? String, "myapp://confirm")
        XCTAssertEqual(event["actionIdentifier"] as? String, Sendrealm.defaultActionIdentifiers[0])
        XCTAssertEqual(action["title"] as? String, "Confirm")
        XCTAssertEqual(liveActivity["activityId"] as? String, "activity_json")
        XCTAssertEqual(liveActivity["imageUrl"] as? String, "https://cdn.example.com/live.png")
        XCTAssertEqual(liveActivity["accentColor"] as? String, "#ffcc00")

        let silentPayload: NSDictionary = [
            "aps": [
                "content-available": NSNumber(value: 1)
            ],
            "notification_id": "silent_notification"
        ]
        sdk.handleNotificationUserInfo(silentPayload, opened: false)
        waitUntil("silent notification tracking queues") {
            let names = sdk.testingQueuedOperations().compactMap { $0["name"] as? String }
            return names.contains("track_delivery") &&
                names.contains("track_background_notification_received")
        }
        XCTAssertTrue(delegate.events.contains { $0.name == Sendrealm.eventSilentNotification })
        XCTAssertFalse(sdk.isSilentPush([:]))

        let noKeyEvent: NSDictionary = [:]
        XCTAssertFalse(sdk.isDuplicateOpen(noKeyEvent))

        var recentKeys: [String: Double] = [:]
        for index in 0..<60 {
            recentKeys["key_\(index)"] = Date().timeIntervalSince1970 - Double(index)
        }
        sdk.saveRecentOpenKeys(recentKeys)
        XCTAssertEqual(sdk.recentOpenKeys().count, 50)
    }

    func testNotificationDelegateHandlersTrackForegroundActionsDismissAndOpens() {
        let sdk = Sendrealm.shared
        let delegate = CapturingSendrealmDelegate()
        sdk.delegate = delegate
        sdk.applicationIntegrationDisabledForTesting = true
        sdk.testingSetState(
            appId: "app_delegate",
            baseUrl: "https://push.example.com",
            deviceId: "device_delegate",
            externalUserId: nil,
            userEmail: nil,
            apnsToken: "apns-token",
            apnsEnvironment: "production",
            subscribed: true,
            initialized: true
        )
        MockURLProtocol.requestHandler = { request in
            try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 500,
                body: ["error": ["message": "offline"]]
            )
        }

        let actionPayload: NSDictionary = [
            "aps": [
                "alert": [
                    "title": "Order ready",
                    "body": "Tap to manage"
                ]
            ],
            "sendrealm_v1": [
                "metadata": [
                    "notification_id": "delegate_action",
                    "click_id": "delegate_click_action",
                    "ios_launch_url": "myapp://notification"
                ],
                "actions": [
                    [
                        "id": "confirm",
                        "text": "Confirm",
                        "launch_url": "myapp://confirm"
                    ]
                ],
                "live_activity": [
                    "activity_id": "activity_delegate",
                    "send_id": "send_delegate"
                ]
            ]
        ]

        var foregroundOptions: UNNotificationPresentationOptions?
        sdk.handleForegroundNotificationUserInfo(
            actionPayload,
            isForeground: true
        ) { options in
            foregroundOptions = options
        }
        if #available(iOS 14.0, *) {
            XCTAssertEqual(foregroundOptions?.contains(.banner), true)
            XCTAssertEqual(foregroundOptions?.contains(.list), true)
        } else {
            XCTAssertEqual(foregroundOptions?.contains(.alert), true)
        }
        waitUntil("foreground delegate tracking queues") {
            let names = sdk.testingQueuedOperations().compactMap { $0["name"] as? String }
            return names.contains("track_delivery") &&
                names.contains("track_foreground_display")
        }

        sdk.handleNotificationResponseUserInfo(
            actionPayload,
            isForeground: false,
            actionIdentifier: Sendrealm.defaultActionIdentifiers[0]
        ) {}
        waitUntil("action delegate tracking queues") {
            let names = sdk.testingQueuedOperations().compactMap { $0["name"] as? String }
            return names.contains("track_open") &&
                names.contains("track_click") &&
                names.contains("track_notification_action") &&
                names.contains("track_live_activity_action")
        }

        let dismissPayload: NSDictionary = [
            "aps": [
                "alert": [
                    "title": "Order ready"
                ]
            ],
            "sendrealm_v1": [
                "metadata": [
                    "notification_id": "delegate_dismiss",
                    "click_id": "delegate_click_dismiss"
                ],
                "live_activity": [
                    "activity_id": "activity_dismiss",
                    "send_id": "send_dismiss"
                ]
            ]
        ]
        sdk.handleNotificationResponseUserInfo(
            dismissPayload,
            isForeground: false,
            actionIdentifier: UNNotificationDismissActionIdentifier
        ) {}
        waitUntil("dismiss delegate tracking queues") {
            let names = sdk.testingQueuedOperations().compactMap { $0["name"] as? String }
            return names.contains("track_dismiss") &&
                names.contains("track_live_activity_dismiss")
        }

        let defaultPayload: NSDictionary = [
            "aps": [
                "alert": [
                    "title": "Order ready"
                ]
            ],
            "sendrealm_v1": [
                "metadata": [
                    "notification_id": "delegate_default",
                    "click_id": "delegate_click_default"
                ],
                "live_activity": [
                    "activity_id": "activity_default",
                    "send_id": "send_default"
                ]
            ]
        ]
        sdk.handleNotificationResponseUserInfo(
            defaultPayload,
            isForeground: false,
            actionIdentifier: UNNotificationDefaultActionIdentifier
        ) {}
        waitUntil("default open delegate tracking queues") {
            let names = sdk.testingQueuedOperations().compactMap { $0["name"] as? String }
            return names.contains("track_live_activity_open")
        }

        sdk.suppressForegroundNotifications = true
        var suppressedOptions: UNNotificationPresentationOptions?
        sdk.handleForegroundNotificationUserInfo(
            defaultPayload,
            isForeground: true
        ) { options in
            suppressedOptions = options
        }
        XCTAssertEqual(suppressedOptions?.isEmpty, true)

        XCTAssertTrue(delegate.events.contains { $0.name == Sendrealm.eventForegroundNotification })
        XCTAssertTrue(delegate.events.contains { $0.name == Sendrealm.eventNotificationClicked })
        XCTAssertTrue(delegate.events.contains { $0.name == Sendrealm.eventNotificationAction })
    }

    func testCoreCategoryCallbacksAndStaticEntrypoints() {
        let sdk = Sendrealm.shared
        sdk.notificationCenterIntegrationDisabledForTesting = true
        sdk.notificationPermissionStatusForTesting = "authorized"
        sdk.applicationIntegrationDisabledForTesting = true
        sdk.testingSetState(
            appId: "app_core",
            baseUrl: "https://push.example.com",
            deviceId: "device_core",
            externalUserId: nil,
            userEmail: nil,
            apnsToken: nil,
            apnsEnvironment: "production",
            subscribed: false,
            initialized: true
        )

        let categories = sdk.defaultNotificationCategories()
        XCTAssertEqual(categories.count, 4)
        let legacy = categories.first { $0.identifier == Sendrealm.defaultActionCategory }
        XCTAssertEqual(legacy?.actions.count, 3)
        XCTAssertTrue(categories.contains { $0.identifier == "\(Sendrealm.defaultActionCategoryPrefix)1" })
        XCTAssertTrue(categories.contains { $0.identifier == "\(Sendrealm.defaultActionCategoryPrefix)2" })
        XCTAssertTrue(categories.contains { $0.identifier == "\(Sendrealm.defaultActionCategoryPrefix)3" })

        sdk.notificationCenterIntegrationDisabledForTesting = false
        var configuredCategories: Set<UNNotificationCategory>?
        sdk.registerNotificationCategoriesForTesting = { categories in
            configuredCategories = categories
        }
        sdk.registerDefaultNotificationCategories()
        XCTAssertEqual(configuredCategories?.count, 4)
        sdk.notificationCenterIntegrationDisabledForTesting = true

        sdk.registerForegroundObserverIfNeeded()
        sdk.registerForegroundObserverIfNeeded()
        XCTAssertTrue(sdk.foregroundObserverRegistered)

        Sendrealm.configure()
        sdk.handleAppWillEnterForeground()

        MockURLProtocol.requestHandler = { request in
            try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 500,
                body: ["error": ["message": "offline"]]
            )
        }
        Sendrealm.didRegisterForRemoteNotifications(
            withDeviceToken: Data([0x01, 0x02, 0xab])
        )
        waitUntil("static APNS callback queues registration") {
            sdk.testingQueuedOperations().contains { $0["name"] as? String == "register" }
        }

        Sendrealm.didReceiveRemoteNotification([
            "aps": [
                "alert": [
                    "title": "Static"
                ]
            ],
            "notification_id": "static_notification"
        ])
        waitUntil("static notification callback queues delivery") {
            sdk.testingQueuedOperations().contains { $0["name"] as? String == "track_delivery" }
        }
    }

    func testIOSIntegrationHooksCoverPermissionSettingsBadgeAndLaunchUrlPaths() {
        let sdk = Sendrealm.shared
        sdk.testingSetState(
            appId: "app_hooks",
            baseUrl: "https://push.example.com",
            deviceId: "device_hooks",
            externalUserId: nil,
            userEmail: nil,
            apnsToken: "apns-token",
            apnsEnvironment: "production",
            subscribed: true,
            initialized: true
        )
        MockURLProtocol.requestHandler = { request in
            try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 500,
                body: ["error": ["message": "offline"]]
            )
        }

        var requestedOptions: UNAuthorizationOptions?
        var registeredForRemoteNotifications = 0
        var openedURLs: [URL] = []
        var badgeCounts: [Int] = []
        sdk.requestNotificationAuthorizationForTesting = { options, completion in
            requestedOptions = options
            completion(true, nil)
        }
        sdk.notificationAuthorizationStatusForTesting = { completion in
            completion(.provisional)
        }
        sdk.registerForRemoteNotificationsForTesting = {
            registeredForRemoteNotifications += 1
        }
        sdk.openURLForTesting = { url, completion in
            openedURLs.append(url)
            completion(true)
        }
        sdk.setBadgeCountForTesting = { count, completion in
            badgeCounts.append(count)
            completion(nil)
        }

        let requestPermissionExpectation = expectation(description: "permission hook completes")
        sdk.requestPermission { granted, error in
            XCTAssertNil(error)
            XCTAssertTrue(granted?.boolValue == true)
            requestPermissionExpectation.fulfill()
        }
        wait(for: [requestPermissionExpectation], timeout: 2)
        XCTAssertEqual(requestedOptions?.contains(.alert), true)
        XCTAssertEqual(requestedOptions?.contains(.badge), true)
        XCTAssertEqual(requestedOptions?.contains(.sound), true)
        waitUntil("remote notification registration hook runs") {
            registeredForRemoteNotifications == 1
        }
        XCTAssertEqual(sdk.lastPermissionStatus, "provisional")

        sdk.requestNotificationAuthorizationForTesting = { _, completion in
            completion(false, NSError(domain: "SendrealmTests", code: 9))
        }
        let requestPermissionErrorExpectation = expectation(description: "permission error hook completes")
        sdk.requestPermission { granted, error in
            XCTAssertNil(granted)
            XCTAssertEqual(error?.domain, "SendrealmTests")
            requestPermissionErrorExpectation.fulfill()
        }
        wait(for: [requestPermissionErrorExpectation], timeout: 2)

        let statusExpectation = expectation(description: "status hook completes")
        sdk.getPermissionStatus { status in
            XCTAssertEqual(status as String, "provisional")
            statusExpectation.fulfill()
        }
        wait(for: [statusExpectation], timeout: 2)

        let hasPermissionExpectation = expectation(description: "has permission hook completes")
        sdk.hasNotificationPermission { granted in
            XCTAssertTrue(granted)
            hasPermissionExpectation.fulfill()
        }
        wait(for: [hasPermissionExpectation], timeout: 2)

        let settingsExpectation = expectation(description: "settings hook completes")
        sdk.openNotificationSettings { opened in
            XCTAssertTrue(opened.boolValue)
            settingsExpectation.fulfill()
        }
        wait(for: [settingsExpectation], timeout: 2)
        XCTAssertTrue(openedURLs.contains { $0.absoluteString.contains("app-settings") })

        let badgeExpectation = expectation(description: "badge hook completes")
        sdk.setBadgeCount(-4) { success in
            XCTAssertTrue(success.boolValue)
            badgeExpectation.fulfill()
        }
        wait(for: [badgeExpectation], timeout: 2)

        let clearBadgeExpectation = expectation(description: "clear badge hook completes")
        sdk.clearBadge { success in
            XCTAssertTrue(success.boolValue)
            clearBadgeExpectation.fulfill()
        }
        wait(for: [clearBadgeExpectation], timeout: 2)
        XCTAssertEqual(badgeCounts, [0, 0])

        sdk.openLaunchUrl("myapp://orders/123")
        waitUntil("launch URL hook receives deep link") {
            openedURLs.contains { $0.absoluteString == "myapp://orders/123" }
        }
    }

    func testNotificationServiceHelperDiagnosticsAndEnrichGuardPaths() {
        let payloadJSON =
            """
            {
              "live_activity": {
                "buttons": [
                  { "title": "Open" },
                  { "id": "dismiss", "text": "Dismiss" },
                  { "text": "Track" },
                  { "text": "Ignored" }
                ]
              },
              "metadata": {
                "imageUrl": "https://example.com/root.png"
              }
            }
            """
        let diagnostics = SendrealmNotificationServiceHelper.testingActionDiagnostics(
            userInfo: [
                "sendrealm_v1": payloadJSON
            ],
            categoryIdentifier: Sendrealm.defaultActionCategoryPrefix + "3"
        )
        let actions = diagnostics["actions"] as? [[String: String]]
        XCTAssertEqual(diagnostics["usesDefaultCategory"] as? Bool, true)
        XCTAssertEqual(actions?.count, 3)
        XCTAssertEqual(actions?.first?["identifier"], Sendrealm.defaultActionIdentifiers[0])
        XCTAssertEqual(actions?[1]["identifier"], "dismiss")
        XCTAssertEqual(diagnostics["imageUrl"] as? String, "https://example.com/root.png")

        let emptyDiagnostics = SendrealmNotificationServiceHelper.testingActionDiagnostics(
            userInfo: [
                "actions": [
                    ["id": "missing-title"]
                ],
                "image_url": "https://example.com/fallback.jpg"
            ],
            categoryIdentifier: "custom"
        )
        XCTAssertEqual(emptyDiagnostics["usesDefaultCategory"] as? Bool, false)
        XCTAssertTrue(emptyDiagnostics["dynamicCategoryIdentifier"] is NSNull)
        XCTAssertEqual(emptyDiagnostics["imageUrl"] as? String, "https://example.com/fallback.jpg")

        let content = UNMutableNotificationContent()
        content.userInfo = [
            "aps": [
                "alert": [
                    "title": "Plain",
                    "body": "No rich media"
                ]
            ]
        ]
        content.categoryIdentifier = "custom"
        let request = UNNotificationRequest(identifier: "plain", content: content, trigger: nil)
        let enrichExpectation = expectation(description: "enrich guard path completes")
        SendrealmNotificationServiceHelper.enrich(
            request: request,
            bestAttemptContent: content
        ) { enriched in
            XCTAssertEqual(enriched.categoryIdentifier, "custom")
            XCTAssertTrue(enriched.attachments.isEmpty)
            enrichExpectation.fulfill()
        }
        wait(for: [enrichExpectation], timeout: 2)

        SendrealmNotificationServiceHelper.notificationCenterIntegrationDisabledForTesting = true
        defer {
            SendrealmNotificationServiceHelper.notificationCenterIntegrationDisabledForTesting = false
        }
        let dynamicContent = UNMutableNotificationContent()
        dynamicContent.categoryIdentifier = Sendrealm.defaultActionCategory
        dynamicContent.userInfo = [
            "sendrealm_v1": [
                "actions": [
                    [
                        "id": "view",
                        "text": "View"
                    ]
                ]
            ]
        ]
        let dynamicRequest = UNNotificationRequest(
            identifier: "dynamic",
            content: dynamicContent,
            trigger: nil
        )
        let dynamicExpectation = expectation(description: "dynamic enrich completes")
        SendrealmNotificationServiceHelper.enrich(
            request: dynamicRequest,
            bestAttemptContent: dynamicContent
        ) { enriched in
            XCTAssertTrue(enriched.categoryIdentifier.hasPrefix("sendrealm_actions_1_"))
            XCTAssertTrue(enriched.attachments.isEmpty)
            dynamicExpectation.fulfill()
        }
        wait(for: [dynamicExpectation], timeout: 2)
    }

    func testPendingQueuesUtilitiesAndSerializationEdges() {
        let sdk = Sendrealm.shared

        sdk.enqueueOperation(name: "", path: "/v1/track", payload: [:])
        sdk.enqueueOperation(name: "track", path: "", payload: [:])
        sdk.enqueueEvent(eventType: "")
        sdk.enqueueTags([:])
        XCTAssertEqual(sdk.queueCounts()["operations"], 0)
        XCTAssertEqual(sdk.queueCounts()["events"], 0)
        XCTAssertEqual(sdk.queueCounts()["tags"], 0)

        for index in 0..<1005 {
            sdk.enqueueOperation(
                name: "operation_\(index)",
                path: "/v1/test",
                payload: ["index": index]
            )
            sdk.enqueueEvent(eventType: "event_\(index)")
        }
        XCTAssertEqual(sdk.queuedOperations().count, 1000)
        XCTAssertEqual(sdk.queuedEvents().count, 1000)
        XCTAssertEqual(sdk.retryDelay(for: 0), 2)
        XCTAssertEqual(sdk.retryDelay(for: 9), 300)

        UserDefaults.standard.set(Data("bad".utf8), forKey: sdk.prefsKey("pending_events"))
        UserDefaults.standard.set(Data("bad".utf8), forKey: sdk.prefsKey("pending_tags"))
        UserDefaults.standard.set(Data("bad".utf8), forKey: sdk.prefsKey("pending_operations"))
        XCTAssertTrue(sdk.queuedEvents().isEmpty)
        XCTAssertTrue(sdk.queuedTags().isEmpty)
        XCTAssertTrue(sdk.queuedOperations().isEmpty)

        sdk.saveQueuedEvents([])
        sdk.saveQueuedTags([:])
        sdk.saveQueuedOperations([])
        XCTAssertNil(UserDefaults.standard.object(forKey: sdk.prefsKey("pending_events")))
        XCTAssertNil(UserDefaults.standard.object(forKey: sdk.prefsKey("pending_tags")))
        XCTAssertNil(UserDefaults.standard.object(forKey: sdk.prefsKey("pending_operations")))

        XCTAssertNil(sdk.normalizedString(123))
        XCTAssertEqual(sdk.normalizedString("  hello  "), "hello")
        XCTAssertEqual(sdk.normalizeApnsEnvironment("development"), "sandbox")
        XCTAssertEqual(sdk.normalizeApnsEnvironment("production"), "production")
        XCTAssertEqual(sdk.normalizeApnsEnvironment("unknown"), sdk.defaultApnsEnvironment())
        XCTAssertEqual(sdk.permissionStatusString(.notDetermined), "not_determined")
        XCTAssertEqual(sdk.permissionStatusString(.denied), "denied")
        XCTAssertEqual(sdk.permissionStatusString(.authorized), "authorized")
        XCTAssertEqual(sdk.permissionStatusString(.provisional), "provisional")
        if #available(iOS 14.0, *) {
            XCTAssertEqual(sdk.permissionStatusString(.ephemeral), "ephemeral")
        }
        XCTAssertEqual(sdk.boolValue(true), true)
        XCTAssertEqual(sdk.boolValue(NSNumber(value: false)), false)
        XCTAssertNil(sdk.boolValue("true"))

        let sanitized = sdk.sanitizeJSON([
            "array": [1, nil, NSNull(), "text"] as [Any?],
            "float": Float(1.5),
            "url": URL(string: "https://example.com") as Any
        ]) as? [String: Any]
        XCTAssertEqual((sanitized?["array"] as? [Any])?.count, 4)
        XCTAssertEqual(sanitized?["float"] as? NSNumber, NSNumber(value: Float(1.5)))
        XCTAssertEqual(sanitized?["url"] as? String, "https://example.com")
        XCTAssertNil(sdk.jsonString(["bad": Double.nan]))
        XCTAssertEqual(sdk.apiErrorMessage(nil, fallback: "Fallback"), "Fallback")
        XCTAssertEqual(sdk.apiErrorMessage(["error": [:]], fallback: "Fallback"), "Fallback")
        XCTAssertEqual(
            sdk.apiErrorMessage(["error": ["details": [["message": "Detail only"]]]], fallback: "Fallback"),
            "Detail only"
        )
        sdk.setLastSdkError(code: "E_TEST", message: "test")
        XCTAssertNotNil(sdk.lastSdkError)
        sdk.clearLastSdkError()
        XCTAssertNil(sdk.lastSdkError)
    }

    func testFlushPendingWorkInitialNotificationAndReregisterPaths() {
        let sdk = Sendrealm.shared
        sdk.testingSetState(
            appId: "app_flush",
            baseUrl: "https://push.example.com",
            deviceId: "device_flush",
            externalUserId: nil,
            userEmail: nil,
            apnsToken: "apns-token",
            apnsEnvironment: "production",
            subscribed: true,
            initialized: true
        )
        sdk.testingEnqueueTags(["plan": "pro"])
        sdk.testingEnqueueEvent(
            eventType: "checkout_completed",
            notificationId: "notification_flush",
            properties: ["order_id": "order_1"]
        )
        sdk.testingEnqueueOperation(
            name: "queued_track",
            path: "/v1/track",
            payload: [
                "app_id": "app_flush",
                "device_id": "device_flush",
                "event_type": "queued"
            ]
        )
        MockURLProtocol.requestHandler = { request in
            let statusCode = request.url?.path == "/v1/track" ? 500 : 200
            return try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: statusCode,
                body: ["error": ["message": "offline"]]
            )
        }

        sdk.flushPendingWork()
        waitUntil("pending work flushes successes and preserves failed events") {
            sdk.testingQueuedTags().isEmpty &&
                sdk.testingQueuedEvents().count == 1 &&
                (sdk.testingQueuedOperations().first?["retryCount"] as? Int) == 1
        }

        sdk.initialNotification = ["notificationId": "initial_1"]
        let initialExpectation = expectation(description: "initial notification completes")
        sdk.getInitialNotification { notification in
            XCTAssertEqual(notification?["notificationId"] as? String, "initial_1")
            initialExpectation.fulfill()
        }
        wait(for: [initialExpectation], timeout: 2)
        let drainedExpectation = expectation(description: "initial notification drains")
        sdk.getInitialNotification { notification in
            XCTAssertNil(notification)
            drainedExpectation.fulfill()
        }
        wait(for: [drainedExpectation], timeout: 2)

        sdk.testingMakeQueuedOperationsReady()
        sdk.lastRegistrationFingerprint = "old"
        MockURLProtocol.requestHandler = { request in
            try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 500,
                body: ["error": ["message": "registration offline"]]
            )
        }
        sdk.reRegisterIfFingerprintChanged()
        waitUntil("fingerprint change re-registers token") {
            sdk.testingQueuedOperations().contains { $0["name"] as? String == "register" }
        }
    }

    func testNotificationServiceHelperAttemptsFileImageEnrichment() throws {
        let imageURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sendrealm-test-image.png")
        let imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!
        try imageData.write(to: imageURL)
        defer {
            try? FileManager.default.removeItem(at: imageURL)
            SendrealmNotificationServiceHelper.imageDownloadForTesting = nil
        }
        SendrealmNotificationServiceHelper.imageDownloadForTesting = { url, completion in
            XCTAssertEqual(url.absoluteString, "https://example.com/rich.png")
            completion(imageURL)
        }

        let content = UNMutableNotificationContent()
        content.userInfo = [
            "sendrealm_v1": [
                "metadata": [
                    "image_url": "https://example.com/rich.png"
                ]
            ]
        ]
        let request = UNNotificationRequest(
            identifier: "file-image",
            content: content,
            trigger: nil
        )
        let enrichExpectation = expectation(description: "file image enrich completes")
        SendrealmNotificationServiceHelper.enrich(
            request: request,
            bestAttemptContent: content
        ) { enriched in
            XCTAssertNotNil(enriched.userInfo["sendrealm_v1"])
            XCTAssertEqual(enriched.attachments.count, 1)
            enrichExpectation.fulfill()
        }
        wait(for: [enrichExpectation], timeout: 2)
    }

    func testLiveActivityQueuesStateTrackingDiagnosticsAndAttributes() throws {
        let sdk = Sendrealm.shared
        sdk.testingSetState(
            appId: "app_live",
            baseUrl: "https://push.example.com",
            deviceId: "device_live",
            externalUserId: nil,
            userEmail: nil,
            apnsToken: "apns-token",
            apnsEnvironment: "production",
            subscribed: true,
            initialized: true
        )
        MockURLProtocol.requestHandler = { request in
            try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 500,
                body: ["error": ["message": "offline"]]
            )
        }

        sdk.testingTrackLiveActivityStateChange(
            activityId: "activity_state",
            sendId: "send_pending",
            activityState: "pending",
            attributesType: "DeliveryAttributes"
        )
        sdk.testingTrackLiveActivityStateChange(
            activityId: "activity_state",
            sendId: "send_active",
            activityState: "active",
            attributesType: "DeliveryAttributes"
        )
        sdk.testingTrackLiveActivityStateChange(
            activityId: "activity_state",
            sendId: "send_stale",
            activityState: "stale",
            attributesType: "DeliveryAttributes"
        )
        sdk.testingTrackLiveActivityStateChange(
            activityId: "activity_state",
            sendId: "send_ended",
            activityState: "ended",
            attributesType: "DeliveryAttributes"
        )
        sdk.testingTrackLiveActivityStateChange(
            activityId: "activity_state",
            sendId: "send_dismissed",
            activityState: "dismissed",
            attributesType: "DeliveryAttributes"
        )
        sdk.testingTrackLiveActivityStateChange(
            activityId: "activity_state",
            sendId: "ignored",
            activityState: "unknown",
            attributesType: "DeliveryAttributes"
        )
        if #available(iOS 16.1, *) {
            sdk.testingObserveLiveActivityStateUpdate(
                .active,
                activityId: "activity_observed_state",
                sendId: "send_observed_state",
                attributesType: "DeliveryAttributes"
            )
            sdk.testingObserveLiveActivityStateUpdate(
                .ended,
                activityId: nil,
                sendId: "ignored",
                attributesType: "DeliveryAttributes"
            )
        }
        sdk.trackLiveActivityDiagnosticsSoon()

        waitUntil("live activity state events queue", timeout: 2.5) {
            let names = sdk.testingQueuedOperations().compactMap { $0["name"] as? String }
            return names.filter { $0 == "track_live_activity_update" }.count >= 2 &&
                names.contains("track_live_activity_start") &&
                names.contains("track_live_activity_end") &&
                names.contains("track_live_activity_dismiss") &&
                names.contains("track_live_activity_diagnostics")
        }

        sdk.testingResetState()
        for index in 0..<1005 {
            sdk.enqueuePendingLiveActivityTokenRegistration(
                token: "token_\(index)",
                activityId: "activity_\(index)",
                tokenType: "ios_update",
                activityType: "DeliveryActivity",
                attributesType: "DeliveryAttributes",
                sendId: "send_\(index)"
            )
        }
        sdk.enqueuePendingLiveActivityTokenRegistration(
            token: "token_1004",
            activityId: "activity_1004",
            tokenType: "ios_update",
            activityType: "DeliveryActivity",
            attributesType: "DeliveryAttributes",
            sendId: "send_1004"
        )
        XCTAssertEqual(sdk.pendingLiveActivityTokenRegistrations.count, 1000)
        XCTAssertEqual(sdk.pendingLiveActivityTokenRegistrations.first?.token, "token_5")

        sdk.rememberLiveActivityTokenRegistration(
            token: "registered-token",
            activityId: "activity_registered",
            tokenType: "ios_update",
            activityType: "DeliveryActivity",
            attributesType: "DeliveryAttributes",
            sendId: "send_registered"
        )
        XCTAssertTrue(
            sdk.hasRegisteredLiveActivityToken(
                token: "registered-token",
                activityId: "activity_registered",
                tokenType: "ios_update",
                activityType: "DeliveryActivity",
                attributesType: "DeliveryAttributes",
                sendId: "send_registered"
            )
        )
        XCTAssertFalse(
            sdk.hasRegisteredLiveActivityToken(
                token: "other-token",
                activityId: "activity_registered",
                tokenType: "ios_update",
                activityType: "DeliveryActivity",
                attributesType: "DeliveryAttributes",
                sendId: "send_registered"
            )
        )

        sdk.testingResetState()
        sdk.enqueuePendingLiveActivityTokenRegistration(
            token: "queued-token",
            activityId: "queued-activity",
            tokenType: "ios_update",
            activityType: "DeliveryActivity",
            attributesType: "DeliveryAttributes",
            sendId: "queued-send"
        )
        sdk.flushPendingLiveActivityTokenRegistrations()
        XCTAssertEqual(sdk.pendingLiveActivityTokenRegistrations.count, 1)

        sdk.testingSetState(
            appId: "app_live",
            baseUrl: "https://push.example.com",
            deviceId: "device_live",
            externalUserId: nil,
            userEmail: nil,
            apnsToken: "apns-token",
            apnsEnvironment: "production",
            subscribed: true,
            initialized: true
        )
        MockURLProtocol.requestHandler = { request in
            try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 500,
                body: ["error": ["message": "token rejected"]]
            )
        }
        sdk.flushPendingLiveActivityTokenRegistrations()
        waitUntil("failed live activity token requeues") {
            sdk.pendingLiveActivityTokenRegistrations.count == 1 &&
                (sdk.liveActivityDiagnostics()["registrationFailures"] as? Int) == 1
        }
        XCTAssertEqual(sdk.liveActivityDiagnostics()["lastTokenType"] as? String, "ios_update")
        XCTAssertEqual(sdk.lastSdkError?["code"] as? String, "E_LIVE_ACTIVITY_TOKEN_SYNC_FAILED")

        if #available(iOS 16.1, *) {
            XCTAssertEqual(sdk.testingDefaultLiveActivityAttributesType(), "SendrealmLiveActivityAttributes")
            XCTAssertEqual(
                [
                    sdk.testingLiveActivityStateName(.active),
                    sdk.testingLiveActivityStateName(.ended),
                    sdk.testingLiveActivityStateName(.dismissed)
                ],
                ["active", "ended", "dismissed"]
            )
            if #available(iOS 16.2, *) {
                XCTAssertEqual(sdk.testingLiveActivityStateName(.stale), "stale")
            }
            if #available(iOS 26.0, *) {
                XCTAssertEqual(sdk.testingLiveActivityStateName(.pending), "pending")
            }

            let button = SendrealmLiveActivityAttributes.Button(
                id: "confirm",
                text: "Confirm",
                title: "Confirm order",
                launch_url: "myapp://confirm"
            )
            let state = SendrealmLiveActivityAttributes.ContentState(
                title: "Order",
                subtitle: "Preparing",
                body: "Almost there",
                status: "active",
                progress: 0.5,
                eta: "5m",
                image_url: "https://example.com/live.png",
                accent_color: "#ffcc00",
                launch_url: "myapp://live",
                send_id: "send_state",
                buttons: [button]
            )
            let attributes = SendrealmLiveActivityAttributes(
                activity_id: "activity_attributes",
                send_id: "send_attributes"
            )

            let encodedAttributes = try JSONEncoder().encode(attributes)
            let decodedAttributes = try JSONDecoder().decode(
                SendrealmLiveActivityAttributes.self,
                from: encodedAttributes
            )
            XCTAssertEqual(decodedAttributes.activity_id, "activity_attributes")
            XCTAssertEqual(state.buttons?.first?.launch_url, "myapp://confirm")
        }
    }

    func testCustomLiveActivityObserverRegistrationStartsAndDeduplicatesTasks() {
        #if canImport(ActivityKit)
        let sdk = Sendrealm.shared

        if #available(iOS 16.1, *) {
            sdk.observeLiveActivityType(
                SendrealmTestLiveActivityAttributes.self,
                attributesTypeName: " TestDelivery ",
                activityId: { $0.activityId },
                attributesSendId: { $0.sendId },
                contentStateSendId: { $0.sendId }
            )
            sdk.observeLiveActivityType(
                SendrealmTestLiveActivityAttributes.self,
                attributesTypeName: " TestDelivery ",
                activityId: { $0.activityId },
                attributesSendId: { $0.sendId },
                contentStateSendId: { $0.sendId }
            )

            let diagnostics = sdk.liveActivityDiagnostics()
            XCTAssertEqual(diagnostics["status"] as? String, "custom_activity_type_observer_starting")
            XCTAssertEqual(diagnostics["customActivityUpdatesObserverCount"] as? Int, 1)
            if #available(iOS 17.2, *) {
                XCTAssertEqual(diagnostics["customPushToStartObserverCount"] as? Int, 1)
            }
        }
        #endif
    }

    func testLiveActivityObserverDefaultsAndDisabledAuthorizationPath() {
        #if canImport(ActivityKit)
        let sdk = Sendrealm.shared

        if #available(iOS 16.1, *) {
            sdk.liveActivityActivitiesEnabledForTesting = false
            sdk.startLiveActivityTokenObserversIfAvailable()

            var diagnostics = sdk.liveActivityDiagnostics()
            XCTAssertEqual(diagnostics["enabled"] as? Bool, false)
            if #available(iOS 17.2, *) {
                XCTAssertEqual(diagnostics["status"] as? String, "push_to_start_observer_active")
                XCTAssertEqual(diagnostics["pushToStartObserverActive"] as? Bool, true)
            } else {
                XCTAssertEqual(
                    diagnostics["status"] as? String,
                    "activities_disabled_push_to_start_requires_ios_17_2"
                )
            }

            sdk.testingResetState()
            sdk.observeLiveActivityType(
                SendrealmTestLiveActivityAttributes.self,
                activityId: { $0.activityId }
            )
            diagnostics = sdk.liveActivityDiagnostics()
            XCTAssertEqual(diagnostics["status"] as? String, "custom_activity_type_observer_starting")
            XCTAssertEqual(diagnostics["customActivityUpdatesObserverCount"] as? Int, 1)
            if #available(iOS 17.2, *) {
                XCTAssertEqual(diagnostics["customPushToStartObserverCount"] as? Int, 1)
            }
        }
        #endif
    }

    func testObservedLiveActivityTokenAndContentHelpersTrackAndQueue() {
        let sdk = Sendrealm.shared
        sdk.testingSetState(
            appId: "app_observed",
            baseUrl: "https://push.example.com",
            deviceId: "device_observed",
            externalUserId: nil,
            userEmail: nil,
            apnsToken: "apns-token",
            apnsEnvironment: "production",
            subscribed: true,
            initialized: true
        )
        MockURLProtocol.requestHandler = { request in
            try MockURLProtocol.jsonResponse(
                for: request,
                statusCode: 500,
                body: ["error": ["message": "offline"]]
            )
        }

        let streamExpectation = expectation(description: "live activity observer stream forwards")
        var continuation: AsyncStream<Data>.Continuation?
        let stream = AsyncStream<Data> { continuation = $0 }
        let observerTask = sdk.liveActivityMainObserverTask(stream) { data in
            XCTAssertEqual(data, Data([0xee]))
            streamExpectation.fulfill()
        }
        continuation?.yield(Data([0xee]))
        wait(for: [streamExpectation], timeout: 2)
        observerTask.cancel()

        sdk.testingHandleObservedPushToStartToken(
            Data([0x0a, 0x0b]),
            status: "custom_push_to_start_token_observed",
            activityType: "DeliveryActivity",
            attributesType: "DeliveryAttributes"
        )
        sdk.testingHandleObservedLiveActivityUpdateToken(
            Data([0x0c, 0x0d]),
            activityId: "activity_observed",
            activityType: "DeliveryActivity",
            attributesType: "DeliveryAttributes",
            sendId: "send_observed"
        )
        sdk.testingHandleObservedLiveActivityContentUpdate(
            activityId: nil,
            sendId: "ignored",
            startSendId: nil,
            attributesType: "DeliveryAttributes"
        )
        sdk.testingHandleObservedLiveActivityContentUpdate(
            activityId: "activity_observed",
            sendId: "send_update",
            startSendId: "send_start",
            attributesType: "DeliveryAttributes"
        )

        waitUntil("observed live activity helpers queue failures") {
            let names = sdk.testingQueuedOperations().compactMap { $0["name"] as? String }
            return names.contains("live_activity_token_ios_push_to_start") &&
                names.contains("live_activity_token_ios_update") &&
                names.contains("track_live_activity_update")
        }
        XCTAssertEqual(sdk.liveActivityDiagnostics()["pushToStartTokenObserved"] as? Bool, true)
        XCTAssertEqual(sdk.liveActivityDiagnostics()["lastTokenType"] as? String, "ios_update")
        XCTAssertEqual(sdk.liveActivityDiagnostics()["registrationFailures"] as? Int, 2)
        XCTAssertEqual(sdk.liveActivityDiagnostics()["status"] as? String, "live_activity_token_registration_failed")
    }

    private func waitUntil(
        _ message: String,
        timeout: TimeInterval = 2,
        condition: @escaping () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)

        while !condition() && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        XCTAssertTrue(condition(), message)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(
                self,
                didFailWithError: NSError(
                    domain: "MockURLProtocol",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No request handler configured"]
                )
            )
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func jsonResponse(
        for request: URLRequest,
        statusCode: Int,
        body: [String: Any]
    ) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!

        return (response, data)
    }
}

private final class CapturingSendrealmDelegate: NSObject, SendrealmDelegate {
    private(set) var events: [(name: String, body: NSDictionary)] = []

    func sendrealm(
        _ sdk: Sendrealm,
        didReceiveEvent name: String,
        body: NSDictionary
    ) {
        events.append((name: name, body: body))
    }
}

#if canImport(ActivityKit)
@available(iOS 16.1, *)
private struct SendrealmTestLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var sendId: String
    }

    var activityId: String
    var sendId: String
}
#endif

private extension URLRequest {
    func testingJSONBody() throws -> [String: Any] {
        let data: Data

        if let httpBody {
            data = httpBody
        } else if let httpBodyStream {
            data = try httpBodyStream.testingReadAllData()
        } else {
            data = try XCTUnwrap(nil as Data?)
        }

        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private extension InputStream {
    func testingReadAllData() throws -> Data {
        open()
        defer { close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while hasBytesAvailable {
            let count = read(&buffer, maxLength: buffer.count)

            if count < 0 {
                throw streamError ?? NSError(
                    domain: "MockURLProtocol",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to read request body stream"]
                )
            }

            if count == 0 {
                break
            }

            data.append(buffer, count: count)
        }

        return data
    }
}

private extension Sendrealm {
    func testingResetState() {
        delegate = nil
        [
            "app_id",
            "base_url",
            "device_id",
            "external_user_id",
            "user_email",
            "apns_token",
            "environment",
            "apns_environment",
            "subscribed",
            "pending_events",
            "pending_tags",
            "pending_operations",
            "permission_status",
            "registration_fingerprint",
            "api_url_source",
            "suppress_foreground_notifications",
            "foreground_banner",
            "foreground_list",
            "foreground_sound",
            "foreground_badge",
            "last_init_result",
            "last_register_result",
            "last_sdk_error",
            "last_notification_payload",
            "last_open_payload",
            "recent_open_keys"
        ].forEach { key in
            UserDefaults.standard.removeObject(forKey: prefsKey(key))
        }

        initialized = false
        subscribed = false
        suppressForegroundNotifications = false
        foregroundBanner = true
        foregroundList = true
        foregroundSound = true
        foregroundBadge = true
        appId = nil
        baseUrl = defaultBaseUrl
        apiUrlSource = "default"
        deviceId = nil
        externalUserId = nil
        userEmail = nil
        apnsToken = nil
        environment = "production"
        apnsEnvironment = defaultApnsEnvironment()
        lastPermissionStatus = "not_determined"
        lastRegistrationFingerprint = nil
        lastInitResult = nil
        lastRegisterResult = nil
        lastSdkError = nil
        lastNotificationPayload = nil
        lastOpenPayload = nil
        initialNotification = nil
        liveActivityPushToStartTokenTask?.cancel()
        liveActivityCustomPushToStartTokenTasks.values.forEach { $0.cancel() }
        liveActivityCustomActivityUpdatesTasks.values.forEach { $0.cancel() }
        liveActivityActivityUpdatesTask?.cancel()
        liveActivityUpdateTokenTasks.values.forEach { $0.cancel() }
        liveActivityStateUpdateTasks.values.forEach { $0.cancel() }
        liveActivityContentUpdateTasks.values.forEach { $0.cancel() }
        liveActivityPushToStartTokenTask = nil
        liveActivityCustomPushToStartTokenTasks = [:]
        liveActivityCustomActivityUpdatesTasks = [:]
        liveActivityActivityUpdatesTask = nil
        liveActivityUpdateTokenTasks = [:]
        liveActivityStateUpdateTasks = [:]
        liveActivityContentUpdateTasks = [:]
        pendingLiveActivityTokenRegistrations = []
        liveActivityRegisteredTokenKeys = []
        liveActivityTrackedReceiptActivityIds = []
        liveActivityTrackedUpdateSendIds = []
        liveActivityStatus = "not_started"
        liveActivityEnabled = nil
        liveActivityPushToStartObserved = false
        liveActivityTokenRegistrationAttempts = 0
        liveActivityTokenRegistrationSuccesses = 0
        liveActivityTokenRegistrationFailures = 0
        liveActivityLastError = nil
        liveActivityLastTokenType = nil
        notificationCenterIntegrationDisabledForTesting = false
        applicationIntegrationDisabledForTesting = false
        notificationPermissionStatusForTesting = nil
        requestNotificationAuthorizationForTesting = nil
        notificationAuthorizationStatusForTesting = nil
        registerForRemoteNotificationsForTesting = nil
        openURLForTesting = nil
        setBadgeCountForTesting = nil
        registerNotificationCategoriesForTesting = nil
        liveActivityActivitiesEnabledForTesting = nil
        SendrealmNotificationServiceHelper.imageDownloadForTesting = nil
    }

    func testingSetState(
        appId: String?,
        baseUrl: String?,
        deviceId: String?,
        externalUserId: String?,
        userEmail: String?,
        apnsToken: String?,
        environment: String = "production",
        apnsEnvironment: String,
        subscribed: Bool,
        initialized: Bool
    ) {
        self.appId = appId
        self.baseUrl = baseUrl
        self.deviceId = deviceId
        self.externalUserId = externalUserId
        self.userEmail = userEmail
        self.apnsToken = apnsToken
        self.environment = normalizePushEnvironment(environment)
        self.apnsEnvironment = normalizeApnsEnvironment(apnsEnvironment)
        self.subscribed = subscribed
        self.initialized = initialized
        persistState()
    }

    func testingReloadState() {
        loadState()
    }

    func testingClearMemoryState() {
        initialized = false
        subscribed = false
        suppressForegroundNotifications = false
        foregroundBanner = true
        foregroundList = true
        foregroundSound = true
        foregroundBadge = true
        appId = nil
        baseUrl = nil
        apiUrlSource = "default"
        deviceId = nil
        externalUserId = nil
        userEmail = nil
        apnsToken = nil
        environment = "production"
        apnsEnvironment = "production"
        lastPermissionStatus = "not_determined"
        lastRegistrationFingerprint = nil
        lastInitResult = nil
        lastRegisterResult = nil
        lastSdkError = nil
        lastNotificationPayload = nil
        lastOpenPayload = nil
        initialNotification = nil
        liveActivityPushToStartTokenTask?.cancel()
        liveActivityCustomPushToStartTokenTasks.values.forEach { $0.cancel() }
        liveActivityCustomActivityUpdatesTasks.values.forEach { $0.cancel() }
        liveActivityActivityUpdatesTask?.cancel()
        liveActivityUpdateTokenTasks.values.forEach { $0.cancel() }
        liveActivityStateUpdateTasks.values.forEach { $0.cancel() }
        liveActivityContentUpdateTasks.values.forEach { $0.cancel() }
        liveActivityPushToStartTokenTask = nil
        liveActivityCustomPushToStartTokenTasks = [:]
        liveActivityCustomActivityUpdatesTasks = [:]
        liveActivityActivityUpdatesTask = nil
        liveActivityUpdateTokenTasks = [:]
        liveActivityStateUpdateTasks = [:]
        liveActivityContentUpdateTasks = [:]
        pendingLiveActivityTokenRegistrations = []
        liveActivityRegisteredTokenKeys = []
        liveActivityTrackedReceiptActivityIds = []
        liveActivityTrackedUpdateSendIds = []
        liveActivityStatus = "not_started"
        liveActivityEnabled = nil
        liveActivityPushToStartObserved = false
        liveActivityTokenRegistrationAttempts = 0
        liveActivityTokenRegistrationSuccesses = 0
        liveActivityTokenRegistrationFailures = 0
        liveActivityLastError = nil
        liveActivityLastTokenType = nil
        notificationCenterIntegrationDisabledForTesting = false
        applicationIntegrationDisabledForTesting = false
        notificationPermissionStatusForTesting = nil
        liveActivityActivitiesEnabledForTesting = nil
    }

    func testingStateSnapshot() -> [String: Any?] {
        [
            "initialized": initialized,
            "subscribed": subscribed,
            "appId": appId,
            "baseUrl": baseUrl,
            "deviceId": deviceId,
            "externalUserId": externalUserId,
            "userEmail": userEmail,
            "apnsToken": apnsToken,
            "apnsEnvironment": apnsEnvironment
        ]
    }

    func testingBaseDevicePayload(additional: [String: Any?] = [:]) -> [String: Any] {
        sanitizeJSON(baseDevicePayload(additional: additional)) as? [String: Any] ?? [:]
    }

    func testingSanitizeJSON(_ value: [String: Any?]) -> [String: Any] {
        sanitizeJSON(value) as? [String: Any] ?? [:]
    }

    func testingAPIErrorMessage(_ json: [String: Any]) -> String {
        apiErrorMessage(json, fallback: "Fallback")
    }

    func testingEnqueueEvent(
        eventType: String,
        notificationId: String? = nil,
        properties: [String: Any]? = nil
    ) {
        enqueueEvent(
            eventType: eventType,
            notificationId: notificationId,
            properties: properties
        )
    }

    func testingQueuedEvents() -> [[String: Any]] {
        queuedEvents()
    }

    func testingEnqueueTags(_ tags: [String: Any]) {
        enqueueTags(tags)
    }

    func testingQueuedTags() -> [String: Any] {
        queuedTags()
    }

    func testingEnqueueOperation(name: String, path: String, payload: [String: Any?]) {
        enqueueOperation(name: name, path: path, payload: payload)
    }

    func testingQueuedOperations() -> [[String: Any]] {
        queuedOperations()
    }

    func testingMakeQueuedOperationsReady() {
        let operations = queuedOperations().map { operation -> [String: Any] in
            var nextOperation = operation
            nextOperation["nextAttemptAt"] = 0.0
            return nextOperation
        }
        saveQueuedOperations(operations)
    }

    func testingQueueCounts() -> [String: Int] {
        queueCounts()
    }

    func testingApplyForegroundPresentation(_ options: NSDictionary) {
        applyForegroundPresentation(options)
    }

    func testingForegroundPresentationDiagnostics() -> [String: Bool] {
        foregroundPresentationDiagnostics()
    }

    func testingRegistrationFingerprint() -> String {
        registrationFingerprint()
    }
}
