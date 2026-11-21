import SwiftUI

@Observable
final class ThreadModel {
    let path: String
    var title: String
    var posts: [Post] = []
    var firstPage = 1
    var lastPage = 0          // highest page loaded
    var totalPages = 1
    var loading = false
    var error: String?
    var live = false
    var lastLiveCheck: Date?
    var newPostCount = 0
    var gameHeader: GameHeader?

    init(path: String, title: String) { self.path = path; self.title = title }

    var hasNext: Bool { lastPage < totalPages }
    var hasPrevious: Bool { firstPage > 1 }

    private func apply(_ p: ThreadPage) {
        if p.page == 1 && !p.title.isEmpty { title = p.title }
        if p.page == 1 { gameHeader = p.gameHeader ?? gameHeader }
        totalPages = max(p.totalPages, p.page)
    }

    /// Merge a page's posts: update votes for existing posts, append new ones in order. Returns number added.
    @discardableResult
    private func merge(_ page: ThreadPage, prepend: Bool = false) -> Int {
        var index = Dictionary(uniqueKeysWithValues: posts.enumerated().map { ($1.id, $0) })
        var fresh: [Post] = []
        for p in page.posts {
            if let i = index[p.id] {
                posts[i].up = p.up; posts[i].down = p.down
                if p.upToken != nil || p.downToken != nil || p.myVote != 0 {
                    posts[i].upToken = p.upToken; posts[i].downToken = p.downToken
                    posts[i].myVote = p.myVote != 0 ? p.myVote : posts[i].myVote
                }
            } else {
                fresh.append(p); index[p.id] = -1
            }
        }
        if prepend { posts.insert(contentsOf: fresh, at: 0) } else { posts += fresh }
        return fresh.count
    }

