import SwiftUI
import Combine
import Sparkle

@MainActor
final class UpdaterModel: ObservableObject {
    static let shared = UpdaterModel()

    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController
    private let channelDelegate = ChannelDelegate()

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: channelDelegate,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

private final class ChannelDelegate: NSObject, SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UserDefaults.standard.bool(forKey: "receiveNightlyBuilds") ? ["nightly"] : []
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject private var updater = UpdaterModel.shared

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}

struct UpdatesSettingsView: View {
    @AppStorage("receiveNightlyBuilds") private var receiveNightly = false

    var body: some View {
        Form {
            Toggle("Receive nightly builds", isOn: $receiveNightly)
            Text("Nightly builds ship the latest changes as they land on main. They may be unstable.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 400)
    }
}
