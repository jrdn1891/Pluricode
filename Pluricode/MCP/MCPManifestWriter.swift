import Foundation

enum MCPManifestWriter {
    static func write(endpoint: MCPEndpoint, role: MCPRole, worktreePath: String, worktreeBranch: String) {
        let manifest: [String: Any] = [
            "mcpServers": [
                "pluricode": [
                    "type": "stdio",
                    "command": endpoint.executablePath,
                    "args": [
                        "--mcp-bridge",
                        String(endpoint.port),
                        endpoint.workspaceID.uuidString,
                        endpoint.token,
                        worktreeBranch
                    ],
                    "env": [
                        "PLURICODE_MCP_ROLE": role.rawValue
                    ]
                ]
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        let url = URL(fileURLWithPath: worktreePath).appendingPathComponent(".mcp.json")
        try? data.write(to: url, options: .atomic)
    }
}
