import Foundation

final class TerminalSettings: ObservableObject {
    static let shared = TerminalSettings()

    static let defaultIdleEmoji = "🥱"

    @Published var useMetalRenderer: Bool {
        didSet { UserDefaults.standard.set(useMetalRenderer, forKey: Self.metalKey) }
    }

    @Published var idleEmoji: String {
        didSet { UserDefaults.standard.set(idleEmoji, forKey: Self.idleEmojiKey) }
    }

    private static let metalKey = "useMetalRenderer"
    private static let idleEmojiKey = "idleEmoji"

    private init() {
        useMetalRenderer = UserDefaults.standard.bool(forKey: Self.metalKey)
        idleEmoji = UserDefaults.standard.object(forKey: Self.idleEmojiKey) as? String ?? Self.defaultIdleEmoji
    }
}
