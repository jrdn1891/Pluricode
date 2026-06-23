import SwiftUI
import UIKit

struct PairingView: View {
    let onPaired: (PluriPairing) -> Void
    @State private var link = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            PluriMascotView(size: 56)
            Text("Connect to your Mac")
                .font(.title2.bold())
            Text("On your Mac open Pluricode → Settings → Mobile, turn on access, then paste the pairing link here.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            TextField("pluri://pair?…", text: $link, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(1...4)
            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack(spacing: 12) {
                Button("Paste") {
                    if let pasted = UIPasteboard.general.string { link = pasted }
                }
                .buttonStyle(.bordered)
                Button("Connect", action: connect)
                    .buttonStyle(.borderedProminent)
                    .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Spacer()
        }
        .padding(28)
    }

    private func connect() {
        guard let pairing = PluriPairing(url: link) else {
            error = "That doesn't look like a Pluri pairing link."
            return
        }
        error = nil
        onPaired(pairing)
    }
}
