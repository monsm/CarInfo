import Foundation

// =============================================================================
//  DateText —— 日期文案的唯一出口（`DateFormatter` 只在这里被构造）
// =============================================================================
//
//  为什么要有这个文件（2026-09-25「性能轮」，先量后改）：
//
//  `DateFormatter` 的构造很贵（它要现装一套 ICU 格式化器），而**每次构造出来的都一样**。
//  在这之前全仓有 9 处 `let f = DateFormatter()`，其中三处落在「每次界面求值都会跑」的
//  路径上，而地图页在车动起来时是**每 1 秒**求值一次（节律见 `RefreshLoop.Cadence`）：
//
//    · `MapTripLine.timeText` —— 「行程」图层里每一枚钉的标题（`MapSpineLayers` 的一行
//      `Text`）。30 段行程 = 30 次构造，**每 1 秒重来一遍**；
//    · `VM.parseDate(_:)` —— 一次调用最多构造 **7 个**（它按 7 种格式挨个试），
//      而它读的是每条记录上的日期串；
//    · `RawLogStore.now()` / `VM.nowText()` —— 每次记一条日志都构造一个。
//
//  改法不是「缓存某一次算出来的字符串」（那会陈旧成假数据），而是**按 (locale, 格式)
//  缓存构造器**：格式串是常量，构造器造一次就永远够用，取出来的值仍是当下的。
//
//  ⚠️ 四条必须写下来的边界：
//
//   ① **locale 是逐调用点的事实，不是这里的规定**。原来 `locale` 有三种情形，这里一种都
//      不合并：`VM.parseDate` 显式钉 `zh_CN`；`APIClient` 与消息自检钉 `en_US_POSIX`
//      （那是**报文格式**，设备若用佛历/和历会打出「2569-09-24」，服务端收到不存在的区间
//      回 0 条，而界面只会说「暂无消息」—— 不报错、不崩、只是永远空，那条注释记在
//      `APIClient.messagesURL` 里）；其余显示用的地方**一直用系统 locale**，所以它们继续
//      传 `nil`（= 不碰 locale）。**搬进来的每一处都与它原来逐字一致** ——
//      这一轮是搬住处，不是改行为。
//
//   ② 池子按 `locale|格式` 做键，所以它**有界**：能进池子的字符串都是写死在源码里的，
//      不存在「用户输入当键」把内存撑大的路。
//
//   ③ **不是 `@MainActor`，也不能是**。读者里有两个明确在后台线程上：`RawLogStore`
//      与 `APIClient`（后者的注释写着「parseMessages 会在协作线程跑，不能在那里假设
//      主线程」）。把本类型标成 `@MainActor` 会让 `messagesURL` 那处**直接编译不过**
//      （调用点是同步的非隔离上下文）—— 所以这里用全仓既有的线程安全形态：
//      `static let shared` + `NSLock`（与 `RawLogStore` 同一个形状，同一个理由）。
//      `DateFormatter` 本身在配置完成后是线程安全的，锁护住的是**池子这张字典**。
//
//   ④ 锁的粒度是「取构造器」这一次，不是「格式化」那一次 —— `string(from:)` 在锁外跑，
//      否则几十段行程的格式化会互相排队。
//
//  `scan/perf.py` 守着①的另一半：**除本文件外，全仓不许再出现 `DateFormatter()`**。
// =============================================================================

final class DateText {

    static let shared = DateText()

    private init() {}

    /// 池子（`locale|格式` → 构造器）。**全仓唯一允许出现 `DateFormatter()` 的地方。**
    private var pool: [String: DateFormatter] = [:]
    private let lock = NSLock()

    /// 取构造器：没有就造一个并留下。**池子的键只有写死在源码里的那几种。**
    ///
    /// - Parameter locale: `nil` = 不碰 locale（沿用系统，与搬迁前的行为一致）；
    ///   显式给字符串 = 钉住那一种（`zh_CN` 给人看，`en_US_POSIX` 给报文）。
    func formatter(_ format: String, locale: String? = nil) -> DateFormatter {
        let key = "\(locale ?? "-")|\(format)"
        lock.lock()
        if let pooled = pool[key] {
            lock.unlock()
            return pooled
        }
        let f = DateFormatter()
        if let locale { f.locale = Locale(identifier: locale) }
        f.dateFormat = format
        pool[key] = f
        lock.unlock()
        return f
    }

    /// 把一个时刻写成那种格式。
    func string(_ date: Date, _ format: String, locale: String? = nil) -> String {
        formatter(format, locale: locale).string(from: date)
    }

    /// 按顺序试几种格式，返回第一个解析成功的时刻（**试的是格式，不是猜内容**）。
    ///
    /// 全部用同一个 locale —— 它原来就是在循环外设一次、循环里共用。
    func date(_ text: String, formats: [String], locale: String? = nil) -> Date? {
        for f in formats {
            if let d = formatter(f, locale: locale).date(from: text) { return d }
        }
        return nil
    }
}
