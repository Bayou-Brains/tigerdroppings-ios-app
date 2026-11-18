import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Non-AI stats that are always available.
struct LocalSummary {
    let postCount: Int
    let pages: String
    let topPosts: [Post]
    let activeUsers: [(String, Int)]
    let repliedTo: [(String, Int)]
    let totalUp: Int
    let totalDown: Int

    init(posts: [Post]) {
        postCount = posts.count
        let pg = Set(posts.map(\.page)).sorted()
        pages = pg.isEmpty ? "-" : (pg.first == pg.last ? "page \(pg[0])" : "pages \(pg.first!)–\(pg.last!)")
        // Every post with more up- than downvotes, best first. No cap.
        topPosts = posts.filter { $0.up > $0.down }.sorted { (a: Post, b: Post) -> Bool in
            let sa = a.up - a.down, sb = b.up - b.down
            return sa == sb ? a.up > b.up : sa > sb
        }
        func top(_ names: [String]) -> [(String, Int)] {
            var counts: [String: Int] = [:]
            for n in names { counts[n, default: 0] += 1 }
            let sorted: [(String, Int)] = counts.map { ($0.key, $0.value) }.sorted { (a: (String, Int), b: (String, Int)) -> Bool in
                a.1 == b.1 ? a.0 < b.0 : a.1 > b.1
            }
            return Array(sorted.prefix(5))
        }
        activeUsers = top(posts.map(\.author))
        repliedTo = top(posts.compactMap(\.replyTo))
        totalUp = posts.reduce(0) { $0 + $1.up }
        totalDown = posts.reduce(0) { $0 + $1.down }
    }
}

extension Post {
    var plainText: String {
        blocks.compactMap { b -> String? in
            switch b {
            case .text(let a): return String(a.characters)
            case .quote(let a): return "(quoting: \(String(a.characters).prefix(80)))"
            default: return nil
            }
        }.joined(separator: " ").replacingOccurrences(of: "\n", with: " ")
    }
}

@Observable
final class SummaryModel {
    enum Phase: Equatable { case loading, generating, done, unavailable, failed }
    var phase: Phase = .loading
    var progress = "Loading posts…"
    var aiText = ""
    var note: String?            // why AI isn't available / what went wrong
    var local: LocalSummary?
    var started = false          // cached: reopening the sheet doesn't regenerate

    @MainActor func runIfNeeded(model: ThreadModel) async {
        guard !started else { return }
        started = true
        await run(model: model)
    }

    @MainActor func regenerate(model: ThreadModel) async {
        aiText = ""; note = nil; local = nil
        started = true
        await run(model: model)
    }

    /// nil when the on-device model can be used.
    static func aiUnavailableReason() -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.deviceNotEligible):
                return "AI summaries run on-device with Apple Intelligence, which requires an iPhone 15 Pro or newer."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in Settings › Apple Intelligence & Siri to get on-device AI summaries."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence is still downloading its on-device model. Try again in a little while."
            case .unavailable(_):
                return "Apple Intelligence isn't available on this device right now."
            }
        }
        return "On-device AI summaries need iOS 26 with Apple Intelligence (iPhone 15 Pro or newer)."
        #else
        return "On-device AI summaries need iOS 26 with Apple Intelligence (iPhone 15 Pro or newer)."
        #endif
    }

    @MainActor func run(model: ThreadModel) async {
        phase = .loading
        progress = "Loading posts…"
        await model.loadForSummary(maxPages: 8)
        let posts = model.posts
        local = LocalSummary(posts: posts)
        if let reason = Self.aiUnavailableReason() {
            note = reason; phase = .unavailable; return
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            phase = .generating
            do {
                try await summarize(posts: posts, title: model.title, chunkChars: 6000)
                phase = .done
            } catch let e as LanguageModelSession.GenerationError {
                if case .exceededContextWindowSize = e, aiText.isEmpty {
                    do { try await summarize(posts: posts, title: model.title, chunkChars: 3000); phase = .done; return } catch {}
                }
                if case .guardrailViolation = e {
                    note = "Apple's on-device model declined to summarize this thread (content safety filter)."
                } else {
                    note = "The on-device model couldn't summarize this thread: \(e.localizedDescription)"
                }
                phase = .failed
            } catch {
                note = "The on-device model couldn't summarize this thread: \(error.localizedDescription)"
                phase = .failed
            }
        }
        #endif
    }

    static func line(_ p: Post, limit: Int = 320) -> String {
        var t = p.plainText
        if t.count > limit { t = String(t.prefix(limit)) + "…" }
        return "\(p.author) [+\(p.up)/-\(p.down)]: \(t)"
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @MainActor private func summarize(posts: [Post], title: String, chunkChars: Int) async throws {
        let instructions = "You summarize LSU / TigerDroppings sports forum threads for a fan. Be concise, specific and neutral. Use plain text with short bullet points starting with •."
        var chunks: [String] = []
        var cur = ""
        for p in posts {
            let l = Self.line(p) + "\n"
            if cur.count + l.count > chunkChars, !cur.isEmpty { chunks.append(cur); cur = "" }
            cur += l
        }
        if !cur.isEmpty { chunks.append(cur) }
        guard !chunks.isEmpty else { aiText = "No posts to summarize."; return }

        var material: String
        if chunks.count == 1 {
            material = "Posts:\n" + chunks[0]
        } else {
            var notes: [String] = []
            for (i, c) in chunks.enumerated() {
                progress = "Reading part \(i + 1) of \(chunks.count)…"
                let s = LanguageModelSession(instructions: instructions)
                let r = try await s.respond(to: "Thread title: \(title)\n\nSummarize the main points, arguments and opinions in these forum posts as 3 to 5 short bullets:\n\n\(c)")
                notes.append(r.content)
            }
            material = "Notes from each part of the thread:\n" + notes.joined(separator: "\n")
            if material.count > 7000 { material = String(material.prefix(7000)) }
        }
        let top = LocalSummary(posts: posts).topPosts.prefix(3).map { Self.line($0, limit: 200) }.joined(separator: "\n")
        let prompt = """
        Thread title: \(title)

        \(material)

        Most upvoted posts:
        \(top)

        Write a short summary of this thread with exactly these sections:
        Topic: one sentence.
        Key points: 3 to 5 bullets.
        Sentiment: one sentence about the overall mood of the posters.
        Top posts: 1 to 3 bullets on the most upvoted takes, naming the poster.
        """
        progress = "Writing summary…"
        let session = LanguageModelSession(instructions: instructions)
        for try await snap in session.streamResponse(to: prompt) {
            aiText = snap.content
        }
    }
    #endif
}

