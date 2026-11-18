import Foundation

struct SiteError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Posting {
    // MARK: Votes
    /// The site's own vote call (mb_display_v35.js processvote): GET /rant/useraction.aspx?beta=1&pID=<anchor id>.
    /// Returns JSON {PostID, Dupl, IsFeat, IsRWD}; Dupl == 1 means you'd already voted on that post.
    struct VoteResult { let duplicate: Bool }

    static func vote(token: String) async throws -> VoteResult {
        let path = "/rant/useraction.aspx?beta=1&pID=" + (token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token)
        let body = try await TD.fetch(path)
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if !AuthModel.isSignedIn(body) { throw SiteError(message: "You're signed out. Sign in again to vote.") }
            let text = Parser.decode(Parser.stripTags(body)).trimmingCharacters(in: .whitespacesAndNewlines)
            throw SiteError(message: text.isEmpty ? "The site didn't accept the vote." : String(text.prefix(200)))
        }
        let dupl = (json["Dupl"] as? Int) ?? Int("\(json["Dupl"] ?? 0)") ?? 0
        return VoteResult(duplicate: dupl != 0)
    }

    // MARK: Replies
    /// Replies use the site's own reply page (/rant/message.aspx?action=create&p=<post id>), an ASP.NET WebForms page.
    /// We load the form with the session cookies, keep every field it gives us (__VIEWSTATE, __EVENTVALIDATION, subject…),
    /// put the message in its textarea and submit it with the form's post button, exactly like the browser.
    static func reply(toPost postId: String, message: String) async throws {
        let formPath = "/rant/message.aspx?action=create&p=\(postId)"
        let html = try await TD.fetch(formPath)
        if html.range(of: "must be logged on", options: .caseInsensitive) != nil || !AuthModel.isSignedIn(html) {
            await MainActor.run { AuthModel.shared.loggedIn = false }
            throw SiteError(message: "You're signed out. Sign in again to reply.")
        }
        guard let form = HTMLForm.parse(html, preferring: "aspnetForm") else {
            throw SiteError(message: siteMessage(html) ?? "Couldn't find the reply form on the site.")
        }
        guard let bodyField = form.messageField else { throw SiteError(message: "Couldn't find the message box on the reply form.") }
        var fields = form.fields
        fields[bodyField] = message
        if let (name, value) = form.submitButton { fields[name] = value }

        let pageURL = TD.url(formPath)
        let postURL = form.action.flatMap { URL(string: $0, relativeTo: pageURL)?.absoluteURL } ?? pageURL
        var req = URLRequest(url: postURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(TD.url(formPath).absoluteString, forHTTPHeaderField: "Referer")
        req.setValue(TD.base.absoluteString, forHTTPHeaderField: "Origin")
        req.httpBody = HTMLForm.encode(fields, order: form.order + [bodyField]).data(using: .utf8)
        let (data, resp) = try await TD.session.data(for: req)
        let out = String(decoding: data, as: UTF8.self)
        let finalURL = (resp as? HTTPURLResponse)?.url?.absoluteString ?? ""
        if let h = resp as? HTTPURLResponse, h.statusCode >= 400 { throw SiteError(message: "The site returned HTTP \(h.statusCode).") }
        // Success: the site leaves the message page (redirects to the thread). Still on the form = an error.
        let stillOnForm = finalURL.contains("message.aspx") && out.contains(bodyField)
        if stillOnForm || out.range(of: "Duplicate post", options: .caseInsensitive) != nil {
            throw SiteError(message: siteMessage(out) ?? "The site didn't accept the reply.")
        }
    }

    /// Pulls a human-readable error from a WebForms page (validation summaries, red text, "Duplicate post?").
    static func siteMessage(_ html: String) -> String? {
        let patterns = [#"<span[^>]*id="[^"]*(?:lbl|Label)?(?:Error|Err|Msg|Message)[^"]*"[^>]*>(.*?)</span>"#,
                        #"<div[^>]*class="[^"]*(?:error|validation|alert|warn)[^"]*"[^>]*>(.*?)</div>"#,
                        #"<font[^>]*color="?red"?[^>]*>(.*?)</font>"#,
                        #"<span[^>]*style="[^"]*color:\s*red[^"]*"[^>]*>(.*?)</span>"#,
                        #"(Duplicate post\??)"#,
                        #"(You must be logged on[^<]*)"#]
        for p in patterns {
            for m in Parser.all(p, in: html) {
                let t = Parser.decode(Parser.stripTags(m[1] ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty && t.count < 300 { return t }
            }
        }
        return nil
    }

    static func quoteBlock(_ post: Post) -> String {
        var text = post.blocks.compactMap { b -> String? in
            if case .text(let a) = b { return String(a.characters) }
            return nil
        }.joined(separator: "\n")
        if text.count > 600 { text = String(text.prefix(600)) + "…" }
        return "[quote]\(text)[/quote]\n"
    }
}

/// Minimal HTML form reader for the reply page.
struct HTMLForm {
    var action: String?
    var fields: [String: String] = [:]
    var order: [String] = []
    var textareas: [(name: String, rows: Int)] = []
    var submits: [(name: String, value: String)] = []

    var messageField: String? {
        if let t = textareas.first(where: { $0.name.range(of: "message|body|post|txt", options: [.regularExpression, .caseInsensitive]) != nil }) { return t.name }
        return textareas.max(by: { $0.rows < $1.rows })?.name
    }

    var submitButton: (String, String)? {
        let good = submits.first { s in
            s.value.range(of: "post|submit|reply|send", options: [.regularExpression, .caseInsensitive]) != nil &&
            s.value.range(of: "preview|cancel|spell", options: [.regularExpression, .caseInsensitive]) == nil
        } ?? submits.first { $0.value.range(of: "preview|cancel", options: [.regularExpression, .caseInsensitive]) == nil }
        return good.map { ($0.name, $0.value) }
    }

    static func attr(_ name: String, _ tag: String) -> String? {
        Parser.first(#"\b"# + name + #"\s*=\s*"([^"]*)""#, in: tag)
            ?? Parser.first(#"\b"# + name + #"\s*=\s*'([^']*)'"#, in: tag)
            ?? Parser.first(#"\b"# + name + #"\s*=\s*([^\s>"']+)"#, in: tag)
    }

    static func parse(_ html: String, preferring id: String) -> HTMLForm? {
        let forms = Parser.all(#"(<form[^>]*>)(.*?)</form>"#, in: html)
        guard let f = forms.first(where: { ($0[1] ?? "").contains(id) }) ?? forms.first,
              let open = f[1], let inner = f[2] else { return nil }
        var form = HTMLForm()
        form.action = attr("action", open).map(Parser.decode)
        for m in Parser.all(#"<input\b[^>]*>"#, in: inner) {
            let tag = m[0] ?? ""
            guard let name = attr("name", tag) else { continue }
            let type = (attr("type", tag) ?? "text").lowercased()
            let value = Parser.decode(attr("value", tag) ?? "")
            switch type {
            case "submit": form.submits.append((name, value))
            case "button", "image", "file", "reset": continue
            case "checkbox", "radio":
                if tag.range(of: #"\bchecked\b"#, options: .regularExpression) != nil { form.set(name, value.isEmpty ? "on" : value) }
            default: form.set(name, value)
            }
        }
        for m in Parser.all(#"(<textarea\b[^>]*>)(.*?)</textarea>"#, in: inner) {
            guard let tag = m[1], let name = attr("name", tag) else { continue }
            form.textareas.append((name, Int(attr("rows", tag) ?? "") ?? 0))
            form.set(name, Parser.decode(m[2] ?? ""))
        }
        for m in Parser.all(#"(<select\b[^>]*>)(.*?)</select>"#, in: inner) {
            guard let tag = m[1], let name = attr("name", tag) else { continue }
            let opts = Parser.all(#"<option\b[^>]*>"#, in: m[2] ?? "").compactMap { $0[0] }
            let sel = opts.first { $0.range(of: #"\bselected\b"#, options: .regularExpression) != nil } ?? opts.first
            form.set(name, Parser.decode(sel.flatMap { attr("value", $0) } ?? ""))
        }
        return form
    }

    mutating func set(_ k: String, _ v: String) {
        if fields[k] == nil { order.append(k) }
        fields[k] = v
    }

    static func encode(_ fields: [String: String], order: [String]) -> String {
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._*")
        func enc(_ s: String) -> String {
            (s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s).replacingOccurrences(of: "%20", with: "+")
        }
        var seen = Set<String>(); var keys: [String] = []
        for k in order + fields.keys.sorted() where !seen.contains(k) && fields[k] != nil { seen.insert(k); keys.append(k) }
        return keys.map { "\(enc($0))=\(enc(fields[$0]!))" }.joined(separator: "&")
    }
}
