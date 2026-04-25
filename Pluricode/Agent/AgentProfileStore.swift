import Foundation
import Observation

@Observable
final class AgentProfileStore {
    var profiles: [AgentProfile]

    private static let key = "agentProfiles"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([AgentProfile].self, from: data) {
            profiles = decoded
        } else {
            profiles = AgentProfile.defaults
        }
    }

    func profile(id: UUID) -> AgentProfile? {
        profiles.first { $0.id == id }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
