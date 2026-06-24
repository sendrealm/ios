import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: DemoViewModel

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusSection
                    configurationSection
                    actionsSection
                    notificationSection
                    logsSection
                }
                .padding()
            }
            .navigationTitle("Sendrealm Native Demo")
            .alert(item: $viewModel.activeAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var statusSection: some View {
        DemoSection(title: "Status") {
            StatusRow(label: "Device ID", value: viewModel.deviceId)
            StatusRow(label: "Token", value: viewModel.tokenStatus)
            StatusRow(label: "Permission", value: viewModel.permissionStatus)
            StatusRow(label: "Subscription", value: viewModel.subscriptionStatus)
            StatusRow(label: "Live Activities", value: viewModel.liveActivityStatus)
            StatusRow(label: "APNs", value: viewModel.apnsEnvironment)
            StatusRow(label: "Last action", value: viewModel.status)
        }
    }

    private var configurationSection: some View {
        DemoSection(title: "Configuration") {
            TextField("Sendrealm App ID", text: $viewModel.appId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            TextField("SDK API URL", text: $viewModel.baseUrl)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            Picker("APNs Environment", selection: $viewModel.apnsEnvironment) {
                Text("Sandbox").tag("sandbox")
                Text("Production").tag("production")
            }
            .pickerStyle(.segmented)

            Toggle("Suppress foreground display", isOn: $viewModel.suppressForegroundNotifications)
        }
    }

    private var actionsSection: some View {
        DemoSection(title: "Actions") {
            Button(action: viewModel.initializeSdk) {
                HStack(spacing: 8) {
                    if viewModel.isInitializing {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(viewModel.isInitializing ? "Initializing..." : "Initialize SDK")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isInitializing)

            HStack {
                Button("Request Permission", action: viewModel.requestPermission)
                Button("Refresh Token", action: viewModel.refreshRegistrationToken)
            }

            HStack {
                Button("Refresh State", action: viewModel.refreshState)
                Button("Sync Live Activities", action: viewModel.syncLiveActivityTokens)
            }

            HStack {
                Button("Opt In", action: viewModel.optIn)
                Button("Opt Out", action: viewModel.optOut)
            }

            Divider()

            TextField("External user ID", text: $viewModel.externalUserId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            TextField("User email", text: $viewModel.userEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Login", action: viewModel.login)
                Button("Logout", action: viewModel.logout)
            }

            Divider()

            HStack {
                TextField("Tag key", text: $viewModel.tagKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                TextField("Tag value", text: $viewModel.tagValue)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }

            Button("Add Tag", action: viewModel.addTag)

            TextField("Event name", text: $viewModel.eventName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            Button("Track Event", action: viewModel.trackEvent)
        }
    }

    private var notificationSection: some View {
        DemoSection(title: "Notifications") {
            Text(viewModel.lastNotification)
                .font(.footnote)
                .textSelection(.enabled)

            ForEach(viewModel.notificationEvents) { event in
                Text(event.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var logsSection: some View {
        DemoSection(title: "Activity Log") {
            ForEach(viewModel.logs) { log in
                Text(log.message)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
    }
}

private struct DemoSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct StatusRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .fontWeight(.semibold)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }
}
