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
    private let fileManager = FileManager.default

    // 日志文件存储路径
    private var logDirectoryURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("vt_logs")
    }

    // MARK: - 分片存储（写入只追加，不再重写整个文件）
    /// 串行队列：日志的编码/加密/追加写盘都在这里完成，避免阻塞主线程
    private let queue = DispatchQueue(label: "com.voidterminal.securelogger", qos: .utility)
    private static let queueKey = DispatchSpecificKey<UInt8>()

    /// 单个分片最多容纳的条目数
    private let shardCapacity = 500
    /// 日志最大保留条数（超出后从最旧的分片删起）
    private let maxEntries = 20000
    /// 日志最大保留时长（7 天）
    private let maxRetention: TimeInterval = 7 * 24 * 60 * 60
    /// 日志目录最大占用（8MB 硬顶）
    private let maxDiskBytes = 8 * 1024 * 1024

    /// 当前活动分片文件
    private var activeShardURL: URL?
    /// 当前活动分片的写入句柄
    private var activeFileHandle: FileHandle?
    /// 当前活动分片已写入的条目数
    private var activeShardEntryCount = 0
    /// 已封存分片的条目数（key = 文件路径）
    private var archivedShardCounts: [String: Int] = [:]

    /// 写盘失败次数（用于排查日志系统本身是否在丢数据）
    private(set) var writeFailureCount = 0
    /// 加密失败次数
    private(set) var encryptFailureCount = 0

    private init() {
        queue.setSpecific(key: SecureLogger.queueKey, value: 1)
        ensureLogDirectory()
        loadExistingShardCounts()
        openNewShard()
        pruneShards()
    }
    
    // MARK: - 公开方法
    
    /// 记录日志（编码/加密/追加写盘都在后台串行队列完成，不阻塞调用方）
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
        queue.async { [weak self] in
            self?.appendEntry(entry)
        }
    }

    /// 等待队列中待写入的日志全部落盘（退出/导出前调用）
    func flushSync() {
        syncOnQueue { }
    }

    /// 导出加密日志：把所有分片合并成一个文件，并清理旧分片
    func exportLog() -> URL? {
        var exported: URL?
        var exportedCount = 0
        var failureMessage: String?

        syncOnQueue {
            // 先收尾当前分片，确保数据都已落盘
            closeActiveShard()

            let entries = collectAllEntryBlobs()
            guard !entries.isEmpty else { return }

            ensureLogDirectory()
            let fileURL = nextShardURL()

            var fileData = Data()
            fileData.append("VTLOG".data(using: .ascii)!)
            var version: UInt32 = UInt32(1).littleEndian
            fileData.append(Data(bytes: &version, count: 4))
            var entryCount: UInt32 = UInt32(entries.count).littleEndian
            fileData.append(Data(bytes: &entryCount, count: 4))
            for entry in entries {
                var length: UInt32 = UInt32(entry.count).littleEndian
                fileData.append(Data(bytes: &length, count: 4))
                fileData.append(entry)
            }

            do {
                try fileData.write(to: fileURL, options: .completeFileProtectionUntilFirstUserAuthentication)
                for oldFile in allShardFiles() where oldFile != fileURL {
                    try? fileManager.removeItem(at: oldFile)
                }
                archivedShardCounts.removeAll()
                activeShardURL = fileURL
                activeShardEntryCount = entries.count
                activeFileHandle = try? FileHandle(forWritingTo: fileURL)
                exported = fileURL
                exportedCount = entries.count
            } catch {
                failureMessage = error.localizedDescription
            }
        }

        if let url = exported {
            log("exported \(exportedCount) entries to \(url.lastPathComponent)", module: "Logger")
        } else if let message = failureMessage {
            log("export failed: \(message)", level: .error, module: "Logger")
        }
        return exported
    }

    /// 清空全部日志
    func clearLogs() {
        syncOnQueue {
            try? activeFileHandle?.close()
            activeFileHandle = nil
            activeShardURL = nil
            activeShardEntryCount = 0
            archivedShardCounts.removeAll()
            if let files = try? fileManager.contentsOfDirectory(at: logDirectoryURL, includingPropertiesForKeys: nil) {
                for file in files {
                    try? fileManager.removeItem(at: file)
                }
            }
            openNewShard()
            writeFailureCount = 0
            encryptFailureCount = 0
        }
    }

    /// 获取当前日志总条数（用于界面显示）
    var logCount: Int {
        var count = 0
        syncOnQueue {
            count = archivedShardCounts.values.reduce(0, +) + activeShardEntryCount
        }
        return count
    }

    // MARK: - 私有方法
    
    private func ensureLogDirectory() {
        if !fileManager.fileExists(atPath: logDirectoryURL.path) {
            try? fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
        }
    }
    
    /// 在日志队列上同步执行；若已在队列上则直接执行，避免死锁
    private func syncOnQueue(_ work: () -> Void) {
        if DispatchQueue.getSpecific(key: SecureLogger.queueKey) != nil {
            work()
        } else {
            queue.sync(execute: work)
        }
    }

    /// 加密一条日志并追加到活动分片（只追加，不重写已有内容）
    private func appendEntry(_ entry: LogEntry) {
        guard let jsonData = try? JSONEncoder().encode(entry) else {
            encryptFailureCount += 1
            return
        }
        guard let encrypted = encryptWithPublicKey(jsonData) else {
            encryptFailureCount += 1
            return
        }
        rotateShardIfNeeded()
        guard let handle = activeFileHandle else {
            writeFailureCount += 1
            return
        }
        do {
            _ = try handle.seekToEnd()
            var length = UInt32(encrypted.count).littleEndian
            try handle.write(contentsOf: Data(bytes: &length, count: 4))
            try handle.write(contentsOf: encrypted)
            activeShardEntryCount += 1
            try updateActiveHeaderCount()
        } catch {
            writeFailureCount += 1
        }
    }

    /// 分片写满则封存并换新分片
    private func rotateShardIfNeeded() {
        if activeFileHandle == nil {
            openNewShard()
        } else if activeShardEntryCount >= shardCapacity {
            closeActiveShard()
            openNewShard()
            pruneShards()
        }
    }

    /// 生成一个不重复的新分片路径
    private func nextShardURL() -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .prefix(19)
        var url = logDirectoryURL.appendingPathComponent("\(stamp).vtlog")
        var suffix = 1
        while fileManager.fileExists(atPath: url.path) {
            url = logDirectoryURL.appendingPathComponent("\(stamp)-\(suffix).vtlog")
            suffix += 1
        }
        return url
    }

    /// 创建一个新分片（写入文件头并打开写入句柄）
    private func openNewShard() {
        ensureLogDirectory()
        let url = nextShardURL()
        var data = Data()
        data.append("VTLOG".data(using: .ascii)!)
        var version: UInt32 = UInt32(1).littleEndian
        data.append(Data(bytes: &version, count: 4))
        var count: UInt32 = 0
        data.append(Data(bytes: &count, count: 4))
        do {
            // completeUntilFirstUserAuthentication：首次解锁后即使锁屏/后台也能写入，静态仍然加密
            try data.write(to: url, options: .completeFileProtectionUntilFirstUserAuthentication)
            activeFileHandle = try FileHandle(forWritingTo: url)
            activeShardURL = url
            activeShardEntryCount = 0
        } catch {
            writeFailureCount += 1
            activeFileHandle = nil
            activeShardURL = nil
            activeShardEntryCount = 0
        }
    }

    /// 收尾当前分片：回写条目数、关闭句柄，并记录进已封存列表
    private func closeActiveShard() {
        guard let url = activeShardURL else { return }
        try? updateActiveHeaderCount()
        try? activeFileHandle?.close()
        activeFileHandle = nil
        if activeShardEntryCount > 0 {
            archivedShardCounts[url.path] = activeShardEntryCount
        }
        activeShardURL = nil
        activeShardEntryCount = 0
    }

    /// 回写文件头中的条目数（第 9 字节起 4 字节小端序）
    private func updateActiveHeaderCount() throws {
        guard let handle = activeFileHandle else { return }
        _ = try handle.seek(toOffset: 9)
        var count = UInt32(activeShardEntryCount).littleEndian
        try handle.write(contentsOf: Data(bytes: &count, count: 4))
    }

    /// 目录里所有 .vtlog 分片，按文件名排序（ISO 文件名即时间顺序）
    private func allShardFiles() -> [URL] {
        let files = (try? fileManager.contentsOfDirectory(at: logDirectoryURL, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "vtlog" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// 解析单个分片里的所有加密条目
    private func entryBlobs(in fileURL: URL) -> [Data] {
        guard let fileData = try? Data(contentsOf: fileURL), fileData.count >= 13 else { return [] }
        guard String(data: fileData.subdata(in: 0..<5), encoding: .ascii) == "VTLOG" else { return [] }
        guard readUInt32LE(from: fileData, at: 5) == 1 else { return [] }
        var blobs: [Data] = []
        var offset = 13
        while offset + 4 <= fileData.count {
            let entryLen = Int(readUInt32LE(from: fileData, at: offset))
            offset += 4
            guard entryLen > 0, offset + entryLen <= fileData.count else { break }
            blobs.append(fileData.subdata(in: offset..<offset + entryLen))
            offset += entryLen
        }
        return blobs
    }

    /// 汇总所有分片里的加密条目（按时间顺序）
    private func collectAllEntryBlobs() -> [Data] {
        var blobs: [Data] = []
        for fileURL in allShardFiles() {
            blobs.append(contentsOf: entryBlobs(in: fileURL))
        }
        return blobs
    }

    /// 启动时统计已有分片的条目数（活动分片此时还没创建）
    private func loadExistingShardCounts() {
        var counts: [String: Int] = [:]
        for fileURL in allShardFiles() {
            counts[fileURL.path] = entryBlobs(in: fileURL).count
        }
        archivedShardCounts = counts
    }

    /// 按「最近 7 天 + 最多 20000 条 + 目录 8MB 硬顶」清理最旧的分片
    private func pruneShards() {
        guard let activeURL = activeShardURL else { return }
        var totalEntries = activeShardEntryCount
        for value in archivedShardCounts.values {
            totalEntries += value
        }

        var totalBytes = 0
        var shards: [(url: URL, date: Date, size: Int, count: Int)] = []
        for fileURL in allShardFiles() {
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let size = values?.fileSize ?? 0
            totalBytes += size
            if fileURL == activeURL { continue }
            let date = values?.contentModificationDate ?? Date.distantPast
            shards.append((fileURL, date, size, archivedShardCounts[fileURL.path] ?? 0))
        }
        shards.sort { $0.date < $1.date }

        let expireBefore = Date().addingTimeInterval(-maxRetention)
        for shard in shards {
            let expired = shard.date < expireBefore
            let overCount = totalEntries > maxEntries
            let overBytes = totalBytes > maxDiskBytes
            guard expired || overCount || overBytes else { break }
            do {
                try fileManager.removeItem(at: shard.url)
                archivedShardCounts.removeValue(forKey: shard.url.path)
                totalEntries -= shard.count
                totalBytes -= shard.size
            } catch {
                // 删除失败则跳过，等下次清理再试
            }
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
