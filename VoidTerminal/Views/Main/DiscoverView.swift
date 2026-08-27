import SwiftUI

struct DiscoverView: View {
    @Binding var showMoments: Bool
    @State private var showTomatoWarning = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.vtBG.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Text("发现")
                            .font(.vt(size: 22, weight: .bold))
                            .foregroundColor(.vtText)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                    ScrollView {
                        VStack(spacing: 8) {
                            discoverItem(icon: "朋", label: "朋友圈") {
                                SecureLogger.shared.log("tap moments entry", module: "UI")
                                withAnimation { showMoments = true }
                            }

                            discoverItem(icon: "书", label: "看番茄小说") {
                                SecureLogger.shared.log("tap tomato novel entry", module: "UI")
                                showTomatoWarning = true
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
            .navigationBarHidden(true)
            .alert("警告", isPresented: $showTomatoWarning) {
                Button("我确认", role: .destructive) {
                    if let url = URL(string: "http://Morax.kdns.fr") {
                        UIApplication.shared.open(url)
                    }
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("您将进入本站的同级网站，此站专注于看番茄小说和下载小说文件。账号密码并不同步，当您第一次进入时，请务必重新注册一个新账号。")
            }
        }
    }

    private func discoverItem(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [Color(hex: "3b82f6"), Color(hex: "8b5cf6")], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(icon)
                        .font(.vt(size: 18, weight: .bold))
                        .foregroundColor(.vtText)
                }
                .frame(width: 40, height: 40)
                Text(label)
                    .font(.vt(size: 16, weight: .medium))
                    .foregroundColor(.vtText)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(Color.vtTextDim)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.vtPanel)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
