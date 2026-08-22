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
    @Published var pendingRequests: [FriendRequest] = []
    @Published var moments: [Moment] = []
    @Published var onlineUsers: Set<String> = []
    @Published var toast: String?
    @Published var currentRoom: RoomType?

    private let ws = WebSocketService.shared
    private let api = APIService.shared

    enum RoomType: Hashable {
        case global
        case dm(peerId: String, peerName: String)
        case group(gid: String, name: String)
    }

    init() {
        setupCallbacks()
    }

    private func setupCallbacks() {
        ws.onHello = { [weak self] msg in
            Task { @MainActor in
                self?.handleHello(msg)
            }
        }
        ws.onGlobalMessage = { [weak self] msg in
            Task { @MainActor in
                var m = msg
                m.isFromMe = (m.from == self?.currentUserId)
                self?.globalMessages.append(m)
                if self?.globalMessages.count ?? 0 > 500 {
                    self?.globalMessages = Array(self?.globalMessages.suffix(500) ?? [])
                }
            }
        }
        ws.onDMMessage = { [weak self] msg in
            Task { @MainActor in
                guard let self = self else { return }
                var m = msg
                m.isFromMe = (m.from == self.currentUserId)
                let peer = m.from == self.currentUserId ? (m.to ?? "") : m.from
                let key = self.dmRoomKey(self.currentUserId, peer)
                if self.dmMessages[key] == nil { self.dmMessages[key] = [] }
                self.dmMessages[key]?.append(m)
            }
        }
        ws.onGroupMessage = { [weak self] msg in
            Task { @MainActor in
                guard let self = self, let gid = msg.gid else { return }
                var m = msg
                m.isFromMe = (m.from == self.currentUserId)
                if self.groupMessages[gid] == nil { self.groupMessages[gid] = [] }
                self.groupMessages[gid]?.append(m)
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
        ws.onFriendRequest = { [weak self] req in
            Task { @MainActor in
                if !(self?.pendingRequests.contains { $0.id == req.id } ?? false) {
                    self?.pendingRequests.append(req)
                }
            }
        }
        ws.onFriendUpdate = { [weak self] list in
            Task { @MainActor in self?.friends = list }
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
            Task { @MainActor in self?.moments = list }
        }
        ws.onHallRenamed = { [weak self] name in
            Task { @MainActor in
                NotificationCenter.default.post(name: .hallRenamed, object: name)
            }
        }
        ws.onHallCleared = { [weak self] in
            Task { @MainActor in self?.globalMessages.removeAll() }
        }
    }

    var currentUserId: String {
        UserDefaults.standard.string(forKey: "vt_current_uid") ?? ""
    }

    func setCurrentUserId(_ id: String) {
        UserDefaults.standard.set(id, forKey: "vt_current_uid")
    }

    private func handleHello(_ msg: HelloMessage) {
        if let user = msg.selfUser {
            setCurrentUserId(user.id)
        }
        globalMessages = (msg.globalMsgs ?? []).map { var m = $0; m.isFromMe = (m.from == currentUserId); return m }
        groups = (msg.groups ?? []).map { var g = $0; g.isOwner = (g.owner == currentUserId); return g }
        friends = msg.friends ?? []
        pendingRequests = msg.pendingRequests ?? []
        if let gm = msg.groupMsgs {
            groupMessages = gm.mapValues { arr in
                arr.map { var m = $0; m.isFromMe = (m.from == currentUserId); return m }
            }
        }
        moments = msg.moments ?? []
        if let hall = msg.hallName {
            NotificationCenter.default.post(name: .hallRenamed, object: hall)
        }
        if let max = msg.maxOnline {
            NotificationCenter.default.post(name: .maxOnlineUpdate, object: max)
        }
        if let admin = msg.isAdmin {
            NotificationCenter.default.post(name: .adminStatusUpdate, object: admin)
        }
        // 处理dmRooms
        if let rooms = msg.dmRooms {
            for room in rooms {
                let key = dmRoomKey(currentUserId, room.peerId)
                if dmMessages[key] == nil { dmMessages[key] = [] }
            }
        }
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
        switch room {
        case .global:
            ws.sendGlobal(content: text, images: images)
        case .dm(let peerId, _):
            ws.sendDM(to: peerId, content: text, images: images)
        case .group(let gid, _):
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

    func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.toast == text { self?.toast = nil }
        }
    }

    func user(by id: String) -> User? {
        friends.first { $0.id == id }
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
}
