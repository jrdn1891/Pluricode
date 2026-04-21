import Foundation

struct Worktree: Identifiable, Hashable {
    let branch: String
    let path: String
    let head: String

    var id: String { branch }

    var displayName: String {
        branch.hasPrefix("xyz-") ? String(branch.dropFirst("xyz-".count)) : branch
    }
}
