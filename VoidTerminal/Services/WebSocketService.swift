import Foundation

// MARK: - WebSocket Service
final class WebSocketService: NSObject, URLSessionWebSocketDelegate {
    static let shared = WebSocketService()

    private var task: URLSessionWebSocketTask?
    private var session: URLSession!
    private var _isConnected = false
    var isConnected: Bool { _isConnected }
    private var token: String?
    private var reconnectAttempts = 0
    private var reconnectTimer: Timer?
    private var heartbeatTimer: Timer?
    private var isManualDisconnect = false

    // 回调
    var onHello: ((HelloMessage) -> Void)?
    var onGlobalMessage: ((ChatMessage) -> Void)?
    var onDMMessage: ((ChatMessage) -> Void)?
    var onGroupMessage: ((ChatMessage) -> Void)?
    var onRecalled: ((String, String, String?, String?) -> Void)?
    var onError: ((String) -> Void)?
    var onBanned: ((String) -> Void)?
    var onKicked: ((String) -> Void)?
    var onSystem: ((String) -> Void)?
    var onPresence: (([String: Bool]) -> Void)?
    var onFriendRequest: ((FriendRequest) -> Void)?
    var onFriendUpdate: (([User]) -> Void)?
    var onRequestRespond: ((Bool, String, String) -> Void)?
    var onRequestSent: ((Bool, String?) -> Void)?
    var onGroupCreated: ((ChatGroup) -> Void)?
    var onGroupRemoved: ((String, String) -> Void)?
    var onGroupRenamed: ((String, ChatGroup) -> Void)?
    var onGroupMemberRemoved: ((String, ChatGroup, String) -> Void)?
    var onGroupAvatarUpdated: ((String, String) -> Void)?
    var onMomentsUpdate: (([Moment]) -> Void)?
    var onMaxOnlineUpdate: ((Int) -> Void)?
    var onHallRenamed: ((String) -> Void)?
    var onHallCleared: (() -> Void)?
    var onDisconnect: (() -> Void)?
    var onGroupApplySent: ((String) -> Void)?
    var onGroupApplyRequest: ((GroupRequest) -> Void)?
    var onGroupApplyAccepted: ((String, ChatGroup?) -> Void)?
    var onGroupApplyRejected: ((String) -> Void)?