struct SummaryView: View {
    let model: ThreadModel
    let summary: SummaryModel          // owned by ThreadView so it survives dismiss / re-open
    var onOpen: (Post) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric private var pad: CGFloat = 16
    @ScaledMetric private var gap: CGFloat = 16

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: gap) {
                    Text(model.title).font(.headline).foregroundStyle(.white)
                    aiSection
                    if let l = summary.local { localSection(l) }
                }
                .padding(pad)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black)
            .navigationTitle("Thread Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await summary.regenerate(model: model) } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Regenerate summary")
                        .disabled(summary.phase == .loading || summary.phase == .generating)
                }
            }
            .task { await summary.runIfNeeded(model: model) }
            .task(id: summary.local?.postCount) {
                // Debug hook for simulator testing: -demoJumpTop N opens the Nth top post
                let n = UserDefaults.standard.integer(forKey: "demoJumpTop")
                guard n > 0, let l = summary.local, !l.topPosts.isEmpty else { return }
                let p = l.topPosts[min(n, l.topPosts.count) - 1]
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                UserDefaults.standard.set(0, forKey: "demoJumpTop")
                onOpen(p)
            }
        }
        .preferredColorScheme(.dark)
        .appTextSize()
    }

    @ViewBuilder private var aiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI summary · on-device", systemImage: "sparkles")
                .font(.subheadline.weight(.bold)).foregroundStyle(Color.lsuGold)
            switch summary.phase {
            case .loading, .generating:
                if summary.aiText.isEmpty {
                    HStack(spacing: 8) { ProgressView(); Text(summary.progress).font(.callout).foregroundStyle(.secondary) }
                } else {
                    Text(summary.aiText).font(.callout).lineSpacing(3).foregroundStyle(.white)
                }
            case .done:
                Text(summary.aiText).font(.callout).lineSpacing(3).foregroundStyle(.white).textSelection(.enabled)
                Text("Generated on your iPhone by Apple Intelligence. May be inaccurate.").font(.caption2).foregroundStyle(.secondary)
            case .unavailable, .failed:
                Text(summary.note ?? "").font(.callout).foregroundStyle(Color(white: 0.75))
                if summary.phase == .unavailable {
                    Text("Showing quick stats from the posts instead.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    private func localSection(_ l: LocalSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Quick stats (not AI)", systemImage: "chart.bar.fill")
                .font(.subheadline.weight(.bold)).foregroundStyle(Color.lsuGold)
            Text("Based on \(l.postCount) loaded posts (\(l.pages)) · ▲\(l.totalUp) ▼\(l.totalDown)")
                .font(.caption).foregroundStyle(.secondary)
            Text("Top-voted posts (\(l.topPosts.count))").font(.footnote.weight(.semibold)).foregroundStyle(.white)
            if l.topPosts.isEmpty {
                Text("No upvoted posts yet.").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Tap a post to jump to it in the thread.").font(.caption2).foregroundStyle(.secondary)
            }
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(l.topPosts) { p in
                    Button { onOpen(p) } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(p.author).font(.footnote.weight(.bold)).foregroundStyle(.white)
                                    Text("p.\(p.page)").font(.caption2).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("▲\(p.up) ▼\(p.down)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Text(p.plainText).font(.footnote).foregroundStyle(Color(white: 0.8)).lineLimit(3)
                                    .multilineTextAlignment(.leading)
                            }
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .scaledPadding(h: 10, v: 8)
                        .contentShape(Rectangle())
                        .voteEdges(up: p.up, down: p.down)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens this post in the thread")
                }
            }
            if !l.activeUsers.isEmpty {
                Text("Most active posters").font(.footnote.weight(.semibold)).foregroundStyle(.white)
                Text(l.activeUsers.map { "\($0.0) (\($0.1))" }.joined(separator: " · ")).font(.footnote).foregroundStyle(Color(white: 0.8))
            }
            if !l.repliedTo.isEmpty {
                Text("Most replied-to").font(.footnote.weight(.semibold)).foregroundStyle(.white)
                Text(l.repliedTo.map { "\($0.0) (\($0.1))" }.joined(separator: " · ")).font(.footnote).foregroundStyle(Color(white: 0.8))
            }
        }
    }
}
