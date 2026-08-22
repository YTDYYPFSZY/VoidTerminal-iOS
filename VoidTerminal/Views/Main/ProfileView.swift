import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var chatVM: ChatViewModel
    @State private var showChangeUsername = false
    @State private var showChangePassword = false
    @State private var showFontSize = false
    @State private var showAdmin = false
    @State private var showServerConfig = false
    @State private var avatarItem: PhotosPickerItem?

    private let api = APIService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.vtBG.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // 标题
                        HStack {
                            Text("我的")
                                .font(.vt(size: 22, weight: .bold))
                                .foregroundColor(.vtText)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 10)

                        // 用户卡片
                        HStack(spacing: 16) {
                            PhotosPicker(selection: $avatarItem, matching: .images) {
                                ZStack(alignment: .bottomTrailing) {
                                    if let user = appState.currentUser {
                                        AvatarView(name: user.username, avatarURL: user.avatar, size: 60,
                                                   gradient: Gradient(colors: [Color(hex: "f59e0b"), Color(hex: "ef4444")]))
                                    }
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: "07c160"))
                                            .frame(width: 20, height: 20)
                                        Image(systemName: "camera.fill")
                                            .font(.vt(size: 10))
                                            .foregroundColor(.vtText)
                                    }
                                    .offset(x: 4, y: 4)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(appState.currentUser?.username ?? "")
                                        .font(.vt(size: 17, weight: .semibold))
                                        .foregroundColor(.vtText)
                                    if appState.isAdmin {
                                        Text("站长")
                                            .font(.vt(size: 10, weight: .semibold))
                                            .foregroundColor(.vtText)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(LinearGradient(colors: [Color(hex: "f59e0b"), Color(hex: "ef4444")], startPoint: .leading, endPoint: .trailing))
                                            .cornerRadius(4)
                                    }
                                }
                                Text("在线")
                                    .font(.vt(size: 12))
                                    .foregroundColor(Color(hex: "07c160"))
                            }
                            Spacer()
                        }
                        .padding(20)
                        .background(Color.vtPanel)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.vtBorder, lineWidth: 1))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                        // 菜单
                        VStack(spacing: 10) {
                            if appState.isAdmin || appState.currentUser?.isAdmin == true {
                                menuButton(title: "⚙ 站长管理", isAdmin: true) { showAdmin = true }
                            }
                            // 调试：显示管理员状态（正式版可移除）
                            HStack {
                                Text("管理员状态: \((appState.isAdmin || appState.currentUser?.isAdmin == true) ? "是" : "否")")
                                    .font(.vt(size: 12))
                                    .foregroundColor(.vtTextDim)
                                Spacer()
                                Button("刷新") {
                                    if let token = appState.token {
                                        WebSocketService.shared.connect(token: token)
                                    }
                                }
                                .font(.vt(size: 12))
                            }
                            .padding(.horizontal, 16)

                            menuButton(title: "日间 / 夜间模式") {
                                appState.theme = appState.theme == .dark ? .light : .dark
                            }

                            menuButton(title: "字体大小") { showFontSize = true }

                            menuButton(title: "更改用户名") { showChangeUsername = true }

                            menuButton(title: "更改密码") { showChangePassword = true }

                            menuButton(title: "服务器设置") { showServerConfig = true }

                            Button {
                                appState.logout()
                            } label: {
                                Text("退出登录")
                                    .font(.vt(size: 15))
                                    .foregroundColor(Color(hex: "e5484d"))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.vtPanel)
                                    .cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.vtBorder, lineWidth: 1))
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .navigationBarHidden(true)
            .onChange(of: avatarItem) { newValue in
                guard let newValue = newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self),
                       let token = appState.token {
                        do {
                            let avatar = try await api.uploadAvatar(token: token, imageData: data)
                            await MainActor.run {
                                appState.currentUser?.avatar = avatar
                            }
                        } catch {
                            chatVM.showToast(error.localizedDescription)
                        }
                    }
                }
            }
            .sheet(isPresented: $showChangeUsername) { ChangeUsernameView() }
            .sheet(isPresented: $showChangePassword) { ChangePasswordView() }
            .sheet(isPresented: $showFontSize) { FontSizeView() }
            .sheet(isPresented: $showAdmin) { AdminView().environmentObject(chatVM) }
            .sheet(isPresented: $showServerConfig) { ServerConfigView() }
        }
    }

    private func menuButton(title: String, isAdmin: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.vt(size: 15))
                    .foregroundColor(.vtText)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(Color.vtTextDim)
                    .font(.vt(size: 12))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isAdmin ? LinearGradient(colors: [Color(hex: "f59e0b"), Color(hex: "ef4444")], startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [Color.vtPanel], startPoint: .leading, endPoint: .trailing))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isAdmin ? Color.clear : Color.vtBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Change Username
