import Foundation
import Security
import CryptoKit

// MARK: - Keychain Helper

/// Keychain 简易封装，用于安全存储 Token 和加密密钥
final class KeychainHelper {
    static let shared = KeychainHelper()
    private init() {}

    /// 默认 service，使用 Bundle Identifier
    private var service: String {
        Bundle.main.bundleIdentifier ?? "com.voidterminal.app"
    }

    /// 保存 Data 到 Keychain
    @discardableResult
    func save(_ data: Data, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        // 先删除已存在的旧值
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        // 仅在设备解锁时可访问，不上传 iCloud 钥匙串
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// 保存字符串到 Keychain
    @discardableResult
    func saveString(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return save(data, account: account)
    }

    /// 从 Keychain 读取 Data
    func readData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    /// 从 Keychain 读取字符串
    func readString(account: String) -> String? {
        guard let data = readData(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 从 Keychain 删除条目
    @discardableResult
    func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - Secure Storage (AES-GCM 加密)

/// 加密本地存储：JSON 编码后用 AES-256-GCM 加密，密钥存 Keychain
final class SecureStorage {
    static let shared = SecureStorage()
    private init() {}

    /// Keychain 中存储加密密钥的 account
    private let keyAccount = "vt_db_key"

    /// 获取或生成 AES-256 加密密钥（存 Keychain）
    private var encryptionKey: SymmetricKey {
        // 尝试从 Keychain 读取已有密钥
        if let keyData = KeychainHelper.shared.readData(account: keyAccount) {
            return SymmetricKey(data: keyData)
        }
        // 首次使用：生成新的 256 位随机密钥并存入 Keychain
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        KeychainHelper.shared.save(keyData, account: keyAccount)
        return newKey
    }

    /// 将 Encodable 对象加密后存入 UserDefaults
    func save<T: Encodable>(_ value: T, forKey key: String) {
        do {
            let encoded = try JSONEncoder().encode(value)
            // AES-GCM 加密，sealedBox.combined 包含 nonce(12字节) + 密文 + tag(16字节)
            let sealedBox = try AES.GCM.seal(encoded, using: encryptionKey)
            guard let combined = sealedBox.combined else { return }
            UserDefaults.standard.set(combined, forKey: key)
        } catch {
            print("[SecureStorage] 加密保存失败 forKey=\(key): \(error)")
        }
    }

    /// 从 UserDefaults 读取并解密为 Decodable 对象
    func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let combined = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            let decrypted = try AES.GCM.open(sealedBox, using: encryptionKey)
            return try JSONDecoder().decode(type, from: decrypted)
        } catch {
            print("[SecureStorage] 解密读取失败 forKey=\(key): \(error)")
            return nil
        }
    }

    /// 删除指定 key 的加密数据
    func remove(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Password Validator

/// 密码强度验证工具
enum PasswordValidator {
    /// 校验密码：8-64位，至少包含一个字母和一个数字
    /// - Returns: (是否通过, 不通过时的错误提示)
    static func validate(_ password: String) -> (isValid: Bool, message: String?) {
        guard password.count >= 8 else {
            return (false, "密码至少8位，需包含字母和数字")
        }
        guard password.count <= 64 else {
            return (false, "密码不能超过64位")
        }
        let hasLetter = password.range(of: "[a-zA-Z]", options: .regularExpression) != nil
        let hasDigit = password.range(of: "[0-9]", options: .regularExpression) != nil
        guard hasLetter else {
            return (false, "密码需至少包含一个字母")
        }
        guard hasDigit else {
            return (false, "密码需至少包含一个数字")
        }
        return (true, nil)
    }
}
