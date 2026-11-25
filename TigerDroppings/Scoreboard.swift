import Foundation

// MARK: - Scoreboard models (TigerDroppings /scores pages)

enum ScoreGameState: String, Hashable {
    case live, final, scheduled, other

    var sectionTitle: String {
        switch self {
        case .live: return "Live"
        case .final: return "Final"
        case .scheduled: return "Scheduled"
        case .other: return "Games"
        }
    }
}

struct ScoreTeam: Hashable {
    var name: String
    var rank: String? = nil
    var record: String? = nil
    var score: String? = nil
    var winner: Bool = false

    var labeledName: String { GameHeader.labeled(rank: rank, name: name) }
}

struct ScoreLink: Identifiable, Hashable {
    var id: String { path + name }
    var name: String
    var path: String
    var isActive: Bool = false
}

struct ScoreGame: Identifiable, Hashable {
    var path: String
    var label: String
    var state: ScoreGameState
    var away: ScoreTeam
    var home: ScoreTeam
    var status: String = ""
    var network: String? = nil
    var line: String? = nil
    var venue: String? = nil
    var situation: String? = nil
    var spread: String? = nil
    var overUnder: String? = nil
    var moneyline: String? = nil
    var isLSU: Bool = false
    var fromCompanionBoard: Bool = false
    var threadPath: String? = nil
    var threadId: String? = nil

    var id: String { path }

    var hasScores: Bool {
        GameHeader.isScoreValue(away.score) || GameHeader.isScoreValue(home.score)
    }

    var margin: Int? {
        guard let a = Int(away.score ?? ""), let h = Int(home.score ?? "") else { return nil }
        return abs(a - h)
    }

    var sport: String? {
        Parser.first(#"^/(ncaaf|ncaab)/"#, in: path)
    }

    var asHeader: GameHeader {
        let title = GameHeader.makeTitle(away: away.name, awayRank: away.rank, awayScore: away.score,
                                         home: home.name, homeRank: home.rank, homeScore: home.score,
                                         status: status.isEmpty ? nil : status)
        return GameHeader(title: title, away: away.name, home: home.name,
                          awayRank: away.rank, homeRank: home.rank,
                          awayScore: away.score, homeScore: home.score,
                          awayRecord: away.record, homeRecord: home.record,
                          status: status.isEmpty ? nil : status,
                          tv: network, venue: venue, notes: line,
                          threadPath: threadPath, threadId: threadId)
    }

    var threadSummary: ThreadSummary? {
        guard let threadPath, let threadId else { return nil }
        return ThreadSummary(id: threadId, title: asHeader.title, path: threadPath, author: "",
                             replies: 0, lastPostTime: "", lastPostBy: "", pages: 1, sticky: true, boardName: nil)
    }
}

struct ScoreboardPage {
    var path: String
    var title: String
    var groupName: String
    var periodLabel: String? = nil
    var timezone: String? = nil
    var sports: [ScoreLink]
    var groups: [ScoreLink]
    var periods: [ScoreLink]
    var games: [ScoreGame]

    var hasLive: Bool { games.contains { $0.state == .live } }
    var lsuGames: [ScoreGame] { games.filter(\.isLSU) }

    var canonicalPath: String {
        periods.first(where: \.isActive)?.path
            ?? groups.first(where: \.isActive)?.path
            ?? sports.first(where: \.isActive)?.path
            ?? path
    }

    var signature: String {
        games.map { "\($0.path):\($0.state.rawValue):\($0.away.score ?? ""):\($0.home.score ?? ""):\($0.status)" }.joined(separator: "|")
    }

