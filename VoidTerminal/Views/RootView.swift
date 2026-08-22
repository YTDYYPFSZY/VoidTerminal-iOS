import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var chatVM = ChatViewModel()
    @State private var hasRestored = false
    @State private var fontTick = 0

    var body: some View {
        Group {
            if appState.token != nil && appState.currentUser != nil {
                MainTabView()
                    .environmentObject(chatVM)
            } else {
                AuthView()
                    .environmentObject(chatVM)
            }
        }
        .id(fontTick)
        .onReceive(NotificationCenter.default.publisher(for: .fontSizeChanged)) { _ in
            fontTick += 1
        }
        .onChange(of: appState.currentUser) { newUser in
            if let user = newUser {
                chatVM.setCurrentUserId(user.id)
            }
        }
        .overlay(
            VStack {
                if let toast = chatVM.toast {
                    ToastView(message: toast)
                    Spacer()
                }
            }
        )
        .task {
            if !hasRestored {
                hasRestored = true
                await appState.restoreSession()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .userBanned)) { _ in
            appState.logout()
        }
        .onReceive(NotificationCenter.default.publisher(for: .userKicked)) { _ in
            appState.logout()
        }
        .onReceive(NotificationCenter.default.publisher(for: .adminStatusUpdate)) { note in
            if let admin = note.object as? Bool {
                appState.isAdmin = admin
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hallRenamed)) { note in
            if let name = note.object as? String {
                appState.hallName = name
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .maxOnlineUpdate)) { note in
            if let max = note.object as? Int {
                appState.maxOnline = max
            }
        }
    }
}
