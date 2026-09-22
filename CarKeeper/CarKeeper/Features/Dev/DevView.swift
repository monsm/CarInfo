import SwiftUI
import UIKit

// =============================================================================
//  开发者工具 —— v4 信息架构
// =============================================================================
//  这一页是「设计令牌 + 运行状态」的检查器，用来在真机上核对深浅双模式。
//  ① 令牌按类分组：画布与表面 / 文字 / 语义色 / 几何 / 动效
//     —— 每个色块都带 HEX，每种字体都用自己的字号渲染出来（不是写一句话描述它）
//  ② 运行状态：加载耗时、指令数、能耗记录数、缓存条目、网络状态
//     —— 还包括那批「启动了但从来没人看」的监控（内存 / 网络质量 / 离线 /
//        性能 / 崩溃 / 充电状态 / 摇一摇 / 维保里程）。它们本来就跑着，
//        只是输出没有任何界面在显示 —— 那就等于没有。
//  ③ 操作：复制诊断信息 / 清除缓存（带确认）
// =============================================================================

struct DevView: View {
    private let store = AppStore.shared
    @State private var showClearConfirm = false

    // 订阅那些「启动了但没人看」的监控。用 @ObservedObject 而不是直接读单例：
    // 内存每 10 秒刷新一次、网络质量也是周期性的 —— 不订阅就永远停在打开那一瞬的值。
    @ObservedObject private var memory = MemoryMonitor.shared
    @ObservedObject private var networkQuality = NetworkQualityMonitor.shared
    @ObservedObject private var offline = OfflineModeManager.shared
    @ObservedObject private var performance = PerformanceTracker.shared
    @ObservedObject private var chargeMonitor = ChargingStatusMonitor.shared
    @ObservedObject private var focus = FocusModeManager.shared
    private let crashReporter = CrashReporter.shared

    private struct SWatch: Identifiable {
        let id = UUID()
        let name: String
        let color: Color
        let note: String
    }

    private struct TypeToken: Identifiable {
        let id = UUID()
        let name: String
        let metrics: String
        let font: Font
        let sample: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TokensSpacing.lg) {
                DSPageTitle(title: "设计令牌", subtitle: "颜色、字体、间距、圆角、动效的唯一来源")
                themeEntry
                swatchGroup(title: "画布与表面", footer: "内容层不透明：玻璃只允许出现在导航栏、Tab 栏与弹层。", items: surfaceTokens)
                swatchGroup(title: "语义色", footer: "颜色只来自系统，且只表达状态；界面里没有装饰性彩色。", items: semanticTokens)
                typographyGroup
                kvGroup("几何", geometry, footer: "页面边距 20pt、分组圆角 12pt、发丝线 0.5pt 是全 App 的定值。")
                kvGroup("动效", motion, footer: "只有两类：状态变化的弹簧，以及一次性绘制。")
                kvGroup("运行状态", runtime)
                actionsGroup
                kvGroup("关于", about)
            }
            .padding(.top, TokensSpacing.sm)
            .padding(.bottom, TokensSpacing.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pageBackground()
        .scrollBounceBehavior(.basedOnSize)
        .dsPageTitle("设计令牌")
        .confirmationDialog("清除全部车端缓存？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清除缓存", role: .destructive) {
                store.clearCache()
                TokensHaptic.result(true)
                ToastManager.shared.show("缓存已清除", icon: "trash")
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("只清空内存中的车况 / 充电 / 定位 / 环境 / 检测 / 消息缓存，不会退出登录。")
        }
    }

    // MARK: - 艺术主题入口