    /// LSU games first (pinned), then Live / Scheduled / Final without duplicating LSU rows.
    func displayedSections() -> [(title: String, games: [ScoreGame])] {
        var used = Set<String>()
        var out: [(String, [ScoreGame])] = []
        let lsu = games.filter(\.isLSU)
        if !lsu.isEmpty {
            out.append(("LSU", lsu))
            lsu.forEach { used.insert($0.id) }
        }
        for state in [ScoreGameState.live, .scheduled, .final, .other] {
            let list = games.filter { $0.state == state && !used.contains($0.id) }
            if !list.isEmpty { out.append((state.sectionTitle, list)) }
        }
        return out
    }
}

// MARK: - Loading

extension TD {
    static let scoreboardPath = "/scores/scoreboard.aspx"

    static func loadScoreboard(_ path: String) async throws -> ScoreboardPage {
        let html = try await fetch(path)
        var page = Parser.scoreboardPage(html, path: path)
        page = await injectLSU(into: page)
        page = await attachGameThreads(to: page)
        return page
    }

    /// Top 25 (and other group boards) often omit an unranked LSU game. Pull it from the SEC board for the same week or date.
    static func injectLSU(into page: ScoreboardPage) async -> ScoreboardPage {
        guard page.lsuGames.isEmpty, let sec = Parser.companionGroupPath(page, group: "sec") else { return page }
        guard let html = try? await fetch(sec) else { return page }
        let extra = Parser.scoreboardPage(html, path: sec).games.filter(\.isLSU)
        guard !extra.isEmpty else { return page }
        var page = page
        let existing = Set(page.games.map(\.id))
        page.games = extra.filter { !existing.contains($0.id) }.map {
            var g = $0; g.fromCompanionBoard = true; return g
        } + page.games
        return page
    }