struct ChangeUsernameView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var newUsername = ""
    @State private var message = ""
    @State private var isLoading = false
    private let api = APIService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("新用户名（2-20位）", text: $newUsername)
                        .autocapitalization(.none)
                        .onChange(of: newUsername) { v in
                            if v.count > 20 { newUsername = String(v.prefix(20)) }
                        }
                }
                if !message.isEmpty {
                    Text(message).foregroundColor(.red)
                }
                Section {
                    Button("确认更改") {
                        guard newUsername.count >= 2 else { message = "用户名至少2位"; return }
                        guard let token = appState.token else { return }
                        isLoading = true
                        Task {
                            do {
                                let user = try await api.changeUsername(token: token, newName: newUsername)
                                await MainActor.run {
                                    appState.currentUser = user
                                    dismiss()
                                }
                            } catch {
                                await MainActor.run {
                                    message = error.localizedDescription
                                    isLoading = false
                                }
                            }
                        }
                    }
                    .foregroundColor(Color(hex: "07c160"))
                    .disabled(isLoading)
                }
            }
            .navigationTitle("更改用户名")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Change Password
struct ChangePasswordView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var message = ""
    @State private var isLoading = false
    private let api = APIService.shared

    var body: some View {
        NavigationStack {
            Form {
                SecureField("当前密码", text: $oldPassword)
                SecureField("新密码（4-64位）", text: $newPassword)
                SecureField("确认新密码", text: $confirmPassword)
                if !message.isEmpty {
                    Text(message).foregroundColor(.red)
                }
                Button("确认更改") {
                    guard newPassword.count >= 4 else { message = "密码至少4位"; return }
                    guard newPassword == confirmPassword else { message = "两次密码不一致"; return }
                    guard let token = appState.token else { return }
                    isLoading = true
                    Task {
                        do {
                            try await api.changePassword(token: token, old: oldPassword, new: newPassword, confirm: confirmPassword)
                            await MainActor.run { dismiss() }
                        } catch {
                            await MainActor.run {
                                message = error.localizedDescription
                                isLoading = false
                            }
                        }
                    }
                }
                .foregroundColor(Color(hex: "07c160"))
                .disabled(isLoading)
            }
            .navigationTitle("更改密码")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Font Size
struct FontSizeView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach([("小", "sm"), ("标准", "md"), ("大", "lg"), ("特大", "xl")], id: \.1) { name, raw in
                        Button {
                            appState.fontSize = AppState.FontSize(rawValue: raw) ?? .md
                            dismiss()
                        } label: {
                            HStack {
                                Text(name).foregroundColor(.vtText)
                                Spacer()
                                if appState.fontSize.rawValue == raw {
                                    Image(systemName: "checkmark").foregroundColor(Color(hex: "07c160"))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("字体大小")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Admin
struct AdminView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var maxOnline = ""
    @State private var banUsername = ""
    @State private var unbanUsername = ""
    @State private var announceText = ""
    @State private var hallName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("在线人数上限") {
                    TextField("0表示不限制", text: $maxOnline)
                        .keyboardType(.numberPad)
                    Button("设置") {
                        if let n = Int(maxOnline) {
                            WebSocketService.shared.setMaxOnline(n)
                            chatVM.showToast("已设置")
                        }
                    }.foregroundColor(Color(hex: "07c160"))
                }
                Section("大厅管理") {
                    TextField("新大厅名称", text: $hallName)
                    Button("改名") {
                        if !hallName.isEmpty {
                            WebSocketService.shared.renameHall(name: hallName)
                            chatVM.showToast("已改名")
                        }
                    }.foregroundColor(Color(hex: "07c160"))
                    Button("清空大厅记录") {
                        WebSocketService.shared.clearHall()
                        chatVM.showToast("已清空")
                    }.foregroundColor(.red)
                }
                Section("用户管理") {
                    TextField("封禁用户名", text: $banUsername)
                    Button("封禁") {
                        if !banUsername.isEmpty {
                            WebSocketService.shared.banUser(username: banUsername)
                            banUsername = ""
                        }
                    }.foregroundColor(.red)
                    TextField("解封用户名", text: $unbanUsername)
                    Button("解封") {
                        if !unbanUsername.isEmpty {
                            WebSocketService.shared.unbanUser(username: unbanUsername)
                            unbanUsername = ""
                        }
                    }.foregroundColor(Color(hex: "07c160"))
                }
                Section("公告") {
                    TextField("公告内容", text: $announceText)
                    Button("发布公告") {
                        if !announceText.isEmpty {
                            WebSocketService.shared.announce(content: announceText)
                            announceText = ""
                            chatVM.showToast("已发布")
                        }
                    }.foregroundColor(Color(hex: "07c160"))
                }
            }
            .navigationTitle("站长管理")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
