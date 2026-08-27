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
    private var connectionCheckTimer: Timer?
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
    var onPresence: (([String]) -> Void)?
    var onAnnouncementUpdate: ((String) -> Void)?
    var onFriendRequest: ((FriendRequest) -> Void)?
    var onFriendUpdate: (([User]) -> Void)?
    var onRequestRespond: ((Bool, String, String) -> Void)?
    var onRequestSent: ((Bool, String?) -> Void)?
    var onGroupCreated: ((ChatGroup) -> Void)?
    var onGroupRemoved: ((String, String) -> Void)?
    var onGroupDissolved: ((String) -> Void)?  // 群解散
    var onGroupRenamed: ((String, ChatGroup) -> Void)?
    var onGroupMemberRemoved: ((String, ChatGroup, String) -> Void)?
    var onGroupAvatarUpdated: ((String, String) -> Void)?
    var onMomentsUpdate: (([Moment]) -> Void)?
    var onMomentPosted: ((Moment) -> Void)?  // 新增单条朋友圈
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
        SecureLogger.shared.log("WebSocket connect called, token length=\(token.count)", module: "WebSocket")
        isManualDisconnect = false
        reconnectAttempts = 0
        if task != nil { disconnect() }
        SecureLogger.shared.log("connecting to \(ServerConfig.shared.wsURL)", module: "WebSocket")
        startConnectionCheck()
        self.token = token
        guard let url = URL(string: ServerConfig.shared.wsURL) else {
            SecureLogger.shared.log("invalid wsURL", level: .error, module: "WebSocket")
            return
        }
        task = session.webSocketTask(with: url)
        task?.resume()
        _isConnected = true
        SecureLogger.shared.log("WebSocket task resumed, starting receive", module: "WebSocket")
        receive()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.sendAuth()
            self?.startHeartbeat()
            SecureLogger.shared.log("WebSocket auth sent and heartbeat started", module: "WebSocket")
        }
    }

    func disconnect() {
        isManualDisconnect = true
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        connectionCheckTimer?.invalidate()
        connectionCheckTimer = nil
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
        send(["type": "moment-like", "mid": momentId])
    }

    func momentComment(momentId: String, text: String) {
        send(["type": "moment-comment", "mid": momentId, "text": text])
    }

    func momentDelete(momentId: String) {
        send(["type": "moment-delete", "mid": momentId])
    }

    func momentCommentDelete(momentId: String, commentId: String) {
        send(["type": "moment-comment-delete", "mid": momentId, "cid": commentId])
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
            case .failure(let error):
                SecureLogger.shared.log("receive error: \(error.localizedDescription)", level: .error, module: "WebSocket")
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
                SecureLogger.shared.log("hello decoded successfully", module: "WebSocket")
                onHello?(msg)
            } catch {
                SecureLogger.shared.log("hello decode FAILED: \(error)", level: .error, module: "WebSocket")
            }
        case "global":
            if var msg = try? decoder.decode(ChatMessage.self, from: data) {
                SecureLogger.shared.log("recv global msg from=\(msg.from)", module: "WebSocket")
                onGlobalMessage?(msg)
            }
        case "dm":
            if var msg = try? decoder.decode(ChatMessage.self, from: data) {
                SecureLogger.shared.log("recv dm msg from=\(msg.from) to=\(msg.to ?? "?")", module: "WebSocket")
                onDMMessage?(msg)
            }
        case "group":
            if var msg = try? decoder.decode(ChatMessage.self, from: data) {
                SecureLogger.shared.log("recv group msg from=\(msg.from) gid=\(msg.gid ?? "?")", module: "WebSocket")
                onGroupMessage?(msg)
            }
        case "recalled":
            let room = dict["room"] as? String ?? ""
            let id = dict["id"] as? String ?? ""
            let to = dict["to"] as? String
            let gid = dict["gid"] as? String
            SecureLogger.shared.log("recv recall room=\(room) id=\(id)", module: "WebSocket")
            onRecalled?(room, id, to, gid)
        case "error":
            let errMsg = dict["error"] as? String ?? "未知错误"
            SecureLogger.shared.log("recv error: \(errMsg)", level: .error, module: "WebSocket")
            onError?(errMsg)
        case "banned":
            let errMsg = dict["error"] as? String ?? "账号已被封禁"
            SecureLogger.shared.log("recv banned: \(errMsg)", level: .error, module: "WebSocket")
            onBanned?(errMsg)
        case "kicked":
            let errMsg = dict["error"] as? String ?? "你已被移出服务器"
            SecureLogger.shared.log("recv kicked: \(errMsg)", level: .error, module: "WebSocket")
            onKicked?(errMsg)
        case "system":
            let content = dict["content"] as? String ?? ""
            SecureLogger.shared.log("recv system: \(content)", module: "WebSocket")
            onSystem?(content)
        case "presence":
            if let online = dict["online"] as? [[String: Any]] {
                let ids = online.compactMap { $0["id"] as? String }
                onPresence?(ids)
            }
        case "announcement-update":
            if let ann = dict["announcement"] as? String {
                onAnnouncementUpdate?(ann)
            }
        case "friend-request":
            if let reqDict = dict["request"] as? [String: Any],
               let reqData = try? JSONSerialization.data(withJSONObject: reqDict),
               let req = try? decoder.decode(FriendRequest.self, from: reqData) {
                SecureLogger.shared.log("recv friend-request from=\(req.fromName)", module: "WebSocket")
                onFriendRequest?(req)
            }
        case "friend-update":
            if let friends = dict["friends"] as? [[String: Any]],
               let fData = try? JSONSerialization.data(withJSONObject: friends),
               let list = try? decoder.decode([User].self, from: fData) {
                SecureLogger.shared.log("recv friend-update count=\(list.count)", module: "WebSocket")
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
        case "group-dissolved":
            let gid = dict["gid"] as? String ?? ""
            onGroupDissolved?(gid)
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
        case "moment-posted":
            if let mDict = dict["moment"] as? [String: Any],
               let mData = try? JSONSerialization.data(withJSONObject: mDict),
               let moment = try? decoder.decode(Moment.self, from: mData) {
                onMomentPosted?(moment)
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
        heartbeatTimer?.invalidate()
        scheduleReconnect()
        onDisconnect?()
    }

    // MARK: - TLS 证书验证
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        // 校验证书链有效性及域名匹配
        let policy = SecPolicyCreateSSL(true, challenge.protectionSpace.host as CFString)
        SecTrustSetPolicies(serverTrust, policy)
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)
        if isValid {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }


    // MARK: - Connection Check
    private func startConnectionCheck() {
        connectionCheckTimer?.invalidate()
        connectionCheckTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self = self, !self.isManualDisconnect else { return }
            if !self.isConnected, let token = self.token {
                print("WS connection check: not connected, reconnecting...")
                self.reconnectAttempts = 0
                self.connect(token: token)
            }
        }
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
        SecureLogger.shared.log("reconnect scheduled in \(Int(delay))s (attempt \(reconnectAttempts))", level: .warn, module: "WebSocket")
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self, !self.isManualDisconnect else { return }
            self.connect(token: token)
        }
    }
}

import Foundation

// AppLogger 已迁移至 SecureLogger.swift
