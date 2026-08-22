import SwiftUI

struct MessagesView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var appState: AppState
    @Binding var showMoments: Bool
    @State private var searchText = ""
    @State private var activeRoom: ChatViewModel.RoomType?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0f1117").ignoresSafeArea()

                VStack(spacing: 0) {
                    // 标题
                    HStack {
                        Text("消息")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                    // 搜索
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(Color(hex: "8a91a0"))
                        TextField("搜索会话", text: $searchText)
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(hex: "161a22"))
                    .cornerRadius(8)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                    // 会话列表
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // 公共大厅
                            convButton(
                                avatar: AnyView(
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(LinearGradient(colors: [Color(hex: "07c160"), Color(hex: "0ea5e9")], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        Image(systemName: "globe.asia.australia.fill")
                                            .foregroundColor(.white)
                                    }
                                    .frame(width: 44, height: 44)
                                ),
                                name: appState.hallName,
                                preview: lastGlobalPreview,
                                unread: 0
                            ) {
                                activeRoom = .global
                                chatVM.currentRoom = .global
                            }

                            // 好友验证
                            if !chatVM.pendingRequests.isEmpty {
                                convButton(
                                    avatar: AnyView(
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(LinearGradient(colors: [Color(hex: "07c160"), Color(hex: "3b82f6")], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            Text("验").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                                        }
                                        .frame(width: 44, height: 44)
                                    ),
                                    name: "好友验证",
                                    preview: "等待处理的验证请求",
                                    unread: chatVM.pendingRequests.count
                                ) {
                                    // 显示好友验证面板
                                }
                            }

                            // 群聊
                            if !filteredGroups.isEmpty {
                                sectionHeader("群聊")
                                ForEach(filteredGroups) { group in
                                    convButton(
                                        avatar: AnyView(AvatarView(name: group.name, avatarURL: group.avatar, size: 38)),
                                        name: group.name,
                                        preview: lastGroupPreview(gid: group.id),
                                        unread: 0
                                    ) {
                                        activeRoom = .group(gid: group.id, name: group.name)
                                        chatVM.currentRoom = .group(gid: group.id, name: group.name)
                                    }
                                }
                            }

                            // 好友
                            if !filteredFriends.isEmpty {
                                sectionHeader("好友")
                                ForEach(filteredFriends) { friend in
                                    convButton(
                                        avatar: AnyView(AvatarView(name: friend.username, avatarURL: friend.avatar, size: 38)),
                                        name: friend.username,
                                        preview: lastDMPreview(peerId: friend.id),
                                        unread: 0,
                                        showOnline: chatVM.isOnline(friend.id)
                                    ) {
                                        activeRoom = .dm(peerId: friend.id, peerName: friend.username)
                                        chatVM.currentRoom = .dm(peerId: friend.id, peerName: friend.username)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationBarHidden(true)
            .fullScreenCover(item: $activeRoom) { room in
                ChatView(room: room)
                    .environmentObject(chatVM)
                    .environmentObject(appState)
            }
        }
    }

    private var filteredGroups: [ChatGroup] {
        if searchText.isEmpty { return chatVM.groups }
        return chatVM.groups.filter { $0.name.contains(searchText) }
    }

    private var filteredFriends: [User] {
        if searchText.isEmpty { return chatVM.friends }
        return chatVM.friends.filter { $0.username.contains(searchText) }
    }

    private var lastGlobalPreview: String {
        guard let last = chatVM.globalMessages.last else { return "在这里畅所欲言" }
        return "\(last.fromName ?? ""): \(last.content)"
    }

    private func lastGroupPreview(gid: String) -> String {
        guard let last = chatVM.groupMessages[gid]?.last else { return "" }
        return "\(last.fromName ?? ""): \(last.content)"
    }

    private func lastDMPreview(peerId: String) -> String {
        let key = chatVM.dmRoomKey(chatVM.currentUserId, peerId)
        guard let last = chatVM.dmMessages[key]?.last else { return "" }
        return last.content
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "8a91a0"))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func convButton<AV: View>(avatar: AV, name: String, preview: String, unread: Int = 0, showOnline: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if showOnline {
                            Circle().fill(Color(hex: "07c160")).frame(width: 6, height: 6)
                        }
                        Spacer()
                        if unread > 0 {
                            Text("\(unread)")
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color(hex: "e5484d"))
                                .clipShape(Capsule())
                        }
                    }
                    Text(preview)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "8a91a0"))
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension ChatViewModel.RoomType: Identifiable {
    var id: String {
        switch self {
        case .global: return "global"
        case .dm(let peerId, _): return "dm_\(peerId)"
        case .group(let gid, _): return "group_\(gid)"
        }
    }
}
