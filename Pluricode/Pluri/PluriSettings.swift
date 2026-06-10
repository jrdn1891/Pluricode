import Foundation

final class PluriSettings: ObservableObject {
    static let shared = PluriSettings()

    static let defaultSetupScript = "claude"

    @Published var setupScript: String {
        didSet { UserDefaults.standard.set(setupScript, forKey: Self.setupScriptKey) }
    }

    @Published var workerSetupScript: String {
        didSet { UserDefaults.standard.set(workerSetupScript, forKey: Self.workerSetupScriptKey) }
    }

    var effectiveWorkerScript: String {
        workerSetupScript.isEmpty ? setupScript : workerSetupScript
    }

    private static let setupScriptKey = "pluriSetupScript"
    private static let workerSetupScriptKey = "pluriWorkerSetupScript"

    private init() {
        setupScript = UserDefaults.standard.string(forKey: Self.setupScriptKey) ?? Self.defaultSetupScript
        workerSetupScript = UserDefaults.standard.string(forKey: Self.workerSetupScriptKey) ?? ""
    }
}
