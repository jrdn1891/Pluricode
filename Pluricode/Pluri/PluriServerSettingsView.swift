import SwiftUI
import CoreImage.CIFilterBuiltins

struct PluriServerSettingsView: View {
    @Bindable var server: PluriServer
    @State private var host = ""

    private var addresses: [String] {
        let found = PluriServer.localAddresses()
        return found.isEmpty ? ["127.0.0.1"] : found
    }

    private var pairing: PluriPairing {
        PluriPairing(host: host.isEmpty ? addresses[0] : host, port: server.port, token: server.token)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                toggleRow
                if server.enabled {
                    pairingRow
                }
            }
            .padding(20)
        }
        .frame(width: 540, height: 560)
        .onAppear { if host.isEmpty { host = addresses.first ?? "" } }
    }

    private var toggleRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mobile access").font(.headline)
                Text("Run a local server so the Pluricode mobile app can drive Pluri over your private network (e.g. a Tailscale tailnet). Pair the phone once with the link below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Allow mobile access", isOn: $server.enabled)
            HStack(spacing: 6) {
                Circle()
                    .fill(server.isRunning ? .green : .secondary)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var statusText: String {
        if let error = server.lastError { return "Error — \(error)" }
        return server.isRunning ? "Listening on port \(server.port)" : "Stopped"
    }

    private var pairingRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pair a device").font(.headline)
            if addresses.count > 1 {
                Picker("This Mac's address", selection: $host) {
                    ForEach(addresses, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
            }
            HStack(alignment: .top, spacing: 16) {
                if let image = qrImage(from: pairing.url) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 160, height: 160)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scan in the mobile app, or paste this link:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(pairing.url)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .truncationMode(.middle)
                    Button("Copy Link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(pairing.url, forType: .string)
                    }
                    Text("Token is stored in your Keychain and only travels inside this link.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func qrImage(from string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
