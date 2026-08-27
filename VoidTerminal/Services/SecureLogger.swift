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
    
    /// 当前活动日志文件（每次启动/导出时一个新文件）
    private var activeLogFileURL: URL
    
    private init() {
        // 直接构造路径，不访问 self 的其他属性
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let date = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .prefix(19)
        activeLogFileURL = docs.appendingPathComponent("vt_logs/\(date).vtlog")
        
        ensureLogDirectory()
        loadExistingLogs()
        writeHeaderIfNeeded()
    }
    
    // MARK: - 公开方法
    
    /// 记录日志（加密并存入内存，导出时统一写盘）
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
        guard let encrypted = encryptWithPublicKey(jsonData) else { return }
        
        encryptedEntries.append(encrypted)
        if encryptedEntries.count > maxEntries {
            encryptedEntries.removeFirst(encryptedEntries.count - maxEntries)
        }
        
        // 实时写盘，确保崩溃后日志不丢失
        flushToDisk()
    }
    
    /// 将所有内存中的加密条目写入活动日志文件
    private func flushToDisk() {
        do {
            var fileData = Data()
            fileData.append("VTLOG".data(using: .ascii)!)
            var version: UInt32 = UInt32(1).littleEndian
            fileData.append(Data(bytes: &version, count: 4))
            var entryCount: UInt32 = UInt32(encryptedEntries.count).littleEndian
            fileData.append(Data(bytes: &entryCount, count: 4))
            for entry in encryptedEntries {
                var length: UInt32 = UInt32(entry.count).littleEndian
                fileData.append(Data(bytes: &length, count: 4))
                fileData.append(entry)
            }
            try fileData.write(to: activeLogFileURL, options: .completeFileProtection)
        } catch {
            // 写盘失败时静默处理，避免日志系统本身导致崩溃
        }
    }
    
    /// 导出加密日志文件
    /// - Returns: 导出的文件路径
    func exportLog() -> URL? {
        guard !encryptedEntries.isEmpty else { return nil }
        
        ensureLogDirectory()
        
        let date = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .prefix(19)
        let fileURL = logDirectoryURL.appendingPathComponent("\(date).vtlog")
        activeLogFileURL = fileURL
        
        var fileData = Data()
        fileData.append("VTLOG".data(using: .ascii)!)
        var version: UInt32 = UInt32(1).littleEndian
        fileData.append(Data(bytes: &version, count: 4))
        let count = encryptedEntries.count
        var entryCount: UInt32 = UInt32(count).littleEndian
        fileData.append(Data(bytes: &entryCount, count: 4))
        for entry in encryptedEntries {
            var length: UInt32 = UInt32(entry.count).littleEndian
            fileData.append(Data(bytes: &length, count: 4))
            fileData.append(entry)
        }
        
        do {
            try fileData.write(to: fileURL, options: .completeFileProtection)
            // 清理旧的 .vtlog 文件（保留当前导出文件）
            if let files = try? fileManager.contentsOfDirectory(at: logDirectoryURL, includingPropertiesForKeys: nil) {
                for oldFile in files where oldFile.pathExtension == "vtlog" && oldFile != fileURL {
                    try? fileManager.removeItem(at: oldFile)
                }
            }
            SecureLogger.shared.log("exported \(count) entries to \(fileURL.lastPathComponent)", module: "Logger")
            return fileURL
        } catch {
            SecureLogger.shared.log("export failed: \(error.localizedDescription)", level: .error, module: "Logger")
            return nil
        }
    }
    
    /// 清除所有日志
    func clearLogs() {
        encryptedEntries.removeAll()
        if let files = try? fileManager.contentsOfDirectory(at: logDirectoryURL, includingPropertiesForKeys: nil) {
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        }
        writeHeaderIfNeeded()
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
    
    /// 如果活动日志文件不存在，写入文件头（VTLOG + version + count占位）
    private func writeHeaderIfNeeded() {
        let fileURL = activeLogFileURL
        guard !fileManager.fileExists(atPath: fileURL.path) else { return }
        var data = Data()
        data.append("VTLOG".data(using: .ascii)!)
        var version: UInt32 = UInt32(1).littleEndian
        data.append(Data(bytes: &version, count: 4))
        var count: UInt32 = 0
        data.append(Data(bytes: &count, count: 4))
        try? data.write(to: fileURL, options: .completeFileProtection)
    }
    
    private func loadExistingLogs() {
        // 启动时从磁盘加载所有 .vtlog 文件的历史条目
        guard let files = try? fileManager.contentsOfDirectory(at: logDirectoryURL, includingPropertiesForKeys: nil) else { return }
        
        let vtlogFiles = files.filter { $0.pathExtension == "vtlog" && $0 != activeLogFileURL }.sorted {
            ($0.lastPathComponent) < ($1.lastPathComponent)
        }
        
        for fileURL in vtlogFiles {
            guard let fileData = try? Data(contentsOf: fileURL) else { continue }
            guard fileData.count >= 13 else { continue }
            
            let magic = String(data: fileData.subdata(in: 0..<5), encoding: .ascii)
            guard magic == "VTLOG" else { continue }
            
            let version = readUInt32LE(from: fileData, at: 5)
            guard version == 1 else { continue }
            
            // 不依赖文件头的 count，按实际数据解析所有条目
            var offset = 13
            while offset + 4 <= fileData.count {
                let entryLen = readUInt32LE(from: fileData, at: offset)
                offset += 4
                guard entryLen > 0, offset + Int(entryLen) <= fileData.count else { break }
                let entryData = fileData.subdata(in: offset..<offset+Int(entryLen))
                encryptedEntries.append(entryData)
                offset += Int(entryLen)
            }
        }
        
        // 限制最大条数
        if encryptedEntries.count > maxEntries {
            encryptedEntries = Array(encryptedEntries.suffix(maxEntries))
        }
    }
    
    /// 从 Data 的指定偏移位置读取小端序 UInt32
    private func readUInt32LE(from data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return data.withUnsafeBytes { ptr in
            let raw = ptr.baseAddress!.advanced(by: offset)
            return raw.assumingMemoryBound(to: UInt32.self).pointee.littleEndian
        }
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
        
        let maxChunkSize = 214  // RSA 2048 with PKCS1: max 245 bytes, leave margin
        
        if data.count <= maxChunkSize {
            guard let encrypted = SecKeyCreateEncryptedData(
                key,
                .rsaEncryptionPKCS1,
                data as CFData,
                nil
            ) else { return nil }
            return encrypted as Data
        } else {
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