    private override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }

    // MARK: - Connection
    func connect(token: String) {
        isManualDisconnect = false
        reconnectAttempts = 0
        if task != nil { disconnect() }
        self.token = token
        guard let url = URL(string: ServerConfig.shared.wsURL) else { return }
        task = session.webSocketTask(with: url)
        task?.resume()
        _isConnected = true
        receive()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.sendAuth()
                self?.startHeartbeat()
        }
    }

    func disconnect() {
        isManualDisconnect = true
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        task?.cancel()
        task = nil
        _isConnected = false
        token = nil
    }

    private func sendAuth() {
        guard let token = token else { return }
        send(["type": "auth", "token": token])
    }

    // MARK: - Send
    func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(str)) { error in
            if let error = error { print("WS send error: \(error)") }
        }
    }

    // 便捷发送方法
    func sendGlobal(content: String, images: [String] = []) {
        var dict: [String: Any] = ["type": "global", "content": content]
        if !images.isEmpty { dict["images"] = images }
        send(dict)
    }

    func sendDM(to: String, content: String, images: [String] = []) {
        var dict: [String: Any] = ["type": "dm", "to": to, "content": content]
        if !images.isEmpty { dict["images"] = images }
        send(dict)
    }

    func sendGroupApply(gid: String) {
        send(["type": "group-apply", "gid": gid])
    }
    
    func sendGroupApplyRespond(applyId: String, action: String) {
        send(["type": "group-apply-respond", "applyId": applyId, "action": action])
    }
    
    func sendGroup(gid: String, content: String, images: [String] = []) {
        var dict: [String: Any] = ["type": "group", "gid": gid, "content": content]
        if !images.isEmpty { dict["images"] = images }
        send(dict)
    }

    func recall(room: String, id: String, to: String? = nil, gid: String? = nil) {
        var dict: [String: Any] = ["type": "recall", "room": room, "id": id]
        if let to = to { dict["to"] = to }
        if let gid = gid { dict["gid"] = gid }
        send(dict)
    }

    func createGroup(name: String, members: [String]) {
        send(["type": "create-group", "name": name, "members": members])
    }

    func sendFriendRequest(username: String) {
        send(["type": "friend-request", "username": username])
    }

    func respondRequest(requestId: String, action: String) {
        send(["type": "request-respond", "requestId": requestId, "action": action])
    }

    func unfriend(userId: String) {
        send(["type": "unfriend", "userId": userId])
    }

    func groupRename(gid: String, name: String) {
        send(["type": "group-rename", "gid": gid, "name": name])
    }

    func groupRemoveMember(gid: String, userId: String) {
        send(["type": "group-remove-member", "gid": gid, "userId": userId])
    }

    func groupLeave(gid: String) {
        send(["type": "group-leave", "gid": gid])
    }

    func groupAddMembers(gid: String, members: [String]) {
        send(["type": "group-add-members", "gid": gid, "members": members])
    }

    func groupDissolve(gid: String) {
        send(["type": "group-dissolve", "gid": gid])
    }

    func momentLike(momentId: String) {
        send(["type": "moment-like", "momentId": momentId])
    }

    func momentComment(momentId: String, text: String) {
        send(["type": "moment-comment", "momentId": momentId, "text": text])
    }

    func momentDelete(momentId: String) {
        send(["type": "moment-delete", "momentId": momentId])
    }

    func momentCommentDelete(momentId: String, commentId: String) {
        send(["type": "moment-comment-delete", "momentId": momentId, "commentId": commentId])
    }

    // Admin
    func setMaxOnline(_ value: Int) {
        send(["type": "set-max-online", "value": value])
    }

    func banUser(username: String) {
        send(["type": "ban-user", "username": username])
    }

    func unbanUser(username: String) {
        send(["type": "unban-user", "username": username])
    }

    func kickUser(userId: String) {
        send(["type": "kick-user", "userId": userId])
    }

    func announce(content: String) {
        send(["type": "announce", "content": content])
    }

    func renameHall(name: String) {
        send(["type": "rename-hall", "name": name])
    }

    func clearHall() {
        send(["type": "clear-hall"])
    }

    // MARK: - Receive
    private func receive() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default: break
                }
                self.receive()
            case .failure:
                self._isConnected = false
                self.heartbeatTimer?.invalidate()
                self.scheduleReconnect()
                self.onDisconnect?()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = dict["type"] as? String else { return }

        let decoder = JSONDecoder()

        switch type {
        case "hello":
            do {
                let msg = try decoder.decode(HelloMessage.self, from: data)
                AppLogger.shared.log("[WS] hello decoded successfully")
                onHello?(msg)
            } catch {
                AppLogger.shared.log("[WS] hello decode FAILED: \(error)")
            }
        case "global":
            if var msg = try? decoder.decode(ChatMessage.self, from: data) {
                onGlobalMessage?(msg)
            }
        case "dm":
            if var msg = try? decoder.decode(ChatMessage.self, from: data) {
                onDMMessage?(msg)
            }
        case "group":
            if var msg = try? decoder.decode(ChatMessage.self, from: data) {
                onGroupMessage?(msg)
            }
        case "recalled":
            let room = dict["room"] as? String ?? ""
            let id = dict["id"] as? String ?? ""
            let to = dict["to"] as? String
            let gid = dict["gid"] as? String
            onRecalled?(room, id, to, gid)
        case "error":
            onError?(dict["error"] as? String ?? "未知错误")
        case "banned":
            onBanned?(dict["error"] as? String ?? "账号已被封禁")
        case "kicked":
            onKicked?(dict["error"] as? String ?? "你已被移出服务器")
        case "system":
            onSystem?(dict["content"] as? String ?? "")
        case "presence":
            if let users = dict["users"] as? [String: Bool] {
                onPresence?(users)
            }
        case "friend-request":
            if let reqDict = dict["request"] as? [String: Any],
               let reqData = try? JSONSerialization.data(withJSONObject: reqDict),
               let req = try? decoder.decode(FriendRequest.self, from: reqData) {
                onFriendRequest?(req)
            }
        case "friend-update":
            if let friends = dict["friends"] as? [[String: Any]],
               let fData = try? JSONSerialization.data(withJSONObject: friends),
               let list = try? decoder.decode([User].self, from: fData) {
                onFriendUpdate?(list)
            }
        case "request-respond":
            let ok = dict["ok"] as? Bool ?? false
            let action = dict["action"] as? String ?? ""
            let fromName = dict["fromName"] as? String ?? ""
            onRequestRespond?(ok, action, fromName)
        case "request-sent":
            let ok = dict["ok"] as? Bool ?? false
            let error = dict["error"] as? String
            onRequestSent?(ok, error)
        case "group-created":
            if let gDict = dict["group"] as? [String: Any],
               let gData = try? JSONSerialization.data(withJSONObject: gDict),
               let group = try? decoder.decode(ChatGroup.self, from: gData) {
                onGroupCreated?(group)
            }
        case "group-removed":
            let gid = dict["gid"] as? String ?? ""
            let error = dict["error"] as? String ?? ""
            onGroupRemoved?(gid, error)
        case "group-renamed":
            let gid = dict["gid"] as? String ?? ""
            if let gDict = dict["group"] as? [String: Any],
               let gData = try? JSONSerialization.data(withJSONObject: gDict),
               let group = try? decoder.decode(ChatGroup.self, from: gData) {
                onGroupRenamed?(gid, group)
            }
        case "group-member-removed":
            let gid = dict["gid"] as? String ?? ""
            let userId = dict["userId"] as? String ?? ""
            if let gDict = dict["group"] as? [String: Any],
               let gData = try? JSONSerialization.data(withJSONObject: gDict),
               let group = try? decoder.decode(ChatGroup.self, from: gData) {
                onGroupMemberRemoved?(gid, group, userId)
            }
        case "group-avatar-updated":
            let gid = dict["gid"] as? String ?? ""
            let avatar = dict["avatar"] as? String ?? ""
            onGroupAvatarUpdated?(gid, avatar)
        case "group-apply-sent":
            let gid = dict["gid"] as? String ?? ""
            onGroupApplySent?(gid)
        case "group-apply-request":
            if let aDict = dict["apply"] as? [String: Any],
               let aData = try? JSONSerialization.data(withJSONObject: aDict),
               let apply = try? decoder.decode(GroupRequest.self, from: aData) {
                onGroupApplyRequest?(apply)
            }
        case "group-apply-accepted":
            let gid = dict["gid"] as? String ?? ""
            var group: ChatGroup?
            if let gDict = dict["group"] as? [String: Any],
               let gData = try? JSONSerialization.data(withJSONObject: gDict) {
                group = try? decoder.decode(ChatGroup.self, from: gData)
            }
            onGroupApplyAccepted?(gid, group)
        case "group-apply-rejected":
            let gid = dict["gid"] as? String ?? ""
            onGroupApplyRejected?(gid)
        case "moments":
            if let moments = dict["moments"] as? [[String: Any]],
               let mData = try? JSONSerialization.data(withJSONObject: moments),
               let list = try? decoder.decode([Moment].self, from: mData) {
                onMomentsUpdate?(list)
            }
        case "max-online":
            let max = dict["maxOnline"] as? Int ?? 0
            onMaxOnlineUpdate?(max)
        case "hall-renamed":
            let name = dict["hallName"] as? String ?? "公共大厅"
            onHallRenamed?(name)
        case "hall-cleared":
            onHallCleared?()
        default:
            break
        }
    }

    // MARK: - URLSessionWebSocketDelegate
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        _isConnected = true
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        _isConnected = false
        onDisconnect?()
    }


    // MARK: - Heartbeat
    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }
    private func sendPing() {
        task?.sendPing { error in
            if let error = error {
                print("WS ping error: \(error)")
            }
        }
    }
    // MARK: - Reconnect
    private func scheduleReconnect() {
        guard !isManualDisconnect, let token = token else { return }
        reconnectAttempts += 1
        let delay = min(Double(reconnectAttempts) * 2, 15)
        print("WS reconnect scheduled in \(delay)s (attempt \(reconnectAttempts))")
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self, !self.isManualDisconnect else { return }
            self.connect(token: token)
        }
    }
}

import Foundation

final class AppLogger {
    static let shared = AppLogger()
    private(set) var logs: [String] = []
    private let maxLogs = 100
    
    func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(message)"
        DispatchQueue.main.async {
            self.logs.insert(line, at: 0)
            if self.logs.count > self.maxLogs {
                self.logs = Array(self.logs.prefix(self.maxLogs))
            }
        }
        print(line)
    }
    
    func clear() {
        logs.removeAll()
    }
}
