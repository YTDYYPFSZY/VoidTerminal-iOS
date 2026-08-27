import Foundation
import SwiftUI

// MARK: - Chat ViewModel
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var globalMessages: [ChatMessage] = []
    @Published var dmMessages: [String: [ChatMessage]] = [:] // roomKey
    @Published var groupMessages: [String: [ChatMessage]] = [:] // gid
    @Published var groups: [ChatGroup] = []
    @Published var friends: [User] = []
    @Published var knownUsers: [String: User] = [:]  // 所有已知用户（含群成员，非好友）
    @Published var pendingRequests: [FriendRequest] = []
    @Published var moments: [Moment] = []
    @Published var onlineUsers: Set<String> = []
    @Published var toast: String?
    @Published var currentRoom: RoomType?
    @Published var searchResults: [SearchGroup] = []
    @Published var groupRequests: [GroupRequest] = []
    @Published var isSearching: Bool = false
    @Published var announcement: String = ""

    private let ws = WebSocketService.shared
    private let api = APIService.shared
    private var currentUserName: String = "我"

    // 发送防重复：记录最近一次发送的内容摘要和时间戳
    private var lastSentContentHash: String = ""
    private var lastSentTimestamp: Int = 0

    enum RoomType: Hashable {
        case global
        case dm(peerId: String, peerName: String)
        case group(gid: String, name: String)
    }

    init() {
        setupCallbacks()
        loadFromLocal()
    }
    
    // MARK: - Local Persistence (AES-GCM 加密存储)
    private func loadFromLocal() {
        let storage = SecureStorage.shared
        if let list = storage.load([User].self, forKey: "vt_friends") {
            friends = list
        }
        if let list = storage.load([ChatGroup].self, forKey: "vt_groups") {
            groups = list
        }
        if let list = storage.load([ChatMessage].self, forKey: "vt_global_msgs") {
            globalMessages = list
        }
        if let dict = storage.load([String: [ChatMessage]].self, forKey: "vt_dm_msgs") {
            dmMessages = dict
        }
        if let dict = storage.load([String: [ChatMessage]].self, forKey: "vt_group_msgs") {
            groupMessages = dict
        }
        // vt_current_uid 不含敏感数据，继续明文存储
        if let uid = UserDefaults.standard.string(forKey: "vt_current_uid") {
            setCurrentUserId(uid)
        }
        SecureLogger.shared.log("local storage loaded: friends=\(friends.count) groups=\(groups.count) globalMsgs=\(globalMessages.count) dmRooms=\(dmMessages.count) groupMsgs=\(groupMessages.count)", module: "Chat")
    }
    private func saveToLocal() {
        let storage = SecureStorage.shared
        storage.save(friends, forKey: "vt_friends")
        storage.save(groups, forKey: "vt_groups")
        storage.save(globalMessages, forKey: "vt_global_msgs")
        storage.save(dmMessages, forKey: "vt_dm_msgs")
        storage.save(groupMessages, forKey: "vt_group_msgs")
    }

    private func setupCallbacks() {
        ws.onHello = { [weak self] msg in
            Task { @MainActor in
                self?.handleHello(msg)
            }
        }
        ws.onGlobalMessage = { [weak self] msg in
            Task { @MainActor in
                guard let self = self else { return }
                self.registerUser(from: msg)
                var m = msg
                m.isFromMe = (m.from == self.currentUserId)
                // 去重：收到自己的消息时，移除所有临时消息
                if m.from == self.currentUserId {
                    self.globalMessages.removeAll { $0.id.hasPrefix("temp_") }
                }
                if !self.globalMessages.contains(where: { $0.id == m.id }) {
                    self.globalMessages.append(m)
                }
                if self.globalMessages.count > 500 {
                    self.globalMessages = Array(self.globalMessages.suffix(500))
                }
                self.saveToLocal()
            }
        }
        ws.onDMMessage = { [weak self] msg in
            Task { @MainActor in
                guard let self = self else { return }
                self.registerUser(from: msg)
                var m = msg
                m.isFromMe = (m.from == self.currentUserId)
                let peer = m.from == self.currentUserId ? (m.to ?? "") : m.from
                let key = self.dmRoomKey(self.currentUserId, peer)
                if self.dmMessages[key] == nil { self.dmMessages[key] = [] }
                // 去重：收到自己的消息时，移除所有临时消息
                if m.from == self.currentUserId {
                    self.dmMessages[key]?.removeAll { $0.id.hasPrefix("temp_") }
                }
                if !(self.dmMessages[key]?.contains(where: { $0.id == m.id }) ?? false) {
                    self.dmMessages[key]?.append(m)
                }
                self.saveToLocal()
            }
        }
        ws.onGroupMessage = { [weak self] msg in
            Task { @MainActor in
                guard let self = self, let gid = msg.gid else { return }
                self.registerUser(from: msg)
                var m = msg
                m.isFromMe = (m.from == self.currentUserId)
                if self.groupMessages[gid] == nil { self.groupMessages[gid] = [] }
                // 去重：收到自己的消息时，移除所有临时消息
                if m.from == self.currentUserId {
                    self.groupMessages[gid]?.removeAll { $0.id.hasPrefix("temp_") }
                }
                if !(self.groupMessages[gid]?.contains(where: { $0.id == m.id }) ?? false) {
                    self.groupMessages[gid]?.append(m)
                }
                self.saveToLocal()
            }
        }
        ws.onRecalled = { [weak self] room, id, to, gid in
            Task { @MainActor in
                switch room {
                case "global":
                    self?.globalMessages.removeAll { $0.id == id }
                case "dm":
                    if let to = to, let self = self {
                        let key = self.dmRoomKey(self.currentUserId, to)
                        self.dmMessages[key]?.removeAll { $0.id == id }
                    }
                case "group":
                    if let gid = gid {
                        self?.groupMessages[gid]?.removeAll { $0.id == id }
                    }
                default: break
                }
            }
        }
        ws.onError = { [weak self] err in
            Task { @MainActor in self?.showToast(err) }
        }
        ws.onBanned = { [weak self] err in
            Task { @MainActor in
                self?.showToast(err)
                NotificationCenter.default.post(name: .userBanned, object: nil)
            }
        }
        ws.onKicked = { [weak self] err in
            Task { @MainActor in
                self?.showToast(err)
                NotificationCenter.default.post(name: .userKicked, object: nil)
            }
        }
        ws.onSystem = { [weak self] content in
            Task { @MainActor in self?.showToast(content) }
        }
        ws.onPresence = { [weak self] ids in
            Task { @MainActor in
                self?.onlineUsers = Set(ids)
            }
        }
        ws.onAnnouncementUpdate = { [weak self] ann in
            Task { @MainActor in
                if !ann.isEmpty {
                    self?.announcement = ann
                }
            }
        }
        ws.onFriendRequest = { [weak self] req in
            Task { @MainActor in
                if !(self?.pendingRequests.contains { $0.id == req.id } ?? false) {
                    self?.pendingRequests.append(req)
                }
            }
        }
        ws.onFriendUpdate = { [weak self] list in
            Task { @MainActor in
                self?.friends = list
                self?.saveToLocal()
            }
        }
        ws.onRequestSent = { [weak self] ok, error in
            Task { @MainActor in
                self?.showToast(ok ? "验证请求已发送" : (error ?? "发送失败"))
            }
        }
        ws.onGroupCreated = { [weak self] group in
            Task { @MainActor in
                var g = group
                g.isOwner = true
                self?.groups.append(g)
                self?.registerGroupMembers(g)
                self?.showToast("群聊「\(group.name)」已创建")
            }
        }
        ws.onGroupRemoved = { [weak self] gid, error in
            Task { @MainActor in
                self?.groups.removeAll { $0.id == gid }
                self?.groupMessages.removeValue(forKey: gid)
                self?.showToast(error)
            }
        }
        ws.onGroupDissolved = { [weak self] gid in
            Task { @MainActor in
                self?.groups.removeAll { $0.id == gid }
                self?.groupMessages.removeValue(forKey: gid)
                self?.showToast("群聊已解散")
            }
        }
        ws.onGroupRenamed = { [weak self] gid, group in
            Task { @MainActor in
                if let idx = self?.groups.firstIndex(where: { $0.id == gid }) {
                    self?.groups[idx].name = group.name
                }
            }
        }
        ws.onGroupMemberRemoved = { [weak self] gid, group, userId in
            Task { @MainActor in
                if let idx = self?.groups.firstIndex(where: { $0.id == gid }) {
                    self?.groups[idx].members = group.members
                }
            }
        }
        ws.onGroupAvatarUpdated = { [weak self] gid, avatar in
            Task { @MainActor in
                if let idx = self?.groups.firstIndex(where: { $0.id == gid }) {
                    self?.groups[idx].avatar = avatar
                }
            }
        }
        ws.onMomentsUpdate = { [weak self] list in
            Task { @MainActor in
                // 按时间倒序排列（最新的在最上面）
                self?.moments = list.sorted { $0.time > $1.time }
            }
        }
        ws.onMomentPosted = { [weak self] moment in
            Task { @MainActor in
                // 将新朋友圈插入到列表开头
                if !((self?.moments.contains(where: { $0.id == moment.id })) ?? true) {
                    self?.moments.insert(moment, at: 0)
                }
            }
        }
        ws.onHallRenamed = { [weak self] name in
            Task { @MainActor in
                NotificationCenter.default.post(name: .hallRenamed, object: name)
            }
        }
        ws.onHallCleared = { [weak self] in
            Task { @MainActor in self?.globalMessages.removeAll() }
        }
        ws.onGroupApplySent = { [weak self] gid in
            Task { @MainActor in
                self?.showToast("申请已发送，请等待群主审批")
            }
        }
        ws.onGroupApplyRequest = { [weak self] apply in
            Task { @MainActor in
                if !(self?.groupRequests.contains { $0.id == apply.id } ?? false) {
                    self?.groupRequests.append(apply)
                    self?.showToast("收到新的入群申请")
                }
            }
        }
        ws.onGroupApplyAccepted = { [weak self] gid, group in
            Task { @MainActor in
                if let group = group {
                    self?.groups.append(group)
                    self?.registerGroupMembers(group)
                }
                self?.showToast("你已成功加入群聊")
                self?.saveToLocal()
            }
        }
        ws.onGroupApplyRejected = { [weak self] gid in
            Task { @MainActor in
                self?.showToast("你的入群申请被拒绝了")
            }
        }
    }

    var currentUserId: String {
        UserDefaults.standard.string(forKey: "vt_current_uid") ?? ""
    }

    func setCurrentUserId(_ id: String) {
        UserDefaults.standard.set(id, forKey: "vt_current_uid")
    }
    
    // MARK: - 搜索群聊
    func searchGroups(keyword: String) {
        guard !keyword.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        Task {
            do {
                let results = try await api.searchGroups(keyword: keyword)
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.showToast("搜索失败: \(error.localizedDescription)")
                    self.isSearching = false
                }
            }
        }
    }
    
    func applyToGroup(gid: String) {
        guard ws.isConnected else {
            showToast("连接未就绪，请稍后重试")
            return
        }
        ws.sendGroupApply(gid: gid)
    }
    
    func respondToGroupRequest(applyId: String, action: String) {
        ws.sendGroupApplyRespond(applyId: applyId, action: action)
        groupRequests.removeAll { $0.id == applyId }
    }

    private func handleHello(_ msg: HelloMessage) {
        SecureLogger.shared.log("friends=\(msg.friends?.count ?? -1) groups=\(msg.groups?.count ?? -1) globalMsgs=\(msg.globalMsgs?.count ?? -1) dmRooms=\(msg.dmRooms?.count ?? -1) isAdmin=\(msg.isAdmin ?? false) hallName=\(msg.hallName ?? "nil")", module: "Chat")
        if let user = msg.selfUser {
            currentUserName = user.username
            setCurrentUserId(user.id)
        }
        // 增量合并：服务端消息与本地缓存按 ID 去重合并，而非全量替换
        let serverGlobal = (msg.globalMsgs ?? []).map { m -> ChatMessage in
            var msg = m; msg.isFromMe = (msg.from == currentUserId); return msg
        }
        globalMessages = mergeMessages(local: globalMessages, remote: serverGlobal, limit: 500)
        groups = (msg.groups ?? []).map { var g = $0; g.isOwner = (g.owner == currentUserId); return g }
        friends = msg.friends ?? []
        pendingRequests = msg.pendingRequests ?? []
        if let gm = msg.groupMsgs {
            for (gid, arr) in gm {
                let serverMsgs = arr.map { m -> ChatMessage in
                    var msg = m; msg.isFromMe = (msg.from == currentUserId); return msg
                }
                groupMessages[gid] = mergeMessages(local: groupMessages[gid] ?? [], remote: serverMsgs, limit: 500)
            }
        }
        moments = (msg.moments ?? []).sorted { $0.time > $1.time }
        if let ann = msg.announcement, !ann.isEmpty {
            self.announcement = ann
        }
        if let hall = msg.hallName {
            NotificationCenter.default.post(name: .hallRenamed, object: hall)
        }
        if let max = msg.maxOnline {
            NotificationCenter.default.post(name: .maxOnlineUpdate, object: max)
        }
        if let admin = msg.isAdmin {
            NotificationCenter.default.post(name: .adminStatusUpdate, object: admin)
        }
        // 处理dmRooms（对象格式：{roomKey: [messages]}，增量合并）
        if let rooms = msg.dmRooms {
            for (key, msgs) in rooms {
                let serverMsgs = msgs.map { m -> ChatMessage in
                    var msg = m; msg.isFromMe = (msg.from == currentUserId); return msg
                }
                dmMessages[key] = mergeMessages(local: dmMessages[key] ?? [], remote: serverMsgs, limit: 300)
            }
        }
        // 从历史消息中提取所有已知用户（群成员、私聊对象等）
        for m in globalMessages { registerUser(from: m) }
        for msgs in dmMessages.values { for m in msgs { registerUser(from: m) } }
        for msgs in groupMessages.values { for m in msgs { registerUser(from: m) } }
        // 从群成员列表中提取用户（即使从未发过消息也能显示）
        for g in groups { registerGroupMembers(g) }
        saveToLocal()
    }
    
    /// 增量合并消息：本地缓存 + 服务端数据按 ID 去重，保留最新内容，按时间排序
    private func mergeMessages(local: [ChatMessage], remote: [ChatMessage], limit: Int) -> [ChatMessage] {
        var merged: [String: ChatMessage] = [:]
        // 先放本地缓存（去除临时消息，临时消息会被服务端确认消息替代）
        for m in local where !m.id.hasPrefix("temp_") {
            merged[m.id] = m
        }
        // 服务端数据覆盖/新增
        for m in remote {
            merged[m.id] = m
        }
        // 按时间排序，截取上限
        return merged.values.sorted { $0.time < $1.time }.suffix(limit).map { $0 }
    }

    func dmRoomKey(_ a: String, _ b: String) -> String {
        a < b ? "\(a)_\(b)" : "\(b)_\(a)"
    }

    func messages(for room: RoomType) -> [ChatMessage] {
        switch room {
        case .global: return globalMessages
        case .dm(let peerId, _): return dmMessages[dmRoomKey(currentUserId, peerId)] ?? []
        case .group(let gid, _): return groupMessages[gid] ?? []
        }
    }

    func sendMessage(_ text: String, images: [String] = []) {
        guard let room = currentRoom, !text.isEmpty || !images.isEmpty else { return }

        // 防重复发送兜底：3秒内相同内容不重复发送
        let now = Int(Date().timeIntervalSince1970)
        let contentHash = "\(text)|\(images.sorted().joined(separator: ","))"
        if contentHash == lastSentContentHash && (now - lastSentTimestamp) < 3 {
            SecureLogger.shared.log("send blocked by anti-duplicate lock", level: .warn, module: "Chat")
            return
        }
        lastSentContentHash = contentHash
        lastSentTimestamp = now
        
        let roomDesc: String
        switch room {
        case .global: roomDesc = "global"
        case .dm(_, let peerName): roomDesc = "dm→\(peerName)"
        case .group(_, let name): roomDesc = "group[\(name)]"
        }
        SecureLogger.shared.log("send msg [\(roomDesc)] text=\(text.prefix(30))... images=\(images.count)", module: "Chat")

        let tempId = "temp_" + UUID().uuidString
        var tempMsg = ChatMessage(
            id: tempId, from: currentUserId,
            fromName: currentUserName, content: text,
            images: images.isEmpty ? nil : images,
            time: now,
            to: nil, gid: nil
        )
        tempMsg.isFromMe = true
        switch room {
        case .global:
            globalMessages.append(tempMsg)
            if globalMessages.count > 500 { globalMessages = Array(globalMessages.suffix(500)) }
            ws.sendGlobal(content: text, images: images)
        case .dm(let peerId, _):
            tempMsg.to = peerId
            let key = dmRoomKey(currentUserId, peerId)
            if dmMessages[key] == nil { dmMessages[key] = [] }
            dmMessages[key]?.append(tempMsg)
            ws.sendDM(to: peerId, content: text, images: images)
        case .group(let gid, _):
            tempMsg.gid = gid
            if groupMessages[gid] == nil { groupMessages[gid] = [] }
            groupMessages[gid]?.append(tempMsg)
            ws.sendGroup(gid: gid, content: text, images: images)
        }
    }

    func recallMessage(_ msg: ChatMessage) {
        guard let room = currentRoom else { return }
        switch room {
        case .global:
            ws.recall(room: "global", id: msg.id)
        case .dm(let peerId, _):
            ws.recall(room: "dm", id: msg.id, to: peerId)
        case .group(let gid, _):
            ws.recall(room: "group", id: msg.id, gid: gid)
        }
    }
    func removeMessageLocally(_ msg: ChatMessage) {
        globalMessages.removeAll { $0.id == msg.id }
        for key in dmMessages.keys {
            dmMessages[key]?.removeAll { $0.id == msg.id }
        }
        for key in groupMessages.keys {
            groupMessages[key]?.removeAll { $0.id == msg.id }
        }
    }

    func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.toast == text { self?.toast = nil }
        }
    }

    /// 从消息中提取发送者信息，注册到 knownUsers（用于非好友群成员显示）
    private func registerUser(from msg: ChatMessage) {
        guard !msg.from.isEmpty, msg.from != currentUserId else { return }
        if knownUsers[msg.from] != nil { return }
        let user = User(
            id: msg.from,
            username: msg.fromName ?? msg.from,
            avatar: msg.fromAvatar,
            role: msg.fromRole,
            banned: false,
            createdAt: nil
        )
        knownUsers[msg.from] = user
    }

    /// 从群成员列表注册已知用户（即使从未发过消息也能在群成员列表和@列表中显示）
    private func registerGroupMembers(_ group: ChatGroup) {
        for memberId in group.members {
            guard !memberId.isEmpty, memberId != currentUserId else { continue }
            if knownUsers[memberId] != nil { continue }
            knownUsers[memberId] = User(id: memberId, username: memberId, avatar: nil, role: nil, banned: false, createdAt: nil)
        }
    }

    func user(by id: String) -> User? {
        friends.first { $0.id == id } ?? knownUsers[id]
    }

    func group(by id: String) -> ChatGroup? {
        groups.first { $0.id == id }
    }

    func isOnline(_ userId: String) -> Bool {
        onlineUsers.contains(userId)
    }
}

extension Notification.Name {
    static let userBanned = Notification.Name("userBanned")
    static let userKicked = Notification.Name("userKicked")
    static let hallRenamed = Notification.Name("hallRenamed")
    static let maxOnlineUpdate = Notification.Name("maxOnlineUpdate")
    static let adminStatusUpdate = Notification.Name("adminStatusUpdate")
    static let fontSizeChanged = Notification.Name("fontSizeChanged")
}
