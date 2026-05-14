import Foundation

final class TerminalSettings: ObservableObject {
    static let shared = TerminalSettings()

    @Published var useMetalRenderer: Bool {
        didSet { UserDefaults.standard.set(useMetalRenderer, forKey: Self.metalKey) }
    }

    private static let metalKey = "useMetalRenderer"

    private init() {
        useMetalRenderer = UserDefaults.standard.bool(forKey: Self.metalKey)
    }
}