    @MainActor func loadInitial(startPage: Int = 1) async {
        guard posts.isEmpty else { return }
        guard startPage > 1 else { await loadNext(); return }
        loading = true; defer { loading = false }
        do {
            let p = try await TD.loadThread(path, page: startPage)
            apply(p)
            if p.posts.isEmpty { loading = false; await loadNext(); return }
            posts = p.posts; firstPage = p.page; lastPage = p.page
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    /// Back to page 1 (drops the loaded pages).
    @MainActor func jumpToFirst() async {
        loading = true; defer { loading = false }
        do {
            let p = try await TD.loadThread(path, page: 1)
            apply(p)
            posts = p.posts; firstPage = 1; lastPage = 1
        } catch { self.error = error.localizedDescription }
    }

    /// Load forward so the summary sees more of the thread.
    @MainActor func loadForSummary(maxPages: Int) async {
        var waited = 0
        while loading && waited < 150 { try? await Task.sleep(nanoseconds: 100_000_000); waited += 1 }
        if posts.isEmpty { await loadNext() }
        while hasNext && (lastPage - firstPage + 1) < maxPages {
            let before = lastPage
            await loadNext()
            if lastPage == before { break }
        }
    }

    @MainActor func loadNext() async {
        guard !loading, lastPage == 0 || hasNext else { return }
        loading = true; defer { loading = false }
        do {
            let p = try await TD.loadThread(path, page: lastPage + 1)
            apply(p); merge(p); lastPage = p.page
            if posts.count == p.posts.count { firstPage = p.page }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    @MainActor func loadPrevious() async {
        guard !loading, hasPrevious else { return }
        loading = true; defer { loading = false }
        do {
            let p = try await TD.loadThread(path, page: firstPage - 1)
            apply(p); merge(p, prepend: true); firstPage = p.page
        } catch { self.error = error.localizedDescription }
    }

    /// Jump to the newest page (used when Live turns on).
    @MainActor func jumpToLatest() async {
        loading = true; defer { loading = false }
        do {
            // learn total pages first if we haven't
            if lastPage == 0 {
                let p1 = try await TD.loadThread(path, page: 1)
                apply(p1)
                if totalPages == 1 { posts = p1.posts; firstPage = 1; lastPage = 1; return }
            }
            guard lastPage < totalPages else { return }
            let p = try await TD.loadThread(path, page: totalPages)
            apply(p)
            var newPosts = p.posts
            var first = p.page
            if p.posts.count < 10 && p.page > 1 {   // short last page: add the previous page for context
                if let prev = try? await TD.loadThread(path, page: p.page - 1) {
                    let ids = Set(newPosts.map(\.id))
                    newPosts = prev.posts.filter { !ids.contains($0.id) } + newPosts
                    first = prev.page
                }
            }
            posts = newPosts; firstPage = first; lastPage = p.page
        } catch { self.error = error.localizedDescription }
    }

    /// Re-fetch every loaded page (after sign-in, so vote links appear).
    @MainActor func reloadLoaded() async {
        guard lastPage > 0 else { return }
        for pg in firstPage...lastPage {
            if let p = try? await TD.loadThread(path, page: pg) {
                apply(p)
                var index = Dictionary(uniqueKeysWithValues: posts.enumerated().map { ($1.id, $0) })
                for np in p.posts {
                    if let i = index[np.id] { posts[i] = np } else { posts.append(np); index[np.id] = posts.count - 1 }
                }
            }
        }
    }

    /// Vote using the site's endpoint; optimistic update, rolled back on failure.
    @MainActor func vote(_ postId: String, up: Bool) async -> String? {
        guard let i = posts.firstIndex(where: { $0.id == postId }) else { return nil }
        let post = posts[i]
        if post.myVote != 0 { return "You already voted on this post." }
        guard let token = up ? post.upToken : post.downToken else {
            return "The site doesn't offer a vote on this post (your own post, or votes are closed)."
        }
        if up { posts[i].up += 1 } else { posts[i].down += 1 }
        posts[i].myVote = up ? 1 : -1
        do {
            let r = try await Posting.vote(token: token)
            if r.duplicate, let j = posts.firstIndex(where: { $0.id == postId }) {
                if up { posts[j].up -= 1 } else { posts[j].down -= 1 }   // already counted on the site
            }
            return nil
        } catch {
            if let j = posts.firstIndex(where: { $0.id == postId }) {
                if up { posts[j].up -= 1 } else { posts[j].down -= 1 }
                posts[j].myVote = 0
            }
            return error.localizedDescription
        }
    }

    /// One live poll: re-fetch the newest loaded page (and any page after it).
    @MainActor func poll() async -> Int {
        guard !loading else { return 0 }
        var added = 0
        do {
            // Keep the live score header fresh even when we're watching later pages.
            if gameHeader != nil && lastPage > 1, let p1 = try? await TD.loadThread(path, page: 1) {
                apply(p1)
            }
            var page = max(lastPage, 1)
            while true {
                let p = try await TD.loadThread(path, page: page)
                apply(p)
                added += merge(p)
                lastPage = max(lastPage, p.page)
                if page < totalPages { page += 1 } else { break }
            }
            lastLiveCheck = Date()
            error = nil
        } catch { self.error = error.localizedDescription }
        return added
    }
}

struct ThreadView: View {
    let thread: ThreadSummary
    @State private var model: ThreadModel
    @State private var atBottom = false
    @State private var auth = AuthModel.shared
    @State private var draft = ""
    @State private var replyTarget: Post?
    @State private var quoteTarget = false
    @State private var sending = false
    @State private var showSummary = UserDefaults.standard.bool(forKey: "demoSummary")
    @State private var summary = SummaryModel()      // cached across opens
    @State private var pendingJump: String?          // post picked in the summary
    @State private var fromSummary = false           // back button returns to the summary
    @State private var highlightId: String?
    @ScaledMetric private var sepGap: CGFloat = 8
    @ScaledMetric private var dividerPad: CGFloat = 12
    @State private var resume: ReadPosition?
    @State private var liveSeen = 0
    private var reads: ReadStore { ReadStore.shared }
    @State private var alertText: String?
    @State private var toast: String?
    @FocusState private var composerFocused: Bool

    init(thread: ThreadSummary) {
        self.thread = thread
        let m = ThreadModel(path: thread.path, title: thread.title)
        _resume = State(initialValue: ReadStore.shared.get(thread.id))
        m.live = UserDefaults.standard.bool(forKey: "demoLive")
        _model = State(initialValue: m)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let h = model.gameHeader {
                        GameHeaderCard(header: h)
                    }
                    if model.hasPrevious {
                        Button { Task { await model.loadPrevious() } } label: {
                            Label("Load earlier posts (page \(model.firstPage - 1))", systemImage: "arrow.up.circle")
                                .font(.footnote)
                        }
                        .padding(8)
                    }
                    ForEach(model.posts) { post in
                        if post.id == firstUnreadId {
                            HStack(spacing: 8) {
                                Rectangle().fill(Color.lsuGold.opacity(0.7)).frame(height: 1)
                                Text("NEW POSTS BELOW").font(.caption2.weight(.heavy)).foregroundStyle(Color.lsuGold)
                                    .fixedSize()
                                Rectangle().fill(Color.lsuGold.opacity(0.7)).frame(height: 1)
                            }
                            .padding(.horizontal, dividerPad).padding(.bottom, sepGap)
                            .id("unread")
                        }
                        PostRow(post: post, isOP: post.author == thread.author,
                                onVote: { up in vote(post, up: up) },
                                onReply: { quote in startReply(post, quote: quote) })
                            .overlay {
                                if highlightId == post.id {
                                    Rectangle().fill(Color.lsuGold.opacity(0.16))
                                        .overlay(Rectangle().stroke(Color.lsuGold, lineWidth: 2))
                                        .allowsHitTesting(false)
                                        .transition(.opacity)
                                }
                            }
                            .id(post.id)
                            .onAppear { reads.markSeen(threadId: thread.id, post: post, replyCount: thread.replies + liveSeen) }
                        Rectangle().fill(VoteHeat.separator).frame(height: 1)
                            .padding(.vertical, sepGap)
                    }
                    footer
                    Color.clear.frame(height: 1).id("bottom")
                        .onAppear {
                            atBottom = true
                            if !model.live { Task { await model.loadNext() } }
                        }
                        .onDisappear { atBottom = false }
                }
            }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .background(Color.black)
            .defaultScrollAnchor(model.live ? .bottom : .top)
            .navigationBarBackButtonHidden(fromSummary)
            .toolbar {
                if fromSummary {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            fromSummary = false
                            highlightId = nil
                            showSummary = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.left").fontWeight(.semibold)
                                Text("Summary")
                            }
                        }
                        .accessibilityLabel("Back to thread summary")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.live.toggle()
                    } label: {
                        Label(model.live ? "Live" : "Go Live", systemImage: model.live ? "dot.radiowaves.left.and.right" : "play.circle")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(model.live ? Color.red : Color.lsuPurple, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .accessibilityIdentifier("liveToggle")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSummary = true } label: { Image(systemName: "sparkles") }
                        .accessibilityLabel("Summarize thread")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task {
                                await model.jumpToFirst()
                                if let f = model.posts.first?.id { proxy.scrollTo(f, anchor: .top) }
                            }
                        } label: { Label("Jump to first page", systemImage: "arrow.up.to.line") }
                        Button("Jump to newest page") {
                            Task { await model.jumpToLatest(); scrollToBottom(proxy, animated: false) }
                        }
                        Link("Open in Safari", destination: TD.url(thread.path))
                        ShareLink(item: TD.url(thread.path))
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .task {
                await model.loadInitial(startPage: resume?.lastPage ?? 1)
                if let r = resume, model.posts.contains(where: { $0.id == r.lastPostId }) {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    proxy.scrollTo(r.lastPostId, anchor: .top)
                }
            }
            .sheet(isPresented: $showSummary, onDismiss: { jumpToPicked(proxy) }) {
                SummaryView(model: model, summary: summary) { post in
                    pendingJump = post.id
                    showSummary = false
                }
            }
            .task(id: model.live) {
                guard model.live else { return }
                await model.jumpToLatest()
                try? await Task.sleep(nanoseconds: 150_000_000)
                scrollToBottom(proxy, animated: false)
                while !Task.isCancelled && model.live {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if Task.isCancelled || !model.live { break }
                    let wasAtBottom = atBottom
                    let added = await model.poll()
                    liveSeen += added
                    if added > 0 {
                        if wasAtBottom { scrollToBottom(proxy, animated: true) }
                        else { model.newPostCount += added }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if model.newPostCount > 0 && !atBottom {
                    Button {
                        model.newPostCount = 0
                        scrollToBottom(proxy, animated: true)
                    } label: {
                        Text("\(model.newPostCount) new post\(model.newPostCount == 1 ? "" : "s") ↓")
                            .font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.lsuPurple, in: Capsule()).foregroundStyle(.white)
                    }
                    .padding(.bottom, 12)
                }
            }
            .onChange(of: atBottom) { _, v in if v { model.newPostCount = 0 } }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer(proxy) }
            .onChange(of: auth.loggedIn) { _, v in if v { Task { await model.reloadLoaded() } } }
            .alert("TigerDroppings", isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(alertText ?? "") }
            .overlay(alignment: .top) {
                if let t = toast {
                    Text(t).font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.lsuPurple, in: Capsule()).foregroundStyle(.white).padding(.top, 6)
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: Reply / vote

    /// First post newer than where the user left off last time (only when resuming).
    private var firstUnreadId: String? {
        guard let r = resume, let last = Int(r.lastPostId) else { return nil }
        return model.posts.first(where: { (Int($0.id) ?? 0) > last })?.id
    }

    private var threadOPId: String { model.posts.first(where: { $0.page == 1 })?.id ?? thread.id }

    private func startReply(_ post: Post, quote: Bool) {
        guard auth.require() else { return }
        replyTarget = post
        quoteTarget = quote
        composerFocused = true
    }

    private func vote(_ post: Post, up: Bool) {
        guard auth.require() else { return }
        Task { if let err = await model.vote(post.id, up: up) { alertText = err } }
    }

    private func send(_ proxy: ScrollViewProxy) {
        guard auth.require() else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        let target = replyTarget?.id ?? (thread.id == "demo" ? threadOPId : thread.id)
        var body = text
        if quoteTarget, let p = replyTarget { body = Posting.quoteBlock(p) + text }
        sending = true
        Task {
            defer { sending = false }
            do {
                try await Posting.reply(toPost: target, message: body)
                draft = ""; replyTarget = nil; quoteTarget = false; composerFocused = false
                showToast("Reply posted")
                if !model.hasNext || model.live {
                    _ = await model.poll()
                    scrollToBottom(proxy, animated: true)
                }
            } catch {
                alertText = error.localizedDescription
            }
        }
    }

    private func showToast(_ t: String) {
        withAnimation { toast = t }
        Task { try? await Task.sleep(nanoseconds: 2_000_000_000); withAnimation { toast = nil } }
    }

    @ViewBuilder private func composer(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 6) {
            if let p = replyTarget {
                HStack(spacing: 6) {
                    Image(systemName: quoteTarget ? "quote.opening" : "arrowshape.turn.up.left.fill").font(.caption2)
                    Text("\(quoteTarget ? "Quoting" : "Replying to") \(p.author)").font(.caption.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Button { quoteTarget.toggle() } label: {
                        Text(quoteTarget ? "Quote on" : "Quote off").font(.caption2.weight(.semibold))
                    }
                    Button { replyTarget = nil; quoteTarget = false } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color.lsuGold)
            }
            HStack(alignment: .bottom, spacing: 8) {
                if auth.loggedIn {
                    TextField(replyTarget == nil ? "Reply to thread…" : "Write a reply…", text: $draft, axis: .vertical)
                        .lineLimit(1...6)
                        .font(.body)
                        .focused($composerFocused)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 18))
                        .foregroundStyle(.white)
                    Button { send(proxy) } label: {
                        if sending { ProgressView().frame(minWidth: 34, minHeight: 34) }
                        else {
                            Image(systemName: "arrow.up.circle.fill").font(.largeTitle)
                                .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.lsuGold)
                        }
                    }
                    .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send reply")
                } else {
                    Button { auth.showLogin = true } label: {
                        HStack {
                            Image(systemName: "person.crop.circle")
                            Text("Sign in to reply and vote")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 18))
                        .foregroundStyle(Color.lsuGold)
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)
        .background(.black)
        .overlay(alignment: .top) { Rectangle().fill(VoteHeat.separator).frame(height: 1) }
    }

    @ViewBuilder private var footer: some View {
        VStack(spacing: 4) {
            if model.loading { ProgressView().padding(6) }
            if let e = model.error {
                Button("Couldn't load (\(e)). Tap to retry") { Task { await model.loadNext() } }.font(.footnote)
            }
            if model.live {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 7, height: 7)
                    Text("Live · checking every 5s").font(.caption2)
                    if let d = model.lastLiveCheck {
                        Text(d, style: .time).font(.caption2)
                    }
                }
                .foregroundStyle(.secondary)
                .padding(8)
            } else if !model.hasNext && model.lastPage > 0 {
                Text("End of thread · page \(model.lastPage) of \(model.totalPages)")
                    .font(.caption2).foregroundStyle(.secondary).padding(8)
            }
        }
    }

