import Foundation

struct Worktree: Identifiable, Hashable {
    let branch: String
    let path: String
    let head: String
    let isPrimary: Bool

    var id: String { path }

    var displayName: String { branch }
}
