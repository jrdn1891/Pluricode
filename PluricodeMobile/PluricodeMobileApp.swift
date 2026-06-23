import SwiftUI

@main
struct PluricodeMobileApp: App {
    @State private var store = PairingStore()

    var body: some Scene {
        WindowGroup {
            if let pairing = store.pairing {
                ConnectedView(pairing: pairing, onUnpair: { store.clear() })
                    .id(pairing)
            } else {
                PairingView { store.save($0) }
            }
        }
    }
}

private struct ConnectedView: View {
    let pairing: PluriPairing
    let onUnpair: () -> Void
    @State private var backend: RemotePluriBackend

    init(pairing: PluriPairing, onUnpair: @escaping () -> Void) {
        self.pairing = pairing
        self.onUnpair = onUnpair
        _backend = State(initialValue: RemotePluriBackend(pairing: pairing))
    }

    var body: some View {
        NavigationStack {
            PluriChatView(backend: backend)
                .navigationTitle("Pluri")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { connectionBadge }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Unpair", role: .destructive, action: onUnpair)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
        }
    }

    @ViewBuilder private var connectionBadge: some View {
        switch backend.connection {
        case .connecting:
            Label("Connecting…", systemImage: "circle.dotted")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
        case .connected:
            Image(systemName: "circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.green)
        case .failed:
            Button {
                backend.reconnect()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.orange)
            }
        }
    }
}
