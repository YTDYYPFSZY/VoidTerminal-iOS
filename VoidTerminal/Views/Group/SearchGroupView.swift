import SwiftUI

struct SearchGroupView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var appState: AppState
    @State private var keyword: String = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 搜索框
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.vtTextDim)
                    TextField("输入群名称关键词", text: $keyword)
                        .foregroundColor(.vtText)
                        .onSubmit {
                            chatVM.searchGroups(keyword: keyword)
                        }
                    if !keyword.isEmpty {
                        Button {
                            keyword = ""
                            chatVM.searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.vtTextDim)
                        }
                    }
                }
                .padding(12)
                .background(Color.vtPanel)
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                // 搜索按钮
                Button {
                    chatVM.searchGroups(keyword: keyword)
                } label: {
                    Text("搜索")
                        .font(.vt(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(keyword.isEmpty ? Color.vtTextDim : Color(hex: "07c160"))
                        .cornerRadius(10)
                }
                .disabled(keyword.isEmpty)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                // 搜索结果
                if chatVM.isSearching {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .vtText))
                    Spacer()
                } else if chatVM.searchResults.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.vtTextDim)
                        Text(keyword.isEmpty ? "输入关键词搜索群聊" : "未找到相关群聊")
                            .font(.vt(size: 14))
                            .foregroundColor(.vtTextDim)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(chatVM.searchResults) { group in
                                SearchGroupRow(group: group) {
                                    chatVM.applyToGroup(gid: group.id)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.vtBG.ignoresSafeArea())
            .navigationTitle("搜索群聊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundColor(.vtText)
                }
            }
        }
    }
}

struct SearchGroupRow: View {
    let group: SearchGroup
    let onApply: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 群头像
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(
                        colors: [Color(hex: "07c160"), Color(hex: "0ea5e9")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                Text(String(group.name.prefix(1)))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // 群信息
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.vt(size: 15, weight: .semibold))
                    .foregroundColor(.vtText)
                    .lineLimit(1)
                Text("\(group.memberCount ?? 0)人 · 群主: \(group.ownerName ?? "未知")")
                    .font(.vt(size: 12))
                    .foregroundColor(.vtTextDim)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 申请按钮
            Button(action: onApply) {
                Text("申请加入")
                    .font(.vt(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color(hex: "07c160"))
                    .cornerRadius(8)
            }
        }
        .padding(12)
        .background(Color.vtPanel)
        .cornerRadius(12)
    }
}
