import SwiftUI

struct DebugLogView: View {
    @State private var logs: [String] = []
    @State private var timer: Timer?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.vtBG.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if logs.isEmpty {
                            Text("暂无日志，登录后会自动记录")
                                .foregroundColor(.vtTextDim)
                                .padding()
                        }
                        ForEach(logs, id: \.self) { log in
                            Text(log)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.vtText)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 12)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("调试日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空") {
                        AppLogger.shared.clear()
                        logs = []
                    }
                }
            }
            .onAppear {
                logs = AppLogger.shared.logs
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    logs = AppLogger.shared.logs
                }
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
        }
    }
}
