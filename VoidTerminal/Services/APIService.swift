import Foundation

// MARK: - Server Configuration
struct ServerConfig {
    static let shared = ServerConfig()

    /// 服务器基础地址，默认 HTTPS，可在设置中修改
    var baseURL: String {
        get {
            UserDefaults.standard.string(forKey: "vt_server_url")
                ?? "https://buer.kdns.fr"
        }
        nonmutating set {
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
        return "wss://" + http + "/ws"
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
final class APIService: NSObject {
    static let shared = APIService()

    /// 自定义 URLSession，使用 delegate 做严格证书验证
    private let session: URLSession

    private override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        super.init()
        self.session = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
    }

    // MARK: - Auth
    func register(username: String, password: String) async throws -> RegisterResponse {
        do {
            let resp: RegisterResponse = try await post("/api/register", body: ["username": username, "password": password])
            SecureLogger.shared.log("API register success: \(username)", module: "API")
            return resp
        } catch {
            SecureLogger.shared.log("API register failed: \(error.localizedDescription)", level: .error, module: "API")
            throw error
        }
    }

    func login(username: String, password: String) async throws -> LoginResponse {
        do {
            let resp: LoginResponse = try await post("/api/login", body: ["username": username, "password": password])
            SecureLogger.shared.log("API login success: \(username)", module: "API")
            return resp
        } catch {
            SecureLogger.shared.log("API login failed: \(error.localizedDescription)", level: .error, module: "API")
            throw error
        }
    }

    func me(token: String) async throws -> User {
        do {
            let resp: MeResponse = try await post("/api/me", body: ["token": token])
            SecureLogger.shared.log("API me success: \(resp.user.username)", module: "API")
            return resp.user
        } catch {
            SecureLogger.shared.log("API me failed: \(error.localizedDescription)", level: .error, module: "API")
            throw error
        }
    }

    // MARK: - Avatar
    func uploadAvatar(token: String, imageData: Data) async throws -> String {
        do {
            let b64 = imageData.base64EncodedString()
            let resp: AvatarResponse = try await post("/api/avatar", body: ["token": token, "data": b64])
            SecureLogger.shared.log("API uploadAvatar success: size=\(imageData.count)", module: "API")
            return resp.avatar
        } catch {
            SecureLogger.shared.log("API uploadAvatar failed: \(error.localizedDescription)", level: .error, module: "API")
            throw error
        }
    }

    func uploadGroupAvatar(token: String, gid: String, imageData: Data) async throws -> String {
        do {
            let b64 = imageData.base64EncodedString()
            let resp: AvatarResponse = try await post("/api/group-avatar", body: ["token": token, "gid": gid, "data": b64])
            SecureLogger.shared.log("API uploadGroupAvatar success: gid=\(gid) size=\(imageData.count)", module: "API")
            return resp.avatar
        } catch {
            SecureLogger.shared.log("API uploadGroupAvatar failed: \(error.localizedDescription)", level: .error, module: "API")
            throw error
        }
    }

    // MARK: - Message Image
    func uploadMessageImage(token: String, imageData: Data) async throws -> String {
        do {
            let b64 = imageData.base64EncodedString()
            let resp: ImageUploadResponse = try await post("/api/upload-msg-image", body: ["token": token, "data": b64])
            SecureLogger.shared.log("API uploadMessageImage success: size=\(imageData.count)", module: "API")
            return resp.url
        } catch {
            SecureLogger.shared.log("API uploadMessageImage failed: \(error.localizedDescription)", level: .error, module: "API")
            throw error
        }
    }

    // MARK: - Moment
    func postMoment(token: String, text: String, images: [Data]) async throws -> Moment {
        do {
            let b64images = images.map { $0.base64EncodedString() }
            let resp: MomentResponse = try await post("/api/moment-post", body: ["token": token, "text": text, "images": b64images])
            SecureLogger.shared.log("API postMoment success: images=\(images.count) textLen=\(text.count)", module: "API")
            return resp.moment
        } catch {
            SecureLogger.shared.log("API postMoment failed: \(error.localizedDescription)", level: .error, module: "API")
            throw error
        }
    }

    // MARK: - Account
    func changePassword(token: String, old: String, new: String, confirm: String) async throws {
        do {
            let _: [String: Bool] = try await post("/api/change-password", body: [
                "token": token, "oldPassword": old, "newPassword": new, "newPassword2": confirm
            ])
            SecureLogger.shared.log("API changePassword success", module: "API")
        } catch {
            SecureLogger.shared.log("API changePassword failed: \(error.localizedDescription)", level: .error, module: "API")
            throw error
        }
    }

    func changeUsername(token: String, newName: String) async throws -> User {
        do {
            let resp: MeResponse = try await post("/api/change-username", body: ["token": token, "newUsername": newName])
            SecureLogger.shared.log("API changeUsername success: newName=\(newName)", module: "API")
            return resp.user
        } catch {
            SecureLogger.shared.log("API changeUsername failed: \(error.localizedDescription)", level: .error, module: "API")
            throw error
        }
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

    // MARK: - 搜索群聊
    func searchGroups(keyword: String) async throws -> [SearchGroup] {
        do {
            let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
            let url = URL(string: ServerConfig.shared.baseURL + "/api/search-groups?keyword=" + encoded)!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            if http.statusCode >= 400 {
                throw APIError.httpError(http.statusCode)
            }
            let result = try JSONDecoder().decode(SearchGroupResponse.self, from: data)
            if result.ok == false {
                throw APIError.serverError(result.error ?? "搜索失败")
            }
            SecureLogger.shared.log("API searchGroups success: keyword=\(keyword) found=\(result.groups?.count ?? 0)", module: "API")
            return result.groups ?? []
        } catch {
            SecureLogger.shared.log("API searchGroups failed: \(error.localizedDescription)", level: .error, module: "API")
            throw error
        }
    }

    // MARK: - 登出
    func logout() async {
        SecureLogger.shared.log("API logout", module: "API")
        let _: [String: Bool]? = try? await post("/api/logout", body: [:])
    }
}

// MARK: - URLSession Delegate（严格证书验证）
extension APIService: URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // 只接受服务器信任验证
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        // 设置 SSL 策略，校验证书域名匹配
        let policy = SecPolicyCreateSSL(true, challenge.protectionSpace.host as CFString)
        SecTrustSetPolicies(serverTrust, policy)

        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)
        if isValid {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            // 证书链无效、自签名或域名不匹配，一律拒绝
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case serverError(String)
    case certError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "无效响应"
        case .httpError(let code): return "HTTP错误 \(code)"
        case .serverError(let msg): return msg
        case .certError(let msg): return "证书验证失败: \(msg)"
        }
    }
}
