import Foundation
import Observation

@MainActor
@Observable
final class PairingStore {
    private static let key = "pluriMobilePairing"
    private(set) var pairing: PluriPairing?

    init() {
        if let url = KeychainStore.string(for: Self.key) {
            pairing = PluriPairing(url: url)
        }
    }

    func save(_ pairing: PluriPairing) {
        KeychainStore.set(pairing.url, for: Self.key)
        self.pairing = pairing
    }

    func clear() {
        KeychainStore.delete(Self.key)
        pairing = nil
    }
}
