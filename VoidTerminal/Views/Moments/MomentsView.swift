import SwiftUI
import PhotosUI

struct MomentsView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var showPostMoment = false
    @State private var commentMoment: Moment?
    @State private var commentText = ""
    @State private var previewImageURL: String?

    var body: some View {
        VStack(spacing: 0) {
            // 头部
            HStack(spacing: 10) {
                Button {
                    withAnimation { isPresented = false }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.vt(size: 20, weight: .semibold))
                        .foregroundColor(.vtText)
                        .padding(.horizontal, 8)
                }
                Text("朋友圈")
                    .font(.vt(size: 16, weight: .semibold))
                    .foregroundColor(.vtText)
                Spacer()
                Button { showPostMoment = true } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.vt(size: 18, weight: .semibold))
                        .foregroundColor(.vtText)
                        .padding(8)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .background(Color.vtPanel)
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color.vtBorder), alignment: .bottom)

            // 朋友圈列表
            ScrollView {
                LazyVStack(spacing: 12) {
                    if chatVM.moments.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.on.rectangle")
                                .font(.vt(size: 40))
                                .foregroundColor(Color.vtTextDim)
                            Text("还没有朋友圈内容")
                                .font(.vt(size: 14))
                                .foregroundColor(Color.vtTextDim)
                        }
                        .padding(.top, 60)
                    } else {
                        ForEach(chatVM.moments) { moment in
                            momentCard(moment)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .padding(.bottom, 20)
            }
        }
        .background(Color.vtBG.ignoresSafeArea())
        .sheet(isPresented: $showPostMoment) {
            PostMomentView()
                .environmentObject(chatVM)
                .environmentObject(appState)
        }
        .alert("评论", isPresented: Binding(
            get: { commentMoment != nil },
            set: { if !$0 { commentMoment = nil } }
        )) {
            TextField("写评论…", text: $commentText)
            Button("发送") {
                if let moment = commentMoment, !commentText.isEmpty {
                    WebSocketService.shared.momentComment(momentId: moment.id, text: commentText)
                    commentText = ""
                    commentMoment = nil
                }
            }
            Button("取消", role: .cancel) { commentMoment = nil }
        }
        .fullScreenCover(item: Binding(
            get: { previewImageURL.map { ImagePreviewURL(url: $0) } },
            set: { previewImageURL = $0?.url }
        )) { item in
            ImagePreviewView(url: item.url)
        }
    }

    private func momentCard(_ moment: Moment) -> some View {
        let authorName = moment.authorName ?? chatVM.user(by: moment.author)?.username ?? "未知用户"
        let authorAvatar = moment.authorAvatar ?? chatVM.user(by: moment.author)?.avatar
        let isMyMoment = moment.author == chatVM.currentUserId
        let isLiked = moment.likes.contains(chatVM.currentUserId)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                AvatarView(name: authorName, avatarURL: authorAvatar, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(authorName)
                        .font(.vt(size: 15, weight: .semibold))
                        .foregroundColor(.vtText)
                    Text(timeAgo(moment.time))
                        .font(.vt(size: 11))
                        .foregroundColor(Color.vtTextDim)
                }
                Spacer()
            }

            if !moment.text.isEmpty {
                Text(moment.text)
                    .font(.vt(size: 15))
                    .foregroundColor(.vtText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !moment.images.isEmpty {
                momentImages(moment.images)
            }

            // 点赞和评论
            HStack(spacing: 8) {
                Button {
                    WebSocketService.shared.momentLike(momentId: moment.id)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundColor(isLiked ? Color(hex: "07c160") : Color.vtTextDim)
                        Text("\(moment.likes.count)")
                            .font(.vt(size: 13))
                            .foregroundColor(Color.vtTextDim)
                    }
                }

                Button {
                    commentMoment = moment
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                            .foregroundColor(Color.vtTextDim)
                        Text("\(moment.comments.count)")
                            .font(.vt(size: 13))
                            .foregroundColor(Color.vtTextDim)
                    }
                }

                Spacer()

                if isMyMoment {
                    Button(role: .destructive) {
                        WebSocketService.shared.momentDelete(momentId: moment.id)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(Color(hex: "e5484d"))
                    }
                }
            }

            // 评论列表
            if !moment.comments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(moment.comments) { comment in
                        HStack(alignment: .top, spacing: 4) {
                            Text(comment.userName ?? comment.user)
                                .font(.vt(size: 13, weight: .semibold))
                                .foregroundColor(Color(hex: "07c160"))
                            Text(comment.text)
                                .font(.vt(size: 13))
                                .foregroundColor(.vtText)
                            Spacer()
                            if comment.user == chatVM.currentUserId || isMyMoment {
                                Button {
                                    WebSocketService.shared.momentCommentDelete(momentId: moment.id, commentId: comment.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.vt(size: 10))
                                        .foregroundColor(Color.vtTextDim)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(Color.vtPanel)
        .cornerRadius(12)
    }

    private func momentImages(_ images: [String]) -> some View {
        let columns = images.count == 1 ? [GridItem(.flexible())] :
                      images.count == 2 ? [GridItem(.flexible()), GridItem(.flexible())] :
                      [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, imgPath in
                let urlStr = imgPath.hasPrefix("http") ? imgPath : ServerConfig.shared.baseURL + imgPath
                Button {
                    previewImageURL = urlStr
                } label: {
                    if let url = URL(string: urlStr) {
                        CachedAsyncImage(
                            url: url,
                            contentMode: .fill,
                            placeholderColor: Color.gray.opacity(0.2)
                        )
                        .frame(width: images.count == 1 ? 200 : 90, height: images.count == 1 ? 200 : 90)
                        .clipped()
                        .cornerRadius(6)
                    }
                }
            }
        }
        .frame(maxWidth: images.count == 1 ? 200 : .infinity)
    }

    private func timeAgo(_ timestamp: Int) -> String {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let diff = now - timestamp
        let minute = 60 * 1000
        let hour = 60 * minute
        let day = 24 * hour

        if diff < minute { return "刚刚" }
        if diff < hour { return "\(diff / minute)分钟前" }
        if diff < day { return "\(diff / hour)小时前" }
        if diff < 7 * day { return "\(diff / day)天前" }

        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Post Moment
struct PostMomentView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var images: [UIImage] = []
    @State private var imagePicker: PhotosPickerItem?
    @State private var isLoading = false
    @State private var message = ""
    private let api = APIService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 100)
                        .foregroundColor(.vtText)
                        .onChange(of: text) { v in
                            if v.count > 2000 { text = String(v.prefix(2000)) }
                        }
                } header: {
                    Text("这一刻的想法…（\(text.count)/2000）")
                }

                Section("图片（最多9张）") {
                    if !images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(images.enumerated()), id: \.offset) { idx, img in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: img)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 70, height: 70)
                                            .clipped()
                                            .cornerRadius(8)
                                        Button {
                                            images.remove(at: idx)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.vtText)
                                                .background(Color.black.opacity(0.6))
                                                .clipShape(Circle())
                                        }
                                        .offset(x: 4, y: -4)
                                    }
                                }
                            }
                        }
                    }

                    PhotosPicker(selection: $imagePicker, matching: .images) {
                        HStack {
                            Image(systemName: "plus")
                            Text("添加图片")
                            Spacer()
                            Text("\(images.count)/9")
                                .foregroundColor(.gray)
                        }
                    }
                    .disabled(images.count >= 9)
                }

                if !message.isEmpty {
                    Text(message).foregroundColor(.red)
                }

                Section {
                    Button("发布") {
                        guard !text.isEmpty || !images.isEmpty else { message = "内容不能为空"; return }
                        isLoading = true
                        Task {
                            do {
                                var imageDataList: [Data] = []
                                for img in images {
                                    if let data = img.jpegData(compressionQuality: 0.8) {
                                        imageDataList.append(data)
                                    }
                                }
                                if let token = appState.token {
                                    _ = try await api.postMoment(token: token, text: text, images: imageDataList)
                                }
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
            }
            .navigationTitle("发布朋友圈")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onChange(of: imagePicker) { newValue in
                guard let newValue = newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       images.count < 9 {
                        await MainActor.run { images.append(image) }
                    }
                }
                imagePicker = nil
            }
        }
    }
}
