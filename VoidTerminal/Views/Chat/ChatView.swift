import SwiftUI
import PhotosUI

struct ChatView: View {
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let room: ChatViewModel.RoomType

    @State private var messageText = ""
    @State private var draftImages: [UIImage] = []
    @State private var imagePicker: PhotosPickerItem?
    @State private var showImagePicker = false
    @State private var showGroupSettings = false
    @State private var showDeleteConfirm = false
    @State private var contextMenuMessage: ChatMessage?
    @State private var previewImageURL: String?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showMentionPanel = false
    @State private var mentionSearchText = ""
    @FocusState private var isInputFocused: Bool
    @State private var isSending = false
    @State private var lastSendAttemptTime: Date = .distantPast

    private let api = APIService.shared

    private var mentionUsers: [User] {
        switch room {
        case .group(let gid, _):
            if let group = chatVM.group(by: gid) {
                return group.members.compactMap { chatVM.user(by: $0) }
                    .filter { $0.id != chatVM.currentUserId }
            }
            return []
        case .dm(let peerId, _):
            if let peer = chatVM.user(by: peerId) { return [peer] }
            return []
        case .global:
            // 大厅不支持 @ 输入框弹出成员列表，改为长按头像@
            return []
        }
    }

    private var filteredMentionUsers: [User] {
        if mentionSearchText.isEmpty { return mentionUsers }
        return mentionUsers.filter { $0.username.lowercased().contains(mentionSearchText.lowercased()) }
    }

