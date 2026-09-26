// =============================================================================
// WallpaperService — 子页面（非地图）的背景图
// =============================================================================
// 它回答的事：五张子页（车辆 / 充电 / 车控 / 出行 / 车与账号）的底下铺什么。
//
// 三条路，用户 2026-09-24/25 的两次原话各对应一条：
//   ① 「其他页面的背景全部设为当前桌面的背景」→ 做不到。壁纸归 SpringBoard 管，
//      iOS 没有读主屏壁纸的公开 API。替代物 = 相册自选一张（本地，不依赖网络）。
//   ② 「现在壁纸用必应和 windows 聚焦（每日的），如果需要密钥就算了」→ 两条都在，
//      都是**免密钥的只读 JSON**（见下）。要密钥就整个不做 —— 这是原话里的边界。
//
// 两个在线源（都不需要注册、不需要 key，都是别人给自己产品用的公开取图口）：
//   · 必应每日一图：`HPImageArchive.aspx?format=js&idx=0&n=1` —— 必应首页当天那张，
//     返回 JSON 里 `urlbase` 拼全尺寸后缀就是图。每天换一张（必应按自己的日界线）。
//   · Windows 聚焦：`fd.api.iris.microsoft.com/v4/api/selection?placement=88000820`
//     —— 就是 Windows 锁屏右下角"喜欢这张吗"那套图，返回一批（bcnt=4），
//     按「今天是第几天 % 张数」轮播，所以每天也是一张新的。
//
// 为什么缓存到磁盘（不是每次启动都取）：
//   启动时是先有界面后有网络的。图没到之前铺画布，图到了再换 —— 若每次都等网络，
//   用户每次冷启动都会看到背景"跳"一下。所以取到的图**存成 JPEG 落盘**，
//   同一天之内直接读盘（`stamp` 记住取到的是哪一天）。
//
// 取不到怎么办：**保留上一天那张**（有就继续铺），没有就铺画布。`failed` 让设置行
// 能说一句人话 —— 静默留白会让用户以为"坏了"。这是本仓库反复写过的那条：
// 「没跑」和「跑了没问题」看起来一样，所以失败必须可见。
//
// 并发：@MainActor 隔离（image / source 是可变状态，唯一写点在网络/磁盘回主线程时）。
// =============================================================================
import SwiftUI
import Foundation
import UIKit
import PhotosUI

/// 背景图从哪来。三选一，写在设置的那一行上。
enum WallpaperSource: String, CaseIterable, Identifiable {
    /// 相册自选（本地，不联网）
    case photo
    /// 必应每日一图
    case bing
    /// Windows 聚焦（锁屏那套图）
    case spotlight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: return "相册自选"
        case .bing: return "必应每日"
        case .spotlight: return "Windows 聚焦"
        }
    }

    /// 分段控件里那一段的名字。
    ///
    /// **必须是短的**：三个段挤在同一行，全名（`title`）在那里装不下 ——
    /// 2026-09-26 用户第 1 条之后，图源不再是一个弹窗，而是行里那三格（见
    /// `MineView.wallpaperRow` 那段说明：弹窗两次出过「打不开」的毛病）。
    /// 全名留在那一行的当前值里与无障碍标签里，所以两个名字都有读者。
    var segmentTitle: String {
        switch self {
        case .photo: return "相册"
        case .bing: return "必应"
        case .spotlight: return "聚焦"
        }
    }

    /// 一句话说清它是什么（设置行里那行小字）。不出现实现词。
    var note: String {
        switch self {
        case .photo: return "自己从相册挑一张，存在本机"
        case .bing: return "必应首页当天那张，每天自动换"
        case .spotlight: return "Windows 锁屏那套图，每天自动换"
        }
    }

    /// 要不要联网。只有相册那条不联。
    var isRemote: Bool { self != .photo }
}

/// 唯一的壁纸状态。三处读：
///   · MapSpineView 的五张子页（它们自己铺底，并在启动时催一次取图）
///   · MineView 设置组里那一行（选图源 / 换一张 / 不铺）
@MainActor
final class WallpaperService: ObservableObject, @unchecked Sendable {
    static let shared = WallpaperService()

    /// 当前铺的那张。nil = 画布底色（没选图 / 取图失败 / 点了"不铺"）。
    @Published private(set) var image: UIImage?
    /// 图源。改了它就会去取（相册那条不用取）。
    @Published private(set) var source: WallpaperSource
    /// 图源给的署名一行（在线图才有；必应/聚焦都会带）。空 = 不显示。
    @Published private(set) var credit: String
    /// 最近一次在线取图没成功。界面据此给一句人话，而不是静默留白。
    @Published private(set) var failed: Bool

