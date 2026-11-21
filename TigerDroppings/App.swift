import SwiftUI

extension Color {
    static let lsuPurple = Color(red: 0x46/255, green: 0x1D/255, blue: 0x7C/255)
    static let lsuGold = Color(red: 0xFD/255, green: 0xD0/255, blue: 0x23/255)
}

@main
struct TigerDroppingsApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var rantPath = NavigationPath()
    @State private var rantModel = BoardModel(board: Boards.tigerRant, followsGameDay: true)
    @State private var auth = AuthModel.shared
    @State private var tab = UserDefaults.standard.integer(forKey: "demoTab")
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $rantPath) { ThreadListView(model: rantModel) }
                .onAppear {
                    // Debug hook for simulator testing: -demoThread /rant/board/slug/123/
                    if rantPath.isEmpty, let p = UserDefaults.standard.string(forKey: "demoThread") {
                        rantPath.append(ThreadSummary(id: Parser.first(#"/(\d+)/?$"#, in: p) ?? "demo", title: "Thread", path: p, author: "",
                                                      replies: UserDefaults.standard.integer(forKey: "demoReplies"),
                                                      lastPostTime: "", lastPostBy: "", pages: 1, sticky: false, boardName: nil))
                    }
                }
                .tabItem { Label(rantModel.showingScoreBoard ? "Score Board" : "Tiger Rant", systemImage: "pawprint.fill") }.tag(0)
            NavigationStack { ThreadListView(board: Boards.trending) }
                .tabItem { Label("Trending", systemImage: "flame.fill") }.tag(1)
            NavigationStack { BoardsView() }
                .tabItem { Label("Boards", systemImage: "list.bullet") }.tag(2)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
        }
        .tint(.lsuGold)
        .preferredColorScheme(.dark)
        .appTextSize()
        .sheet(isPresented: $auth.showLogin) { LoginView().appTextSize() }
        .onAppear { if UserDefaults.standard.bool(forKey: "demoLogin") { auth.showLogin = true } }
        .task { if AuthModel.shared.loggedIn { await AuthModel.shared.verify() } }
    }
}

struct BoardsView: View {
    var body: some View {
        List {
            ForEach(Boards.sections, id: \.0) { section in
                Section(section.0) {
                    ForEach(section.1) { b in
                        NavigationLink(value: b) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(b.name).font(.subheadline.weight(section.0 == "LSU" ? .bold : .regular))
                                if !b.subtitle.isEmpty {
                                    Text(b.subtitle).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .listRowBackground(section.0 == "LSU" ? Color.lsuPurple.opacity(0.35) : Color.black)
                    }
                }
            }
        }
        .environment(\.defaultMinListRowHeight, 32)
        .navigationTitle("Boards")
        .navigationDestination(for: Board.self) { ThreadListView(board: $0) }
    }
}

struct SettingsView: View {
    @AppStorage("tintThreadList") private var tintThreadList = true
    @AppStorage("showImages") private var showImages = true
    @State private var auth = AuthModel.shared
    var body: some View {
        Form {
            Section("TigerDroppings account") {
                if auth.loggedIn {
                    HStack {
                        Image(systemName: "person.crop.circle.fill").foregroundStyle(Color.lsuGold)
                        Text("Signed in as")
                        Text(auth.username ?? "your account").fontWeight(.bold)
                        Spacer()
                        if auth.checking { ProgressView() }
                    }
                    Button("Log Out", role: .destructive) { Task { await auth.logout() } }
                } else {
                    Button { auth.showLogin = true } label: {
                        Label("Sign in to reply and vote", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            }
            Section {
                TextSizeSettings()
                TextSizePreview()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.black)
            } header: {
                Text("Text size")
            } footer: {
                Text("Scales the whole app: posts, titles, buttons, spacing and vote bars.")
            }
            Section {
                Toggle("Tint thread list by first-post votes", isOn: $tintThreadList)
                Toggle("Show images in posts", isOn: $showImages)
            } footer: {
                Text("Thread lists on TigerDroppings don't show votes, so the app loads each thread's first post to color the row's edge bars. Turn off to save data.")
            }
            Section("Vote colors") {
                ForEach(Array([(20, 0), (10, 5), (3, 1), (6, 5), (0, 0), (5, 10), (5, 20)].enumerated()), id: \.offset) { _, pair in
                    let (u, d) = pair
                    HStack {
                        Text("\(u) up / \(d) down").font(.footnote.monospacedDigit()).foregroundStyle(.white)
                        Spacer()
                        Text(String(format: "%+.2f", VoteHeat.score(up: u, down: d))).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .scaledPadding(h: 10, v: 8)
                    .voteEdges(up: u, down: d)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.black)
                }
            }
            Section {
                Link("Open TigerDroppings.com", destination: TD.base)
            } footer: {
                Text("Unofficial read-only reader. Content © TigerDroppings.com.")
            }
        }
        .navigationTitle("Settings")
    }
}
