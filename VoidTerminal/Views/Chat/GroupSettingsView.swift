import SwiftUI
import PhotosUI

struct GroupSettingsView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    let group: ChatGroup

    @State private var showRename = false
    @State private var newName = ""
    @State private var showAddMembers = false
    @State private var avatarItem: PhotosPickerItem?
    @State private var message = ""

    var isOwner: Bool { group.owner == chatVM.currentUserId }

    var body: some View {
        NavigationStack {
            Form {
                // 群头像和名称
                Section {
                    HStack {
                        if isOwner {
                            PhotosPicker(selection: $avatarItem, matching: .images) {
                                AvatarView(name: group.name, avatarURL: group.avatar, size: 56)
                            }
                        } else {
                            AvatarView(name: group.name, avatarURL: group.avatar, size: 56)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name)
                                .font(.vt(size: 17, weight: .semibold))
                                .foregroundColor(.vtText)
                            Text("\(group.members.count) 人")
                                .font(.vt(size: 13))
                                .foregroundColor(Color.vtTextDim)
                        }
                        Spacer()
                    }
                }

                // 群成员
                Section("群成员") {
                    ForEach(group.members, id: \.self) { memberId in
                        if let member = chatVM.user(by: memberId) {
                            HStack {
                                AvatarView(name: member.username, avatarURL: member.avatar, size: 36)
                                Text(member.username)
                                    .foregroundColor(.vtText)
                                if memberId == group.owner {
                                    Text("群主")
                                        .font(.vt(size: 10, weight: .semibold))
                                        .foregroundColor(.vtText)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(LinearGradient(colors: [Color(hex: "07c160"), Color(hex: "0ea5e9")], startPoint: .leading, endPoint: .trailing))
                                        .cornerRadius(4)
                                }
                                Spacer()
                                if isOwner && memberId != group.owner {
                                    Button(role: .destructive) {
                                        SecureLogger.shared.log("remove member gid=\(group.id) userId=\(memberId)", module: "GroupSettings")
                                        WebSocketService.shared.groupRemoveMember(gid: group.id, userId: memberId)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        }
                    }
                }

                // 群主操作
                if isOwner {
                    Section("群管理") {
                        Button {
                            newName = group.name
                            showRename = true
                        } label: {
                            Text("修改群名称")
                                .foregroundColor(.vtText)
                        }

                        Button {
                            showAddMembers = true
                        } label: {
                            Text("添加成员")
                                .foregroundColor(.vtText)
                        }

                        Button(role: .destructive) {
                            SecureLogger.shared.log("dissolve group gid=\(group.id)", module: "GroupSettings")
                            WebSocketService.shared.groupDissolve(gid: group.id)
                            dismiss()
                        } label: {
                            Text("解散群聊")
                                .foregroundColor(.red)
                        }
                    }
                } else {
                    Section {
                        Button(role: .destructive) {
                            SecureLogger.shared.log("leave group gid=\(group.id)", module: "GroupSettings")
                            WebSocketService.shared.groupLeave(gid: group.id)
                            dismiss()
                        } label: {
                            Text("退出群聊")
                                .foregroundColor(.red)
                        }
                    }
                }

                if !message.isEmpty {
                    Text(message).foregroundColor(.red)
                }
            }
            .navigationTitle("群设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("修改群名称", isPresented: $showRename) {
                TextField("新群名称", text: $newName)
                    .onChange(of: newName) { v in
                        if v.count > 20 { newName = String(v.prefix(20)) }
                    }
                Button("确定") {
                    if !newName.isEmpty {
                        SecureLogger.shared.log("rename group gid=\(group.id) newName=\(newName)", module: "GroupSettings")
                        WebSocketService.shared.groupRename(gid: group.id, name: newName)
                    }
                }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showAddMembers) {
                AddGroupMembersView(group: group)
                    .environmentObject(chatVM)
            }
            .onChange(of: avatarItem) { newValue in
                guard let newValue = newValue else { return }
                SecureLogger.shared.log("change group avatar gid=\(group.id)", module: "GroupSettings")
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self),
                       let token = UserDefaults.standard.string(forKey: "vt_token") {
                        do {
                            _ = try await APIService.shared.uploadGroupAvatar(token: token, gid: group.id, imageData: data)
                            chatVM.showToast("群头像已更新")
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
            }
        }
    }
}

struct AddGroupMembersView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    let group: ChatGroup
    @State private var selected = Set<String>()

    var availableFriends: [User] {
        chatVM.friends.filter { !group.members.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("选择好友（未入群）") {
                    if availableFriends.isEmpty {
                        Text("没有可添加的好友")
                            .foregroundColor(.gray)
                    }
                    ForEach(availableFriends) { friend in
                        Button {
                            if selected.contains(friend.id) {
                                selected.remove(friend.id)
                            } else {
                                selected.insert(friend.id)
                            }
                        } label: {
                            HStack {
                                AvatarView(name: friend.username, avatarURL: friend.avatar, size: 36)
                                Text(friend.username).foregroundColor(.vtText)
                                Spacer()
                                if selected.contains(friend.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color(hex: "07c160"))
                                }
                            }
                        }
                    }
                }
                Section {
                    Button("确定添加") {
                        if !selected.isEmpty {
                            SecureLogger.shared.log("add members gid=\(group.id) count=\(selected.count)", module: "GroupSettings")
                            WebSocketService.shared.groupAddMembers(gid: group.id, members: Array(selected))
                            dismiss()
                        }
                    }
                    .foregroundColor(Color(hex: "07c160"))
                    .disabled(selected.isEmpty)
                }
            }
            .navigationTitle("添加成员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
