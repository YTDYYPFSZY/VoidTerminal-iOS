import Foundation
import UIKit
import CommonCrypto

// MARK: - 图片缓存管理器（内存 + 磁盘双层缓存）
/// 统一为头像和消息图片提供缓存服务
/// 内存缓存：NSCache，~50MB 上限，App 生命周期内有效
/// 磁盘缓存：Caches/ImageCache 目录，~200MB 上限，跨 App 启动持久化
final class ImageCacheManager {
    static let shared = ImageCacheManager()

    // 内存缓存
    private let memoryCache = NSCache<NSString, UIImage>()
    // 磁盘缓存目录
    private let diskCacheDir: URL
    // 正在进行的下载任务（去重用，避免同一 URL 并发请求多次）
    private var activeTasks: [String: Task<UIImage?, Never>] = [:]
    private let lock = NSLock()

    // 配置
    private let memoryCostLimit: Int = 50 * 1024 * 1024   // 50MB
    private let diskCostLimit: UInt64 = 200 * 1024 * 1024  // 200MB
    private let maxDiskItems = 2000  // 磁盘最多存 2000 个文件

    private init() {
        memoryCache.totalCostLimit = memoryCostLimit
        memoryCache.countLimit = 500

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheDir = caches.appendingPathComponent("ImageCache", isDirectory: true)
        // 确保目录存在
        try? FileManager.default.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// 获取缓存的图片（先内存 → 再磁盘，均无则返回 nil）
    func cachedImage(for url: URL) -> UIImage? {
        let key = cacheKey(for: url)
        // 1. 内存缓存
        if let img = memoryCache.object(forKey: key as NSString) {
            return img
        }
        // 2. 磁盘缓存
        if let data = try? Data(contentsOf: diskFilePath(for: key)),
           let img = UIImage(data: data) {
            // 回填到内存
            let cost = data.count
            memoryCache.setObject(img, forKey: key as NSString, cost: cost)
            return img
        }
        return nil
    }

    /// 加载图片：缓存命中直接返回，否则下载并缓存
    func loadImage(from url: URL) async -> UIImage? {
        let key = cacheKey(for: url)

        // 1. 先查内存缓存（瞬间返回）
        if let img = memoryCache.object(forKey: key as NSString) {
            return img
        }

        // 2. 再查磁盘缓存
        if let data = try? Data(contentsOf: diskFilePath(for: key)),
           let img = UIImage(data: data) {
            let cost = data.count
            memoryCache.setObject(img, forKey: key as NSString, cost: cost)
            return img
        }

        // 3. 去重：如果已有相同 URL 的下载任务在进行，等待它完成
        lock.lock()
        if let existingTask = activeTasks[key] {
            lock.unlock()
            return await existingTask.value
        }
        // 创建新的下载任务
        let task = Task<UIImage?, Never> {
            return await self.downloadAndCache(url: url, key: key)
        }
        activeTasks[key] = task
        lock.unlock()

        let result = await task.value

        lock.lock()
        activeTasks.removeValue(forKey: key)
        lock.unlock()

        return result
    }

    /// 清除所有缓存（内存 + 磁盘）
    func clearAll() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: diskCacheDir)
        try? FileManager.default.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }

    /// 获取磁盘缓存大小（字节）
    var diskCacheSize: UInt64 {
        guard let files = FileManager.default.enumerator(at: diskCacheDir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: UInt64 = 0
        for case let fileURL as URL in files {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += UInt64(size)
            }
        }
        return total
    }

    // MARK: - Private

    private func downloadAndCache(url: URL, key: String) async -> UIImage? {
        var req = URLRequest(url: url)
        req.cachePolicy = .returnCacheDataElseLoad
        req.timeoutInterval = 15

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let img = UIImage(data: data) else { return nil }

            // 写入内存缓存
            let cost = data.count
            memoryCache.setObject(img, forKey: key as NSString, cost: cost)

            // 写入磁盘缓存
            let filePath = diskFilePath(for: key)
            try? data.write(to: filePath, options: .atomic)

            // 异步清理过期缓存
            Task.detached(priority: .background) { [weak self] in
                self?.trimDiskCacheIfNeeded()
            }

            return img
        } catch {
            return nil
        }
    }

    private func cacheKey(for url: URL) -> String {
        // 用 URL 绝对字符串的 MD5 作为缓存 key，避免文件名过长或含特殊字符
        let str = url.absoluteString
        return str.md5Hash
    }

    private func diskFilePath(for key: String) -> URL {
        diskCacheDir.appendingPathComponent(key)
    }

    /// 当磁盘缓存超限，按文件修改时间删除最旧的文件
    private func trimDiskCacheIfNeeded() {
        guard let fm = try? FileManager.default.contentsOfDirectory(
            at: diskCacheDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        var totalSize: UInt64 = 0
        var fileInfos: [(url: URL, size: Int, date: Date)] = []

        for fileURL in fm {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize,
                  let date = values.contentModificationDate else { continue }
            totalSize += UInt64(size)
            fileInfos.append((fileURL, size, date))
        }

        guard totalSize > diskCostLimit || fileInfos.count > maxDiskItems else { return }

        // 按修改时间升序（最旧的在前），删除到 80% 限额
        fileInfos.sort { $0.date < $1.date }
        let targetSize = UInt64(Double(diskCostLimit) * 0.8)
        let targetCount = Int(Double(maxDiskItems) * 0.8)

        for info in fileInfos {
            if totalSize <= targetSize && fileInfos.count <= targetCount { break }
            try? FileManager.default.removeItem(at: info.url)
            totalSize -= UInt64(info.size)
        }
    }
}

// MARK: - String MD5 辅助（用于缓存 key）
extension String {
    var md5Hash: String {
        let data = Data(self.utf8)
        var digest = [UInt8](repeating: 0, count: 16)
        data.withUnsafeBytes { buffer in
            CC_MD5(buffer.baseAddress!, CC_LONG(buffer.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
