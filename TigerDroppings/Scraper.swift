import Foundation

// MARK: - Models

struct Board: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String        // e.g. /rant/lsu-sports/
    var subtitle: String = ""
    var pageable: Bool = true
}

struct ThreadSummary: Identifiable, Hashable {
    let id: String          // numeric thread id
    let title: String
    let path: String        // /rant/lsu-sports/slug/123/
    let author: String
    let replies: Int
    let lastPostTime: String
    let lastPostBy: String
    let pages: Int
    let sticky: Bool
    let boardName: String?
}

/// Live or pregame score shown at the top of the Score Board and the game thread.
struct GameHeader: Hashable {
    var title: String
    var away: String
    var home: String
    var awayRank: String? = nil
    var homeRank: String? = nil
    var awayScore: String? = nil
    var homeScore: String? = nil
    var awayRecord: String? = nil
    var homeRecord: String? = nil
    var status: String? = nil          // kickoff time, quarter, or "Final"
    var date: String? = nil
    var tv: String? = nil
    var venue: String? = nil
    var notes: String? = nil           // spread / over-under
    var threadPath: String? = nil
    var threadId: String? = nil

    var hasScores: Bool {
        Self.isScoreValue(awayScore) || Self.isScoreValue(homeScore)
    }

    var detail: String {
        [status, tv, notes, venue].compactMap { s in
            let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }.joined(separator: " · ")
    }

    static func isScoreValue(_ s: String?) -> Bool {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return false }
        return s.allSatisfy(\.isNumber)
    }

    static func labeled(rank: String?, name: String, score: String? = nil) -> String {
        var s = name
        if let r = rank?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty { s = "#\(r) \(name)" }
        if isScoreValue(score) { s += " \(score!)" }
        return s
    }

    static func makeTitle(away: String, awayRank: String?, awayScore: String?,
                          home: String, homeRank: String?, homeScore: String?,
                          status: String?) -> String {
        let a = labeled(rank: awayRank, name: away, score: awayScore)
        let b = labeled(rank: homeRank, name: home, score: homeScore)
        var title = (isScoreValue(awayScore) || isScoreValue(homeScore)) ? "\(a) – \(b)" : "\(a) vs \(b)"
        if let st = status?.trimmingCharacters(in: .whitespacesAndNewlines), !st.isEmpty {
            // Don't repeat a pregame kickoff time already used as a "score" slot.
            if isScoreValue(awayScore) || isScoreValue(homeScore) || !title.contains(st) {
                title += " (\(st))"
            }
        }
        return title
    }
}

enum PostBlock: Hashable {
    case text(AttributedString)
    case quote(AttributedString)
    case image(URL)
    case link(URL, String)
}

struct Post: Identifiable, Hashable {
    let id: String
    let author: String
    let time: String
    let replyTo: String?
    let avatar: URL?
    let blocks: [PostBlock]
    var up: Int
    var down: Int
    var page: Int
    var upToken: String? = nil     // pID for the site's processvote() call (only present when signed in)
    var downToken: String? = nil
    var myVote: Int = 0            // 1 = you upvoted, -1 = you downvoted
}

struct ThreadPage {
    let title: String
    let posts: [Post]
    let page: Int
    let totalPages: Int
    var gameHeader: GameHeader? = nil
}

struct BoardPage {
    let threads: [ThreadSummary]
    let page: Int
    let hasNext: Bool
    var locked: Bool = false
    var boardTitle: String? = nil
    var gameHeader: GameHeader? = nil
}

// MARK: - Boards

enum Boards {
    static let tigerRant = Board(name: "Tiger Rant", path: "/rant/lsu-sports/", subtitle: "Discuss LSU Sports with fellow Tiger fans")
    static let scoreBoard = Board(name: "LSU Score Board", path: "/rant/lsu-score-board/", subtitle: "Game-day threads and the live score")
    static let trending = Board(name: "Trending", path: "/rant/a/trending/", subtitle: "Hot threads across all boards", pageable: false)
    static let active = Board(name: "Active", path: "/rant/a/active/", subtitle: "Most recently active threads", pageable: false)
    static let new = Board(name: "New", path: "/rant/a/new/", subtitle: "Newest threads", pageable: false)

