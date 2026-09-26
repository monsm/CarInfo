import SwiftUI

// =============================================================================
//  MapWallpaperLayer —— 五张子页（非地图）铺的底色
// =============================================================================
//
//  从 `MapSpineView.swift` 搬来这里（2026-09-25）：那个文件涨到 1211 行，越过了
//  `lintcfg.py` 的 1200 阈值 —— 按那个阈值的用法是把东西搬出去，而不是把文件加进排除清单。
//  搬的是**一件独立的事**（一张铺底的图），界面一字未改。
//
//  为什么是壁纸图而不是 `TokensPalette.canvas`（用户 2026-09-24：「其他页面的背景全部
//  设为当前桌面的背景」）：iOS 没有读主屏壁纸的公开 API（壁纸归 SpringBoard 管，
//  App 进程拿不到）。能做到的最接近的一版是让用户从相册选一张（见 WallpaperService）。
//
//  观感：图片 `resizable + aspectRatio(.fill)` 铺满全屏，`ignoresSafeArea()`；
//  取图失败（或用户点了「不铺」）就回落到 `TokensPalette.canvas` —— 观感上等于删暗层
//  之前那层 `TokensPalette.canvas`，只是现在它是 AppCanvas 透出来的画布，不再是「暗层」。
//
//  调用点只有一个：`MapSpineView.pageBody` 里那五张子页的
//  `.background { MapWallpaperLayer(image: wallpaper.image).ignoresSafeArea() }`。
//  外层还要 `.ignoresSafeArea()` 一次，是因为**铺到屏顶的是背景、内容要留在安全区里**
//（用户 2026-09-25 第 3 条：子页顶部的圆角被状态栏切掉了）。
struct MapWallpaperLayer: View {
    /// 相册选中的那张（`nil` = 没选 / 点了「不铺」）
    let image: UIImage?

    var body: some View {
        ZStack {
            // 底色兜底：没选图（或点了「不铺」）就铺画布（跟随系统深浅色 ——
            // 浅色模式浅灰、深色模式近黑，但那是 AppCanvas 的颜色，不再是「暗层」）。
            TokensPalette.canvas
            // 选中的那张（相册本地取，不依赖网络）：铺满全屏，`aspectRatio(.fill)` 裁满。
            if let img = image {
                //  ⚠️ 2026-09-26（「聚焦那一档时图源点不动」那一轮）——这一格补了
                //  `.frame(...)` / `.clipped()` / `.allowsHitTesting(false)` 三件。
                //  **它不是那一轮的病根**（那一层在 `MineView.wallpaperRow` 的缩略图上，
                //  诊断写在那里），但它是**同一类写法**里的最大一张：`.fill` 报出来的
                //  尺寸是「填满提案」的那个尺寸（竖图铺 402×874 的屏报 491×874，
                //  横图报 1554×874）——一大截画在框外，而且没有人裁它。
                //  两张图的差别就在这里：一张铺底图不需要任何一份命中，
                //  所以这两句是照「背景装饰」这个事实写的，不是照那一轮的猜测写的。
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
        }
    }
}