    private enum Key {
        static let source = "carkeeper_wallpaper_source"
        /// 取到的是哪一天（`dayStamp`）。同一天不重复取。
        static let stamp = "carkeeper_wallpaper_stamp"
        static let credit = "carkeeper_wallpaper_credit"
    }

    /// 持久化文件（Documents 目录，文件共享没开，用户看不见它）。
    /// 存**JPEG 数据**而不是 UIImage：UIImage 的 NSCoding 在 4K 图上不小，
    /// JPEG 压过一遍（0.82 质量）既省磁盘又不会撑爆启动时的解码。
    /// 相册那张与在线那张**共用这一个文件** —— 铺图只有一条路径，不按来源分叉。
    private static let imageFile = "carkeeper-wallpaper.jpg"

    /// 两个取图口（免密钥）。写在这里而不是散在函数里：它们是这套功能的外部依赖。
    private static let bingIndex =
        "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=zh-CN"
    private static let spotlightIndex =
        "https://fd.api.iris.microsoft.com/v4/api/selection?placement=88000820&bcnt=4&country=cn&locale=zh-cn&fmt=json"

    private init() {
        // 初始化顺序：先读盘（同一天的图立刻可见），source/credit 从 UserDefaults 读回。
        source = WallpaperSource(rawValue: UserDefaults.standard.string(forKey: Key.source) ?? "")
            ?? .photo
        credit = UserDefaults.standard.string(forKey: Key.credit) ?? ""
        failed = false
        if let data = Self.readDisk(), let img = UIImage(data: data) {
            image = img
        } else {
            image = nil
        }
    }

    // MARK: - 选图源

    /// 换一种背景来源。在线两条会立刻去取（今天那张已在盘上就重读，不重复下载）。
    func use(_ new: WallpaperSource) {
        guard new != source else { return }
        source = new
        UserDefaults.standard.set(new.rawValue, forKey: Key.source)
        failed = false
        switch new {
        case .photo:
            // 相册那份（选了才有）就在同一个文件里：直接读回来，读不到就是画布。
            credit = ""
            UserDefaults.standard.removeObject(forKey: Key.credit)
            loadFromDisk()
        case .bing, .spotlight:
            Task { await refresh(force: true) }
        }
    }

    /// 再取一次。失败后在设置行上点「重试」走这里 —— 否则「取图没成功」就是一句
    /// 没有出口的话（选同一档不会触发 `Picker` 的 setter，源里也没地方重新发起）。
    func reload() {
        Task { await refresh(force: true) }
    }

