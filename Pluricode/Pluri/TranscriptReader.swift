import Foundation

enum TranscriptReader {
    static func lastAssistantText(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        var collected: [String] = []
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            guard let entry = try? decoder.decode(Entry.self, from: Data(line)),
                  entry.isSidechain != true else { continue }
            switch entry.type {
            case "assistant":
                collected.insert(contentsOf: entry.message?.textBlocks ?? [], at: 0)
            case "user" where entry.message?.isHumanPrompt == true:
                return joined(collected)
            default:
                break
            }
        }
        return joined(collected)
    }

    private static func joined(_ parts: [String]) -> String? {
        let text = parts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private struct Entry: Decodable {
        let type: String
        let isSidechain: Bool?
        let message: Message?
    }

    private struct Message: Decodable {
        let content: Content

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            content = (try? container.decode(Content.self, forKey: .content)) ?? .blocks([])
        }

        enum CodingKeys: String, CodingKey { case content }

        var textBlocks: [String] {
            guard case .blocks(let blocks) = content else { return [] }
            return blocks
                .compactMap { $0.type == "text" ? $0.text : nil }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        var isHumanPrompt: Bool {
            switch content {
            case .text: return true
            case .blocks(let blocks): return blocks.contains { $0.type == "text" || $0.type == "image" }
            }
        }
    }

    private enum Content: Decodable {
        case text(String)
        case blocks([Block])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .text(string)
            } else {
                self = .blocks((try? container.decode([Block].self)) ?? [])
            }
        }
    }

    private struct Block: Decodable {
        let type: String
        let text: String?
    }
}
