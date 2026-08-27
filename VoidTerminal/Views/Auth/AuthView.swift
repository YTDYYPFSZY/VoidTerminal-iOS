import SwiftUI

struct AuthView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var chatVM: ChatViewModel
    @State private var isLogin = true
    @State private var loginUsername = ""
    @State private var loginPassword = ""
    @State private var regUsername = ""
    @State private var regPassword = ""
    @State private var regPassword2 = ""
    @State private var message = ""
    @State private var isLoading = false
    @State private var showServerConfig = false

    private let api = APIService.shared

    var body: some View {
        ZStack {
            // 渐变背景
            Color.vtBG.ignoresSafeArea()
            RadialGradient(colors: [Color(hex: "07c160").opacity(0.08), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 400)
                .ignoresSafeArea()
            RadialGradient(colors: [Color(hex: "3b82f6").opacity(0.06), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 350)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                // Logo
                VStack(spacing: 8) {
                    Text("虚空终端")
                        .font(.vt(size: 30, weight: .bold))
                        .foregroundColor(.vtText)
                        .tracking(2)
                    Text("简约 · 轻量 · 随时聊天")
                        .font(.vt(size: 14))
                        .foregroundColor(Color.vtTextDim)
                }
                .padding(.bottom, 28)

                // 卡片
                VStack(spacing: 16) {
                    // Tab切换
                    HStack(spacing: 0) {
                        tabButton(title: "登录", isActive: isLogin) {
                            isLogin = true
                            message = ""
                        }
                        tabButton(title: "注册", isActive: !isLogin) {
                            isLogin = false
                            message = ""
                        }
                    }
                    .overlay(
                        Rectangle().frame(height: 1).foregroundColor(Color.vtBorder),
                        alignment: .bottom
                    )

                    if isLogin {
                        loginForm
                    } else {
                        registerForm
                    }
                }
                .padding(24)
                .background(Color.vtPanel)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.vtBorder, lineWidth: 1)
                )
                .padding(.horizontal, 20)

                Text("无需手机号与实名，注册即可开聊")
                    .font(.vt(size: 12))
                    .foregroundColor(Color.vtTextDim)
                    .padding(.top, 18)

                Spacer()

                // 服务器配置
                Button {
                    showServerConfig = true
                } label: {
                    Text("服务器设置")
                        .font(.vt(size: 12))
                        .foregroundColor(Color.vtTextDim)
                }
                .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $showServerConfig) {
            ServerConfigView()
        }
    }

    private func tabButton(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? Color(hex: "07c160") : Color.vtTextDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .overlay(
                    Rectangle().frame(height: 2).foregroundColor(isActive ? Color(hex: "07c160") : .clear),
                    alignment: .bottom
                )
        }
    }

    private var loginForm: some View {
        VStack(spacing: 12) {
            AppTextField(placeholder: "用户名", text: $loginUsername)
            AppTextField(placeholder: "密码", text: $loginPassword, isSecure: true)

            if !message.isEmpty {
                Text(message)
                    .font(.vt(size: 13))
                    .foregroundColor(Color(hex: "e5484d"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            PrimaryButton(title: isLoading ? "登录中..." : "登 录", action: doLogin, isDisabled: isLoading)
        }
    }

    private var registerForm: some View {
        VStack(spacing: 12) {
            AppTextField(placeholder: "用户名（2-20位字母/数字/中文）", text: $regUsername)
            AppTextField(placeholder: "密码（8-64位，需含字母和数字）", text: $regPassword, isSecure: true)
            AppTextField(placeholder: "确认密码", text: $regPassword2, isSecure: true)

            if !message.isEmpty {
                Text(message)
                    .font(.vt(size: 13))
                    .foregroundColor(Color(hex: "e5484d"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            PrimaryButton(title: isLoading ? "注册中..." : "注 册", action: doRegister, isDisabled: isLoading)

            Text("本站不支持找回密码，请妥善保管自己的密码。")
                .font(.vt(size: 12))
                .foregroundColor(Color.vtTextDim)
                .multilineTextAlignment(.center)
        }
    }

    private func doLogin() {
        guard !loginUsername.isEmpty, !loginPassword.isEmpty else {
            message = "请输入用户名和密码"
            return
        }
        isLoading = true
        message = ""
        SecureLogger.shared.log("login attempt: \(loginUsername)", module: "Auth")
        Task {
            do {
                let resp = try await api.login(username: loginUsername, password: loginPassword)
                SecureLogger.shared.log("login success: \(loginUsername)", module: "Auth")
                await MainActor.run {
                    appState.token = resp.token
                    appState.currentUser = resp.user
                    chatVM.setCurrentUserId(resp.user.id)
                    isLoading = false
                }
            } catch {
                SecureLogger.shared.log("login failed: \(error.localizedDescription)", level: .error, module: "Auth")
                await MainActor.run {
                    message = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func doRegister() {
        guard regUsername.count >= 2, regUsername.count <= 20 else {
            message = "用户名需为2-20位"
            return
        }
        let validation = PasswordValidator.validate(regPassword)
        guard validation.isValid else {
            message = validation.message ?? "密码不符合要求"
            return
        }
        guard regPassword == regPassword2 else {
            message = "两次密码不一致"
            return
        }
        isLoading = true
        message = ""
        SecureLogger.shared.log("register attempt: \(regUsername)", module: "Auth")
        Task {
            do {
                _ = try await api.register(username: regUsername, password: regPassword)
                SecureLogger.shared.log("register success: \(regUsername)", module: "Auth")
                await MainActor.run {
                    message = "注册成功，请登录"
                    isLogin = true
                    loginUsername = regUsername
                    isLoading = false
                }
            } catch {
                SecureLogger.shared.log("register failed: \(error.localizedDescription)", level: .error, module: "Auth")
                await MainActor.run {
                    message = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Server Config
struct ServerConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var serverURL: String = ServerConfig.shared.baseURL

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器地址") {
                    TextField("https://buer.kdns.fr", text: $serverURL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Text("WebSocket地址将自动推导：\(derivedWSURL)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Section {
                    Button("保存") {
                        ServerConfig.shared.baseURL = serverURL
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "07c160"))
                }
            }
            .navigationTitle("服务器设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var derivedWSURL: String {
        let http = serverURL
        if http.hasPrefix("https://") {
            return "wss://" + http.dropFirst(8) + "/ws"
        } else if http.hasPrefix("http://") {
            return "ws://" + http.dropFirst(7) + "/ws"
        }
        return "ws://" + http + "/ws"
    }
}
