import Foundation
import Network

/// 网络状态监控
/// 使用 NWPathMonitor 监控网络连接状态，状态变化时通过 SecureLogger 记录
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private var isStarted = false
    private var lastStatus: String = ""

    private init() {}

    /// 启动网络监控
    func start() {
        guard !isStarted else { return }
        isStarted = true

        let pathMonitor = NWPathMonitor()
        monitor = pathMonitor

        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            let status: String
            if path.status == .satisfied {
                if path.usesInterfaceType(.wifi) {
                    status = "WiFi"
                } else if path.usesInterfaceType(.cellular) {
                    status = "蜂窝"
                } else if path.usesInterfaceType(.wiredEthernet) {
                    status = "有线"
                } else {
                    status = "已连接"
                }
                if self.lastStatus != status && !self.lastStatus.isEmpty {
                    SecureLogger.shared.log("network connected via \(status)", module: "Network")
                } else if self.lastStatus.isEmpty {
                    // 首次启动只记录一次
                    SecureLogger.shared.log("network initial status: \(status)", module: "Network")
                }
            } else {
                status = "断开"
                if self.lastStatus != status {
                    SecureLogger.shared.log("network disconnected", level: .warn, module: "Network")
                }
            }

            self.lastStatus = status
        }

        pathMonitor.start(queue: queue)
    }

    /// 停止网络监控
    func stop() {
        guard isStarted else { return }
        isStarted = false
        monitor?.cancel()
        monitor = nil
        SecureLogger.shared.log("network monitor stopped", module: "Network")
    }

    /// 当前是否有网络连接
    var isConnected: Bool {
        return monitor?.currentPath.status == .satisfied
    }
}
