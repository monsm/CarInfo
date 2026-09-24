import Foundation
import UIKit
// `os_proc_available_memory()` 在 os 框架里（iOS 13+，externalID c:@F@os_proc_available_memory）。
import os

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
//
//  ⚠️ 追加（同日第二轮）：上面那套**在 2–12 秒之间是瞎的**。打点全落在启动的头一两秒
//  （根视图出现 / 首页外壳出现），之后到第 12 秒的收尾标记之间一行都没有 ——
//  而用户报的正是「地图出现之后几秒」自己退出，那恰好落在盲区里：事后打开文件，
//  最后一行是两秒前的某个阶段，既说不出「死在第几秒」，也看不出死的时候主线程在不在动。
//  所以补两样，判据因此变成两条：
//    · **心跳**：每 1 秒一行，写在**后台队列**上 —— 最后一行离死亡时刻不超过 1 秒；
//    · **主线程有没有卡住**：每次心跳让主线程回一句话。心跳还在写、主线程却已经
//      N 秒没回话 = **卡死**（看门狗那种）；心跳自己也停了 = **进程被直接处决**
//      （jetsam 那种）。这两种终止在系统里都没有日志，但在轨迹里长得完全不一样。
//
//  ⚠️ 追加（同日第三轮）：上面那套能说出「死在第几秒、主线程在不在动」，
//  但说出不了「死的时候离被处决还有多远」。用户这一轮的原话是一句猜测：
//  **「没闪退，我感觉是因为内存占用太多被系统杀了」**。
//  而只记常驻内存（320 MB）并不能回答那句猜测 —— 4 GB 与 8 GB 的机器、前台与
//  后台，额度完全不同，320 MB 在有的设备上很远、在有的设备上已经很近。
//  所以补两个数：
//    · **距上限还剩多少**（`os_proc_available_memory()`：系统直接给出的那个额度）——
//      末行只剩 12 MB 就是被内存处决；还剩 320 MB 就**不是**内存的事；
//    · **系统挤压过几次**（`didReceiveMemoryWarningNotification` 计数）——
//      处决之前通常先有一声警告，有与没有指向的不是同一件事。
//  并且从这一版起，下一次启动的结论由 `conclude(...)` 直接写出来
//  （见「结论」一节）：界面与复制出来的轨迹都以那句话开头，不再要求读的人
//  自己拿一张对照表去推 —— 猜到这个阶段就该结束了。
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

    /// 被信号杀掉时留下的那张纸条（见 `catchSignalDeaths`）。
    /// 它**单独一个文件**：写它的地方在信号处理里，那里不能碰轨迹这把锁 ——
    /// 撞上锁就是死锁，而死锁留下的东西比没有更坏（心跳会停在同一秒，
    /// 看起来与「被系统拿走」一模一样）。
    static let fatalName = "carkeeper-fatal.txt"

    /// 打点会从网络回调与后台任务里调用（不只是主线程）——
    /// 与 `RawLogStore` 同一种做法：一把锁 + `@unchecked Sendable`。
    private let lock = NSLock()
    private var lines: [String] = []
    private var bytes = 0
    private var startedAt = Date()
    private var started = false
    private var stopped = false
    /// 上一次那声「被信号杀死」的原文（`begin()` 时取走并删掉，见 `previousRun()`）
    private var previousFatal = ""

    /// 系统挤压过我们几次（`didReceiveMemoryWarningNotification`）。
    ///
    /// 它回答的是「处决之前有没有征兆」：被内存处决之前，系统通常会先发一次内存警告，
    /// 所以「心跳突然断掉，而前面挤压过三次」与「心跳断掉，一声警告都没有」
    /// 指向的并不是同一件事。
    /// 它只活在轨迹里，不另存一份统计 —— 那正是 2026-09-23 删掉的那一类
    /// 「本机攒出来的数」。
    private var memoryWarnings = 0

    /// 通知可能在任意线程到，所以照旧走这把锁。
    func noteMemoryWarning() {
        lock.lock()
        defer { lock.unlock() }
        memoryWarnings += 1
    }

    /// 心跳看门狗。它必须在**后台队列**上跑：否则「主线程卡住」时它自己也停了，
    /// 而「卡住」与「被杀」就分不出来了 —— 那正是它唯一要分辨的那件事。
    private var beat: DispatchSourceTimer?
    private static let beatQueue = DispatchQueue(label: "carkeeper.startup.journal.beat")
    /// 主线程最后一次回话的时刻（与心跳对时用）。
    private var lastMainReply = Date()

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
        // 上一次若是被信号杀掉的，它留了一张纸条：取走、然后删掉 ——
        // 留着会被读成「这一次也崩了」（本仓库最贵的那个坑：分不清「没记」与「没走到」）。
        if let fatal = url(Self.fatalName) {
            previousFatal = Self.read(fatal) ?? ""
            try? FileManager.default.removeItem(at: fatal)
        }
        // 装了哪几个围栏，写进第一行之外的一行 —— 复制轨迹出来时，
        // 「这一次是哪个实验」必须与数据在一起。
        add("＝ 这一次启动 \(Self.stamp()) ＝ \(Self.versionLine())")
        add(LaunchFence.summary)
        // 系统在处决之前通常会先挤压一次。把它记在轨迹这一份东西里，
        // 判据才不只是一条曲线。
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: nil) { _ in
            StartupJournal.shared.noteMemoryWarning()
        }
        // 前台 / 后台各留一行。真机那份轨迹（2026-09-24 第五轮，用户贴回来的原文）
        // 暴露了一个分不开的情况：心跳突然停掉时，**三种死法在轨迹里长得一模一样**——
        // 被系统处决（jetsam）、被用户划掉（SIGKILL，抓不到任何信号）、
        // 以及被切到后台后挂起（挂起时定时器不再开火，轨迹也停在那一秒）。
        // 补上这两行，至少能分出「它是在前台死的，还是被切走了以后才没的」。
        // （只记启动阶段内那 12 秒 —— `mark` 在 `finish()` 之后就不再写。）
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                               object: nil, queue: nil) { _ in
            StartupJournal.shared.mark("进入后台")
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                               object: nil, queue: nil) { _ in
            StartupJournal.shared.mark("回到前台")
        }
        flush()
        startHeartbeat()
    }

    /// 一个可命名的启动阶段。
    func mark(_ step: String) {
        lock.lock()
        defer { lock.unlock() }
        guard started, !stopped else { return }
        add(String(format: "%6.2fs  %@  %@",
                   Date().timeIntervalSince(startedAt), step, Self.memoryTail()))
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
        stopHeartbeat()
    }

    // MARK: - 心跳

    /// 启动阶段内每 1 秒一行。走完启动阶段（`finish`）就停 —— 之后死掉不再是
    /// 「启动阶段的问题」，而「✅」那一行已经把这条边界写在文件里了。
    private func startHeartbeat() {
        stopHeartbeat()
        let timer = DispatchSource.makeTimerSource(queue: Self.beatQueue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.tick() }
        beat = timer
        timer.resume()
    }

    private func stopHeartbeat() {
        beat?.cancel()
        beat = nil
    }

    /// 一次心跳：先问主线程一句话（回话极轻，回不上来才是信息），再落一行。
    private func tick() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.lastMainReply = Date()
            self.lock.unlock()
        }
        lock.lock()
        defer { lock.unlock() }
        guard started, !stopped else { return }
        let now = Date()
        var line = String(format: "%6.2fs  · 心跳  %@",
                          now.timeIntervalSince(startedAt), Self.memoryTail())
        if memoryWarnings > 0 { line += "  内存警告 \(memoryWarnings) 次" }
        // 2.5 秒：正常的一次布局卡顿不该被判成卡死（1 秒的窗口太松，5 秒太迟）。
        // 连续几次心跳都带上这句话 = 主线程一直没回来；中间某一次没有了 = 它回来了。
        let stalled = now.timeIntervalSince(lastMainReply)
        if stalled > 2.5 {
            line += String(format: "  ⚠️ 主线程 %.1f 秒没回话", stalled)
        }
        add(line)
        flush()
    }

    // MARK: - 信号捕获（临时仪器，见 LaunchFence）

    /// 装上信号处理：SIGTRAP（Swift 自己踩到的 trap：越界 / 溢出 / 强解包失败）、
    /// SIGSEGV / SIGBUS / SIGILL（内存与非法指令）、SIGABRT（运行时断言）。
    ///
    /// 为什么必要：1 秒心跳只能告诉你「进程在某一秒没了」，而**两种死法在轨迹里
    /// 长得一样** —— 自己踩到 trap（会发一个信号）与被系统直接拿走
    /// （jetsam / 看门狗，一个信号都不发）。有了这张纸条就分得开：
    ///   · 纸条在 → 是我们自己的代码崩的，纸条里还带着当时的调用栈；
    ///   · 纸条不在 → 进程被系统处决，去读心跳那一列（内存水位 / 主线程是否回话）。
    func catchSignalDeaths() {
        _ = signal(SIGTRAP) { sig in StartupJournal.recordSignalDeath("SIGTRAP", sig) }
        _ = signal(SIGSEGV) { sig in StartupJournal.recordSignalDeath("SIGSEGV", sig) }
        _ = signal(SIGBUS) { sig in StartupJournal.recordSignalDeath("SIGBUS", sig) }
        _ = signal(SIGILL) { sig in StartupJournal.recordSignalDeath("SIGILL", sig) }
        _ = signal(SIGABRT) { sig in StartupJournal.recordSignalDeath("SIGABRT", sig) }
    }

    /// 信号处理体：**不取锁、不碰轨迹**，只把纸条放好然后立刻退出。
    /// 带着一个已经崩掉的运行环境继续跑，只会生出第二份说不清的东西。
    /// （它必须是 `static` 且不捕获任何东西：`signal` 要的是 C 函数指针。）
    static func recordSignalDeath(_ name: String, _ sig: Int32) {
        let stack = Thread.callStackSymbols.joined(separator: "\n      ")
        writeFatal("\(name)（信号 \(sig)）\n      \(stack)")
        _exit(sig)
    }

    private static func writeFatal(_ text: String) {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(fatalName) else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - 读上一次

    /// 上一次启动的轨迹、它是否走完，以及**一句话结论**。
    struct PreviousRun {
        let exists: Bool
        let finished: Bool
        let lines: [String]
        /// 上一次到底是怎么结束的。判据全在轨迹里，不让看的人自己推。
        let verdict: String
    }

    func previousRun() -> PreviousRun {
        var lines: [String] = []
        var hadJournal = false
        if let text = Self.read(url(previousName)) {
            hadJournal = true
            lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        }
        // 纸条排在最前面：它是「上一次怎么死的」最直接的那句话。
        // 它与「✅」可以同时存在 —— 那表示启动那 12 秒走完了，是之后才崩的：
        // 两件事都写着，不替对方下结论。
        if !previousFatal.isEmpty { lines.insert("⚠️ 被信号终止：" + previousFatal, at: 0) }
        // 三元里不放尾随闭包：本仓库在那一带上真出过 CI 编译错（见 4203c67 / 2f088bd），
        // 先算成两个名字，读起来也不再要人替编译器断句。
        let journalFinished = lines.contains { $0.contains("✅") }
        // 什么都没有时按「走完了」报：空不能当证据（同 `add` 的说明）。
        let finished = hadJournal ? journalFinished : previousFatal.isEmpty
        let verdict = Self.conclude(hasJournal: hadJournal,
                                    finished: finished,
                                    signalNote: !previousFatal.isEmpty,
                                    lastLine: lines.last ?? "")
        return PreviousRun(exists: !lines.isEmpty, finished: finished, lines: lines, verdict: verdict)
    }

    // MARK: - 结论

    /// 离额度只剩这么点，就是「被挤死」的样子。
    /// 选 50：一个前台 App 在剩下不到 50 MB 时继续申请内存，系统把它收走是常态；
    /// 而剩下几百 MB 却断掉，就不是内存的事（去看卡死 / 被拒 / 系统策略那一头）。
    private static let tightMB: Double = 50

    /// 一句话结论。判据全部来自轨迹本身，一共两条：
    /// 有没有那张信号纸条，没走完时末行「距上限」还剩多少。
    ///
    /// 它存在的理由很具体：这张表本来是要**人**读的（「心跳停在高水位就是被杀」），
    /// 而用户回过来的是「我感觉是因为内存占用太多被系统杀了」—— 一句猜测。
    /// 判据能算的东西就不该让人猜，所以算成一句能直接读懂的话。
    private static func conclude(hasJournal: Bool,
                                 finished: Bool,
                                 signalNote: Bool,
                                 lastLine: String) -> String {
        if signalNote { return "上一次被信号终止：是我们自己的代码崩的" }
        if !hasJournal { return "没有更早的启动记录" }
        if finished { return "上一次启动走完了：退出的原因不在这里" }
        // 停在「进入后台」之后：它被切走了。挂起与「在后台被收走」从轨迹里分不出来，
        // 但有两件是确定的 —— 不是崩溃（没有纸条），也不是在前台被就地处决。
        if lastLine.contains("进入后台") { return "上一次停在进入后台之后：切走了，或在后台被收走" }
        let head = Self.headroomIn(lastLine)
        // 老轨迹（这一版之前写的）里没有那个数 —— 这里绝不能当成 0：
        // 「没测到」与「一兆都不剩」长得一样，是本仓库最贵的那个坑。
        if head < 0 { return "上一次没走完，末行没有额度读数" }
        if head < Self.tightMB { return "上一次像是被内存杀掉的：末行只剩 \(Int(head)) MB" }
        return "上一次不像内存的事：末行还剩 \(Int(head)) MB"
    }

    /// 从一行里取出「距上限 X MB」里的 X。取不到返回 -1（**不能返回 0**，
    /// 理由同上：0 会被读成「一兆都不剩」，而那正是判据要用的那个数）。
    private static func headroomIn(_ line: String) -> Double {
        guard let r = line.range(of: "距上限 ") else { return -1 }
        let digits = line[r.upperBound...].prefix { $0.isNumber }
        guard !digits.isEmpty else { return -1 }
        return Double(String(digits)) ?? -1
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

    /// 此刻距「被系统处决」还剩多少 MB（`os_proc_available_memory()`，os 框架 iOS 13+）。
    ///
    /// 它是这一版补上的那个数：常驻内存单独看没有判据 —— 320 MB 在 4 GB 的机器上
    /// 很远，在只有几百 MB 额度可用的进程里已经很近。系统把额度直接给出来了，
    /// 所以「水位算不算高」不再需要解释。
    ///
    /// 取不到（模拟器 / 系统不肯给）时返回 0，而 0 在轨迹里写成「—」：
    /// **不能写成 0 MB** —— 「没测到」与「真要没额度了」长得一样，是最贵的那个坑。
    private static func headroomMB() -> Double {
        let bytes = os_proc_available_memory()
        guard bytes > 0 else { return 0 }
        return Double(bytes) / 1024 / 1024
    }

    /// 每一行尾部的那两个数：常驻内存 + 距上限还剩多少。
    ///
    /// 拆成两段拼（而不是写成一个长格式串）：`scan/copy.py` 按**每一行**量长度，
    /// 原来那截再加一个括号就超过 30 字了。
    private static func memoryTail() -> String {
        let used = String(format: "内存 %.0f MB", Self.residentMB())
        let head = Self.headroomMB()
        if head <= 0 { return used + "（距上限 —）" }
        return used + String(format: "（距上限 %.0f MB）", head)
    }
}
