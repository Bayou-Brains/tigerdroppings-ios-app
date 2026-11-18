import Foundation
import Observation

/// Per-thread read position, stored locally in UserDefaults as JSON.
struct ReadPosition: Codable, Equatable {
    var lastPostId: String      // furthest post viewed
    var lastPage: Int
    var replyCount: Int         // thread's reply count as of the last visit
    var updated: Date = Date()
}

@Observable
final class ReadStore {
    static let shared = ReadStore()
    private static let key = "readPositions"
    private(set) var positions: [String: ReadPosition] = [:]

    private init() {
        if let s = UserDefaults.standard.string(forKey: Self.key), let d = s.data(using: .utf8),
           let v = try? JSONDecoder().decode([String: ReadPosition].self, from: d) { positions = v }
    }

    private func persist() {
        if positions.count > 500 {
            let keep = positions.sorted { $0.value.updated > $1.value.updated }.prefix(500)
            positions = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if let d = try? JSONEncoder().encode(positions), let s = String(data: d, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: Self.key)
        }
    }

    func get(_ threadId: String) -> ReadPosition? { positions[threadId] }

    /// Record that a post was seen; the position only moves forward.
    func markSeen(threadId: String, post: Post, replyCount: Int) {
        var p = positions[threadId] ?? ReadPosition(lastPostId: post.id, lastPage: post.page, replyCount: replyCount)
        var changed = positions[threadId] == nil
        if (Int(post.id) ?? 0) > (Int(p.lastPostId) ?? 0) { p.lastPostId = post.id; p.lastPage = post.page; changed = true }
        if replyCount > p.replyCount { p.replyCount = replyCount; changed = true }
        guard changed else { return }
        p.updated = Date()
        positions[threadId] = p
        persist()
    }

    func newReplies(_ t: ThreadSummary) -> Int? {
        guard let p = positions[t.id] else { return nil }
        return max(0, t.replies - p.replyCount)
    }

    func reset(_ threadId: String) { positions[threadId] = nil; persist() }
}
