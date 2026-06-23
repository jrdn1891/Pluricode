import Foundation
import Observation

@MainActor
@Observable
final class LocalPluriBackend: PluriChatBackend {
    let session: PluriSession
    let bridge: PluriBridge
    let registry: PluriTaskRegistry

    init(session: PluriSession, bridge: PluriBridge, registry: PluriTaskRegistry) {
        self.session = session
        self.bridge = bridge
        self.registry = registry
    }

    var blocks: [PluriBlock] { session.blocks }
    var isRunning: Bool { session.isRunning }
    var tasks: [PluriTask] { registry.tasks }

    var proposal: [PluriProposalItem]? {
        registry.proposal?.map {
            PluriProposalItem(repoName: $0.repo.name, branch: $0.branch, prompt: $0.prompt)
        }
    }

    func hasLiveWorker(_ task: PluriTask) -> Bool {
        bridge.workerSession(for: task) != nil
    }

    func send(_ text: String) { session.send(text) }
    func interrupt() { session.interrupt() }
    func clearConversation() { session.clear() }

    func approveProposal() {
        let count = registry.proposal?.count ?? 0
        Task {
            await bridge.approveProposal()
            session.postEvent("[approval] The user approved the proposal — \(count) worker\(count == 1 ? "" : "s") dispatched.")
        }
    }

    func declineProposal() {
        registry.proposal = nil
        session.postEvent("[approval] The user declined the proposed tasks.")
    }

    func reply(to task: PluriTask, text: String) {
        bridge.reply(to: task, text: text)
    }

    func redispatch(_ task: PluriTask) {
        Task { _ = await bridge.redispatch(task) }
    }

    func focusWorkerPane(_ task: PluriTask) {
        _ = bridge.focusWorkerPane(for: task)
    }
}
