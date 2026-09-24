// =============================================================================
// WallpaperService — 子页面（非地图）的背景图
// =============================================================================
// 它回答的事：五张子页（车辆 / 充电 / 车控 / 出行 / 车与账号）的底下铺什么。
//
// 为什么是网络图而不是相册图：用户 2026-09-24 的原话是「其他页面的背景全部
// 设为当前桌面的背景」。iOS **没有**读取主屏壁纸的公开 API（壁纸归
// SpringBoard 管，App 进程拿不到），能做到的最接近的一版是：铺一张风景图，
// 观感上与「桌面壁纸」同类；并且可以整张换掉、或者不铺（铺 App 自己的画布）。
//
// 图源：Unsplash 的官方直链（images.unsplash.com/photo-…），它给的就是「CDN 图
// 直接铺底」这件事：带 ?w=&q=&fit= 裁剪，失败时静默回退（不弹错、不白屏）。
//
// 持久化：UserDefaults 里存一个**索引**（存 URL 字符串同样可以，但索引更稳 ——
// 图源列表将来加一张，旧数据不需要迁移）。没有 AppStorage 泛型，所以走这里。
//
// 并发：@MainActor 隔离（index / image 是可变状态，唯一写点在网络回主线程时）。
// 与 StartupJournal 那把 NSLock 的区别：它被打点从任意线程调，这里不是 ——
// 两个读点（MapSpineView 的 @ObservedObject / MineView 的 @ObservedObject）都在主线程。
// =============================================================================
import SwiftUI
import Foundation
import UIKit

/// 壁纸源：Unsplash 官方直链（宽 900、q60、裁剪），按顺序轮换。
/// 为什么不用 `source.unsplash.com`：那个域名已弃用，直链才在服役。
enum WallpaperSource {
    static let photos = [
        "https://images.unsplash.com/photo-1502920151028-3de3b18c9986?w=900&q=60&fit=crop",
        "https://images.unsplash.com/photo-1470071459904-10518252b694?w=900&q=60&fit=crop",
        "https://images.unsplash.com/photo-1449824913835-54d20cfc86f7?w=900&q=60&fit=crop",
        "https://images.unsplash.com/photo-1418019755577-78086b9b3bbe?w=900&q=60&fit=crop"
    ]

    static var count: Int { photos.count }

    /// 越界（负数 / 超范围）时循环取模；列表为空返回 nil。
    static func url(index: Int) -> URL? {
        guard !photos.isEmpty else { return nil }
        let safe = index % photos.count
        let idx = safe < 0 ? safe + photos.count : safe
        return URL(string: photos[idx])
    }
}

/// 唯一的壁纸状态。两处读：
///   · MapSpineView 的五张子页（它们自己铺底）
///   · MineView 设置组里那一行（选 / 换 / 不铺）
///
/// @MainActor：`index` / `image` 是可变状态，唯一写点（网络取完）在 MainActor 上，
/// 读点（视图 body / `@ObservedObject`）也在主线程 —— 主线程内不需要锁，
/// 隔离本身保证一致性。Task 的 hop 回 MainActor 后写 `index` / `image` 是合法的。
@MainActor
final class WallpaperService: ObservableObject, @unchecked Sendable {
    static let shared = WallpaperService()

    @Published var index: Int
    @Published var image: UIImage?

    private static let key = "carkeeper_wallpaper_index"

    private init() {
        let stored = UserDefaults.standard.integer(forKey: Self.key)
        // integer(forKey:) 没存过返回 0 —— 正好等于第一张，不用额外判断。
        index = stored >= 0 ? min(stored, WallpaperSource.count - 1) : 0
        image = nil
    }

    /// 当前这张的 URL（index 越界时循环回范围内；图源空 = nil）。
    var url: URL? { WallpaperSource.url(index: index) }

    /// 手头的图是哪张的 index（-1 = 没有图；`loadImage` 里「等图期间索引被改
    /// 了，旧图不写进来」的判据就是拿它比）。
    private var imageIndex: Int = -1

    /// 取一次当前这张。幂等：已有图且还是同一张就早退，不重发。
    /// body 每帧都会问它，网络不能跟着每帧发。
    func loadImage() {
        let targetIndex = index
        let have = imageIndex
        guard let targetURL = WallpaperSource.url(index: targetIndex) else { return }
        if have == targetIndex { return }  // 手头的就是这一张

        Task { [weak self] in
            guard let self else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: targetURL)
                guard let ui = UIImage(data: data) else { return }
                // 回到 MainActor（写 index / image 都在主线程上，与 @MainActor 隔离一致）。
                await MainActor.run {
                    // 等图期间索引被改（用户连按「换一张」）：旧图不写进来，
                    // 交给下一次 loadImage() 重新取。
                    guard self.index == targetIndex else { return }
                    self.image = ui
                    self.imageIndex = targetIndex
                }
            } catch {
                // 失败静默：背景退回到 App 画布（底色），不弹错、不留白屏。
                // 「失败」与「没图」观感上都是「没有图」，不区分没有意义。
            }
        }
    }

    /// 换下一张（循环，到最后一张回到第一张）。写进 UserDefaults + 立刻取新图。
    func next() {
        index = (index + 1) % max(1, WallpaperSource.count)
        UserDefaults.standard.set(index, forKey: Self.key)
        image = nil
        imageIndex = -1
        loadImage()
    }

    /// 不铺了（底色兜底）：清掉图与持久化。
    func clear() {
        image = nil
        imageIndex = -1
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}
