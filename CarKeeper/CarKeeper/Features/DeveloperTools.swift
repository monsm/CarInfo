// =============================================================================
// E63-E67 开发者与调试工具
// =============================================================================

import SwiftUI
import UniformTypeIdentifiers

// MARK: - E63 崩溃日志在线查看
struct CrashLogViewer: View {
    @StateObject private var reporter = CrashReporter.shared

    var body: some View {
        List(reporter.readCrashHistory(), id: \.self) { log in
            ScrollView {
                Text(log)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .listStyle(.plain)
        .background(TokensPalette.background)
        .navigationTitle("崩溃日志")
        .toolbar {
            Button("清除日志") { reporter.clearCrashHistory() }
                .foregroundColor(TokensPalette.error)
        }
    }
}

// MARK: - E64 性能瓶颈报告
struct PerformanceReport: View {
    @StateObject private var tracker = PerformanceTracker.shared

    var body: some View {
        VStack(spacing: TokensSpacing.md) {
            HStack {
                Text("页面加载时间")
                Spacer()
                Text("\(tracker.homeLoadTime, specifier: "%.2f")s")
                    .foregroundColor(tracker.homeLoadTime > 2 ? .red : .green)
            }
            HStack {
                Text("内存使用")
                Spacer()
                Text("\(MemoryMonitor.shared.usedMemoryMB, specifier: "%.0f") MB")
                    .foregroundColor(MemoryMonitor.shared.warningLevel > 0 ? .orange : .green)
            }
            HStack {
                Text("网络延迟")
                Spacer()
                Text("\(NetworkQualityMonitor.shared.latency, specifier: "%.0f")ms")
                    .foregroundColor(NetworkQualityMonitor.shared.latency > 500 ? .red : .green)
            }
        }
        .padding()
        .glassCard()
    }
}

// MARK: - E65 API请求模拟
class MockAPIClient {
    static let shared = MockAPIClient()
    @Published var mockMode = false

    func getMockCarData() -> [String: Any] {
        return [
            // 用真实报文的键名，避免模拟数据与线上解析逻辑“互相印证”出错误结论
            "charge": ["RemainPower": 75, "RemainedPowerMile": 280, "ChrgStatus": "0"],
            "control": ["DriverDoorLock": 0, "Door": 0, "LeftAnteriorWindowDegree": 0],
            "location": ["Lat": 39.9, "Lng": 116.4, "ValidGps": true]
        ]
    }
}

// MARK: - E66 数据导入恢复
struct DataImportView: View {
    private let store = AppStore.shared
    @State private var showPicker = false

    var body: some View {
        List {
            Section("导入数据") {
                Button("从JSON导入") { showPicker = true }
                Button("从CSV导入行程") {}
            }
            Section("恢复数据") {
                Button("恢复上次会话") {}
                Button("从备份恢复") {}
            }
        }
        .sheet(isPresented: $showPicker) {
            FilePicker(allowedContentTypes: [.json])
        }
    }
}

struct FilePicker: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            // 处理文件选择
        }
    }
}

// MARK: - E67 A/B测试框架
class FeatureFlags : ObservableObject {
    static let shared = FeatureFlags()
    @Published var flags: [String: Bool] = [:]

    func enable(_ flag: String) { flags[flag] = true }
    func disable(_ flag: String) { flags[flag] = false }
    func isAvailable(_ flag: String) -> Bool { flags[flag] ?? false }
}

struct FeatureFlagToggle: View {
    let flag: String
    let title: String
    @StateObject private var flags = FeatureFlags.shared

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle("", isOn: Binding(
                get: { flags.isAvailable(flag) },
                set: { (newValue: Bool) in
                    if newValue { flags.enable(flag) } else { flags.disable(flag) }
                }
            ))
            .labelsHidden()
        }
        .padding()
        .glassCard()
    }
}
