import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    @State private var showMoments = false

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                MessagesView(showMoments: $showMoments)
                    .tabItem {
                        Image(systemName: "message.fill")
                        Text("消息")
                    }
                    .tag(0)

                ContactsView()
                    .tabItem {
                        Image(systemName: "person.2.fill")
                        Text("通讯录")
                    }
                    .tag(1)

                DiscoverView(showMoments: $showMoments)
                    .tabItem {
                        Image(systemName: "safari.fill")
                        Text("发现")
                    }
                    .tag(2)

                ProfileView()
                    .tabItem {
                        Image(systemName: "person.fill")
                        Text("我的")
                    }
                    .tag(3)
            }
            .tint(Color(hex: "07c160"))

            // 朋友圈全屏覆盖
            if showMoments {
                MomentsView(isPresented: $showMoments)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .background(Color.vtBG.ignoresSafeArea())
        .onAppear {
            SecureLogger.shared.log("MainTabView onAppear", module: "App")
            // 确保进入主界面后建立WebSocket连接（此时ChatViewModel回调已就绪）
            if let token = appState.token {
                SecureLogger.shared.log("MainTabView: token found, connecting WebSocket", module: "App")
                WebSocketService.shared.connect(token: token)
            } else {
                SecureLogger.shared.log("MainTabView: no token, skip WebSocket", module: "App")
            }
        }
    }
}
