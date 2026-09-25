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
            let index = try await Self.fetch(URL(string: indexURL))
            var pick: RemotePick?
            if kind == .bing {
                pick = Self.bingPick(from: index)
            } else {
                pick = Self.spotlightPick(from: index, stamp: today)
            }
            guard let pick, let imgURL = URL(string: pick.url) else {
                failed = true
                return
            }
            let bytes = try await Self.fetch(imgURL)
            guard let decoded = UIImage(data: bytes),
                  let jpeg = decoded.jpegData(compressionQuality: 0.82) else {
                failed = true
                return
            }
            Self.writeDisk(jpeg)
            image = UIImage(data: jpeg)
            credit = pick.credit
            failed = false
            UserDefaults.standard.set(today, forKey: Key.stamp)
            UserDefaults.standard.set(pick.credit, forKey: Key.credit)
        } catch {
            // 网络不通 / 对面改了格式 —— 都走这里。**不抛给界面**：背景图不值当弹错。
            failed = true
        }
    }

    /// 「今天是第几天」（UTC 天序号）。用它而不是日期字符串：比"格式对不对"少一类错。
    private static func dayStamp() -> Int {
        Int(Date().timeIntervalSince1970 / 86_400)
    }

    // MARK: - 取图（两个源各自的解析）

    /// 一条只读 GET，12 秒超时，非 200 当失败。
    /// UA 写成本和 App 自己的名字 —— 不伪装成浏览器。
    private static func fetch(_ url: URL?) async throws -> Data {
        guard let url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue("CarKeeper/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return data
    }

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
    /// 里面有 `ad`，`ad` 下面的资源键名随版本变过（landscape / portrait / square …）。
    /// 所以不列键名，改成"在 ad 的每个子字典里找 `u` / `url`"—— 加一个尺寸不会失效。
    private static func spotlightPick(from data: Data, stamp: Int) -> RemotePick? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let batch = root["batchrsp"] as? [String: Any],
              let items = batch["items"] as? [[String: Any]] else { return nil }
        var picks: [RemotePick] = []
        for it in items {
            guard let text = it["item"] as? String,
                  let inner = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  let ad = inner["ad"] as? [String: Any],
                  let url = assetURL(in: ad) else { continue }
            let credit = (ad["copyright_text"] as? String) ?? (ad["title_text"] as? String) ?? ""
            picks.append(RemotePick(url: url, credit: credit))
        }
        guard !picks.isEmpty else { return nil }
        return picks[stamp % picks.count]
    }

    /// 在 `ad` 的每个子字典里找取图地址（值以 http 开头的 `u` 或 `url`）。
    private static func assetURL(in ad: [String: Any]) -> String? {
        for value in ad.values {
            guard let asset = value as? [String: Any] else { continue }
            for key in ["u", "url"] {
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
