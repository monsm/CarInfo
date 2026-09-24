// =============================================================================
// WallpaperService — 子页面（非地图）的背景图
// =============================================================================
// 它回答的事：五张子页（车辆 / 充电 / 车控 / 出行 / 车与账号）的底下铺什么。
//
// 为什么是「相册里选一张」而不是在线图：用户 2026-09-24 的原话是「其他页面的
// 背景全部设为当前桌面的背景」。两件事都做不到，于是只能给替代物 ——
//  · iOS 没有读取主屏壁纸的公开 API（壁纸归 SpringBoard 管，App 拿不到）；
//  · 在线图（Unsplash 直链）在部分网络下取不到，取不到就静默回落画布，
//    深色模式下画布是纯黑 —— 用户看到的就是「根本没变，而且更暗了」。
// 本地相册是**唯一不依赖网络**的替代物：用户把桌面壁纸那张图选进来
//（或选任意一张喜欢的图），存成 JPEG 落盘，之后每次启动都还在。
//
// 未选图时的底：`TokensPalette.canvas`（跟随系统深浅色 —— 浅色模式的画布
// 是浅灰、深色模式是黑，都读得清）。选图之后，图铺在画布之上。
//
// 并发：@MainActor 隔离（index / image 是可变状态，唯一写点在网络/磁盘回
// 主线程时）。与 StartupJournal 那把 NSLock 的区别：它被打点从任意线程调，
// 这里不是 —— 两个读点（MapSpineView 的 @ObservedObject / MineView 的
// @ObservedObject）都在主线程。
// =============================================================================
import SwiftUI
import Foundation
import UIKit
import PhotosUI

/// 唯一的壁纸状态。两处读：
///   · MapSpineView 的五张子页（它们自己铺底）
///   · MineView 设置组里那一行（选 / 换 / 不铺）
@MainActor
final class WallpaperService: ObservableObject, @unchecked Sendable {
    static let shared = WallpaperService()

    @Published var image: UIImage?

    /// 持久化文件（Documents 目录，文件共享没开，用户看不见它）。
    /// 存**JPEG 数据**而不是 UIImage：UIImage 的 NSCoding 在 4K 图上不小，
    /// JPEG 压过一遍（0.82 质量）既省磁盘又不会撑爆启动时的解码。
    private static let fileName = "carkeeper-wallpaper.jpg"

    private init() {
        loadFromDisk()
    }

    /// 启动时把上次选的那张读回来（没有就是 nil → 铺画布）。
    private func loadFromDisk() {
        guard let data = Self.readDisk() else { image = nil; return }
        image = UIImage(data: data)  // 解码失败（文件损坏）当没有处理
    }

    /// 相册选中的 `Data`（PhotosPicker 给的就是它）。
    /// 存 JPEG（质量 0.82）：原始 PNG/TIFF 动辄几十 MB，铺背景不需要那个精度。
    func setPhoto(_ data: Data?) {
        guard let data, let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.82) else {
            image = nil
            Self.removeDisk()
            return
        }
        Self.writeDisk(jpeg)
        image = UIImage(data: jpeg)
    }

    /// 不铺了（画布兜底）：清掉图与磁盘。
    func clear() {
        image = nil
        Self.removeDisk()
    }

    // MARK: - 磁盘

    private static func fileURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(fileName)
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
