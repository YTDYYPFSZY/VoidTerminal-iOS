import Foundation

// MARK: - User
struct User: Codable, Identifiable, Hashable {
    let id: String
    let username: String
    var avatar: String?
    var role: String?
    var banned: Bool?
    let createdAt: Int?

    var displayName: String { username }
    var isAdmin: Bool { role == "admin" }
    var isBot: Bool { role == "bot" }
}

// MARK: - Message
struct ChatMessage: Codable, Identifiable, Hashable {
    let id: String
    let from: String
    var fromName: String?
    var fromAvatar: String?
    var fromRole: String?
    var fromBot: Bool?
    let content: String
    var images: [String]?
    let time: Int
    // dm only
    var to: String?
    // group only
    var gid: String?

    var isFromMe: Bool = false
    var isImageOnly: Bool { content.isEmpty && !(images?.isEmpty ?? true) }

    enum CodingKeys: String, CodingKey {
        case id, from, fromName, fromAvatar, fromRole, fromBot, content, images, time, to, gid
    }
    // 成员初始化器（自定义init(from:)后需手动提供）
    init(id: String, from: String, fromName: String? = nil, fromAvatar: String? = nil,
         fromRole: String? = nil, fromBot: Bool? = nil, content: String, images: [String]? = nil,
         time: Int, to: String? = nil, gid: String? = nil) {
        self.id = id
        self.from = from
        self.fromName = fromName
        self.fromAvatar = fromAvatar
        self.fromRole = fromRole
        self.fromBot = fromBot
        self.content = content
        self.images = images
        self.time = time
        self.to = to
        self.gid = gid
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // id兜底：服务端历史消息可能缺id，用from+content+time生成
        if let id = try? container.decode(String.self, forKey: .id) {
            self.id = id
        } else {
            let from = try container.decode(String.self, forKey: .from)
            let content = try container.decode(String.self, forKey: .content)
            let time = try container.decode(Int.self, forKey: .time)
            self.id = "\(from)_\(content)_\(time)"
        }
        from = try container.decode(String.self, forKey: .from)
        fromName = try? container.decode(String.self, forKey: .fromName)
        fromAvatar = try? container.decode(String.self, forKey: .fromAvatar)
        fromRole = try? container.decode(String.self, forKey: .fromRole)
        fromBot = try? container.decode(Bool.self, forKey: .fromBot)
        content = try container.decode(String.self, forKey: .content)
        images = try? container.decode([String].self, forKey: .images)
        time = try container.decode(Int.self, forKey: .time)
        to = try? container.decode(String.self, forKey: .to)
        gid = try? container.decode(String.self, forKey: .gid)
    }
}

// MARK: - Group
struct ChatGroup: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    let owner: String
    var members: [String]
    var avatar: String?
    let createdAt: Int?
    var isOwner: Bool = false
    enum CodingKeys: String, CodingKey {
        case id, name, owner, members, avatar, createdAt
    }
}

// MARK: - Friend Request
struct FriendRequest: Codable, Identifiable, Hashable {
    let id: String
    let from: String
    let fromName: String
    var fromAvatar: String?
    let time: Int
}

// MARK: - Moment
struct Moment: Codable, Identifiable, Hashable {
    let id: String
    let author: String
    var authorName: String?
    var authorAvatar: String?
    let text: String
    var images: [String]
    let time: Int
    var likes: [String]
    var comments: [MomentComment]

    var isLiked: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, author, authorName, authorAvatar, text, images, time, likes, comments
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        author = try container.decode(String.self, forKey: .author)
        authorName = try? container.decode(String.self, forKey: .authorName)
        authorAvatar = try? container.decode(String.self, forKey: .authorAvatar)
        text = try container.decode(String.self, forKey: .text)
        images = (try? container.decode([String].self, forKey: .images)) ?? []
        time = try container.decode(Int.self, forKey: .time)
        likes = (try? container.decode([String].self, forKey: .likes)) ?? []
        // comments兜底：解码失败给空数组，不让整条moment崩
        comments = (try? container.decode([MomentComment].self, forKey: .comments)) ?? []
    }
}

struct MomentComment: Codable, Hashable, Identifiable {
    var id: String { user + text + String(time) }
    let user: String
    var userName: String?
    let text: String
    let time: Int
    enum CodingKeys: String, CodingKey {
        case user = "author"
        case userName = "authorName"
        case text, time
    }
}

struct MomentResponse: Codable {
    let ok: Bool
    let moment: Moment
}

struct AvatarResponse: Codable {
    let ok: Bool
    let avatar: String
}

struct ImageUploadResponse: Codable {
    let ok: Bool
    let url: String
}

// MARK: - API Responses
struct LoginResponse: Codable {
    let ok: Bool
    let token: String
    let user: User
}

struct RegisterResponse: Codable {
    let ok: Bool
}

struct MeResponse: Codable {
    let ok: Bool
    let user: User
}

struct HelloMessage: Codable {
    let type: String
    let selfUser: User?
    let maxOnline: Int?
    let isAdmin: Bool?
    let hallName: String?
    let announcement: String?
    let globalMsgs: [ChatMessage]?
    let groups: [ChatGroup]?
    let friends: [User]?
    let pendingRequests: [FriendRequest]?
    let dmRooms: [String: [ChatMessage]]?
    let groupMsgs: [String: [ChatMessage]]?
    let moments: [Moment]?

    enum CodingKeys: String, CodingKey {
        case type, maxOnline, isAdmin, hallName, announcement, globalMsgs, groups, friends, pendingRequests, dmRooms, groupMsgs, moments
        case selfUser = "self"
    }
}

// MARK: - 搜索群聊结果
struct SearchGroup: Codable, Identifiable {
    let id: String
    let name: String
    let owner: String?
    let ownerName: String?
    let memberCount: Int?
    let avatar: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, owner, ownerName, memberCount, avatar
    }
}

struct SearchGroupResponse: Codable {
    let groups: [SearchGroup]?
}

// MARK: - 群申请
struct GroupRequest: Codable, Identifiable {
    let id: String
    let gid: String
    let groupName: String?
    let from: String
    let fromName: String?
    let fromAvatar: String?
    let time: Int
    let status: String?
    
    enum CodingKeys: String, CodingKey {
        case id, gid, groupName, from, fromName, fromAvatar, time, status
    }
}

// MARK: - WebSocket Message Wrapper
struct WSMessage: Codable {
    let type: String
    // Various payloads
    var error: String?
    var token: String?
    var content: String?
    var images: [String]?
    var to: String?
    var gid: String?
    var id: String?
    var room: String?
    var name: String?
    var members: [String]?
    var username: String?
    var requestId: String?
    var action: String?
    var value: Int?
    var userId: String?
    var text: String?
    var momentId: String?
    var commentId: String?
    var newUsername: String?
    var oldPassword: String?
    var newPassword: String?
    var newPassword2: String?
    var data: String? // base64 image
    var image: String?
    // 群申请相关
    var apply: GroupRequest?
    var group: ChatGroup?
    var applyId: String?
}