    static let sections: [(String, [Board])] = [
        ("LSU", [
            tigerRant,
            scoreBoard,
            Board(name: "LSU Recruiting", path: "/rant/lsu-recruiting/", subtitle: "Discuss the future of LSU Football"),
            Board(name: "Ticket Exchange", path: "/rant/lsu-tickets/", subtitle: "Buy, sell and trade"),
        ]),
        ("Across TD", [trending, active, new]),
        ("Sports", [
            Board(name: "Saints Talk", path: "/rant/new-orleans-saints/"),
            Board(name: "Pelicans Talk", path: "/rant/new-orleans-pelicans/"),
            Board(name: "More Sports", path: "/rant/more-sports/", subtitle: "NFL, NBA, MLB, NCAA and more"),
            Board(name: "Coaching Changes", path: "/rant/coaching-changes/"),
            Board(name: "Fantasy Sports", path: "/rant/fantasy-sports/"),
            Board(name: "Golf", path: "/rant/golf/"),
            Board(name: "Soccer", path: "/rant/soccer/"),
        ]),
        ("Lounge", [
            Board(name: "O-T Lounge", path: "/rant/o-t-lounge/", subtitle: "Abandon all hope, ye who enter here"),
            Board(name: "Political Talk", path: "/rant/politics/"),
            Board(name: "Money Talk", path: "/rant/money/"),
            Board(name: "Tech", path: "/rant/tech/"),
            Board(name: "Outdoor", path: "/rant/outdoor/", subtitle: "Hunting, fishing and more"),
            Board(name: "Food and Drink", path: "/rant/food-and-drink/"),
            Board(name: "Home & Garden", path: "/rant/home-and-garden/"),
            Board(name: "Health/Fitness", path: "/rant/health-fitness/"),
            Board(name: "Movie/TV", path: "/rant/movie-tv/"),
            Board(name: "Music", path: "/rant/music/"),
            Board(name: "Books", path: "/rant/books/"),
            Board(name: "Gaming", path: "/rant/gaming/"),
            Board(name: "Travel", path: "/rant/travel/"),
            Board(name: "Fark", path: "/rant/fark/"),
            Board(name: "Help", path: "/rant/help/"),
        ]),
    ]
}

// MARK: - Networking

