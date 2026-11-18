import SwiftUI

/// Caches first-post vote counts for thread rows (thread lists don't include votes).
actor VoteCache {
    static let shared = VoteCache()
    private var cache: [String: (Int, Int)] = [:]
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func cached(_ id: String) -> (Int, Int)? { cache[id] }

    func votes(for t: ThreadSummary) async -> (Int, Int)? {
        if let c = cache[t.id] { return c }
        while inFlight >= 6 { await withCheckedContinuation { waiters.append($0) } }
        if let c = cache[t.id] { return c }
        inFlight += 1
        defer {
            inFlight -= 1
            if !waiters.isEmpty { waiters.removeFirst().resume() }
        }
        guard let page = try? await TD.loadThread(t.path, page: 1), let op = page.posts.first else { return nil }
        cache[t.id] = (op.up, op.down)
        return (op.up, op.down)
    }
}

@Observable
final class BoardModel {
    let board: Board
    var threads: [ThreadSummary] = []
    var page = 0
    var hasNext = true
    var loading = false
    var error: String?

    init(board: Board) { self.board = board }

    @MainActor func refresh() async {
        page = 0; hasNext = true
        await loadNext(reset: true)
    }

    @MainActor func loadNext(reset: Bool = false) async {
        guard !loading, hasNext || reset else { return }
        loading = true; defer { loading = false }
        do {
            let p = try await TD.loadBoard(board, page: page + 1)
            if reset { threads = [] }
            let existing = Set(threads.map(\.id))
            threads += p.threads.filter { !existing.contains($0.id) }
            page = p.page
            hasNext = p.hasNext && !p.threads.isEmpty
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ThreadListView: View {
    let board: Board
    @State private var model: BoardModel

    init(board: Board) {
        self.board = board
        _model = State(initialValue: BoardModel(board: board))
    }

    var body: some View {
        List {
            ForEach(model.threads) { t in
                ThreadRow(thread: t)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.visible)
                    .listRowSeparatorTint(VoteHeat.separator)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    .onAppear {
                        if t.id == model.threads.last?.id { Task { await model.loadNext() } }
                    }
            }
            if model.loading || model.hasNext {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
                    .onAppear { Task { await model.loadNext() } }
            }
            if let e = model.error {
                Button("Couldn't load (\(e)). Tap to retry") { Task { await model.loadNext() } }
                    .font(.footnote)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .listRowSeparatorTint(VoteHeat.separator)
        .environment(\.defaultMinListRowHeight, 0)
        .navigationTitle(board.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ThreadSummary.self) { ThreadView(thread: $0) }
        .refreshable { await model.refresh() }
        .task { if model.threads.isEmpty { await model.loadNext() } }
    }
}

struct ThreadRow: View {
    let thread: ThreadSummary
    @AppStorage("tintThreadList") private var tint = true
    @State private var votes: (Int, Int)?
    private var reads: ReadStore { ReadStore.shared }
    private var newReplies: Int? { reads.newReplies(thread) }
    @ScaledMetric private var gap: CGFloat = 6
    @ScaledMetric private var lineGap: CGFloat = 5

    var body: some View {
        ZStack {
            content.voteEdges(up: votes?.0 ?? 0, down: votes?.1 ?? 0)
            NavigationLink(value: thread) { EmptyView() }.opacity(0)
        }
        .listRowBackground(Color.black)
            .task(id: tint) {
                guard tint else { votes = nil; return }
                votes = await VoteCache.shared.votes(for: thread)
            }
    }

    private var content: some View {
        HStack(spacing: gap) {
            VStack(alignment: .leading, spacing: lineGap) {
                Text(thread.title)
                    .font(.callout.weight(thread.sticky ? .semibold : .regular))
                    .lineSpacing(2)
                    .foregroundStyle(newReplies == 0 ? Color(white: 0.55) : .white)
                    .lineLimit(2)
                HStack(spacing: gap) {
                    if thread.sticky { Image(systemName: "pin.fill").foregroundStyle(Color.lsuGold) }
                    if let b = thread.boardName { Text(b).foregroundStyle(Color.lsuGold).fontWeight(.semibold) }
                    Text(thread.author)
                    Label("\(thread.replies)", systemImage: "bubble.left").labelStyle(.titleAndIcon)
                    if thread.pages > 1 { Text("\(thread.pages)p") }
                    if let v = votes { Text("▲\(v.0) ▼\(v.1)").monospacedDigit() }
                    Spacer(minLength: 0)
                    if let n = newReplies, n > 0 {
                        Text("+\(n)").font(.caption.weight(.heavy)).foregroundStyle(.black)
                            .scaledPadding(h: 6, v: 1)
                            .background(Color.lsuGold, in: Capsule())
                    }
                    Text(thread.lastPostTime)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .scaledPadding(v: 11)
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .scaledPadding(h: 12)
    }
}
