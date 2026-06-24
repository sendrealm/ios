import Foundation

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
public struct SendrealmLiveActivityAttributes: ActivityAttributes, Codable {
    public struct Button: Codable, Hashable {
        public var id: String
        public var text: String
        public var title: String
        public var launch_url: String?

        public init(
            id: String = "",
            text: String = "",
            title: String = "",
            launch_url: String? = nil
        ) {
            self.id = id
            self.text = text
            self.title = title
            self.launch_url = launch_url
        }
    }

    public struct ContentState: Codable, Hashable {
        public var title: String
        public var subtitle: String
        public var body: String
        public var status: String
        public var progress: Double?
        public var eta: String
        public var image_url: String
        public var accent_color: String
        public var launch_url: String
        public var send_id: String
        public var buttons: [Button]?

        public init(
            title: String = "",
            subtitle: String = "",
            body: String = "",
            status: String = "",
            progress: Double? = nil,
            eta: String = "",
            image_url: String = "",
            accent_color: String = "",
            launch_url: String = "",
            send_id: String = "",
            buttons: [Button]? = []
        ) {
            self.title = title
            self.subtitle = subtitle
            self.body = body
            self.status = status
            self.progress = progress
            self.eta = eta
            self.image_url = image_url
            self.accent_color = accent_color
            self.launch_url = launch_url
            self.send_id = send_id
            self.buttons = buttons
        }
    }

    public var activity_id: String
    public var send_id: String

    public init(activity_id: String, send_id: String = "") {
        self.activity_id = activity_id
        self.send_id = send_id
    }
}
#endif