    var body: some View {
        VStack(spacing: 0) {
            chatHeader

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(messages) { msg in
                            messageRow(msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .onAppear {
                    scrollProxy = proxy
                    chatVM.currentRoom = room
                    // 进入聊天室日志
                    let roomDesc: String
                    switch room {
                    case .global: roomDesc = "global 大厅"
                    case .dm(_, let peerName): roomDesc = "dm \(peerName)"
                    case .group(_, let name): roomDesc = "group \(name)"
                    }
                    SecureLogger.shared.log("enter chat room: \(roomDesc)", module: "UI")
                    // 打开对话时滚动到最新消息
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let last = messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if showMentionPanel {
                mentionPanel
            }

            if !draftImages.isEmpty {
                draftImagesView
            }

            inputBar
        }
        .background(Color.vtBG.ignoresSafeArea())
        .navigationBarHidden(true)
        .sheet(isPresented: $showGroupSettings) {
            if case .group(let gid, _) = room, let group = chatVM.group(by: gid) {
                GroupSettingsView(group: group)
                    .environmentObject(chatVM)
            }
        }
        .confirmationDialog("消息操作", isPresented: Binding(
            get: { contextMenuMessage != nil },
            set: { if !$0 { contextMenuMessage = nil } }
        )) {
            if let msg = contextMenuMessage {
                if msg.isFromMe {
                    Button("撤回", role: .destructive) {
                        let roomDesc: String
                        switch room {
                        case .global: roomDesc = "global"
                        case .dm: roomDesc = "dm"
                        case .group: roomDesc = "group"
                        }
                        SecureLogger.shared.log("recall message room=\(roomDesc) id=\(msg.id)", module: "Chat")
                        chatVM.recallMessage(msg)
                        chatVM.removeMessageLocally(msg)
                        contextMenuMessage = nil
                    }
                }
                Button("复制") {
                    UIPasteboard.general.string = msg.content
                    contextMenuMessage = nil
                }
                Button("取消", role: .cancel) { contextMenuMessage = nil }
            }
        }
        .fullScreenCover(item: Binding(
            get: { previewImageURL.map { ImagePreviewURL(url: $0) } },
            set: { previewImageURL = $0?.url }
        )) { item in
            ImagePreviewView(url: item.url)
        }
        .photosPicker(isPresented: $showImagePicker, selection: $imagePicker, matching: .images)
        .onChange(of: imagePicker) { newValue in
            guard let newValue = newValue else { return }
            SecureLogger.shared.log("image picker selected", module: "UI")
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run { draftImages.append(image) }
                }
            }
            imagePicker = nil
        }
        .confirmationDialog("删除联系人", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) {
                if case .dm(let peerId, _) = room {
                    SecureLogger.shared.log("delete friend userId=\(peerId)", module: "Chat")
                    WebSocketService.shared.unfriend(userId: peerId)
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要删除该联系人吗？")
        }
    }

    private var mentionPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().frame(height: 1).foregroundColor(Color.vtBorder)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if filteredMentionUsers.isEmpty {
                        Text("无匹配用户")
                            .font(.vt(size: 14))
                            .foregroundColor(Color.vtTextDim)
                            .padding()
                    } else {
                        ForEach(filteredMentionUsers) { user in
                            Button {
                                insertMention(user.username)
                            } label: {
                                HStack(spacing: 10) {
                                    AvatarView(name: user.username, avatarURL: user.avatar, size: 32)
                                    Text(user.username)
                                        .font(.vt(size: 15))
                                        .foregroundColor(.vtText)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxHeight: 200)
            .background(Color.vtPanel)
        }
    }

    private func insertMention(_ username: String) {
        if let atRange = messageText.range(of: "@", options: .backwards) {
            messageText = String(messageText[..<atRange.lowerBound]) + "@" + username + " "
        } else {
            messageText += "@" + username + " "
        }
        showMentionPanel = false
        mentionSearchText = ""
    }

    private func handleTextChange(_ text: String) {
        messageText = text
        // 大厅（global）不支持 @ 弹出成员列表，只能长按头像@
        if case .global = room {
            showMentionPanel = false
            mentionSearchText = ""
            return
        }
        if let lastChar = text.last, lastChar == "@" {
            showMentionPanel = true
            mentionSearchText = ""
            return
        }
        if let atRange = text.range(of: "@", options: .backwards) {
            let afterAt = String(text[atRange.upperBound...])
            if !afterAt.contains(" ") && !afterAt.contains("\n") {
                showMentionPanel = true
                mentionSearchText = afterAt
                return
            }
        }
        showMentionPanel = false
        mentionSearchText = ""
    }

    private var chatHeader: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.vt(size: 20, weight: .semibold))
                    .foregroundColor(.vtText)
                    .padding(.horizontal, 8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(roomTitle)
                    .font(.vt(size: 16, weight: .semibold))
                    .foregroundColor(.vtText)
                    .lineLimit(1)
                if let sub = roomSubtitle {
                    Text(sub)
                        .font(.vt(size: 12))
                        .foregroundColor(Color.vtTextDim)
                }
            }
            Spacer()
            if case .group = room {
                Button { showGroupSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.vtText)
                        .padding(8)
                }
            }
            if case .dm = room {
                Button { showDeleteConfirm = true } label: {
                    Image(systemName: "person.fill.badge.minus")
                        .foregroundColor(Color(hex: "e5484d"))
                        .padding(8)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(Color.vtPanel)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.vtBorder), alignment: .bottom)
    }

    private var roomTitle: String {
        switch room {
        case .global: return appState.hallName
        case .dm(_, let name): return name
        case .group(_, let name): return name
        }
    }

    private var roomSubtitle: String? {
        switch room {
        case .global: return nil
        case .dm(let peerId, _): return chatVM.isOnline(peerId) ? "在线" : "离线"
        case .group(let gid, _):
            if let g = chatVM.group(by: gid) { return "\(g.members.count) 人" }
            return nil
        }
    }

    private var messages: [ChatMessage] {
        chatVM.messages(for: room)
    }

