import Observation

@MainActor
protocol PluriChatBackend: Observable, AnyObject {
    var blocks: [PluriBlock] { get }
    var isRunning: Bool { get }
    var tasks: [PluriTask] { get }
    var proposal: [PluriProposalItem]? { get }
    func hasLiveWorker(_ task: PluriTask) -> Bool

    func send(_ text: String)
    func interrupt()
    func clearConversation()
    func approveProposal()
    func declineProposal()
    func reply(to task: PluriTask, text: String)
    func redispatch(_ task: PluriTask)
    func focusWorkerPane(_ task: PluriTask)
}
