import SwiftUI

struct GroupRequestsView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                if chatVM.groupRequests.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 40))
                            .foregroundColor(.vtTextDim)
                        Text("暂无待处理的入群申请")
                            .font(.vt(size: 14))
                            .foregroundColor(.vtTextDim)
                    }
                } else {
                    List {
                        ForEach(chatVM.groupRequests) { req in
                            GroupRequestRow(req: req) { action in
                                chatVM.respondToGroupRequest(applyId: req.id, action: action)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.vtBG.ignoresSafeArea())
            .navigationTitle("群申请")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }
                        .foregroundColor(.vtText)
                }
            }
        }
    }
}

struct GroupRequestRow: View {
    let req: GroupRequest
    let onAction: (String) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 用户头像
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hex: "07c160"), Color(hex: "0ea5e9")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                Text(String((req.fromName ?? "?").prefix(1)))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(req.fromName ?? "未知用户")
                    .font(.vt(size: 15, weight: .semibold))
                    .foregroundColor(.vtText)
                Text("申请加入「\(req.groupName ?? "未知群")」")
                    .font(.vt(size: 12))
                    .foregroundColor(.vtTextDim)
            }
            
            Spacer()
            
            // 操作按钮
            HStack(spacing: 8) {
                Button {
                    onAction("accept")
                } label: {
                    Text("通过")
                        .font(.vt(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color(hex: "07c160"))
                        .cornerRadius(8)
                }
                Button {
                    onAction("deny")
                } label: {
                    Text("拒绝")
                        .font(.vt(size: 13, weight: .semibold))
                        .foregroundColor(.vtText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.vtPanel2)
                        .cornerRadius(8)
                }
            }
        }
        .padding(.vertical, 8)
        .listRowBackground(Color.vtBG)
    }
}
