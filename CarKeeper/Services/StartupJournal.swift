import Foundation
import UIKit

// =============================================================================
//  启动轨迹 —— 「上一次启动走到了哪一步、是怎么结束的」
// =============================================================================
//
//  为什么需要它（用户 2026-09-24 报的现象）：App 载入不到 10 秒就自己退出，
//  而**系统里没有崩溃记录**。没有记录这件事本身就是诊断信息：
//    · 应用层错误（`fatalError`、数组越界、强解包失败）通常会留下一份 .ips 报告；
//    · 什么都没有，通常意味着**系统级处决** —— 内存回收（jetsam）或看门狗（watchdog）。
//  而系统级处决**不会调用 App 里任何一行代码**，所以想在事后知道「死在哪一步」，
//  唯一的办法是在死之前把路标写到盘上。
//
//  它只做一件事：每到一个可命名的启动阶段，往一个**有界的小文件**里追加一行
//  （阶段名 + 相对启动的秒数 + 此刻的内存水位）。启动阶段结束（默认 12 秒后仍在运行）
//  时写一行收尾标记。下一次启动读它：**没有收尾标记 = 上一次没走完**，
//  于是它出现在「我的 → 诊断 → 上一次启动」里，可一键复制。
//
//  与 2026-09-23 删掉的 N38 `CrashReporter` 的区别（那次删除是用户的要求，
//  理由记在 `Services/Monitoring.swift` 头注里 —— 「不要本机攒出来的数」）：
//    · 不收集业务数据：没有一条来自车端的读数，只有「阶段名 + 时间 + 内存」；
//    · 不累积：只保留**上一次**与**这一次**两次启动，每份上限 4 KB；
//    · 不上业务界面：只在诊断页里，没有「历史条数」这类统计，也不上报任何地方。
//  需要它的理由很具体：没有它，这类闪退只能靠猜 —— 而我们已经猜了一轮。
//
//  落盘方式：整份重写（≤ 4 KB，一次启动十几次），用 `String.write(to:atomically:)` ——
//  与 `ExportDataSection` / `Theme.swift` 同一套已登记的 API，不为它多开几个 SDK 名字。
//  `atomically: true` 是**故意的**：它走临时文件 + rename，所以进程被系统处决也不会留下
//  半份文件（半份文件的「最后一行」会骗人 —— 那是比没有更坏的结果）。
//
//  它记录的内存水位同时也是 jetsam 的证据：如果轨迹停在某个阶段、水位接近上限，
//  那就是内存被杀；如果水位很平，就要去看别的（看门狗 / 被拒 / 系统策略）。
// =============================================================================

final class StartupJournal: @unchecked Sendable {
    static let shared = StartupJournal()

    /// 单个文件的上限：超过就停笔（诊断要的是「死前那几步」，不是长篇日志）。
    static let capBytes = 4096

    /// 启动阶段的长度：这么久之后仍在运行 = 这一次启动**走完了**。
    /// 没有收尾标记，就是「上一次没走完」—— 这是整个机制唯一的判据。
    static let windowSeconds: Double = 12

    private let currentName = "carkeeper-startup-journal.txt"
    private let previousName = "carkeeper-startup-journal-prev.txt"

    /// 打点会从网络回调与后台任务里调用（不只是主线程）——
    /// 与 `RawLogStore` 同一种做法：一把锁 + `@unchecked Sendable`。
    private let lock = NSLock()
    private var lines: [String] = []
    private var bytes = 0
    private var startedAt = Date()
    private var started = false
    private var stopped = false

    private init() {}

    // MARK: - 路径

    /// 放 Documents：文件共享没开（Info.plist 里没有那两个键），用户看不见它；
    /// 里面也没有任何业务数据（见文件头）。
    private func url(_ name: String) -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(name)
    }

    private static func read(_ url: URL?) -> String? {
        guard let url else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - 生命周期

    /// 启动最早的一步（`CarKeeperApp.init`）。把上一次的轨迹留档，再开一份新的。
    func begin() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true
        stopped = false
        startedAt = Date()
        lines = []
        bytes = 0

        // 路径取不到（沙盒目录缺失）时**不静默放过**：那样「上一次」永远是空的，
        // 而空轨迹会被读成「上一次启动是好的」—— 正好反了。所以先取新迹，再留档。
        if let cur = url(currentName), let text = Self.read(cur) {
            if let prev = url(previousName) {
                try? FileManager.default.removeItem(at: prev)
                try? text.write(to: prev, atomically: true, encoding: .utf8)
            }
            try? FileManager.default.removeItem(at: cur)
        }
        add("＝ 这一次启动 \(Self.stamp()) ＝ \(Self.versionLine())")
        flush()
    }

    /// 一个可命名的启动阶段。
    func mark(_ step: String) {
        lock.lock()
        defer { lock.unlock() }
        guard started, !stopped else { return }
        add(String(format: "%6.2fs  %@  内存 %.0f MB",
                   Date().timeIntervalSince(startedAt), step, Self.residentMB()))
        flush()
    }

    /// 在指定秒数之后收尾（默认 12 秒）。走完这一步 = 这一次启动是好的。
    func scheduleFinish(after seconds: Double = StartupJournal.windowSeconds) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.finish()
        }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard started, !stopped else { return }
        stopped = true
        add(String(format: "%6.2fs  ✅ 启动阶段完成", Date().timeIntervalSince(startedAt)))
        flush()
    }

    // MARK: - 读上一次

    /// 上一次启动的轨迹与它是否走完。
    struct PreviousRun {
        let exists: Bool
        let finished: Bool
        let lines: [String]
    }

    func previousRun() -> PreviousRun {
        guard let text = Self.read(url(previousName)) else {
            return PreviousRun(exists: false, finished: true, lines: [])
        }
        let all = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return PreviousRun(exists: true,
                           finished: all.contains { $0.contains("✅") },
                           lines: all)
    }

    // MARK: - 写

    private func add(_ line: String) {
        // 到了上限就停笔（不是截断），而**停笔这件事本身**也写一行 ——
        // 否则「没记」与「没走到」在文件里长得一样（本仓库反复踩的那个坑）。
        if bytes > Self.capBytes { return }
        if bytes + line.utf8.count > Self.capBytes {
            lines.append("（轨迹已达上限，后面的阶段不再记录）")
            bytes = Self.capBytes + 1
            return
        }
        lines.append(line)
        bytes += line.utf8.count
    }

    private func flush() {
        guard let cur = url(currentName) else { return }
        try? lines.joined(separator: "\n").write(to: cur, atomically: true, encoding: .utf8)
    }

    // MARK: - 小工具

    private static func stamp() -> String {
        let f = DateFormatter()
        // 钉住 locale，理由与网络层那处一样：非公历设备会打出不存在的年份。
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm:ss"
        return f.string(from: Date())
    }

    private static func versionLine() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "版本 \(v) (\(b)) · iOS \(UIDevice.current.systemVersion)"
    }

    /// 此刻的常驻内存（与 `MemoryMonitor` 同一套 `task_info`；这里各记各的，
    /// 不依赖监控是否已启动 —— 轨迹要能在监控启动之前就工作）。
    private static func residentMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.stride) / 4
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1024 / 1024
    }
}
