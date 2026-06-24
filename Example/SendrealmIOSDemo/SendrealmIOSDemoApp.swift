import SendrealmIOS
import SwiftUI

@main
struct SendrealmIOSDemoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = DemoViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onOpenURL { url in
                    if Sendrealm.handleOpenURL(url) {
                        NotificationCenter.default.post(
                            name: .sendrealmDemoLog,
                            object: "Opened Live Activity URL: \(url.absoluteString)"
                        )
                    }
                }
        }
    }
}
