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
    private(set) var board: Board
    let followsGameDay: Bool
    var threads: [ThreadSummary] = []
    var page = 0
    var hasNext = true
    var loading = false
    var error: String?
    var locked = false
    var gameHeader: GameHeader?
    /// Set when the first tab auto-switches from a locked Rant to the Score Board.
    var lockedNotice: String?
    var showingScoreBoard = false

    init(board: Board, followsGameDay: Bool = false) {
        self.board = board
        self.followsGameDay = followsGameDay
    }

    @MainActor func refresh() async {
        page = 0; hasNext = true
        await loadNext(reset: true)
    }

    @MainActor func loadNext(reset: Bool = false) async {
        guard !loading, hasNext || reset else { return }
        loading = true; defer { loading = false }
        do {
            if followsGameDay && (reset || page == 0) {
                if await followGameDayIfNeeded() { return }
            }
            let p = try await TD.loadBoard(board, page: page + 1)
            apply(p, board: board, notice: lockedNotice, reset: reset)
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor private func apply(_ p: BoardPage, board: Board, notice: String?, reset: Bool) {
        if reset || self.page == 0 { threads = [] }
        let existing = Set(threads.map(\.id))
        threads += p.threads.filter { !existing.contains($0.id) }
        page = p.page
        hasNext = p.hasNext && !p.threads.isEmpty
        locked = p.locked
        gameHeader = p.gameHeader
        lockedNotice = notice
        showingScoreBoard = board.path == Boards.scoreBoard.path
        self.board = board
        error = nil
    }

    /// On game day, Tiger Rant is locked (or redirected) and discussion moves to the Score Board.
    /// Returns true if this call already filled `threads`.
    @MainActor private func followGameDayIfNeeded() async -> Bool {
        do {
            let rant = try await TD.loadBoard(Boards.tigerRant, page: 1)
            if rant.locked || Parser.isScoreBoardPageLooks(rant) {
                if Parser.isScoreBoardPageLooks(rant), !rant.threads.isEmpty {
                    apply(rant, board: Boards.scoreBoard, notice: rant.locked ? "Tiger Rant is locked for the game" : nil, reset: true)
                    return true
                }
                let sb = try await TD.loadBoard(Boards.scoreBoard, page: 1)
                apply(sb, board: Boards.scoreBoard,
                      notice: rant.locked ? "Tiger Rant is locked for the game" : "Showing the LSU Score Board",
                      reset: true)
                return true
            }
            apply(rant, board: Boards.tigerRant, notice: nil, reset: true)
            return true
        } catch {
            if let sb = try? await TD.loadBoard(Boards.scoreBoard, page: 1), !sb.threads.isEmpty {
                apply(sb, board: Boards.scoreBoard,
                      notice: "Couldn't load Tiger Rant. Showing the Score Board.",
                      reset: true)
                return true
            }
            return false
        }
    }
}

private extension Parser {
    static func isScoreBoardPageLooks(_ page: BoardPage) -> Bool {
        if page.boardTitle?.localizedCaseInsensitiveContains("Score Board") == true { return true }
        if page.gameHeader != nil { return true }
        return page.threads.contains { $0.path.contains("/lsu-score-board/") }
    }
}

struct ThreadListView: View {
    @State private var model: BoardModel

    init(board: Board, followsGameDay: Bool = false) {
        _model = State(initialValue: BoardModel(board: board, followsGameDay: followsGameDay))
    }

    init(model: BoardModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        List {
            if let notice = model.lockedNotice, model.showingScoreBoard {
                Text(notice)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.lsuGold)
                    .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 4, trailing: 14))
                    .listRowBackground(Color.black)
                    .listRowSeparator(.hidden)
            } else if model.locked && !model.showingScoreBoard {
                NavigationLink(value: Boards.scoreBoard) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This board is locked for the game")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Open the LSU Score Board to follow along and post")
                            .font(.caption)
                            .foregroundStyle(Color.lsuGold)
                    }
                    .scaledPadding(v: 6)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                .listRowBackground(Color.lsuPurple.opacity(0.45))
            }
            if let h = model.gameHeader {
                headerRow(h)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.black)
            }
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
        .navigationTitle(model.board.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ThreadSummary.self) { ThreadView(thread: $0) }
        .navigationDestination(for: Board.self) { ThreadListView(board: $0) }
        .refreshable { await model.refresh() }
        .task { if model.threads.isEmpty { await model.loadNext() } }
    }

    @ViewBuilder
    private func headerRow(_ h: GameHeader) -> some View {
        if let path = h.threadPath, let id = h.threadId {
            let t = ThreadSummary(id: id, title: h.title, path: path, author: "",
                                  replies: 0, lastPostTime: "", lastPostBy: "", pages: 1, sticky: true, boardName: nil)
            ZStack {
                GameHeaderCard(header: h)
                NavigationLink(value: t) { EmptyView() }.opacity(0)
            }
        } else {
            GameHeaderCard(header: h)
        }
    }
}

struct GameHeaderCard: View {
    let header: GameHeader
    @ScaledMetric private var pad: CGFloat = 12
    @ScaledMetric private var gap: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            HStack(alignment: .firstTextBaseline) {
                teamLine(rank: header.awayRank, name: header.away, record: header.awayRecord)
                Spacer(minLength: 8)
                if header.hasScores {
                    Text(header.awayScore ?? "–")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                teamLine(rank: header.homeRank, name: header.home, record: header.homeRecord)
                Spacer(minLength: 8)
                if header.hasScores {
                    Text(header.homeScore ?? "–")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
            HStack(spacing: 6) {
                if let s = header.status, !s.isEmpty {
                    Text(s).fontWeight(.semibold)
                } else if !header.hasScores {
                    Text("vs").fontWeight(.semibold)
                }
                if let d = header.date, !d.isEmpty { Text(d) }
                if let tv = header.tv, !tv.isEmpty { Text("· \(tv)") }
                Spacer(minLength: 0)
                if header.threadPath != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)
            .foregroundStyle(Color.lsuGold)
            if let notes = header.notes, !notes.isEmpty {
                Text(notes).font(.caption).foregroundStyle(.secondary)
            }
            if let venue = header.venue, !venue.isEmpty {
                Text(venue).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .scaledPadding(h: pad, v: 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.lsuPurple.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.lsuGold.opacity(0.35), lineWidth: 1)
        )
        .scaledPadding(h: 12, v: 8)
    }

    private func teamLine(rank: String?, name: String, record: String?) -> some View {
        HStack(spacing: 6) {
            if let r = rank, !r.isEmpty {
                Text("#\(r)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.lsuGold)
            }
            Text(name).font(.headline).foregroundStyle(.white)
            if let rec = record, !rec.isEmpty {
                Text(rec).font(.caption).foregroundStyle(.secondary)
            }
        }
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
