import SwiftUI

struct SpawnApprovalBanner: View {
    let workspace: Workspace

    var body: some View {
        if !workspace.pendingSpawnRequests.isEmpty {
            VStack(spacing: 8) {
                ForEach(workspace.pendingSpawnRequests) { request in
                    BannerRow(workspace: workspace, request: request)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

private struct BannerRow: View {
    let workspace: Workspace
    let request: PendingSpawnRequest

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Agent wants to act on this workspace")
                    .font(.system(size: 12, weight: .semibold))
                Text(request.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            Menu {
                Button("Always allow in this workspace") {
                    workspace.setSpawnPolicy(.allow)
                    workspace.resolveSpawnRequest(id: request.id, approve: true)
                }
                Button("Allow up to 5 in this session") {
                    workspace.setSpawnPolicy(.allowUpTo(5))
                    workspace.resolveSpawnRequest(id: request.id, approve: true)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button("Deny") {
                workspace.resolveSpawnRequest(id: request.id, approve: false)
            }
            .keyboardShortcut(.cancelAction)
            Button("Allow") {
                workspace.resolveSpawnRequest(id: request.id, approve: true)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
}
