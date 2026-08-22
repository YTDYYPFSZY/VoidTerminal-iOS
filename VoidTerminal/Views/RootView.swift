import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var chatVM = ChatViewModel()
    @State private var hasRestored = false
    @State private var isCheckingLogin = true
    @State private var fontTick = 0

    var body: some View {
        Group {
            if isCheckingLogin {
                SplashView()
            } else if appState.token != nil && appState.currentUser != nil {
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
                // 最短显示0.8秒启动页，避免闪一下
                try? await Task.sleep(nanoseconds: 800_000_000)
                isCheckingLogin = false
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
import SwiftUI

struct SplashView: View {
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            Color(hex: "0f1117").ignoresSafeArea()
            
            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(LinearGradient(
                            colors: [Color(hex: "07c160"), Color(hex: "0ea5e9")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.white)
                }
                .scaleEffect(scale)
                
                Text("虚空终端")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(opacity)
                
                Text("VoidTerminal")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
                    .opacity(opacity)
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .padding(.top, 20)
                    .opacity(opacity)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}
