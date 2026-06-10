import Foundation

final class PluriSettings: ObservableObject {
    static let shared = PluriSettings()

    static let defaultCommand = "claude"

    @Published var command: String {
        didSet { UserDefaults.standard.set(command, forKey: Self.commandKey) }
    }

    @Published var workerSetupScript: String {
        didSet { UserDefaults.standard.set(workerSetupScript, forKey: Self.workerSetupScriptKey) }
    }

    var effectiveWorkerScript: String {
        workerSetupScript.isEmpty ? command : workerSetupScript
    }

    private static let commandKey = "pluriCommand"
    private static let workerSetupScriptKey = "pluriWorkerSetupScript"

    private init() {
        command = UserDefaults.standard.string(forKey: Self.commandKey) ?? Self.defaultCommand
        workerSetupScript = UserDefaults.standard.string(forKey: Self.workerSetupScriptKey) ?? ""
    }
}
