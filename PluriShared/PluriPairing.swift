import Foundation

struct PluriPairing: Hashable {
    var host: String
    var port: Int
    var token: String

    var url: String {
        var components = URLComponents()
        components.scheme = "pluri"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "port", value: String(port)),
            URLQueryItem(name: "token", value: token)
        ]
        return components.string ?? ""
    }

    init(host: String, port: Int, token: String) {
        self.host = host
        self.port = port
        self.token = token
    }

    init?(url string: String) {
        guard let components = URLComponents(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "pluri",
              let items = components.queryItems,
              let host = items.first(where: { $0.name == "host" })?.value, !host.isEmpty,
              let portString = items.first(where: { $0.name == "port" })?.value, let port = Int(portString),
              let token = items.first(where: { $0.name == "token" })?.value, !token.isEmpty
        else { return nil }
        self.host = host
        self.port = port
        self.token = token
    }
}
