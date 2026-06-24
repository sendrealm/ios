import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

private let sendrealmLiveActivityCallbackScheme = "sendrealm-ios-demo"

@available(iOSApplicationExtension 16.1, *)
struct SendrealmLiveActivityAttributes: ActivityAttributes, Codable {
    struct ActionButton: Codable, Hashable {
        var id: String
        var text: String
        var title: String
        var launch_url: String?

        private enum CodingKeys: String, CodingKey {
            case id
            case text
            case title
            case launchURL = "launch_url"
            case launchUrl
        }

        init(id: String = "", text: String = "", title: String = "", launch_url: String? = nil) {
            self.id = id
            self.text = text
            self.title = title
            self.launch_url = launch_url
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
            text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""

            if let snakeLaunchURL = try container.decodeIfPresent(String.self, forKey: .launchURL) {
                launch_url = snakeLaunchURL
            } else {
                launch_url = try container.decodeIfPresent(String.self, forKey: .launchUrl)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(text, forKey: .text)
            try container.encode(title, forKey: .title)
            try container.encodeIfPresent(launch_url, forKey: .launchURL)
        }
    }

    public struct ContentState: Codable, Hashable {
        var title: String
        var subtitle: String
        var body: String
        var status: String
        var progress: Double?
        var eta: String
        var image_url: String
        var accent_color: String
        var launch_url: String
        var send_id: String
        var buttons: [ActionButton]?
    }

    var activity_id: String
    var send_id: String
}

@available(iOSApplicationExtension 16.1, *)
struct SendrealmLiveActivityLockScreenView: View {
    let context: ActivityViewContext<SendrealmLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(context.state.title.isEmpty ? "Sendrealm" : context.state.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(context.state.eta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(context.state.status.isEmpty ? context.state.body : context.state.status)
                .font(.subheadline)
                .lineLimit(2)

            if let progress = context.state.progress {
                ProgressView(value: max(0, min(progress, 1)))
                    .tint(accentColor)
            }

            actionLinks
        }
        .padding()
        .activityBackgroundTint(Color(.secondarySystemBackground))
        .activitySystemActionForegroundColor(accentColor)
        .widgetURL(liveActivityOpenURL(
            targetURL: context.state.launch_url,
            activityId: context.attributes.activity_id,
            sendId: liveActivitySendId
        ))
    }

    private var accentColor: Color {
        Color(hex: context.state.accent_color) ?? .accentColor
    }

    private var liveActivitySendId: String {
        let stateSendId = context.state.send_id.trimmingCharacters(in: .whitespacesAndNewlines)
        return stateSendId.isEmpty ? context.attributes.send_id : stateSendId
    }

    private var actionButtons: [SendrealmLiveActivityAttributes.ActionButton] {
        Array((context.state.buttons ?? []).prefix(3)).filter { button in
            !actionTitle(button).isEmpty
        }
    }

    private var actionLinks: some View {
        Group {
            if !actionButtons.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(actionButtons.enumerated()), id: \.offset) { _, button in
                        if let url = actionURL(button) {
                            Link(destination: url) {
                                actionLabel(button)
                            }
                        } else {
                            actionLabel(button)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func actionTitle(_ button: SendrealmLiveActivityAttributes.ActionButton) -> String {
        let title = button.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = button.text.trimmingCharacters(in: .whitespacesAndNewlines)

        return title.isEmpty ? text : title
    }

    private func actionLabel(_ button: SendrealmLiveActivityAttributes.ActionButton) -> some View {
        Text(actionTitle(button))
            .font(.caption.bold())
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(accentColor.opacity(0.16))
            .clipShape(Capsule())
    }

    private func actionURL(_ button: SendrealmLiveActivityAttributes.ActionButton) -> URL? {
        liveActivityActionURL(
            targetURL: button.launch_url,
            actionId: button.id,
            activityId: context.attributes.activity_id,
            sendId: liveActivitySendId
        )
    }
}

@available(iOSApplicationExtension 16.1, *)
struct SendrealmLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SendrealmLiveActivityAttributes.self) { context in
            SendrealmLiveActivityLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.title.isEmpty ? "Sendrealm" : context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.eta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.status.isEmpty ? context.state.body : context.state.status)
                            .font(.caption)
                            .lineLimit(2)

                        if let progress = context.state.progress {
                            ProgressView(value: max(0, min(progress, 1)))
                        }

                        SendrealmLiveActivityActionsView(
                            buttons: context.state.buttons ?? [],
                            activityId: context.attributes.activity_id,
                            sendId: liveActivitySendId(context),
                            accentColor: Color(hex: context.state.accent_color) ?? .accentColor
                        )
                    }
                }
            } compactLeading: {
                Text("SR")
                    .font(.caption2.bold())
            } compactTrailing: {
                if let progress = context.state.progress {
                    Text("\(Int(max(0, min(progress, 1)) * 100))%")
                        .font(.caption2)
                } else {
                    Text(context.state.eta)
                        .font(.caption2)
                }
            } minimal: {
                Text("SR")
                    .font(.caption2.bold())
            }
            .widgetURL(liveActivityOpenURL(
                targetURL: context.state.launch_url,
                activityId: context.attributes.activity_id,
                sendId: liveActivitySendId(context)
            ))
        }
    }
}

