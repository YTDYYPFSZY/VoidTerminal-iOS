import Foundation
import Security

/// 加密日志管理器
/// 日志从产生时即使用 RSA 公钥加密存储，App 内不显示日志内容
/// 导出 .vtlog 文件后，管理员使用私钥解密查看
final class SecureLogger {
    static let shared = SecureLogger()
    
    // MARK: - RSA 公钥（Base64 编码，用于加密日志）
    // PKCS#1 格式 RSA 公钥（270 字节 DER），适配 SecKeyCreateWithData
    private static let publicKeyBase64 = "MIIBCgKCAQEA0hYtc6pwgsLpWyZk3y8dQezstuIilPyG6yTbeofSwysXeQIigfDVsLX7zro6cfB4fVhMAagQ/1M0puvyTruYwgMVY90lIujHlHYjs8mZxKjB0aQJUZXsRqWWoGdAbT6GSHZt4xxTN3KsrUD25IA5zaehDqdGLAZoy/OLW6Qs4mcg2B0cMI4o+inYaeodJoD4jQiUZO/svdr+S+xmRLK83E4qCCrDkr41ruAv/3V9OM673ILpt+6zhgzQG6dJxEVOnm2ik0oRPvxPZNER7QuZ+YzguOLcI3UqzKND8iFon1yWj7I8lnMBGpVKrkSAc39/BkDnZz+78BWoaRCJeNoOMwIDAQAB"
    
    // MARK: - 日志条目
    private struct LogEntry: Codable {
        let timestamp: Double
        let level: String
        let module: String
        let message: String
    }
    
    // MARK: - 属性
    private var encryptedEntries: [Data] = []  // 内存中保存加密后的日志条目
    private let maxEntries = 500
    private let fileManager = FileManager.default
    
    // 日志文件存储路径
    private var logDirectoryURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("vt_logs")
    }
    
    private var currentLogFileURL: URL {
        let date = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .prefix(19)
        return logDirectoryURL.appendingPathComponent("\(date).vtlog")
    }
    
    private init() {
        ensureLogDirectory()
        loadExistingLogs()
    }
    
    // MARK: - 公开方法
    
    /// 记录日志（立即加密）
    func log(_ message: String, level: LogLevel = .info, module: String = "General", userId: String? = nil) {
        var msg = message
        if let uid = userId {
            msg = "[user:\(uid)] \(message)"
        }
        
        let entry = LogEntry(
            timestamp: Date().timeIntervalSince1970,
            level: level.rawValue,
            module: module,
            message: msg
        )
        
        guard let jsonData = try? JSONEncoder().encode(entry) else { return }
        
        // 使用 RSA 公钥加密每条日志
        guard let encrypted = encryptWithPublicKey(jsonData) else { return }
        
        DispatchQueue.main.async {
            self.encryptedEntries.append(encrypted)
            if self.encryptedEntries.count > self.maxEntries {
                self.encryptedEntries.removeFirst(self.encryptedEntries.count - self.maxEntries)
            }
        }
    }
    
    /// 导出加密日志文件
    /// - Returns: 导出的文件路径
    func exportLog() -> URL? {
        guard !encryptedEntries.isEmpty else { return nil }
        
        ensureLogDirectory()
        let fileURL = currentLogFileURL
        
        // 文件格式：魔数 + 版本号 + 条目数量 + 加密条目列表
        var fileData = Data()
        
        // 魔数 "VTLOG" (4 bytes)
        fileData.append("VTLOG".data(using: .ascii)!)
        
        // 版本号 (4 bytes, big endian)
        var version: UInt32 = 1
        fileData.append(Data(bytes: &version, count: 4))
        
        // 条目数量 (4 bytes, big endian)
        let count = encryptedEntries.count
        var entryCount: UInt32 = UInt32(count)
        fileData.append(Data(bytes: &entryCount, count: 4))
        
        // 每条加密日志：长度(4 bytes) + 加密数据
        for entry in encryptedEntries {
            var length: UInt32 = UInt32(entry.count)
            fileData.append(Data(bytes: &length, count: 4))
            fileData.append(entry)
        }
        
        do {
            try fileData.write(to: fileURL, options: .completeFileProtection)
            return fileURL
        } catch {
            return nil
        }
    }
    
    /// 清除所有日志
    func clearLogs() {
        encryptedEntries.removeAll()
        // 删除所有日志文件
        if let files = try? fileManager.contentsOfDirectory(at: logDirectoryURL, includingPropertiesForKeys: nil) {
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        }
    }
    
    /// 获取当前日志条数（用于界面显示）
    var logCount: Int {
        return encryptedEntries.count
    }
    
    // MARK: - 私有方法
    
    private func ensureLogDirectory() {
        if !fileManager.fileExists(atPath: logDirectoryURL.path) {
            try? fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
        }
    }
    
    private func loadExistingLogs() {
        // 启动时不加载旧日志文件，每次从空开始
        // 如需加载历史日志，可在此实现
    }
    
    /// 使用 RSA 公钥加密数据
    private func encryptWithPublicKey(_ data: Data) -> Data? {
        guard let publicKeyData = Data(base64Encoded: SecureLogger.publicKeyBase64) else {
            return nil
        }
        
        guard let key = SecKeyCreateWithData(
            publicKeyData as CFData,
            [
                kSecAttrKeyType: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass: kSecAttrKeyClassPublic,
                kSecAttrKeySizeInBits: 2048
            ] as CFDictionary,
            nil
        ) else { return nil }
        
        // RSA 加密（PKCS1 填充），较长日志分段加密
        let maxChunkSize = 214  // RSA 2048 with PKCS1: max 245 bytes, leave margin
        
        if data.count <= maxChunkSize {
            // 短数据直接加密
            guard let encrypted = SecKeyCreateEncryptedData(
                key,
                .rsaEncryptionPKCS1,
                data as CFData,
                nil
            ) else { return nil }
            return encrypted as Data
        } else {
            // 长数据分段加密
            var encryptedData = Data()
            var offset = 0
            while offset < data.count {
                let chunkEnd = min(offset + maxChunkSize, data.count)
                let chunk = data[offset..<chunkEnd]
                
                guard let encryptedChunk = SecKeyCreateEncryptedData(
                    key,
                    .rsaEncryptionPKCS1,
                    chunk as CFData,
                    nil
                ) else { return nil }
                
                let chunkData = encryptedChunk as Data
                // 写入分块长度 + 加密数据
                var chunkLen: UInt32 = UInt32(chunkData.count)
                encryptedData.append(Data(bytes: &chunkLen, count: 4))
                encryptedData.append(chunkData)
                
                offset = chunkEnd
            }
            return encryptedData
        }
    }
    
    // MARK: - 日志级别
    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
    }
}