    /// If the LSU Score Board has a matching game thread, attach it so a tap opens the thread.
    static func attachGameThreads(to page: ScoreboardPage) async -> ScoreboardPage {
        guard page.games.contains(where: \.isLSU) else { return page }
        guard let board = try? await loadBoard(Boards.scoreBoard, page: 1) else { return page }
        var page = page
        page.games = page.games.map { g in
            var g = g
            if g.threadPath == nil, let t = Parser.matchingThread(for: g, in: board) {
                g.threadPath = t.path
                g.threadId = t.id
            }
            return g
        }
        return page
    }
}

// MARK: - Scoreboard parsing

extension Parser {
    static func scoreboardPage(_ html: String, path: String) -> ScoreboardPage {
        let title = spacedText(first(#"<h1[^>]*>(.*?)</h1>"#, in: html) ?? "Scores")
        var sports: [ScoreLink] = []
        for m in all(#"<a class="sd-sport-pill([^"]*)" href="([^"]+)"[^>]*>([^<]+)</a>"#, in: html) {
            let href = decode(m[2] ?? "")
            let name = decode(m[3] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty, !name.isEmpty else { continue }
            let cls = m[1] ?? ""
            let active = cls.contains("is-active") || (m[0] ?? "").contains("aria-current")
            sports.append(ScoreLink(name: name, path: href, isActive: active))
        }
        var groups: [ScoreLink] = []
        if let nav = first(#"<nav aria-label="Scoreboard groups">(.*?)</nav>"#, in: html) {
            for m in all(#"<a href="([^"]+)"([^>]*)>([^<]+)</a>"#, in: nav) {
                let href = decode(m[1] ?? "")
                let name = decode(m[3] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !href.isEmpty, !name.isEmpty else { continue }
                groups.append(ScoreLink(name: name, path: href, isActive: (m[2] ?? "").contains("aria-current")))
            }
        }
        let summary = decode(first(#"<details class="sd-filter-menu">\s*<summary>([^<]+)</summary>"#, in: html) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var periods: [ScoreLink] = []
        if let nav = first(#"<nav class="sd-week-navigation"[^>]*>(.*?)</nav>"#, in: html) {
            for m in all(#"<a class="sd-week-item([^"]*)" href="([^"]+)"[^>]*>(.*?)</a>"#, in: nav) {
                let href = decode(m[2] ?? "")
                let name = spacedText(m[3] ?? "")
                guard !href.isEmpty, !name.isEmpty else { continue }
                periods.append(ScoreLink(name: name, path: href, isActive: (m[1] ?? "").contains("is-active")))
            }
        }
        let tz = decode(first(#"class="sd-scoreboard-timezone"[^>]*>([^<]+)"#, in: html) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var games: [ScoreGame] = []
        var seen = Set<String>()
        for c in chunks(html, splitOn: "<article class=\"sd-scoreboard-game") {
            guard let g = scoreGame(from: c), !seen.contains(g.id) else { continue }
            seen.insert(g.id)
            games.append(g)
        }
        let groupName = groups.first(where: \.isActive)?.name
            ?? (summary.isEmpty ? "Scores" : summary)
        let period = periods.first(where: \.isActive)?.name
        return ScoreboardPage(path: path, title: title.isEmpty ? "Scores" : title,
                              groupName: groupName, periodLabel: period,
                              timezone: tz.isEmpty ? nil : tz,
                              sports: sports, groups: groups, periods: periods, games: games)
    }

    static func scoreGame(from c: String) -> ScoreGame? {
        let cls = first(#"^([^"]+)""#, in: c) ?? ""
        let state: ScoreGameState
        if cls.contains("is-live") { state = .live }
        else if cls.contains("is-final") { state = .final }
        else if cls.contains("is-scheduled") { state = .scheduled }
        else { state = .other }
        let label = decode(first(#"aria-label="([^"]+)""#, in: c) ?? "")
        guard let href = first(#"class="sd-scoreboard-game-link" href="([^"]+)""#, in: c) else { return nil }
        let path = decode(href)
        guard let away = scoreTeam(side: "away", in: c), let home = scoreTeam(side: "home", in: c) else { return nil }
        let status = decode(first(#"class="sd-scoreboard-status[^"]*"[^>]*>([^<]+)"#, in: c) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        func field(_ name: String) -> String? {
            let t = decode(first(#"class="sd-scoreboard-\#(name)"[^>]*>([^<]+)"#, in: c) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        var spread: String? = nil, ou: String? = nil, ml: String? = nil
        for m in all(#"<div class="sd-betting-row">\s*<span>([^<]+)</span>\s*<strong>([^<]*)</strong>"#, in: c) {
            let k = decode(m[1] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let v = decode(m[2] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !v.isEmpty else { continue }
            switch k {
            case "Spread": spread = v
            case "O/U": ou = v
            case "ML": ml = v
            default: break
            }
        }
        return ScoreGame(path: path, label: label.isEmpty ? "\(away.name) at \(home.name)" : label,
                         state: state, away: away, home: home, status: status,
                         network: field("network"), line: field("line"), venue: field("venue"),
                         situation: field("situation"), spread: spread, overUnder: ou, moneyline: ml,
                         isLSU: isLSUName(away.name) || isLSUName(home.name))
    }

    static func scoreTeam(side: String, in c: String) -> ScoreTeam? {
        let pat = #"<div class="sd-scoreboard-team sd-scoreboard-team-\#(side)([^"]*)">(.*?)</div>\s*<strong class="sd-scoreboard-score sd-scoreboard-score-\#(side)"[^>]*>([^<]*)"#
        guard let cls = first(pat, in: c, group: 1),
              let block = first(pat, in: c, group: 2),
              let name = first(#"class="sd-scoreboard-team-name"[^>]*>([^<]+)"#, in: block) else { return nil }
        let n = decode(name).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return nil }
        func opt(_ p: String) -> String? {
            let t = decode(first(p, in: block) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        let score = decode(first(pat, in: c, group: 3) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ScoreTeam(name: n,
                         rank: opt(#"class="sd-scoreboard-rank-inline"[^>]*>([^<]+)"#),
                         record: opt(#"class="sd-scoreboard-record"[^>]*>([^<]+)"#),
                         score: score.isEmpty ? nil : score,
                         winner: cls.contains("is-winner"))
    }

    static func isLSUName(_ name: String) -> Bool {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return t == "LSU" || t.hasPrefix("LSU ") || t.hasPrefix("LSU-")
    }

    /// Insert spaces between tags so "Week""13" becomes "Week 13".
    static func spacedText(_ html: String) -> String {
        let spaced = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return decode(spaced)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Swap the group slug of a /{sport}/scores/{group}/… URL for a companion board (usually SEC) with the same week or date.
    static func companionGroupPath(_ page: ScoreboardPage, group: String) -> String? {
        if page.groupName.compare("SEC", options: .caseInsensitive) == .orderedSame { return nil }
        let src = page.periods.first(where: \.isActive)?.path
            ?? page.groups.first(where: \.isActive)?.path
            ?? page.sports.first(where: \.isActive)?.path
            ?? page.path
        guard let sport = first(#"/(ncaaf|ncaab)/scores/"#, in: src) else { return nil }
        if src.lowercased().contains("/scores/\(group)") { return nil }
        if let q = first(#"(\?.*)$"#, in: src) {
            return "/\(sport)/scores/\(group)/\(q)"
        }
        return "/\(sport)/scores/\(group)/"
    }

    static func matchingThread(for game: ScoreGame, in board: BoardPage) -> ThreadSummary? {
        if let h = board.gameHeader,
           teamsMatch(game, h.away, h.home),
           let path = h.threadPath, let id = h.threadId {
            return ThreadSummary(id: id, title: h.title, path: path, author: "",
                                 replies: 0, lastPostTime: "", lastPostBy: "", pages: 1, sticky: true, boardName: nil)
        }
        return board.threads.first { titleMatches(game, $0.title) }
    }

    static func teamsMatch(_ game: ScoreGame, _ a: String, _ b: String) -> Bool {
        let names = [game.away.name, game.home.name]
        return names.contains(where: { teamName($0, matches: a) })
            && names.contains(where: { teamName($0, matches: b) })
    }

    static func titleMatches(_ game: ScoreGame, _ title: String) -> Bool {
        containsTeam(title, game.away.name) && containsTeam(title, game.home.name)
    }

    static func containsTeam(_ title: String, _ name: String) -> Bool {
        let t = title.lowercased()
        let n = name.lowercased()
        if t.contains(n) { return true }
        if n.hasSuffix(" st.") {
            let long = String(n.dropLast(4)) + " state"
            if t.contains(long) { return true }
        }
        if n.hasSuffix(" state"), t.contains(String(n.dropLast(6)) + " st.") { return true }
        return false
    }

    static func teamName(_ a: String, matches b: String) -> Bool {
        containsTeam(a, b) || containsTeam(b, a)
    }

    /// A /rant/board/slug/id/ link on a game detail page, skipping generic nav.
    static func gameThreadLink(in html: String) -> (path: String, id: String)? {
        for m in all(#"href="(/rant/[^"]+/\d+/?)"#, in: html) {
            let path = decode(m[1] ?? "")
            let low = path.lowercased()
            if low.contains("/forums") || low.contains("/help/") || low.contains("useraction")
                || low.contains("message.aspx") || low.contains("postsearch") || low.contains("/s/") { continue }
            if let id = first(#"/(\d+)/?$"#, in: path) { return (path, id) }
        }
        return nil
    }
}

// MARK: - Deterministic rundowns (used on every phone; AI may replace them)

enum ScoreRundown {
    enum Kind { case quick, ai }

    static func quick(_ page: ScoreboardPage) -> String {
        var parts: [String] = []
        let lsu = page.lsuGames
        if lsu.isEmpty {
            var line = "LSU: no game on this board"
            if let p = page.periodLabel { line += " (\(p))" }
            line += "."
            parts.append(line)
        } else {
            for g in lsu { parts.append(lsuBlurb(g)) }
        }

        let live = page.games.filter { $0.state == .live }
        if !live.isEmpty {
            let listed = live.prefix(6).map(shortLive).joined(separator: "; ")
            let more = live.count > 6 ? " …and \(live.count - 6) more" : ""
            parts.append("On now (\(live.count)): \(listed)\(more).")
        }

        let finals = page.games.filter { $0.state == .final }
        let upsets = finals.filter(isUpset)
        if !upsets.isEmpty {
            parts.append("Top-25 upsets: " + upsets.map(upsetLine).joined(separator: "; ") + ".")
        }
        let close = finals.filter { isClose($0) && !isUpset($0) }
        if !close.isEmpty {
            parts.append("Close finishes: " + close.prefix(5).map(finalLine).joined(separator: "; ")
                         + (close.count > 5 ? " …" : "") + ".")
        } else if finals.count >= 3 && upsets.isEmpty && live.isEmpty {
            parts.append("Finals: " + finals.prefix(4).map(finalLine).joined(separator: "; ")
                         + (finals.count > 4 ? " …" : "") + ".")
        }

        let upcoming = page.games.filter { $0.state == .scheduled && !$0.isLSU }
        if !upcoming.isEmpty {
            parts.append("Upcoming: " + upcoming.prefix(5).map(upcomingLine).joined(separator: "; ")
                         + (upcoming.count > 5 ? " …" : "") + ".")
        }
        if parts.isEmpty { return "No games to recap on this board." }
        return parts.joined(separator: "\n\n")
    }

    static func catchUp(game: ScoreGame, posts: [Post]) -> String {
        var parts = [blurb(game)]
        if let sit = game.situation, !sit.isEmpty { parts.append(sit) }
        if let v = game.venue, !v.isEmpty { parts.append("Venue: \(v).") }
        if let line = game.line, !line.isEmpty { parts.append("Line: \(line).") }
        let top = LocalSummary(posts: posts).topPosts
        if !top.isEmpty {
            let lines = top.prefix(5).map { p -> String in
                var t = p.plainText
                if t.count > 180 { t = String(t.prefix(180)) + "…" }
                return "• \(p.author) (▲\(p.up)): \(t)"
            }
            parts.append("From the game thread:\n" + lines.joined(separator: "\n"))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    static func lsuBlurb(_ g: ScoreGame) -> String {
        "LSU: " + blurb(g)
    }

    static func blurb(_ g: ScoreGame) -> String {
        let a = g.away.labeledName, h = g.home.labeledName
        switch g.state {
        case .final:
            let ascore = g.away.score ?? "–", hscore = g.home.score ?? "–"
            var s: String
            if g.isLSU {
                let lsuIsAway = Parser.isLSUName(g.away.name)
                let won = lsuIsAway ? g.away.winner : g.home.winner
                let opp = lsuIsAway ? h : a
                let lsuScore = lsuIsAway ? ascore : hscore
                let oppScore = lsuIsAway ? hscore : ascore
                s = won ? "LSU beat \(opp) \(lsuScore)–\(oppScore)" : "LSU fell to \(opp) \(lsuScore)–\(oppScore)"
            } else if g.away.winner {
                s = "\(a) beat \(h) \(ascore)–\(hscore)"
            } else if g.home.winner {
                s = "\(h) beat \(a) \(hscore)–\(ascore)"
            } else {
                s = "Final, \(a) \(ascore), \(h) \(hscore)"
            }
            if !g.status.isEmpty { s += " (\(g.status))" }
            if let tv = g.network { s += ", \(tv)" }
            return s + "."
        case .live:
            var s = "\(a) \(g.away.score ?? "–"), \(h) \(g.home.score ?? "–")"
            if !g.status.isEmpty { s += " (\(g.status))" }
            if let tv = g.network { s += ", \(tv)" }
            return s + "."
        case .scheduled, .other:
            var s = "\(a) at \(h)"
            if !g.status.isEmpty { s += ", \(g.status)" }
            if let tv = g.network { s += ", \(tv)" }
            if let line = g.line { s += ". Line: \(line)" }
            return s + "."
        }
    }

    static func shortLive(_ g: ScoreGame) -> String {
        var s = "\(g.away.labeledName) \(g.away.score ?? "–")–\(g.home.score ?? "–") \(g.home.labeledName)"
        if !g.status.isEmpty { s += " (\(g.status))" }
        return s
    }

    static func finalLine(_ g: ScoreGame) -> String {
        let ascore = g.away.score ?? "–", hscore = g.home.score ?? "–"
        if g.away.winner { return "\(g.away.labeledName) \(ascore)–\(hscore) \(g.home.labeledName)" }
        if g.home.winner { return "\(g.home.labeledName) \(hscore)–\(ascore) \(g.away.labeledName)" }
        return "\(g.away.labeledName) \(ascore)–\(hscore) \(g.home.labeledName)"
    }

    static func upcomingLine(_ g: ScoreGame) -> String {
        var s = "\(g.away.labeledName) at \(g.home.labeledName)"
        if !g.status.isEmpty { s += ", \(g.status)" }
        if let tv = g.network { s += " (\(tv))" }
        return s
    }

    static func upsetLine(_ g: ScoreGame) -> String {
        finalLine(g)
    }

    static func isClose(_ g: ScoreGame) -> Bool {
        guard let m = g.margin else { return false }
        return g.sport == "ncaab" ? m <= 5 : m <= 8
    }

    static func isUpset(_ g: ScoreGame) -> Bool {
        guard g.state == .final, g.hasScores else { return false }
        let aw = g.away, hm = g.home
        let ar = Int(aw.rank ?? ""), hr = Int(hm.rank ?? "")
        if aw.winner {
            if let hr, ar == nil || (ar ?? 99) > hr { return true }
        }
        if hm.winner {
            if let ar, hr == nil || (hr ?? 99) > ar { return true }
        }
        return false
    }

    static func aiPrompt(for page: ScoreboardPage, fallback: String) -> String {
        var lines: [String] = []
        if let p = page.periodLabel { lines.append("Period: \(p)") }
        lines.append("Board: \(page.groupName). \(page.title).")
        for g in page.games {
            var row = "[\(g.state.rawValue)] \(blurb(g))"
            if g.isLSU { row = "LSU GAME — " + row }
            lines.append(row)
        }
        let material = lines.joined(separator: "\n")
        return """
        Here is a college sports scoreboard (LSU fans are the audience):

        \(material)

        A plain recap already drafted:
        \(fallback)

        Write a short "Today's rundown" with short bullet points starting with •, covering, in this order when they apply:
        - The LSU result or upcoming LSU game
        - What's on now (live games, especially close ones)
        - Top-25 upsets
        - Close final games
        - Notable upcoming games
        Be concise, specific and neutral. Plain text only. Don't invent scores or games that aren't listed.
        """
    }

    static func catchUpPrompt(game: ScoreGame, posts: [Post], fallback: String) -> String {
        let top = LocalSummary(posts: posts).topPosts.prefix(8).map { p in
            SummaryModel.line(p, limit: 220)
        }.joined(separator: "\n")
        return """
        Catch a fan up on this game. Be concise, specific and neutral. Plain text, short bullets starting with •.

        Game:
        \(blurb(game))
        Status: \(game.status)
        TV: \(game.network ?? "n/a")
        Venue: \(game.venue ?? "n/a")
        Line: \(game.line ?? "n/a")
        \(game.situation.map { "Situation: \($0)" } ?? "")

        Top-voted posts from the game thread (may be empty):
        \(top.isEmpty ? "(none loaded)" : top)

        A plain recap already drafted:
        \(fallback)

        Cover the score and game state first, then the best thread takes if any are listed. Don't invent posts or scores.
        """
    }
}
