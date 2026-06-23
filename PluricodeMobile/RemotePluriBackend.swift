import Foundation
import Network
import Observation

@MainActor
@Observable
final class RemotePluriBackend: PluriChatBackend {
    enum Connection: Equatable {
        case connecting
        case connected
        case failed(String)
    }

    private(set) var state = PluriChatState()
    private(set) var connection: Connection = .connecting

    private let pairing: PluriPairing
    private var socket: NWConnection?
    private var reconnectScheduled = false

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(pairing: PluriPairing) {
        self.pairing = pairing
        connect()
    }

    var blocks: [PluriBlock] { state.blocks }
    var isRunning: Bool { state.isRunning }
    var tasks: [PluriTask] { state.tasks }
    var proposal: [PluriProposalItem]? { state.proposal }

    func hasLiveWorker(_ task: PluriTask) -> Bool {
        state.liveWorkers.contains(task.id)
    }

    func send(_ text: String) { dispatch(.send(text)) }
    func interrupt() { dispatch(.interrupt) }
    func clearConversation() { dispatch(.clear) }
    func approveProposal() { dispatch(.approveProposal) }
    func declineProposal() { dispatch(.declineProposal) }
    func reply(to task: PluriTask, text: String) { dispatch(.reply(taskID: task.id, text: text)) }
    func redispatch(_ task: PluriTask) { dispatch(.redispatch(taskID: task.id)) }
    func focusWorkerPane(_ task: PluriTask) { dispatch(.focusPane(taskID: task.id)) }

    func reconnect() {
        guard case .failed = connection else { return }
        connect()
    }

    private func connect() {
        socket?.cancel()
        connection = .connecting
        guard let url = URL(string: "ws://\(pairing.host):\(pairing.port)/") else {
            connection = .failed("Invalid pairing details")
            return
        }
        let parameters = NWParameters(tls: nil)
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        let socket = NWConnection(to: .url(url), using: parameters)
        socket.stateUpdateHandler = { state in
            MainActor.assumeIsolated { self.handle(state) }
        }
        self.socket = socket
        socket.start(queue: .main)
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            sendAuth()
            connection = .connected
            receive()
        case .failed(let error):
            connection = .failed(error.localizedDescription)
            scheduleReconnect()
        case .cancelled:
            break
        case .waiting(let error):
            connection = .failed(error.localizedDescription)
        default:
            break
        }
    }

    private struct AuthMessage: Encodable { let token: String }

    private func sendAuth() {
        send(AuthMessage(token: pairing.token))
    }

    private func dispatch(_ message: PluriClientMessage) {
        guard connection == .connected else { return }
        send(message)
    }

    private func send<T: Encodable>(_ value: T) {
        guard let data = try? encoder.encode(value) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])
        socket?.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }

    private func receive() {
        socket?.receiveMessage { [weak self] data, context, _, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
                let isClose = metadata?.opcode == .close
                if let data, !data.isEmpty,
                   let message = try? self.decoder.decode(PluriServerMessage.self, from: data) {
                    if case .state(let state) = message { self.state = state }
                }
                if error != nil || isClose {
                    self.connection = .failed("Disconnected")
                    self.scheduleReconnect()
                } else {
                    self.receive()
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard !reconnectScheduled else { return }
        reconnectScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.reconnectScheduled = false
            guard let self, self.connection != .connected else { return }
            self.connect()
        }
    }
}