enum TD {
    static let base = URL(string: "https://www.tigerdroppings.com")!
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 20
        c.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: c)
    }()

    static func url(_ path: String) -> URL {
        if path.hasPrefix("http") { return URL(string: path) ?? base }
        return URL(string: path, relativeTo: base)?.absoluteURL ?? base
    }

    static func fetch(_ path: String) async throws -> String {
        var req = URLRequest(url: url(path))
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
            throw URLError(.badServerResponse)
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func boardPagePath(_ board: Board, page: Int) -> String {
        page <= 1 ? board.path : board.path + "page-\(page)/"
    }

    static func threadPagePath(_ threadPath: String, page: Int) -> String {
        var p = threadPath
        if let r = p.range(of: #"page-\d+/.*$"#, options: .regularExpression) { p.removeSubrange(r) }
        if let r = p.range(of: "#") { p = String(p[..<r.lowerBound]) }
        if !p.hasSuffix("/") { p += "/" }
        return page <= 1 ? p : p + "page-\(page)/"
    }

    static func loadBoard(_ board: Board, page: Int) async throws -> BoardPage {
        let html = try await fetch(boardPagePath(board, page: page))
        return Parser.boardPage(html, board: board, page: page)
    }

    static func loadThread(_ path: String, page: Int) async throws -> ThreadPage {
        let html = try await fetch(threadPagePath(path, page: page))
        return Parser.threadPage(html, page: page)
    }
}

// MARK: - Parsing

enum Parser {
    static func re(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: [.dotMatchesLineSeparators, .caseInsensitive])
    }

    static func first(_ p: String, in s: String, group: Int = 1) -> String? {
        let ns = s as NSString
        guard let m = re(p).firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.range(at: group).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: group))
    }

    static func all(_ p: String, in s: String) -> [[String?]] {
        let ns = s as NSString
        return re(p).matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i))
            }
        }
    }

    static func chunks(_ s: String, splitOn marker: String) -> [String] {
        let parts = s.components(separatedBy: marker)
        return parts.count > 1 ? Array(parts.dropFirst()) : []
    }

    // Board / thread list
    static func boardPage(_ html: String, board: Board, page: Int) -> BoardPage {
        var threads: [ThreadSummary] = []
        var seen = Set<String>()
        var header: GameHeader? = nil
        for c in chunks(html, splitOn: "<div class=\"index indRow") {
            // Game threads use <h2 class="scoreboard-subject">, so allow attributes on <h2>.
            guard let href = first(#"<h2[^>]*>\s*<a\s+href="([^"]+)""#, in: c),
                  let titleHTML = first(#"<h2[^>]*>\s*<a\s+href="[^"]+"\s*>(.*?)</a>"#, in: c),
                  let id = first(#"/(\d+)/$"#, in: href), !seen.contains(id) else { continue }
            seen.insert(id)
            if header == nil, let gh = gameHeaderFromBoardRow(c, path: href, id: id) { header = gh }
            let pages = all(#"/page-(\d+)/"#, in: first(#"<span Class= "pg2[^"]*">(.*?)</span>"#, in: c) ?? "")
                .compactMap { $0[1].flatMap(Int.init) }.max() ?? 1
            threads.append(ThreadSummary(
                id: id,
                title: threadTitle(titleHTML: titleHTML, row: c),
                path: href,
                author: decode(first(#"class=author[^>]*>([^<]+)</a>"#, in: c) ?? ""),
                replies: Int(first(#"class="cicon"\s*/?>\s*(\d+)"#, in: c) ?? "") ?? 0,
                lastPostTime: decode(first(#"class="lp"[^>]*>([^<]+)<span"#, in: c) ?? "").trimmingCharacters(in: .whitespaces),
                lastPostBy: decode(first(#"<span class="lp">([^<]*)</span>"#, in: c) ?? ""),
                pages: pages,
                sticky: c.contains("alt=\"sticky post\"") || c.contains("srcstick"),
                boardName: first(#"<a class="bname"[^>]*>([^<]+)</a>"#, in: c).map(decode)))
        }
        // Pagination: if the site served the Score Board under the Rant URL (game-day
        // redirect), look for the score-board page-2 link instead of the requested path.
        var pageablePath = board.path
        if isScoreBoardPage(html) { pageablePath = Boards.scoreBoard.path }
        let hasNext = board.pageable && html.contains(pageablePath + "page-\(page + 1)/")
        return BoardPage(threads: threads, page: page, hasNext: hasNext,
                         locked: isBoardLocked(html),
                         boardTitle: boardTitle(html),
                         gameHeader: header)
    }

    static func isBoardLocked(_ html: String) -> Bool {
        html.contains("err-lock") || html.localizedCaseInsensitiveContains("This forum is currently locked")
    }

    static func isScoreBoardPage(_ html: String) -> Bool {
        if let name = boardTitle(html), name.localizedCaseInsensitiveContains("Score Board") { return true }
        if let canon = first(#"rel="canonical" href="([^"]+)""#, in: html),
           canon.localizedCaseInsensitiveContains("/rant/lsu-score-board") { return true }
        return false
    }

    static func boardTitle(_ html: String) -> String? {
        let raw = first(#"class="MessName"[^>]*>([^<]+)"#, in: html)
            ?? first(#"<h1 class="PgBoardNameT"[^>]*>\s*<a[^>]*>([^<]+)"#, in: html)
        guard let raw else { return nil }
        let name = decode(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Pinned game threads put a live scoreboard inside the title link instead of plain text.
    static func threadTitle(titleHTML: String, row: String) -> String {
        if let h = gameHeaderFromBoardRow(row) { return h.title }
        return decode(stripTags(titleHTML)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func scoreboardTitle(_ row: String) -> String? {
        gameHeaderFromBoardRow(row)?.title
    }

    static func gameHeaderFromBoardRow(_ row: String, path: String? = nil, id: String? = nil) -> GameHeader? {
        guard row.contains("scoreboard-subject") || row.contains("scoreteam") else { return nil }
        let teams = all(#"<span class="scoreteam">(?:<span class="score-rank"[^>]*>\s*([^<]*?)\s*</span>)?\s*([^<]*?)\s*</span>"#, in: row)
        var names: [(rank: String?, name: String)] = []
        for m in teams {
            let name = decode(m[2] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let rank = decode(m[1] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            names.append((rank.isEmpty ? nil : rank, name))
        }
        guard names.count >= 2 else { return nil }
        let slots = all(#"class="scorescr[^"]*"[^>]*>\s*([^<]*)"#, in: row)
            .compactMap { $0[1].map { decode($0).trimmingCharacters(in: .whitespacesAndNewlines) } }
            .filter { !$0.isEmpty }
        var awayScore: String? = nil
        var homeScore: String? = nil
        var tv: String? = first(#"class="scoretv(?:desktop)?"[^>]*>([^<]+)"#, in: row).map {
            decode($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if slots.count >= 2, GameHeader.isScoreValue(slots[0]) || GameHeader.isScoreValue(slots[1]) {
            if GameHeader.isScoreValue(slots[0]) { awayScore = slots[0] }
            if GameHeader.isScoreValue(slots[1]) { homeScore = slots[1] }
            if let extra = slots.first(where: { !GameHeader.isScoreValue($0) }), tv == nil || tv?.isEmpty == true {
                tv = extra
            }
        } else if slots.count >= 2, tv == nil || tv?.isEmpty == true {
            tv = slots[1]
        }
        if tv?.isEmpty == true { tv = nil }
        let status = first(#"class="scoreqtr"[^>]*>([^<]+)"#, in: row).map {
            decode($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let notes = first(#"class="scorenotes"[^>]*>([^<]+)"#, in: row).map {
            decode($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let title = GameHeader.makeTitle(away: names[0].name, awayRank: names[0].rank, awayScore: awayScore,
                                         home: names[1].name, homeRank: names[1].rank, homeScore: homeScore,
                                         status: status)
        return GameHeader(title: title, away: names[0].name, home: names[1].name,
                          awayRank: names[0].rank, homeRank: names[1].rank,
                          awayScore: awayScore, homeScore: homeScore,
                          status: status?.isEmpty == true ? nil : status,
                          tv: tv, notes: notes?.isEmpty == true ? nil : notes,
                          threadPath: path, threadId: id)
    }

    // Thread
    static func threadPage(_ html: String, page: Int) -> ThreadPage {
        let gameHeader = gameHeaderFromGameThread(html)
        var title = decode(stripTags(first(#"<h1 class="SubjectDisplay[^"]*">(.*?)</h1>"#, in: html) ?? ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty, let t = first(#"<title[^>]*>(.*?)</title>"#, in: html) {
            title = decode(stripTags(t)).components(separatedBy: "|").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        if title.isEmpty, let g = gameHeader { title = g.title }
        var total = Int(first(#"Page\s+\d+\s+of\s+(\d+)"#, in: html) ?? "") ?? 0
        if total == 0 {
            total = all(#"class="pg" href="[^"]*/page-(\d+)/""#, in: html).compactMap { $0[1].flatMap(Int.init) }.max() ?? 1
            total = max(total, page)
        }
        var posts: [Post] = []
        for c in chunks(html, splitOn: "<div class=\"maincont1 indRow") {
            guard let m = all(#"<div class="pText" id="ptext_(\d+)"\s*>(.*?)<div class="mtdivide">"#, in: c).first,
                  let id = m[1], var body = m[2] else { continue }
            if let r = body.range(of: "</div>", options: .backwards) { body.removeSubrange(r.lowerBound..<body.endIndex) }
            body = stripGameWidget(body)
            let up = Int(first(#"id="T_Up_p\d+"[^>]*>\s*(\d+)"#, in: c) ?? "") ?? 0
            let down = Int(first(#"id="T_Down_p\d+"[^>]*>\s*(\d+)"#, in: c) ?? "") ?? 0
            let author = first(#"class="RegUser"[^>]*>([^<]+)</a>"#, in: c)
                ?? first(#"<div class="author">.*?<a[^>]*>([^<]+)</a>"#, in: c) ?? "?"
            let time = first(#"<div class="time">.*?Posted on </span>([^<]+)</span>"#, in: c)
                ?? first(#"Posted on ([^<]+)<"#, in: c) ?? ""
            let replyTo = first(#"class="PostInfo"[^>]*>([^<]+)</a>"#, in: c).map(decode)
            let avatar = first(#"<div class="ava"><img[^>]*src="([^"]+)""#, in: c).flatMap { URL(string: $0) }
            var post = Post(id: id, author: decode(author), time: decode(time).trimmingCharacters(in: .whitespaces),
                            replyTo: replyTo, avatar: avatar, blocks: blocks(body), up: up, down: down, page: page)
            let likes = first(#"<div class="likes">(.*?)</div>"#, in: c) ?? c
            for v in voteTokens(likes) { if v.up { post.upToken = v.token } else { post.downToken = v.token } }
            if likes.contains("uArw_af") { post.myVote = 1 } else if likes.contains("dArw_af") { post.myVote = -1 }
            posts.append(post)
        }
        return ThreadPage(title: title, posts: posts, page: page, totalPages: max(total, 1), gameHeader: page == 1 ? gameHeader : nil)
    }

    /// Pull a compact score header out of the game-thread widget (sgt-scoreboard).
    static func gameHeaderFromGameThread(_ html: String) -> GameHeader? {
        guard html.contains("sgt-scoreboard") || html.contains("sgt-team-away") else { return nil }
        func team(_ side: String) -> (rank: String?, name: String, record: String?, score: String?)? {
            let block = first(#"<div class="sgt-team sgt-team-\#(side)"[^>]*>([\s\S]*?)(?:<div class="sgt-team sgt-team-|<div class="sgt-game-center"|<section )"#, in: html)
                ?? first(#"<div class="sgt-team sgt-team-\#(side)"[^>]*>([\s\S]*?)</div>\s*</div>"#, in: html)
            guard let block else { return nil }
            let rank = first(#"class="sgt-team-rank"[^>]*>\s*([^<]+)"#, in: block).map {
                decode($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let name = first(#"<strong>(?:<span class="sgt-team-rank"[^>]*>[^<]*</span>)?\s*([^<]+)</strong>"#, in: block).map {
                decode($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let record = first(#"class="sgt-record"[^>]*>([^<]+)"#, in: block).map {
                decode($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let score = first(#"class="sgt-(?:team-)?score(?:-value)?[^"]*"[^>]*>([^<]+)"#, in: block)
                ?? first(#"class="sgt-points"[^>]*>([^<]+)"#, in: block)
            let scoreTrim = score.map { decode($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let name, !name.isEmpty else { return nil }
            return (rank?.isEmpty == true ? nil : rank, name, record?.isEmpty == true ? nil : record,
                    (scoreTrim?.isEmpty == true ? nil : scoreTrim))
        }
        guard let away = team("away"), let home = team("home") else { return nil }
        let status = first(#"class="sgt-game-status"[^>]*>([^<]+)"#, in: html).map {
            decode($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let date = first(#"class="sgt-game-date"[^>]*>([^<]+)"#, in: html).map {
            decode($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let tv = first(#"sgt-info-tv"[^>]*>[\s\S]*?<strong>([^<]+)"#, in: html).map {
            decode($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var venue = first(#"sgt-info-venue"[^>]*>[\s\S]*?<strong>([^<]+)"#, in: html).map {
            decode($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let city = first(#"sgt-info-venue"[^>]*>[\s\S]*?<strong>[^<]+</strong>\s*<span>([^<]+)"#, in: html) {
            let c = decode(city).trimmingCharacters(in: .whitespacesAndNewlines)
            if !c.isEmpty { venue = [venue, c].compactMap { $0 }.joined(separator: ", ") }
        }
        let notes = first(#"sgt-info-betting"[^>]*>[\s\S]*?<strong>([^<]+)"#, in: html).map {
            decode($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let title = GameHeader.makeTitle(away: away.name, awayRank: away.rank, awayScore: away.score,
                                         home: home.name, homeRank: home.rank, homeScore: home.score,
                                         status: status)
        return GameHeader(title: title, away: away.name, home: home.name,
                          awayRank: away.rank, homeRank: home.rank,
                          awayScore: away.score, homeScore: home.score,
                          awayRecord: away.record, homeRecord: home.record,
                          status: status?.isEmpty == true ? nil : status,
                          date: date?.isEmpty == true ? nil : date,
                          tv: tv?.isEmpty == true ? nil : tv,
                          venue: venue?.isEmpty == true ? nil : venue,
                          notes: notes?.isEmpty == true ? nil : notes)
    }

    /// The first post of a game thread is a big scoreboard widget; drop it so the
    /// condensed view isn't a wall of nav links and season stats.
    static func stripGameWidget(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: #"<header class="sd-scoreboard-header[\s\S]*?</header>"#, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<section class="sgt-op"[\s\S]*</section>"#, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<section class="sgt-scoreboard"[\s\S]*</section>"#, with: "", options: [.regularExpression, .caseInsensitive])
        return s
    }

    /// Signed-in pages render vote links that call processvote(pID, 'u'|'d') (mb_display_v35.js).
    /// The pID is either a quoted literal or `this.id`, in which case it's the anchor's id attribute.
    static func voteTokens(_ html: String) -> [(token: String, up: Bool)] {
        var out: [(String, Bool)] = []
        for m in all(#"<[a-z]+\b[^>]*processvote[^>]*>"#, in: html) {
            let tag = m[0] ?? ""
            guard let call = all(#"processvote\(\s*([^,]+?)\s*,\s*['"]([ud])['"]"#, in: tag).first,
                  let arg = call[1], let kind = call[2] else { continue }
            var token: String?
            if let lit = first(#"^['"]([^'"]+)['"]$"#, in: arg) { token = lit }
            else { token = first(#"\bid\s*=\s*["']([^"']+)["']"#, in: tag) }
            if let t = token { out.append((t, kind.lowercased() == "u")) }
        }
        return out
    }

    // Post body -> blocks
    static func blocks(_ raw: String) -> [PostBlock] {
        var html = raw.replacingOccurrences(of: #"<div class="editText">.*?</div>"#, with: "", options: [.regularExpression, .caseInsensitive])
        html = html.replacingOccurrences(of: #"<script.*?</script>"#, with: "", options: [.regularExpression, .caseInsensitive])
        let token = #"<blockquote[^>]*>(.*?)</blockquote>|<img[^>]*?src="([^"]+)"[^>]*>|<iframe[^>]*?src="([^"]+)"[^>]*>(?:\s*</iframe>)?"#
        let ns = html as NSString
        var out: [PostBlock] = []
        var cursor = 0
        func addText(_ s: String) {
            let a = inline(s)
            if !a.characters.isEmpty { out.append(.text(a)) }
        }
        for m in re(token).matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            addText(ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)))
            cursor = m.range.location + m.range.length
            if m.range(at: 1).location != NSNotFound {
                var q = ns.substring(with: m.range(at: 1))
                q = q.replacingOccurrences(of: #"<span class="PostItalic">\s*quote:\s*</span>"#, with: "", options: [.regularExpression, .caseInsensitive])
                let a = inline(q)
                if !a.characters.isEmpty { out.append(.quote(a)) }
            } else if m.range(at: 2).location != NSNotFound {
                let src = decode(ns.substring(with: m.range(at: 2)))
                if let u = URL(string: src.hasPrefix("//") ? "https:" + src : src), u.scheme?.hasPrefix("http") == true {
                    out.append(.image(u))
                }
            } else if m.range(at: 3).location != NSNotFound {
                let src = decode(ns.substring(with: m.range(at: 3)))
                if let u = URL(string: src.hasPrefix("//") ? "https:" + src : src) {
                    out.append(.link(u, u.host ?? "Embedded media"))
                }
            }
        }
        addText(ns.substring(from: cursor))
        return out
    }

    static func inline(_ s: String) -> AttributedString {
        var html = s.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        html = html.replacingOccurrences(of: #"<hr[^>]*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        let ns = html as NSString
        var result = AttributedString()
        var cursor = 0
        for m in re(#"<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#).matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            result += AttributedString(decode(stripTags(ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)))))
            cursor = m.range.location + m.range.length
            let href = decode(ns.substring(with: m.range(at: 1)))
            var label = decode(stripTags(ns.substring(with: m.range(at: 2)))).trimmingCharacters(in: .whitespacesAndNewlines)
            if label.isEmpty { label = href }
            var a = AttributedString(label)
            if let u = URL(string: href, relativeTo: TD.base)?.absoluteURL { a.link = u }
            result += a
        }
        result += AttributedString(decode(stripTags(ns.substring(from: cursor))))
        // normalize whitespace
        var str = String(result.characters)
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return AttributedString() }
        // Trim leading/trailing whitespace while keeping attributes
        while let f = result.characters.first, f.isWhitespace { result.removeSubrange(result.startIndex..<result.index(afterCharacter: result.startIndex)) }
        while let l = result.characters.last, l.isWhitespace { result.removeSubrange(result.index(beforeCharacter: result.endIndex)..<result.endIndex) }
        // collapse runs of 3+ newlines
        str = String(result.characters)
        while let r = result.range(of: "\n \n \n") { result.replaceSubrange(r, with: AttributedString("\n\n")) }
        while let r = result.range(of: "\n\n\n") { result.replaceSubrange(r, with: AttributedString("\n\n")) }
        while let r = result.range(of: "\n \n") { result.replaceSubrange(r, with: AttributedString("\n\n")) }
        return result
    }

    static func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }

    static let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
                                          "rsquo": "\u{2019}", "lsquo": "\u{2018}", "rdquo": "\u{201D}", "ldquo": "\u{201C}",
                                          "hellip": "\u{2026}", "mdash": "\u{2014}", "ndash": "\u{2013}", "raquo": "\u{00BB}", "laquo": "\u{00AB}",
                                          "copy": "\u{00A9}", "reg": "\u{00AE}", "trade": "\u{2122}", "deg": "\u{00B0}"]

    static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let ns = s as NSString
        var out = ""
        var cursor = 0
        for m in re(#"&(#x[0-9a-f]+|#\d+|[a-z]+);"#).matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            cursor = m.range.location + m.range.length
            let ent = ns.substring(with: m.range(at: 1))
            var rep: String? = nil
            if ent.hasPrefix("#x") || ent.hasPrefix("#X") {
                if let v = UInt32(ent.dropFirst(2), radix: 16), let sc = Unicode.Scalar(v) { rep = String(Character(sc)) }
            } else if ent.hasPrefix("#") {
                if let v = UInt32(ent.dropFirst()), let sc = Unicode.Scalar(v) { rep = String(Character(sc)) }
            } else { rep = named[ent.lowercased()] }
            out += rep ?? ns.substring(with: m.range)
        }
        out += ns.substring(from: cursor)
        return out
    }
}
