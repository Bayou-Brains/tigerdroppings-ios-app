import SwiftUI
import WebKit
import Security

/// Session cookies for tigerdroppings.com are kept in the Keychain (never the password),
/// and mirrored into HTTPCookieStorage.shared so URLSession requests are authenticated.
enum CookieVault {
    private static let service = "com.danielarbour.tigerdroppings.session"
    private static let account = "cookies"

    static func save(_ cookies: [HTTPCookie]) {
        let props = cookies.compactMap { c -> [String: Any]? in
            guard var p = c.properties else { return nil }
            // Persist session cookies too, with a long expiry, so login survives relaunches.
            if p[.expires] == nil { p[.expires] = Date().addingTimeInterval(60 * 60 * 24 * 30) }
            return Dictionary(uniqueKeysWithValues: p.map { ($0.key.rawValue, $0.value) })
        }
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: props, requiringSecureCoding: false) else { return }
        clear()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecValueData as String: data,
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load() -> [HTTPCookie] {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
              let arr = (try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data)) as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            HTTPCookie(properties: Dictionary(uniqueKeysWithValues: d.map { (HTTPCookiePropertyKey($0.key), $0.value) }))
        }
    }

    static func clear() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}

@Observable
final class AuthModel {
    static let shared = AuthModel()
    var username: String? = UserDefaults.standard.string(forKey: "tdUsername")
    var loggedIn = false
    var showLogin = false
    var checking = false

    private init() {
        for c in CookieVault.load() { HTTPCookieStorage.shared.setCookie(c) }
        loggedIn = !CookieVault.load().isEmpty && username != nil
    }

    static func tdCookies(_ all: [HTTPCookie]) -> [HTTPCookie] {
        all.filter { $0.domain.contains("tigerdroppings.com") }
    }

    /// Ask for login (used by reply/vote taps while logged out). Returns true if already logged in.
    @MainActor func require() -> Bool {
        if loggedIn { return true }
        showLogin = true
        return false
    }

    /// Called by the login web view after each page load. Copies cookies and checks for a signed-in page.
    @MainActor func adoptWebSession(from store: WKHTTPCookieStore, capturedUser: String?) async -> Bool {
        let cookies = Self.tdCookies(await store.allCookies())
        for c in cookies { HTTPCookieStorage.shared.setCookie(c) }
        guard await verify() else { return false }
        if let u = capturedUser, !u.isEmpty { username = u }
        UserDefaults.standard.set(username, forKey: "tdUsername")
        CookieVault.save(Self.tdCookies(HTTPCookieStorage.shared.cookies ?? []))
        return true
    }

    /// Fetch the forums page with current cookies; logged-in pages have no "Sign In" link.
    @MainActor @discardableResult func verify() async -> Bool {
        checking = true; defer { checking = false }
        guard let html = try? await TD.fetch("/rant/forums.aspx") else { return loggedIn }
        let ok = Self.isSignedIn(html)
        loggedIn = ok
        if ok, username == nil, let u = Self.usernameFrom(html) { username = u; UserDefaults.standard.set(u, forKey: "tdUsername") }
        if ok { CookieVault.save(Self.tdCookies(HTTPCookieStorage.shared.cookies ?? [])) }
        return ok
    }

    static func isSignedIn(_ html: String) -> Bool {
        let signInLink = html.range(of: #"href="/users/login\.aspx"[^>]*>\s*Sign In"#, options: [.regularExpression, .caseInsensitive]) != nil
        let signOut = html.range(of: "Sign Out", options: .caseInsensitive) != nil
        return signOut || !signInLink
    }

    static func usernameFrom(_ html: String) -> String? {
        Parser.first(#"<div class="SignIn">.*?<a[^>]*>([^<]+)</a>"#, in: html).map(Parser.decode)
            .flatMap { $0.lowercased().contains("sign") ? nil : $0 }
    }

    @MainActor func logout() async {
        // Best effort: hit the site's sign-out link if we can find it.
        if let html = try? await TD.fetch("/rant/forums.aspx"),
           let href = Parser.first(#"<a[^>]*href="([^"]+)"[^>]*>\s*Sign Out\s*</a>"#, in: html) {
            _ = try? await TD.fetch(Parser.decode(href))
        }
        for c in Self.tdCookies(HTTPCookieStorage.shared.cookies ?? []) { HTTPCookieStorage.shared.deleteCookie(c) }
        let store = WKWebsiteDataStore.default()
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                               for: records.filter { $0.displayName.contains("tigerdroppings") })
        CookieVault.clear()
        UserDefaults.standard.removeObject(forKey: "tdUsername")
        username = nil
        loggedIn = false
    }
}

/// The real tigerdroppings.com login page in a web view. We only read the username field (to show it in Settings);
/// the password is typed into the site's own form and never touched by the app.
struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var status = "Sign in with your TigerDroppings account"
    @State private var done = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(status).font(.footnote).foregroundStyle(.secondary).padding(8)
                LoginWebView(status: $status, done: $done)
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: done) { _, d in if d { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }
}

struct LoginWebView: UIViewRepresentable {
    @Binding var status: String
    @Binding var done: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let js = """
        document.addEventListener('submit', function(){
          var u = document.querySelector('input[name=UserName]');
          if (u) { window.webkit.messageHandlers.td.postMessage(u.value); }
        }, true);
        document.addEventListener('click', function(e){
          if (e.target && e.target.name && e.target.name.indexOf('cmdSubmit') >= 0) {
            var u = document.querySelector('input[name=UserName]');
            if (u) { window.webkit.messageHandlers.td.postMessage(u.value); }
          }
        }, true);
        """
        cfg.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        cfg.userContentController.add(context.coordinator, name: "td")
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.customUserAgent = TD.userAgent
        // Seed the web view with any cookies we already have.
        let store = cfg.websiteDataStore.httpCookieStore
        for c in AuthModel.tdCookies(HTTPCookieStorage.shared.cookies ?? []) { store.setCookie(c) }
        wv.load(URLRequest(url: TD.url("/users/login.aspx")))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: LoginWebView
        var capturedUser: String?
        var submitted = false
        init(_ p: LoginWebView) { parent = p }

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            capturedUser = (message.body as? String)?.trimmingCharacters(in: .whitespaces)
            submitted = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let onLogin = webView.url?.path.lowercased().contains("login.aspx") ?? true
            guard submitted || !onLogin else { return }
            Task { @MainActor in
                parent.status = "Checking sign-in…"
                let ok = await AuthModel.shared.adoptWebSession(from: webView.configuration.websiteDataStore.httpCookieStore,
                                                                capturedUser: capturedUser)
                if ok {
                    parent.status = "Signed in"
                    parent.done = true
                } else {
                    // Show the site's own error text if the login page reports one.
                    let err = try? await webView.evaluateJavaScript(
                        "(function(){var e=document.querySelector('.error,.Error,.errmsg,.loginerror,font[color=red],span[style*=red]');return e?e.innerText:'';})()") as? String
                    parent.status = (err?.isEmpty == false) ? err! : "Not signed in yet"
                    submitted = false
                }
            }
        }
    }
}
