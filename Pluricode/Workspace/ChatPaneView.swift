import SwiftUI
import AppKit

struct ChatPaneView: View {
    let pane: Pane
    let tabID: UUID
    let worktreePath: String
    let repoPath: String
    let workspace: Workspace
    let title: String
    let branch: String
    let repoName: String?
    let repoColor: Color?
    let profile: AgentProfile?
    let isExpanded: Bool
    let onActivate: () -> Void
    let onToggleRaw: () -> Void
    let onExpand: () -> Void
    let onClose: () -> Void

    var body: some View {
        if useNativeChat {
            NativeChatPaneView(
                tabID: tabID,
                worktreePath: worktreePath,
                workspace: workspace,
                title: title,
                branch: branch,
                repoName: repoName,
                repoColor: repoColor,
                profile: profile,
                isExpanded: isExpanded,
                onActivate: onActivate,
                onToggleRaw: onToggleRaw,
                onExpand: onExpand,
                onClose: onClose
            )
        } else {
            TerminalChatPaneView(
                pane: pane,
                tabID: tabID,
                worktreePath: worktreePath,
                repoPath: repoPath,
                workspace: workspace,
                title: title,
                branch: branch,
                repoName: repoName,
                repoColor: repoColor,
                profile: profile,
                isExpanded: isExpanded,
                onActivate: onActivate,
                onToggleRaw: onToggleRaw,
                onExpand: onExpand,
                onClose: onClose
            )
        }
    }

    private var useNativeChat: Bool {
        (profile?.agentDefinition ?? AgentDefinition.claudeCode.name) == AgentDefinition.claudeCode.name
    }
}

private struct NativeChatPaneView: View {
    let tabID: UUID
    let worktreePath: String
    let workspace: Workspace
    let title: String
    let branch: String
    let repoName: String?
    let repoColor: Color?
    let profile: AgentProfile?
    let isExpanded: Bool
    let onActivate: () -> Void
    let onToggleRaw: () -> Void
    let onExpand: () -> Void
    let onClose: () -> Void

    var body: some View {
        let session = workspace.chatSession(forTab: tabID, worktreePath: worktreePath)
        VStack(spacing: 0) {
            ChatHeader(
                status: status(from: session),
                title: title,
                branch: branch,
                repoName: repoName,
                repoColor: repoColor,
                profile: profile,
                isExpanded: isExpanded,
                onActivate: onActivate,
                onToggleRaw: onToggleRaw,
                onExpand: onExpand,
                onClose: onClose
            )
            TranscriptView(transcript: session.transcript)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(transcriptBackground)
                .contentShape(Rectangle())
                .onTapGesture(perform: onActivate)
            ChatComposer(
                isBusy: session.transcript.isStreaming,
                onStop: { session.cancel() },
                onSend: { session.send($0) }
            )
        }
    }

    private func status(from session: ChatSession) -> TerminalStatus {
        session.transcript.isStreaming ? .working : .idle
    }

    private var transcriptBackground: Color {
        Color(nsColor: NSColor.textBackgroundColor)
    }
}

private struct TerminalChatPaneView: View {
    let pane: Pane
    let tabID: UUID
    let worktreePath: String
    let repoPath: String
    let workspace: Workspace
    let title: String
    let branch: String
    let repoName: String?
    let repoColor: Color?
    let profile: AgentProfile?
    let isExpanded: Bool
    let onActivate: () -> Void
    let onToggleRaw: () -> Void
    let onExpand: () -> Void
    let onClose: () -> Void

    var body: some View {
        let host = workspace.terminalHost(forTab: tabID, worktreePath: worktreePath, repoPath: repoPath)
        VStack(spacing: 0) {
            ChatHeader(
                status: host.session.status,
                title: title,
                branch: branch,
                repoName: repoName,
                repoColor: repoColor,
                profile: profile,
                isExpanded: isExpanded,
                onActivate: onActivate,
                onToggleRaw: onToggleRaw,
                onExpand: onExpand,
                onClose: onClose
            )
            transcriptArea(host: host)
            ChatComposer(onSend: { host.session.submit($0) })
        }
        .onAppear {
            host.setChatStyled(true)
            host.session.setReadOnly(true)
        }
        .onDisappear {
            host.session.setReadOnly(false)
            host.setChatStyled(false)
        }
    }

    @ViewBuilder
    private func transcriptArea(host: TerminalHost) -> some View {
        TerminalPaneView(tabID: tabID, worktreePath: worktreePath, repoPath: repoPath, workspace: workspace)
            .id(tabID)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [Color.clear, Color(nsColor: Theme(from: NSApp.effectiveAppearance).chatTerminalBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 36)
                .allowsHitTesting(false)
            }
            .overlay {
                IdleOverlay(session: host.session)
            }
    }
}
