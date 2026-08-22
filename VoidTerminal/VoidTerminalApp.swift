import SwiftUI

@main
struct VoidTerminalApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(appState.theme == .dark ? .dark : .light)
        }
    }
}

// MARK: - App State
final class AppState: ObservableObject {
    @Published var token: String? {
        didSet {
            if let token = token {
                UserDefaults.standard.set(token, forKey: "vt_token")
            } else {
                UserDefaults.standard.removeObject(forKey: "vt_token")
            }
        }
    }
    @Published var currentUser: User?
    @Published var theme: Theme = .dark {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "vt_theme") }
    }
    @Published var fontSize: FontSize = .md {
        didSet { UserDefaults.standard.set(fontSize.rawValue, forKey: "vt_font") }
    }
    @Published var isAdmin: Bool = false
    @Published var hallName: String = "公共大厅"
    @Published var maxOnline: Int = 0

    private let ws = WebSocketService.shared
    private let api = APIService.shared

    enum Theme: String { case dark, light }
    enum FontSize: String { case sm, md, lg, xl }

    init() {
        self.token = UserDefaults.standard.string(forKey: "vt_token")
        if let themeStr = UserDefaults.standard.string(forKey: "vt_theme"),
           let t = Theme(rawValue: themeStr) { self.theme = t }
        if let fontStr = UserDefaults.standard.string(forKey: "vt_font"),
           let f = FontSize(rawValue: fontStr) { self.fontSize = f }
    }

    func restoreSession() async {
        guard let token = token else { return }
        do {
            let me = try await api.me(token: token)
            await MainActor.run {
                self.currentUser = me
            }
            // WebSocket连接统一在MainTabView.onAppear中建立，避免重复连接
        } catch {
            await MainActor.run { self.token = nil }
        }
    }

    func logout() {
        ws.disconnect()
        token = nil
        currentUser = nil
        isAdmin = false
    }
}