    /// 相册选中的 `Data`（PhotosPicker 给的就是它）。
    /// 存 JPEG（质量 0.82）：原始 PNG/TIFF 动辄几十 MB，铺背景不需要那个精度。
    func setPhoto(_ data: Data?) {
        source = .photo
        UserDefaults.standard.set(WallpaperSource.photo.rawValue, forKey: Key.source)
        credit = ""
        failed = false
        UserDefaults.standard.removeObject(forKey: Key.credit)
        guard let data, let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.82) else {
            image = nil
            Self.removeDisk()
            return
        }
        Self.writeDisk(jpeg)
        image = UIImage(data: jpeg)
    }

    /// 不铺了（画布兜底）：清掉图与磁盘，并退回相册那一档 —— 否则下一次
    /// `refreshIfStale()` 会立刻把它又取回来，"不铺"就成了"过一会儿再铺"。
    func clear() {
        image = nil
        credit = ""
        failed = false
        source = .photo
        UserDefaults.standard.set(WallpaperSource.photo.rawValue, forKey: Key.source)
        UserDefaults.standard.removeObject(forKey: Key.stamp)
        UserDefaults.standard.removeObject(forKey: Key.credit)
        Self.removeDisk()
    }

    // MARK: - 每天一次

    /// 启动时催一次（MapSpineView 的 `.task` 调）。同一天已经取到过就什么都不做。
    func refreshIfStale() async {
        guard source.isRemote else { return }
        // 两种情况要取：盘上没有图（首次安装 / 上次没取到），或盘上那张是昨天的。
        if image == nil || UserDefaults.standard.integer(forKey: Key.stamp) != Self.dayStamp() {
            await refresh(force: false)
        }
    }

    /// 取当天那张。`force = true` 时忽略"今天已取过"（用户刚点了某个在线源）。
    ///
    /// 取不到**不删盘上那张**：留着上一天的图比留白强，失败由 `failed` 说出去。
    func refresh(force: Bool) async {
        guard source.isRemote else { return }
        let today = Self.dayStamp()
        if !force, UserDefaults.standard.integer(forKey: Key.stamp) == today, image != nil { return }
        let kind = source
        // 两个源各有一份解析（返回的东西不一样），取图与落盘那一半是共用的。
        var indexURL = Self.spotlightIndex
        if kind == .bing { indexURL = Self.bingIndex }
        do {
            // 索引是一小段 JSON：12 秒对它够用到离谱（那个 timeout 不改）。
            let index = try await Self.fetch(URL(string: indexURL), timeout: Self.indexTimeout)
            // 两个源都归成「一串候选」：必应只有一条（它就是当天那张，没有备选），
            // 聚焦按天轮一张、其余顺次排在后面顶位。
            let picks: [RemotePick]
            if kind == .bing {
                picks = Self.bingPick(from: index).map { [$0] } ?? []
            } else {
                picks = Self.spotlightPicks(from: index, stamp: today)
            }
            guard !picks.isEmpty else {
                failed = true
                return
            }
            //  这一层原本不循环：解析出**一张**，下载它，失败就是 `failed = true`。
            //  用户 2026-09-25 第 8 条（「Windows 聚焦好像又失败了，必应倒是 100% 成功」）
            //  量出来的原因在尺寸：必应那张 341 KB、聚焦那张 1.34–2.0 MB，
            //  而两者此前共用一个 12 秒 timeout（见 `fetch` 的说明）。
            //  所以这里做两件事，**都是加法**（不改「当天是哪张」：候选[0] 仍是轮播给出的那张）：
            //    ① 图用 `imageTimeout`（45 秒）而不是索引那个 12；
            //    ② 这一张下不来就试下一张 —— 索引里本来就给了 4 张。
            var success = false
            for pick in picks.prefix(3) {
                guard let imgURL = URL(string: pick.url) else { continue }
                guard let bytes = try? await Self.fetch(imgURL, timeout: Self.imageTimeout),
                      let decoded = UIImage(data: bytes),
                      let jpeg = decoded.jpegData(compressionQuality: 0.82) else { continue }
                Self.writeDisk(jpeg)
                image = UIImage(data: jpeg)
                credit = pick.credit
                UserDefaults.standard.set(today, forKey: Key.stamp)
                UserDefaults.standard.set(pick.credit, forKey: Key.credit)
                success = true
                break
            }
            failed = !success
        } catch {
            // 索引都没拿到（网络不通 / 对面改了格式）—— 走到这里。
            // **不抛给界面**：背景图不值当弹错，失败由 `failed` 说出去。
            failed = true
        }
    }

    /// 「今天是第几天」（UTC 天序号）。用它而不是日期字符串：比"格式对不对"少一类错。
    private static func dayStamp() -> Int {
        Int(Date().timeIntervalSince1970 / 86_400)
    }

    // MARK: - 取图（两个源各自的解析）

    /// 一条只读 GET，非 200 当失败。
    /// UA 写成本和 App 自己的名字 —— 不伪装成浏览器。
    ///
    /// ⚠️ `timeout` 是**参数**，2026-09-25 晚（用户第 8 条：「Windows 聚焦好像又失败了，
    /// 必应倒是 100% 成功」）拆出来的。量出来的证据：
    ///   · 必应那张 `_1920x1080.jpg` = **341 KB**（实测）
    ///   · 聚焦那张竖图 = **1.34 MB**、横图 = **2.0 MB**（实测，同一个时刻）
    ///   两者相差 4–6 倍，而此前**共用一个 12 秒的 timeout**。
    ///   于是「同一个网络下必应每次成、聚焦有时败」正是这个比值的样子：
    ///   341 KB 在 12 秒内几乎不可能超时，1.34–2 MB 在弱网/移动数据上会。
    ///   这是**尺寸差**，不是解析差 —— 解析那一段（`asset` 键）上一轮已经对着真报文改对，
    ///   本轮又用真响应逐层核过一遍（索引 200 → `ad.portraitImage.asset` 在 → 该 URL 200）。
    private static func fetch(_ url: URL?, timeout: TimeInterval = 12) async throws -> Data {
        guard let url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.setValue("CarKeeper/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// 索引用它（一小段 JSON，12 秒够用到离谱）。
    private static let indexTimeout: TimeInterval = 12
    /// 图用它。**45 秒**是按最慢的那张算的：2.0 MB 在 45 KB/s 的网上正好一分钟，
    /// 留一半余量 —— 「一张 4K 图没下完」不该被记成「聚焦这一源坏了」。
    private static let imageTimeout: TimeInterval = 45

    /// 一天一张图：地址 + 署名。
    private struct RemotePick {
        let url: String
        let credit: String
    }

    /// 必应：`images[0]` 就是当天那张。
    /// `urlbase` 是 `https://www.bing.com/th?id=OHR.xxx_ZH-CN123`，后面接尺寸后缀即可。
    /// 取 1920×1080 而不是 UHD：铺在卡片背后的一层，UHD 要多下几 MB 换不回来的清晰度。
    private static func bingPick(from data: Data) -> RemotePick? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let images = obj["images"] as? [[String: Any]],
              let first = images.first,
              let base = first["urlbase"] as? String else { return nil }
        let credit = (first["copyright"] as? String) ?? ""
        return RemotePick(url: "https://www.bing.com" + base + "_1920x1080.jpg", credit: credit)
    }

    /// Windows 聚焦：外层 `batchrsp.items[]`，每条的 `item` 是**一段 JSON 文本**，
    /// 里面有 `ad`。除图以外的东西都在同一层：`copyright`（署名）、`title`（这张的标题）。
    ///
    /// 署名那两个键名 2026-09-25 用真报文改过：此前读的是 `copyright_text` /
    /// `title_text` —— **这两个键在返回里根本不存在**（真报文只有 `copyright` / `title`），
    /// 所以解析永远落空、署名那行永远是空的。它与图一起坏、但坏得不一样：图整张没有，
    /// 署名只是不显示，看起来像"这张图没有署名"。
    ///
    /// 返回的是**一串候选**（当天那张在最前，其余顺次），不是一个 —— 理由见 `refresh`：
    /// 当天选中的那一张下不来时，下一张顶上。`bcnt=4` 那 4 条本来就都带着图，
    /// 此前只用其中一条，等于把三次现成的机会丢掉。
    private static func spotlightPicks(from data: Data, stamp: Int) -> [RemotePick] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let batch = root["batchrsp"] as? [String: Any],
              let items = batch["items"] as? [[String: Any]] else { return [] }
        var picks: [RemotePick] = []
        for it in items {
            guard let text = it["item"] as? String,
                  let inner = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  let ad = inner["ad"] as? [String: Any],
                  let url = assetURL(in: ad) else { continue }
            // 署名优先取 `copyright`（© 摄影师 / 图库）—— 那是真正的出处；
            // `title` 是这张图的标题，只能算退路。
            let credit = (ad["copyright"] as? String) ?? (ad["title"] as? String) ?? ""
            picks.append(RemotePick(url: url, credit: credit))
        }
        guard !picks.isEmpty else { return [] }
        // 轮播仍然按天（「今天第几天 % 张数」）—— 同一份列表在同一天里给出同一张，
        // 所以「今天这张」是确定的；变的只是「它下不来时谁顶上」。
        let start = max(0, stamp) % picks.count
        return Array(picks[start...]) + Array(picks[..<start])
    }

    /// 在 `ad` 里找取图地址。
    ///
    /// **`asset` 这个键名是 2026-09-25 用真报文核出来的**（此前这里只有 `u` / `url`）。
    /// 实际接口返回的形状是：
    /// ```
    /// "ad": { "landscapeImage": { "asset": "https://res.public.onecdn.static.microsoft/…" },
    ///         "portraitImage":  { "asset": "…" }, "title": …, "copyright": … }
    /// ```
    /// 键名是 `asset`。于是只找 `u` / `url` 的结果是 **`picks` 永远为空 → 聚焦这一源永远取不到图**，
    /// 而必应那一源走的是 `urlbase`（另一条路），所以「必应行、聚焦不行」—— 用户 2026-09-25 报的第 4 条。
    ///
    /// 顺序是**写死的**，不再遍历 `ad.values`：字典遍历顺序在 Swift 里是未定义的，
    /// 同一份报文可能今天取竖图、明天取横图。竖屏手机上先要竖图（1080×1920），
    /// 再退横图，最后才扫所有子字典（接口以后再加尺寸也不会失效）。
    private static func assetURL(in ad: [String: Any]) -> String? {
        for name in ["portraitImage", "landscapeImage", "squareImage"] {
            if let asset = ad[name] as? [String: Any],
               let s = asset["asset"] as? String, s.hasPrefix("http") {
                return s
            }
        }
        // 兜底：接口若是又换了键名，退回「扫每个子字典里的 u / url / asset」。
        for value in ad.values {
            guard let asset = value as? [String: Any] else { continue }
            for key in ["asset", "u", "url"] {
                guard let s = asset[key] as? String else { continue }
                if s.hasPrefix("http") { return s }
            }
        }
        return nil
    }

    // MARK: - 磁盘

    /// 启动时把上次那张读回来（没有就是 nil → 铺画布）。
    private func loadFromDisk() {
        guard let data = Self.readDisk() else { image = nil; return }
        image = UIImage(data: data)  // 解码失败（文件损坏）当没有处理
    }

    private static func fileURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(imageFile)
    }

    private static func readDisk() -> Data? {
        guard let url = fileURL() else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func writeDisk(_ data: Data) {
        guard let url = fileURL() else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func removeDisk() {
        guard let url = fileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
