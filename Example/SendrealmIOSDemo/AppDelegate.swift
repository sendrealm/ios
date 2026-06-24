import SendrealmIOS
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Sendrealm.configure()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Sendrealm.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
        NotificationCenter.default.post(
            name: .sendrealmDemoLog,
            object: "APNs token received"
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NotificationCenter.default.post(
            name: .sendrealmDemoLog,
            object: "APNs registration failed: \(error.localizedDescription)"
        )
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Sendrealm.didReceiveRemoteNotification(userInfo as NSDictionary)
        completionHandler(.newData)
    }
}

extension Notification.Name {
    static let sendrealmDemoLog = Notification.Name("SendrealmDemoLog")
}
