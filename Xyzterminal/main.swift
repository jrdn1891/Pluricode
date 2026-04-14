import SwiftUI

if CommandLine.arguments.contains("--mcp-bridge") {
    MCPBridge.run()
    exit(0)
}

XyzterminalApp.main()
