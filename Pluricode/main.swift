import Foundation
import SwiftUI

let args = CommandLine.arguments
if args.count >= 5, args[1] == "--mcp-bridge" {
    let port = UInt16(args[2]) ?? 0
    let workspaceID = args[3]
    let token = args[4]
    let worktree = args.count >= 6 ? args[5] : ""
    MCPBridge.run(port: port, workspaceID: workspaceID, token: token, worktree: worktree)
}

PluricodeApp.main()
