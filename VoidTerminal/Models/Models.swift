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

// MARK: - DM Room
struct DMRoom: Codable, Hashable {
    let peerId: String
    let peerName: String
    var peerAvatar: String?
    var lastMessage: String?
    var lastTime: Int?
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
    let globalMsgs: [ChatMessage]?
    let groups: [ChatGroup]?
    let friends: [User]?
    let pendingRequests: [FriendRequest]?
    let dmRooms: [DMRoom]?
    let groupMsgs: [String: [ChatMessage]]?
    let moments: [Moment]?

    enum CodingKeys: String, CodingKey {
        case type, maxOnline, isAdmin, hallName, globalMsgs, groups, friends, pendingRequests, dmRooms, groupMsgs, moments
        case selfUser = "self"
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
}
