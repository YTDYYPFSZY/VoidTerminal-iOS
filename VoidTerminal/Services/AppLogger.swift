import Foundation

final class AppLogger {
    static let shared = AppLogger()
    private(set) var logs: [String] = []
    private let maxLogs = 100
    
    func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(message)"
        DispatchQueue.main.async {
            self.logs.insert(line, at: 0)
            if self.logs.count > self.maxLogs {
                self.logs = Array(self.logs.prefix(self.maxLogs))
            }
        }
        print(line)
    }
    
    func clear() {
        logs.removeAll()
    }
}
