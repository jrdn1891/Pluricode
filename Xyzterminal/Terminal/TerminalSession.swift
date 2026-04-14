import AppKit
import SwiftTerm

final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate {
    let nodeID: UUID
    let terminalView: LocalProcessTerminalView
    var worktreePath: String?
    var onProcessTerminated: ((Int32?) -> Void)?

    init(nodeID: UUID) {
        self.nodeID = nodeID
        self.terminalView = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 270))
        super.init()
        terminalView.processDelegate = self
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    }

    func updateColors(theme: Theme) {
        terminalView.nativeBackgroundColor = theme.terminalBackground
        terminalView.nativeForegroundColor = theme.terminalForeground
    }

    func start(in directory: String? = nil) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = Array(ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" })
        if let dir = directory {
            env.removeAll { $0.hasPrefix("PWD=") }
            env.append("PWD=\(dir)")
        }
        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: env,
            execName: (shell as NSString).lastPathComponent,
            currentDirectory: directory
        )
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        onProcessTerminated?(exitCode)
    }
}