    private func messageRow(_ msg: ChatMessage) -> some View {
        let isMe = msg.isFromMe || msg.from == chatVM.currentUserId
        return HStack(alignment: .top, spacing: 10) {
            if isMe { Spacer(minLength: 40) }
            if !isMe {
                AvatarView(name: msg.fromName ?? "?", avatarURL: msg.fromAvatar, size: 36)
                    .onLongPressGesture(minimumDuration: 0.3) {
                        // 群聊 / 大厅：长按成员头像，自动@该成员
                        switch room {
                        case .group, .global:
                            guard let name = msg.fromName, !name.isEmpty, msg.from != "system" else { return }
                            if !messageText.isEmpty && !messageText.hasSuffix(" ") {
                                messageText += " "
                            }
                            messageText += "@" + name + " "
                            isInputFocused = true
                        default:
                            break
                        }
                    }
            }
            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                if !isMe, msg.from != "system", let name = msg.fromName, !name.isEmpty {
                    HStack(spacing: 4) {
                        Text(name)
                            .font(.vt(size: 12))
                            .foregroundColor(Color.vtTextDim)
                        if msg.fromBot == true {
                            Text("BOT")
                                .font(.vt(size: 9, weight: .bold))
                                .foregroundColor(Color(hex: "2563eb"))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.vtPanel2)
                                .cornerRadius(3)
                        }
                        if msg.fromRole == "admin" {
                            Text("站长")
                                .font(.vt(size: 9, weight: .bold))
                                .foregroundColor(Color(hex: "dc2626"))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color(hex: "fef2f2"))
                                .cornerRadius(3)
                        } else if case .group(let gid, _) = room,
                                  let group = chatVM.group(by: gid),
                                  group.owner == msg.from {
                            Text("群主")
                                .font(.vt(size: 9, weight: .bold))
                                .foregroundColor(Color(hex: "d97706"))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color(hex: "fffbeb"))
                                .cornerRadius(3)
                        }
                    }
                }
                messageBubble(msg, isMe: isMe)
                Text(formatMessageTime(msg.time))
                    .font(.vt(size: 10))
                    .foregroundColor(Color.vtTextDim.opacity(0.7))
            }
            if isMe {
                AvatarView(name: appState.currentUser?.username ?? "我", avatarURL: appState.currentUser?.avatar, size: 36,
                           gradient: Gradient(colors: [Color(hex: "f59e0b"), Color(hex: "ef4444")]))
            }
            if !isMe { Spacer(minLength: 40) }
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.4) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            contextMenuMessage = msg
        }
    }

    private func formatMessageTime(_ unix: Int) -> String {
        // 兼容秒和毫秒时间戳：大于1e12视为毫秒
        let ts = unix > 1_000_000_000_000 ? TimeInterval(unix) / 1000.0 : TimeInterval(unix)
        let date = Date(timeIntervalSince1970: ts)
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(date) {
            f.dateFormat = "HH:mm"
        } else if cal.isDateInYesterday(date) {
            f.dateFormat = "昨天 HH:mm"
        } else {
            f.dateFormat = "MM-dd HH:mm"
        }
        return f.string(from: date)
    }

    private func messageBubble(_ msg: ChatMessage, isMe: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !msg.content.isEmpty {
                mentionHighlightedText(msg.content, isMe: isMe)
            }
            if let images = msg.images, !images.isEmpty {
                messageImages(images, isMe: isMe)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(isMe ? Color(hex: "07c160") : Color.vtBorder)
        .cornerRadius(10)
    }

    private func mentionHighlightedText(_ text: String, isMe: Bool) -> some View {
        let normalColor = isMe ? Color(hex: "062") : Color.vtText
        let mentionColor = isMe ? Color.white.opacity(0.95) : Color(hex: "07c160")

        let pattern = "@([\\w\\u4e00-\\u9fa5]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return Text(text).font(.vt(size: 15)).foregroundColor(normalColor).fixedSize(horizontal: false, vertical: true)
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        var result = Text("").font(.vt(size: 15))
        var lastEnd = 0

        for match in matches {
            if match.range.location > lastEnd {
                let normal = nsText.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                result = result + Text(normal).foregroundColor(normalColor)
            }
            let mention = nsText.substring(with: match.range)
            result = result + Text(mention).foregroundColor(mentionColor).fontWeight(.semibold)
            lastEnd = match.range.location + match.range.length
        }
        if lastEnd < nsText.length {
            let remaining = nsText.substring(from: lastEnd)
            result = result + Text(remaining).foregroundColor(normalColor)
        }

        return result.fixedSize(horizontal: false, vertical: true)
    }

    private func messageImages(_ images: [String], isMe: Bool) -> some View {
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
                        .frame(width: images.count == 1 ? 160 : 70, height: images.count == 1 ? 160 : 70)
                        .clipped()
                        .cornerRadius(6)
                    }
                }
            }
        }
        .frame(maxWidth: images.count == 1 ? 160 : 220)
    }

    private var draftImagesView: some View {
        HStack(spacing: 8) {
            ForEach(Array(draftImages.enumerated()), id: \.offset) { idx, img in
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipped()
                        .cornerRadius(8)
                    Button {
                        draftImages.remove(at: idx)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.vtText)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .offset(x: 4, y: -4)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.vtPanel)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            Button { showImagePicker = true } label: {
                Image(systemName: "plus")
                    .font(.vt(size: 18, weight: .semibold))
                    .foregroundColor(.vtText)
                    .frame(width: 42, height: 42)
                    .background(Color.vtPanel2)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.vtBorder, lineWidth: 1))
            }

            TextField("输入消息，Enter发送，@提及用户", text: Binding(
                get: { messageText },
                set: { handleTextChange($0) }
            ), axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.vtBG)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.vtBorder, lineWidth: 1))
                .foregroundColor(.vtText)
                .focused($isInputFocused)
                .onSubmit { sendMessage() }

            Button { sendMessage() } label: {
                Text("发送")
                    .font(.vt(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "062"))
                    .padding(.horizontal, 18)
                    .frame(height: 42)
                    .background(Color(hex: "07c160"))
                    .cornerRadius(8)
            }
            .disabled((messageText.isEmpty && draftImages.isEmpty) || isSending)
            .opacity((messageText.isEmpty && draftImages.isEmpty) || isSending ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.vtPanel)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.vtBorder), alignment: .top)
    }

    private func sendMessage() {
        // 双层防重复：isSending 锁 + 时间戳防抖（2秒内不允许二次触发）
        let now = Date()
        guard !isSending else { return }
        guard now.timeIntervalSince(lastSendAttemptTime) >= 2.0 else { return }
        lastSendAttemptTime = now

        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !draftImages.isEmpty else { return }

        // 立即锁定 + 清空输入，防止重复发送
        isSending = true
        let currentText = text
        let currentImages = draftImages
        messageText = ""
        draftImages.removeAll()
        showMentionPanel = false
        mentionSearchText = ""

        if !currentImages.isEmpty {
            Task {
                var uploadedURLs: [String] = []
                for img in currentImages {
                    if let data = img.jpegData(compressionQuality: 0.8),
                       let token = appState.token {
                        do {
                            let url = try await api.uploadMessageImage(token: token, imageData: data)
                            uploadedURLs.append(url)
                        } catch {
                            await MainActor.run {
                                chatVM.showToast("图片上传失败: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                await MainActor.run {
                    chatVM.sendMessage(currentText, images: uploadedURLs)
                    // 图片消息等上传完成后再延迟解锁
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isSending = false
                    }
                }
            }
        } else {
            chatVM.sendMessage(currentText)
            // 纯文本消息延迟解锁，防止快速双击重复发送
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isSending = false
            }
        }
    }
}

struct ImagePreviewURL: Identifiable {
    let url: String
    var id: String { url }
}

struct ImagePreviewView: View {
    let url: String
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .onTapGesture { dismiss() }
        .task {
            if let u = URL(string: url) {
                image = await ImageCacheManager.shared.loadImage(from: u)
            }
        }
    }
}