@available(iOSApplicationExtension 16.1, *)
private struct SendrealmLiveActivityActionsView: View {
    let buttons: [SendrealmLiveActivityAttributes.ActionButton]
    let activityId: String
    let sendId: String
    let accentColor: Color

    private var visibleButtons: [SendrealmLiveActivityAttributes.ActionButton] {
        Array(buttons.prefix(3)).filter { button in
            !actionTitle(button).isEmpty
        }
    }

    var body: some View {
        if !visibleButtons.isEmpty {
            HStack(spacing: 8) {
                ForEach(Array(visibleButtons.enumerated()), id: \.offset) { _, button in
                    if let url = actionURL(button) {
                        Link(destination: url) {
                            actionLabel(button)
                        }
                    } else {
                        actionLabel(button)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func actionTitle(_ button: SendrealmLiveActivityAttributes.ActionButton) -> String {
        let title = button.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = button.text.trimmingCharacters(in: .whitespacesAndNewlines)

        return title.isEmpty ? text : title
    }

    private func actionLabel(_ button: SendrealmLiveActivityAttributes.ActionButton) -> some View {
        Text(actionTitle(button))
            .font(.caption2.bold())
            .lineLimit(1)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(accentColor.opacity(0.16))
            .clipShape(Capsule())
    }

    private func actionURL(_ button: SendrealmLiveActivityAttributes.ActionButton) -> URL? {
        liveActivityActionURL(
            targetURL: button.launch_url,
            actionId: button.id,
            activityId: activityId,
            sendId: sendId
        )
    }
}

@available(iOSApplicationExtension 16.1, *)
private func liveActivitySendId(_ context: ActivityViewContext<SendrealmLiveActivityAttributes>) -> String {
    let stateSendId = context.state.send_id.trimmingCharacters(in: .whitespacesAndNewlines)
    return stateSendId.isEmpty ? context.attributes.send_id : stateSendId
}

private func liveActivityOpenURL(targetURL: String?, activityId: String, sendId: String?) -> URL? {
    liveActivityCallbackURL(
        path: "/live-activity-open",
        targetURL: targetURL,
        actionId: nil,
        activityId: activityId,
        sendId: sendId
    )
}

private func liveActivityActionURL(
    targetURL: String?,
    actionId: String?,
    activityId: String,
    sendId: String?
) -> URL? {
    liveActivityCallbackURL(
        path: "/live-activity-action",
        targetURL: targetURL,
        actionId: actionId,
        activityId: activityId,
        sendId: sendId
    )
}

private func liveActivityCallbackURL(
    path: String,
    targetURL: String?,
    actionId: String?,
    activityId: String,
    sendId: String?
) -> URL? {
    guard let targetURL = liveActivityURL(targetURL) else {
        return nil
    }

    var components = URLComponents()
    components.scheme = sendrealmLiveActivityCallbackScheme
    components.host = "sendrealm"
    components.path = path
    components.queryItems = [
        URLQueryItem(name: "target_url", value: targetURL.absoluteString),
        URLQueryItem(name: "action_id", value: actionId),
        URLQueryItem(name: "activity_id", value: activityId),
        URLQueryItem(name: "send_id", value: sendId)
    ].filter { item in
        guard let value = item.value else {
            return false
        }

        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    return components.url
}

private func liveActivityURL(_ value: String?) -> URL? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else {
        return nil
    }

    return URL(string: value)
}

@main
@available(iOSApplicationExtension 16.1, *)
struct SendrealmLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        SendrealmLiveActivityWidget()
    }
}

private extension Color {
    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard trimmed.count == 6, let value = UInt64(trimmed, radix: 16) else {
            return nil
        }

        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}