    /// After the summary sheet closes on a picked post: scroll to it, flash it, and
    /// swap the back button for "‹ Summary" so going back reopens the summary.
    private func jumpToPicked(_ proxy: ScrollViewProxy) {
        guard let id = pendingJump else { return }
        pendingJump = nil
        guard model.posts.contains(where: { $0.id == id }) else {
            alertText = "That post isn't loaded anymore. Open the summary again to refresh it."
            return
        }
        model.live = false            // don't let Live yank the view to the bottom
        fromSummary = true
        Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .top) }
            withAnimation(.easeIn(duration: 0.2)) { highlightId = id }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if highlightId == id { withAnimation(.easeOut(duration: 0.6)) { highlightId = nil } }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) } }
        else { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}

struct PostRow: View {
    let post: Post
    let isOP: Bool
    var onVote: (Bool) -> Void = { _ in }
    var onReply: (Bool) -> Void = { _ in }
    @AppStorage("showImages") private var showImages = true
    @ScaledMetric private var gap: CGFloat = 7
    @ScaledMetric private var vPad: CGFloat = 12
    @ScaledMetric private var hPad: CGFloat = 14
    @ScaledMetric private var actionGap: CGFloat = 18
    @ScaledMetric private var icon: CGFloat = 24
    @ScaledMetric private var imgW: CGFloat = 280
    @ScaledMetric private var imgH: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            HStack(spacing: 6) {
                Text(post.author).font(.subheadline.weight(.bold))
                    .foregroundStyle(isOP ? Color.lsuGold : .white)
                    .lineLimit(1).layoutPriority(1)
                if isOP { Text("OP").font(.caption2.weight(.heavy)).padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.lsuGold, in: RoundedRectangle(cornerRadius: 3)).foregroundStyle(.black) }
                if let r = post.replyTo { Text("→ \(r)").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength: 4)
                Text(post.time).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            ForEach(Array(post.blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let a):
                    Text(a).font(.callout).lineSpacing(3).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                case .quote(let a):
                    Text(a).font(.subheadline).lineSpacing(2).foregroundStyle(VoteHeat.quoteText)
                        .lineLimit(8)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(VoteHeat.quoteBox, in: RoundedRectangle(cornerRadius: 6))
                case .image(let u) where u.path.lowercased().contains("/images/icons/"):
                    AsyncImage(url: u) { $0.resizable().interpolation(.none).scaledToFit() } placeholder: { Color.clear }
                        .frame(width: icon, height: icon)
                case .image(let u):
                    if showImages {
                        AsyncImage(url: u) { img in
                            img.resizable().scaledToFit()
                        } placeholder: { Color.secondary.opacity(0.1).frame(height: 60) }
                        .frame(maxWidth: imgW, maxHeight: imgH, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Link("🖼 image", destination: u).font(.caption)
                    }
                case .link(let u, let label):
                    Link("▶︎ \(label)", destination: u.absoluteString.contains("youtube.com/embed/")
                         ? URL(string: u.absoluteString.replacingOccurrences(of: "/embed/", with: "/watch?v=").replacingOccurrences(of: "?version", with: "&version")) ?? u
                         : u).font(.subheadline)
                }
            }
            // Action bar: vote + reply. At big text sizes Quote/Reply drop to icons.
            ViewThatFits(in: .horizontal) {
                actionBar(compact: false)
                actionBar(compact: true)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, vPad)
        .padding(.horizontal, hPad)
        .voteEdges(up: post.up, down: post.down)
        .contextMenu {
            Button { onReply(false) } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
            Button { onReply(true) } label: { Label("Quote reply", systemImage: "quote.opening") }
            Button { onVote(true) } label: { Label("Upvote", systemImage: "arrowshape.up") }
            Button { onVote(false) } label: { Label("Downvote", systemImage: "arrowshape.down") }
            Button { UIPasteboard.general.string = post.blocks.compactMap { if case .text(let a) = $0 { return String(a.characters) }; return nil }.joined(separator: "\n") } label: { Label("Copy text", systemImage: "doc.on.doc") }
        }
    }

    private func actionBar(compact: Bool) -> some View {
        HStack(spacing: actionGap) {
            Button { onVote(true) } label: {
                Label("\(post.up)", systemImage: post.myVote == 1 ? "arrowshape.up.fill" : "arrowshape.up")
                    .foregroundStyle(post.myVote == 1 ? VoteHeat.green : Color(white: 0.75))
            }
            .accessibilityLabel("Upvote, \(post.up)")
            Button { onVote(false) } label: {
                Label("\(post.down)", systemImage: post.myVote == -1 ? "arrowshape.down.fill" : "arrowshape.down")
                    .foregroundStyle(post.myVote == -1 ? VoteHeat.red : Color(white: 0.75))
            }
            .accessibilityLabel("Downvote, \(post.down)")
            Spacer(minLength: 8)
            Button { onReply(true) } label: {
                if compact { Image(systemName: "quote.opening") } else { Label("Quote", systemImage: "quote.opening") }
            }
            .foregroundStyle(Color(white: 0.75))
            .accessibilityLabel("Quote")
            Button { onReply(false) } label: {
                if compact { Image(systemName: "arrowshape.turn.up.left") } else { Label("Reply", systemImage: "arrowshape.turn.up.left") }
            }
            .foregroundStyle(Color(white: 0.75))
            .accessibilityLabel("Reply")
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
    }
}
