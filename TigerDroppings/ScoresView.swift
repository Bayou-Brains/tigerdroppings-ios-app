import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

@Observable
final class ScoresModel {
    var path: String
    var page: ScoreboardPage?
    var loading = false
    var refreshing = false
    var error: String?
    var rundownText = ""
    var rundownKind: ScoreRundown.Kind = .quick
    var rundownNote: String?
    var rundownGenerating = false

    init() {
        if let p = UserDefaults.standard.string(forKey: "demoScoresPath"), !p.isEmpty {
            path = p
        } else {
            path = TD.scoreboardPath
        }
    }

    var hasLive: Bool { page?.hasLive == true }

    @MainActor func load(_ newPath: String? = nil, silent: Bool = false) async {
        if let newPath { path = newPath }
        if silent { refreshing = true } else if page == nil { loading = true }
        defer { loading = false; refreshing = false }
        do {
            let p = try await TD.loadScoreboard(path)
            let changed = page?.signature != p.signature
            page = p
            path = p.canonicalPath
            error = nil
            if changed || rundownText.isEmpty {
                rundownText = ScoreRundown.quick(p)
                rundownKind = .quick
                rundownNote = nil
                await generateAIRundownIfAvailable(p)
            }
        } catch {
            if page == nil { self.error = error.localizedDescription }
        }
    }

    @MainActor func generateAIRundownIfAvailable(_ page: ScoreboardPage) async {
        guard ScoreAI.isAvailable else { return }
        rundownGenerating = true
        defer { rundownGenerating = false }
        let fallback = ScoreRundown.quick(page)
        do {
            let text = try await ScoreAI.complete(
                instructions: "You write short, neutral college-sports rundowns for LSU fans. Use plain text and short bullet points starting with •. Never invent scores or games.",
                prompt: ScoreRundown.aiPrompt(for: page, fallback: fallback)
            )
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rundownText = text
                rundownKind = .ai
                rundownNote = nil
            }
        } catch {
            rundownNote = "Couldn't write an on-device rundown. Showing the Quick rundown instead."
        }
    }
}

enum ScoreAI {
    static var isAvailable: Bool { SummaryModel.aiUnavailableReason() == nil }

    static func complete(instructions: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: instructions)
            var text = ""
            for try await snap in session.streamResponse(to: prompt) {
                text = snap.content
            }
            return text
        }
        #endif
        throw CancellationError()
    }
}

struct ScoresView: View {
    @State private var model = ScoresModel()
    @ScaledMetric private var gap: CGFloat = 10