    /// 艺术主题入口。切换后**全 App** 立刻变 ——
    /// 令牌（TokensPalette）是唯一读取点，而这里换的是值，不是名字。
    /// 样张页：Features/ThemeGalleryView.swift；取值：Design/ArtTheme.swift。
    private var themeEntry: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            DSSectionHeader(title: "艺术主题")
            NavigationLink {
                ThemeGalleryView()
            } label: {
                HStack(spacing: TokensSpacing.md) {
                    Circle()
                        .fill(TokensPalette.accent)
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ArtThemeStore.current.title)
                            .font(TokensTypo.subheadline)
                            .foregroundStyle(TokensPalette.primary)
                        Text(ArtThemeStore.current.mechanism)
                            .font(TokensTypo.caption)
                            .foregroundStyle(TokensPalette.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: TokensSpacing.sm)
                    Image(systemName: "chevron.right")
                        .font(.system(size: TokensSize.iconSm, weight: .semibold))
                        .foregroundStyle(TokensPalette.tertiary)
                }
                .padding(TokensSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                        .fill(TokensPalette.surface)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 色板

    private var surfaceTokens: [SWatch] {
        [
            SWatch(name: "canvas", color: TokensPalette.background, note: "页面画布 · systemGroupedBackground"),
            SWatch(name: "surface", color: TokensPalette.nightSurface, note: "分组表面 · secondarySystemGroupedBackground"),
            SWatch(name: "surfaceRaised", color: TokensPalette.nightSurface,
                    note: "内凹表面 · tertiarySystemGroupedBackground"),
            SWatch(name: "hairline", color: TokensPalette.glassBorder, note: "发丝分隔线 · UIColor.separator"),
            SWatch(name: "fill", color: TokensPalette.glassLight, note: "通用填充 · tertiarySystemFill"),
            SWatch(name: "tintSoft", color: TokensPalette.ambient, note: "强调色淡底（选中胶囊）")
        ]
    }

    private var semanticTokens: [SWatch] {
        [
            SWatch(name: "tint", color: TokensPalette.ambient, note: "唯一强调色 · 系统蓝 #007AFF / #0A84FF"),
            SWatch(name: "ok", color: TokensPalette.success, note: "正常 / 已就绪 · systemGreen"),
            SWatch(name: "warn", color: TokensPalette.warning, note: "预警 / 需关注 · systemOrange"),
            SWatch(name: "bad", color: TokensPalette.error, note: "故障 / 异常 · systemRed"),
            SWatch(name: "charge", color: TokensPalette.info, note: "充电 / 电驱状态"),
            SWatch(name: "labelTertiary", color: TokensPalette.tertiary, note: "文字第三级 · 30%")
        ]
    }

    private func swatchGroup(title: String, footer: String? = nil, items: [SWatch]) -> some View {
        DSGroup(title: title, trailing: "\(items.count)", footer: footer) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                DSGroupRow(showsSeparator: idx < items.count - 1) {
                    HStack(spacing: TokensSpacing.md) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(item.color)
                            .frame(width: 28, height: 28)
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(TokensPalette.glassBorder, lineWidth: TokensHair.line))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(TokensTypo.body)
                                .foregroundStyle(TokensPalette.primary)
                            Text(item.note)
                                .font(TokensTypo.caption)
                                .foregroundStyle(TokensPalette.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: TokensSpacing.sm)
                        Text(item.color.hexString())
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(TokensPalette.secondary)
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - 字体

    private var typeTokens: [TypeToken] {
        [
            TypeToken(name: "display", metrics: "96 / ultraLight · 等宽数字", font: TokensTypo.display(96), sample: "88"),
            TypeToken(name: "metric", metrics: "34 / light · 等宽数字", font: TokensTypo.metric(34), sample: "420 km"),
            TypeToken(name: "largeTitle", metrics: "34 / bold", font: TokensTypo.largeTitle, sample: "车况"),
            TypeToken(name: "title2", metrics: "22 / semibold", font: TokensTypo.title2, sample: "驾驶舱"),
            TypeToken(name: "title3", metrics: "20 / semibold", font: TokensTypo.title3, sample: "充电设置"),
            TypeToken(name: "headline", metrics: "17 / semibold", font: TokensTypo.headline, sample: "主操作按钮"),
            TypeToken(name: "body", metrics: "17 / regular · 字距 −0.41", font: TokensTypo.body, sample: "正文与列表行标题"),
            TypeToken(name: "callout", metrics: "16", font: TokensTypo.callout, sample: "次级正文"),
            TypeToken(name: "subheadline", metrics: "15", font: TokensTypo.subheadline, sample: "字段名与说明"),
            TypeToken(name: "footnote", metrics: "13", font: TokensTypo.footnote, sample: "分组标题与脚注"),
            TypeToken(name: "caption", metrics: "12", font: TokensTypo.caption, sample: "标签"),
            TypeToken(name: "data", metrics: "17 · 等宽数字", font: TokensTypo.data, sample: "356 V / 12 A")
        ]
    }

    private var typographyGroup: some View {
        DSGroup(title: "文字", trailing: "\(typeTokens.count)", footer: "字号用 iOS 的真实阶梯；仪器感来自字重差，不来自颜色。") {
            ForEach(Array(typeTokens.enumerated()), id: \.element.id) { idx, token in
                DSGroupRow(showsSeparator: idx < typeTokens.count - 1) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(token.sample)
                            .font(token.font)
                            .foregroundStyle(TokensPalette.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("\(token.name) · \(token.metrics)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(TokensPalette.secondary)
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - 通用键值组

    private func kvGroup(_ title: String, _ rows: [(String, String)], footer: String? = nil) -> some View {
        DSGroup(title: title, footer: footer) {
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                DSGroupRow(showsSeparator: idx < rows.count - 1) {
                    DSKeyValueRow(key: row.0, value: row.1, mono: false)
                }
            }
        }
    }

    // MARK: - 令牌数值

    private var geometry: [(String, String)] {
        [
            ("页面边距", "\(Int(TokensSpacing.page)) pt"),
            ("分组内边距", "\(Int(TokensSpacing.md)) pt"),
            ("行高", "\(Int(TokensSpacing.row)) pt"),
            ("圆角 · 小 / 分组 / 弹层",
             "\(Int(TokensRadius.small)) / \(Int(TokensRadius.medium)) / \(Int(TokensRadius.large)) pt"),
            ("发丝线", "\(TokensHair.line) pt"),
            ("主按钮高度", "\(Int(TokensSize.button)) pt")
        ]
    }

    private var motion: [(String, String)] {
        [
            ("press（按压）", "spring 0.30 / 0.86"),
            ("value（数值变化）", "spring 0.36 / 0.88"),
            ("screen（页面过渡）", "spring 0.42 / 0.90"),
            ("draw（光条一次性绘制）", "easeOut 1.1 s")
        ]
    }

    // MARK: - 运行状态与操作

    private var runtime: [(String, String)] {
        let homeLoad = UserDefaults.standard.double(forKey: "carkeeper_home_load_time")
        let cachedCount = store.caches.compactMap { $0.value }.count
        let mileage = UserDefaults.standard.integer(forKey: "carkeeper_current_mileage")
        let lastService = UserDefaults.standard.integer(forKey: AppStore.lastServiceMileageKey)
        let crashes = crashReporter.readCrashHistory().count

        return [
            ("首页加载耗时", homeLoad > 0 ? String(format: "%.2f s", homeLoad) : "—"),
            ("指令历史", "\(store.commandHistory.count) 条"),
            ("能耗记录", "\(store.energyHistory.count) 次"),
            ("已缓存接口", "\(cachedCount) 项"),
            ("网络状态", networkText),
            ("车辆 ID", store.carId.isEmpty ? "—" : store.carId),
            // ——— 监控：每个都对应一个真的在跑的服务 ———
            ("内存占用", memory.usedMemoryMB > 0
                ? String(format: "%.1f MB", memory.usedMemoryMB) + "（\(memoryLevelText)）"
                : "采样中…"),
            ("网络延迟", networkQuality.latency > 0
                ? String(format: "%.0f ms", networkQuality.latency) + " · \(networkQuality.connectionType)"
                : "未测出"),
            ("离线模式", offline.isOffline ? "已开启" : "关闭"),
            ("API 成功率", performance.apiSuccessRate().map { String(format: "%.0f%%", $0 * 100) } ?? "—"),
            ("崩溃记录", crashes == 0 ? "无" : "\(crashes) 条"),
            ("充电监控", chargeMonitor.summary),
            ("摇一摇锁车", ShakeDetector.shared.isEnabled ? "已开启" : "关闭"),
            ("专注模式", focus.config.enabled ? "已开启" : "关闭"),
            ("车端里程", mileage > 0 ? "\(mileage) km" : "未取到"),
            ("上次保养里程", lastService > 0 ? "\(lastService) km" : "未设置")
        ]
    }

    private var memoryLevelText: String {
        switch memory.warningLevel {
        case 2: return "临界"
        case 1: return "偏高"
        default: return "正常"
        }
    }

    private var networkText: String { store.networkStatus.rawValue }

    private var actionsGroup: some View {
        DSGroup(title: "操作", footer: "诊断信息包含版本、车辆 ID、缓存与网络状态，用于报障时贴给开发。") {
            DSGroupRow {
                DSRow(icon: "doc.on.doc", title: "复制诊断信息") {
                    UIPasteboard.general.string = diagnostics
                    TokensHaptic.result(true)
                    ToastManager.shared.show("诊断信息已复制", icon: "doc.on.doc.fill")
                }
            }
            DSGroupRow(showsSeparator: false) {
                DSRow(icon: "trash", title: "清除缓存", subtitle: "不会退出登录") {
                    showClearConfirm = true
                }
            }
        }
    }

    private var diagnostics: String {
        var lines = ["【CarKeeper 诊断信息】", "版本 \(appVersion) (\(buildNumber))"]
        lines.append("车辆 ID：\(store.carId.isEmpty ? "未绑定" : store.carId)")
        lines.append("登录状态：\(store.isLoggedIn ? "已登录" : "未登录")")
        lines.append("网络状态：\(networkText)")
        for row in runtime { lines.append("\(row.0)：\(row.1)") }
        return lines.joined(separator: "\n")
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private var about: [(String, String)] {
        [
            ("版本", appVersion),
            ("构建", buildNumber),
            ("设计语言", "CarKeeper v4 · iOS 原生"),
            ("外观", "跟随系统（浅色 / 深色各一套）")
        ]
    }
}

// MARK: - HEX 辅助

extension Color {
    /// 返回 6 位 HEX 字符串（不含 #），按当前外观解析动态色
    func hexString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
