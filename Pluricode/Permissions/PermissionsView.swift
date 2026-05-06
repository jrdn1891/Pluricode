import SwiftUI

struct PermissionsView: View {
    @State private var service = PermissionsService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Apps launched in Pluricode terminals inherit Pluricode's macOS permissions. Grant the ones your tools need.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Permission.allCases) { permission in
                    PermissionRow(
                        permission: permission,
                        status: service.statuses[permission] ?? .notDetermined,
                        service: service
                    )
                }
            }
            .padding(20)
        }
        .frame(width: 540, height: 520)
        .onAppear { service.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            service.refresh()
        }
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let status: PermissionStatus
    let service: PermissionsService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(permission.title).font(.headline)
                Spacer()
                StatusBadge(status: status)
            }
            Text(permission.rationale)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                actionButton
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var actionButton: some View {
        switch status {
        case .notDetermined:
            Button("Grant") { service.request(permission) }
                .controlSize(.small)
        case .denied:
            Button("Open System Settings") { service.openSystemSettings(permission) }
                .controlSize(.small)
        case .granted:
            Button("Open System Settings") { service.openSystemSettings(permission) }
                .controlSize(.small)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatusBadge: View {
    let status: PermissionStatus

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var label: String {
        switch status {
        case .granted: "Granted"
        case .denied: "Not Granted"
        case .notDetermined: "Not Set"
        }
    }

    private var color: Color {
        switch status {
        case .granted: .green
        case .denied: .orange
        case .notDetermined: .secondary
        }
    }
}
