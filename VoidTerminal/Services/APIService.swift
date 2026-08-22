import Foundation

// MARK: - Server Configuration
struct ServerConfig {
    static let shared = ServerConfig()

    /// 服务器基础地址，可在设置中修改
    var baseURL: String {
        get {
            UserDefaults.standard.string(forKey: "vt_server_url")
                ?? "http://buer.kdns.fr"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "vt_server_url")
        }
    }

    var wsURL: String {
        let http = baseURL
        if http.hasPrefix("https://") {
            return "wss://" + http.dropFirst(8) + "/ws"
        } else if http.hasPrefix("http://") {
            return "ws://" + http.dropFirst(7) + "/ws"
        }
        return "ws://" + http + "/ws"
    }

    func url(for path: String) -> URL {
        URL(string: baseURL + path)!
    }

    func resourceURL(for path: String) -> URL {
        if path.hasPrefix("http") { return URL(string: path)! }
        return URL(string: baseURL + path)!
    }
}

// MARK: - API Service
final class APIService {
    static let shared = APIService()
    private let session = URLSession.shared

    private init() {}

    // MARK: - Auth
    func register(username: String, password: String) async throws -> RegisterResponse {
        try await post("/api/register", body: ["username": username, "password": password])
    }

    func login(username: String, password: String) async throws -> LoginResponse {
        try await post("/api/login", body: ["username": username, "password": password])
    }

    func me(token: String) async throws -> User {
        let resp: MeResponse = try await post("/api/me", body: ["token": token])
        return resp.user
    }

    // MARK: - Avatar
    func uploadAvatar(token: String, imageData: Data) async throws -> String {
        let b64 = imageData.base64EncodedString()
        let resp: [String: String] = try await post("/api/avatar", body: ["token": token, "data": b64])
        return resp["avatar"] ?? ""
    }

    func uploadGroupAvatar(token: String, gid: String, imageData: Data) async throws -> String {
        let b64 = imageData.base64EncodedString()
        let resp: [String: String] = try await post("/api/group-avatar", body: ["token": token, "gid": gid, "data": b64])
        return resp["avatar"] ?? ""
    }

    // MARK: - Message Image
    func uploadMessageImage(token: String, imageData: Data) async throws -> String {
        let b64 = imageData.base64EncodedString()
        let resp: [String: String] = try await post("/api/upload-msg-image", body: ["token": token, "data": b64])
        return resp["url"] ?? ""
    }

    // MARK: - Moment
    func postMoment(token: String, text: String, images: [Data]) async throws -> Moment {
        let b64images = images.map { $0.base64EncodedString() }
        let resp: MomentResponse = try await post("/api/moment-post", body: ["token": token, "text": text, "images": b64images])
        return resp.moment
    }

    // MARK: - Account
    func changePassword(token: String, old: String, new: String, confirm: String) async throws {
        let _: [String: Bool] = try await post("/api/change-password", body: [
            "token": token, "oldPassword": old, "newPassword": new, "newPassword2": confirm
        ])
    }

    func changeUsername(token: String, newName: String) async throws -> User {
        let resp: MeResponse = try await post("/api/change-username", body: ["token": token, "newUsername": newName])
        return resp.user
    }

    // MARK: - Generic POST
    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: ServerConfig.shared.url(for: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if http.statusCode >= 400 {
            if let err = try? JSONDecoder().decode([String: String].self, from: data),
               let msg = err["error"] {
                throw APIError.serverError(msg)
            }
            throw APIError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "无效响应"
        case .httpError(let code): return "HTTP错误 \(code)"
        case .serverError(let msg): return msg
        }
    }
}