    var body: some View {
        Group {
            if let e = model.error, model.page == nil {
                ContentUnavailableView {
                    Label("Couldn't load scores", systemImage: "sportscourt")
                } description: {
                    Text(e)
                } actions: {
                    Button("Retry") { Task { await model.load() } }
                }
            } else if model.loading, model.page == nil {
                ProgressView("Loading scores…")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let page = model.page {
                list(page)
            }
        }
        .background(Color.black)
        .navigationTitle("Scores")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.refreshing || model.loading {
                    ProgressView()
                } else {
                    Button { Task { await model.load() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh scores")
                }
            }
        }
        .navigationDestination(for: ScoreGame.self) { GameDetailView(game: $0) }
        .navigationDestination(for: ThreadSummary.self) { ThreadView(thread: $0) }
        .task { if model.page == nil { await model.load() } }
        .task(id: model.hasLive) {
            guard model.hasLive else { return }
            while !Task.isCancelled && model.hasLive {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if Task.isCancelled || !model.hasLive { break }
                await model.load(silent: true)
            }
        }
        .refreshable { await model.load() }
    }

    private func list(_ page: ScoreboardPage) -> some View {
        List {
            controls(page)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 4, trailing: 12))
                .listRowBackground(Color.black)
                .listRowSeparator(.hidden)
            rundownCard
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
                .listRowBackground(Color.black)
                .listRowSeparator(.hidden)
            let sections = page.displayedSections()
            if sections.isEmpty {
                Text("No games on this board.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.black)
            }
            ForEach(sections, id: \.title) { section in
                Section {
                    ForEach(section.games) { game in
                        row(game)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.visible)
                            .listRowSeparatorTint(VoteHeat.separator)
                            .listRowBackground(game.isLSU ? Color.lsuPurple.opacity(0.35) : Color.black)
                    }
                } header: {
                    sectionHeader(section.title, count: section.games.count)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .environment(\.defaultMinListRowHeight, 0)
    }

    private func controls(_ page: ScoreboardPage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if page.sports.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(page.sports) { s in
                            pill(s.name, active: s.isActive) { Task { await model.load(s.path) } }
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                if !page.groups.isEmpty {
                    Menu {
                        ForEach(page.groups) { g in
                            Button(g.name) { Task { await model.load(g.path) } }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(page.groupName).font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(Color.lsuGold)
                    }
                    .accessibilityLabel("Scoreboard group, \(page.groupName)")
                }
                Spacer(minLength: 0)
                if let tz = page.timezone {
                    Text(tz).font(.caption2).foregroundStyle(.secondary)
                }
                if model.hasLive {
                    Text("LIVE")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.white)
                        .scaledPadding(h: 6, v: 2)
                        .background(Color.red, in: Capsule())
                }
            }
            if !page.periods.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(page.periods) { p in
                                Button {
                                    Task { await model.load(p.path) }
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(p.name)
                                            .font(.caption.weight(p.isActive ? .bold : .semibold))
                                            .foregroundStyle(p.isActive ? Color.lsuGold : Color(white: 0.7))
                                        Rectangle()
                                            .fill(p.isActive ? Color.lsuGold : Color.clear)
                                            .frame(height: 2)
                                    }
                                    .scaledPadding(h: 10, v: 4)
                                }
                                .id(p.path)
                            }
                        }
                    }
                    .onAppear {
                        if let active = page.periods.first(where: \.isActive) {
                            proxy.scrollTo(active.path, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func pill(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(active ? .black : .white)
                .scaledPadding(h: 12, v: 6)
                .background(active ? Color.lsuGold : Color(white: 0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var rundownCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if model.rundownKind == .ai {
                    Label("Today's rundown · on-device", systemImage: "sparkles")
                        .font(.subheadline.weight(.bold)).foregroundStyle(Color.lsuGold)
                } else {
                    Label("Quick rundown", systemImage: "list.bullet.rectangle")
                        .font(.subheadline.weight(.bold)).foregroundStyle(Color.lsuGold)
                }
                if model.rundownGenerating { ProgressView().scaleEffect(0.8) }
                Spacer(minLength: 0)
            }
            if !model.rundownText.isEmpty {
                Text(model.rundownText)
                    .font(.footnote)
                    .foregroundStyle(Color(white: 0.88))
                    .lineSpacing(3)
            }
            if let n = model.rundownNote {
                Text(n).font(.caption2).foregroundStyle(.secondary)
            } else if model.rundownKind == .quick, ScoreAI.isAvailable == false {
                Text("A scored recap of this board. On-device AI rundowns need Apple Intelligence (iPhone 15 Pro or newer).")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if model.rundownKind == .ai {
                Text("Generated on your iPhone by Apple Intelligence. May be inaccurate.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .scaledPadding(h: 12, v: 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(title == "Live" ? Color.red : (title == "LSU" ? Color.lsuGold : Color(white: 0.6)))
            Text("\(count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            Spacer()
        }
        .textCase(nil)
    }

    private func row(_ game: ScoreGame) -> some View {
        ZStack(alignment: .leading) {
            ScoreGameRow(game: game)
            if let t = game.threadSummary {
                NavigationLink(value: t) { EmptyView() }.opacity(0)
            } else {
                NavigationLink(value: game) { EmptyView() }.opacity(0)
            }
        }
    }
}

struct ScoreGameRow: View {
    let game: ScoreGame
    @ScaledMetric private var pad: CGFloat = 12
    @ScaledMetric private var gap: CGFloat = 4

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: gap) {
                teamLine(game.away)
                teamLine(game.home)
                HStack(spacing: 6) {
                    if game.state == .live {
                        Text("LIVE")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.white)
                            .scaledPadding(h: 5, v: 1)
                            .background(Color.red, in: Capsule())
                    }
                    if game.isLSU {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Color.lsuGold)
                    }
                    if !game.status.isEmpty {
                        Text(game.status)
                            .font(.caption.weight(game.state == .live ? .semibold : .regular))
                            .foregroundStyle(game.state == .live ? Color.red.opacity(0.95) : Color.lsuGold)
                    }
                    if let tv = game.network { Text("· \(tv)").font(.caption).foregroundStyle(.secondary) }
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
                if let line = game.line, !line.isEmpty {
                    Text(line).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .scaledPadding(h: pad, v: 10)
        .contentShape(Rectangle())
    }

    private func teamLine(_ team: ScoreTeam) -> some View {
        HStack(spacing: 6) {
            if let r = team.rank, !r.isEmpty {
                Text("#\(r)").font(.caption.weight(.bold)).foregroundStyle(Color.lsuGold)
                    .frame(minWidth: 22, alignment: .leading)
            }
            Text(team.name)
                .font(.subheadline.weight(team.winner || Parser.isLSUName(team.name) ? .semibold : .regular))
                .foregroundStyle(team.winner ? Color.white : Color(white: 0.92))
            if let rec = team.record, !rec.isEmpty {
                Text(rec).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let s = team.score, !s.isEmpty {
                Text(s)
                    .font(.title3.weight(team.winner ? .bold : .semibold).monospacedDigit())
                    .foregroundStyle(team.winner || game.state == .live ? .white : Color(white: 0.8))
            }
        }
    }
}

struct GameDetailView: View {
    let game: ScoreGame
    @State private var posts: [Post] = []
    @State private var text = ""
    @State private var kind: ScoreRundown.Kind = .quick
    @State private var note: String?
    @State private var generating = false
    @State private var thread: ThreadSummary?
    @ScaledMetric private var pad: CGFloat = 16
    @ScaledMetric private var gap: CGFloat = 14

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: gap) {
                GameHeaderCard(header: game.asHeader)
                if let ml = game.moneyline, !ml.isEmpty {
                    Text("ML \(ml)").font(.caption).foregroundStyle(.secondary)
                        .scaledPadding(h: 12)
                }
                catchUpCard
                if let t = thread ?? game.threadSummary {
                    NavigationLink(value: t) {
                        Label("Open game thread", systemImage: "bubble.left.and.bubble.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.lsuGold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .scaledPadding(h: 12, v: 10)
                            .background(Color.lsuPurple.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .padding(.bottom, pad)
        }
        .background(Color.black)
        .navigationTitle(game.label)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ThreadSummary.self) { ThreadView(thread: $0) }
        .task { await loadCatchUp() }
    }

    private var catchUpCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if kind == .ai {
                    Label("Catch me up · on-device", systemImage: "sparkles")
                        .font(.subheadline.weight(.bold)).foregroundStyle(Color.lsuGold)
                } else {
                    Label("Catch me up", systemImage: "text.alignleft")
                        .font(.subheadline.weight(.bold)).foregroundStyle(Color.lsuGold)
                }
                if generating { ProgressView().scaleEffect(0.8) }
                Spacer(minLength: 0)
            }
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color(white: 0.88))
                .lineSpacing(3)
            if let note {
                Text(note).font(.caption2).foregroundStyle(.secondary)
            } else if kind == .quick {
                Text(ScoreAI.isAvailable
                     ? "Writing an on-device catch-up if Apple Intelligence is available."
                     : "A scored recap. On-device AI catch-up needs Apple Intelligence (iPhone 15 Pro or newer).")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Generated on your iPhone by Apple Intelligence. May be inaccurate.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .scaledPadding(h: 12, v: 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .scaledPadding(h: 12, v: 0)
    }

    @MainActor private func loadCatchUp() async {
        var g = game
        text = ScoreRundown.catchUp(game: g, posts: [])
        kind = .quick
        if g.threadPath == nil, let html = try? await TD.fetch(g.path), let link = Parser.gameThreadLink(in: html) {
            g.threadPath = link.path
            g.threadId = link.id
            thread = g.threadSummary
        }
        var loaded: [Post] = []
        if let path = g.threadPath ?? thread?.path {
            if let p1 = try? await TD.loadThread(path, page: 1) {
                loaded = p1.posts
                if p1.totalPages > 1, let last = try? await TD.loadThread(path, page: p1.totalPages) {
                    let ids = Set(loaded.map(\.id))
                    loaded += last.posts.filter { !ids.contains($0.id) }
                }
            }
        }
        posts = loaded
        text = ScoreRundown.catchUp(game: g, posts: loaded)
        guard ScoreAI.isAvailable else { return }
        generating = true
        defer { generating = false }
        do {
            let ai = try await ScoreAI.complete(
                instructions: "You catch a fan up on one college game for LSU fans. Be concise, specific and neutral. Use plain text and short bullet points starting with •. Don't invent scores or posts.",
                prompt: ScoreRundown.catchUpPrompt(game: g, posts: loaded, fallback: text)
            )
            if !ai.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text = ai
                kind = .ai
            }
        } catch {
            note = "Couldn't write an on-device catch-up. Showing the scored recap instead."
        }
    }
}
