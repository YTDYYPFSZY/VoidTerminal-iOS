import SwiftUI

struct ContactsView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @State private var showAddFriend = false
    @State private var showCreateGroup = false
    @State private var showSearchGroup = false
    @State private var activeRoom: ChatViewModel.RoomType?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.vtBG.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // 标题
                        HStack {
                            Text("通讯录")
                                .font(.vt(size: 22, weight: .bold))
                                .foregroundColor(.vtText)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 10)

                        // 新的朋友
                        if !chatVM.pendingRequests.isEmpty {
                            contactRow(
                                icon: "验",
                                gradient: [Color(hex: "07c160"), Color(hex: "3b82f6")],
                                name: "新的朋友",
                                subtitle: "\(chatVM.pendingRequests.count) 条等待处理"
                            ) {
                                // 显示好友验证
                            }
                        }

                        // 添加好友
                        contactRow(
                            icon: "＋",
                            gradient: [Color(hex: "3b82f6"), Color(hex: "8b5cf6")],
                            name: "添加好友",
                            subtitle: nil
                        ) {
                            showAddFriend = true
                        }

                        // 创建群聊
                        contactRow(
                            icon: "群",
                            gradient: [Color(hex: "3b82f6"), Color(hex: "8b5cf6")],
                            name: "创建群聊",
                            subtitle: nil
                        ) {
                            showCreateGroup = true
                        }

                        // 搜索群聊
                        contactRow(
                            icon: "?",
                            gradient: [Color(hex: "07c160"), Color(hex: "0ea5e9")],
                            name: "搜索群聊",
                            subtitle: nil
                        ) {
                            showSearchGroup = true
                        }

                        // 群聊列表
                        if !chatVM.groups.isEmpty {
                            sectionHeader("群聊")
                            ForEach(chatVM.groups) { group in
                                contactRow(
                                    avatar: AvatarView(name: group.name, avatarURL: group.avatar, size: 40),
                                    name: group.name,
                                    subtitle: "\(group.members.count) 人"
                                ) {
                                    activeRoom = .group(gid: group.id, name: group.name)
                                    chatVM.currentRoom = .group(gid: group.id, name: group.name)
                                }
                            }
                        }

                        // 好友列表
                        if !chatVM.friends.isEmpty {
                            sectionHeader("好友")
                            ForEach(chatVM.friends) { friend in
                                contactRow(
                                    avatar: AvatarView(name: friend.username, avatarURL: friend.avatar, size: 40),
                                    name: friend.username,
                                    subtitle: chatVM.isOnline(friend.id) ? "在线" : "离线",
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
            .navigationBarHidden(true)
            .fullScreenCover(item: $activeRoom) { room in
                ChatView(room: room)
                    .environmentObject(chatVM)
            }
            .sheet(isPresented: $showAddFriend) {
                AddFriendView()
                    .environmentObject(chatVM)
            }
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupView()
                    .environmentObject(chatVM)
            }
            .sheet(isPresented: $showSearchGroup) {
                SearchGroupView()
                    .environmentObject(chatVM)
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.vt(size: 12))
                .foregroundColor(Color.vtTextDim)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func contactRow<AV: View>(avatar: AV, name: String, subtitle: String?, showOnline: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.vt(size: 15, weight: .medium))
                        .foregroundColor(.vtText)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.vt(size: 12))
                            .foregroundColor(showOnline ? Color(hex: "07c160") : Color.vtTextDim)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(Color.vtTextDim)
                    .font(.vt(size: 12))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func contactRow(icon: String, gradient: [Color], name: String, subtitle: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(icon).font(.vt(size: 18, weight: .semibold)).foregroundColor(.vtText)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.vt(size: 15, weight: .medium))
                        .foregroundColor(.vtText)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.vt(size: 12))
                            .foregroundColor(Color.vtTextDim)
                    }
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

// MARK: - Add Friend
struct AddFriendView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var message = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("输入对方用户名", text: $username)
                        .autocapitalization(.none)
                }
                if !message.isEmpty {
                    Section {
                        Text(message)
                            .foregroundColor(.red)
                    }
                }
                Section {
                    Button("发送验证") {
                        guard !username.isEmpty else { message = "请输入用户名"; return }
                        WebSocketService.shared.sendFriendRequest(username: username)
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "07c160"))
                }
            }
            .navigationTitle("添加好友")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Create Group
struct CreateGroupView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var groupName = ""
    @State private var selectedMembers = Set<String>()
    @State private var message = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("群名称") {
                    TextField("群名称（1-20位）", text: $groupName)
                        .onChange(of: groupName) { newValue in
                            if newValue.count > 20 { groupName = String(newValue.prefix(20)) }
                        }
                }
                Section("选择好友（至少1位）") {
                    ForEach(chatVM.friends) { friend in
                        Button {
                            if selectedMembers.contains(friend.id) {
                                selectedMembers.remove(friend.id)
                            } else {
                                selectedMembers.insert(friend.id)
                            }
                        } label: {
                            HStack {
                                AvatarView(name: friend.username, avatarURL: friend.avatar, size: 32)
                                Text(friend.username).foregroundColor(.vtText)
                                Spacer()
                                if selectedMembers.contains(friend.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color(hex: "07c160"))
                                }
                            }
                        }
                    }
                }
                if !message.isEmpty {
                    Text(message).foregroundColor(.red)
                }
                Section {
                    Button("创建") {
                        guard !groupName.isEmpty else { message = "请输入群名称"; return }
                        guard !selectedMembers.isEmpty else { message = "请至少选择一位好友"; return }
                        WebSocketService.shared.createGroup(name: groupName, members: Array(selectedMembers))
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "07c160"))
                }
            }
            .navigationTitle("创建群聊")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
