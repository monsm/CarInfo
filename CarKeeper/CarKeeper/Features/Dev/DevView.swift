import SwiftUI
import UIKit

// =============================================================================
//  开发者工具 —— v4 信息架构
// =============================================================================
//  这一页是「设计令牌 + 运行状态」的检查器，用来在真机上核对深浅双模式。
//  ① 令牌按类分组：画布与表面 / 文字 / 语义色 / 几何 / 动效
//     —— 每个色块都带 HEX，每种字体都用自己的字号渲染出来（不是写一句话描述它）
//  ② 运行状态：加载耗时、指令数、能耗记录数、缓存条目、网络状态
//  ③ 操作：复制诊断信息 / 清除缓存（带确认）
// =============================================================================

struct DevView: View {
    private let store = AppStore.shared
    @State private var showClearConfirm = false

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
            VStack(alignment: .leading, spacing: DS.Space.gap) {
                swatchGroup(title: "画布与表面", footer: "内容层不透明：玻璃只允许出现在导航栏、Tab 栏与弹层。", items: surfaceTokens)
                swatchGroup(title: "语义色", footer: "颜色只来自系统，且只表达状态；界面里没有装饰性彩色。", items: semanticTokens)
                typographyGroup
                kvGroup("几何", geometry, footer: "页面边距 20pt、分组圆角 12pt、发丝线 0.5pt 是全 App 的定值。")
                kvGroup("动效", motion, footer: "只有两类：状态变化的弹簧，以及一次性绘制。")
                kvGroup("运行状态", runtime)
                actionsGroup
                kvGroup("关于", about)
            }
            .padding(.top, DS.Space.sm)
            .padding(.bottom, DS.Space.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(KanseiPalette.background)
        .navigationTitle("设计令牌")
        .confirmationDialog("清除全部车端缓存？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清除缓存", role: .destructive) {
                store.clearCache()
                DSHaptic.result(true)
                ToastManager.shared.show("缓存已清除", icon: "trash")
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("只清空内存中的车况 / 充电 / 定位 / 环境 / 检测 / 消息缓存，不会退出登录。")
        }
    }

    // MARK: - 色板

    private var surfaceTokens: [SWatch] {
        [
            SWatch(name: "canvas", color: KanseiPalette.background, note: "页面画布 · systemGroupedBackground"),
            SWatch(name: "surface", color: KanseiPalette.nightSurface, note: "分组表面 · secondarySystemGroupedBackground"),
            SWatch(name: "surfaceRaised", color: KanseiPalette.nightSurface,
                    note: "内凹表面 · tertiarySystemGroupedBackground"),
            SWatch(name: "hairline", color: KanseiPalette.glassBorder, note: "发丝分隔线 · UIColor.separator"),
            SWatch(name: "fill", color: KanseiPalette.glassLight, note: "通用填充 · tertiarySystemFill"),
            SWatch(name: "tintSoft", color: KanseiPalette.ambient, note: "强调色淡底（选中胶囊）")
        ]
    }

    private var semanticTokens: [SWatch] {
        [
            SWatch(name: "tint", color: KanseiPalette.ambient, note: "唯一强调色 · 系统蓝 #007AFF / #0A84FF"),
            SWatch(name: "ok", color: KanseiPalette.success, note: "正常 / 已就绪 · systemGreen"),
            SWatch(name: "warn", color: KanseiPalette.warning, note: "预警 / 需关注 · systemOrange"),
            SWatch(name: "bad", color: KanseiPalette.error, note: "故障 / 异常 · systemRed"),
            SWatch(name: "charge", color: KanseiPalette.info, note: "充电 / 电驱状态"),
            SWatch(name: "labelTertiary", color: KanseiPalette.tertiary, note: "文字第三级 · 30%")
        ]
    }

    private func swatchGroup(title: String, footer: String? = nil, items: [SWatch]) -> some View {
        DSGroup(title: title, trailing: "\(items.count)", footer: footer) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                DSGroupRow(showsSeparator: idx < items.count - 1) {
                    HStack(spacing: DS.Space.md) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(item.color)
                            .frame(width: 28, height: 28)
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(KanseiPalette.glassBorder, lineWidth: DS.Hair.line))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(DS.Typo.body)
                                .foregroundStyle(KanseiPalette.primary)
                            Text(item.note)
                                .font(DS.Typo.caption)
                                .foregroundStyle(KanseiPalette.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: DS.Space.sm)
                        Text(item.color.hexString())
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(KanseiPalette.secondary)
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
            TypeToken(name: "display", metrics: "96 / ultraLight · 等宽数字", font: DS.Typo.display(96), sample: "88"),
            TypeToken(name: "metric", metrics: "34 / light · 等宽数字", font: DS.Typo.metric(34), sample: "420 km"),
            TypeToken(name: "largeTitle", metrics: "34 / bold", font: DS.Typo.largeTitle, sample: "车况"),
            TypeToken(name: "title2", metrics: "22 / semibold", font: DS.Typo.title2, sample: "驾驶舱"),
            TypeToken(name: "title3", metrics: "20 / semibold", font: DS.Typo.title3, sample: "充电设置"),
            TypeToken(name: "headline", metrics: "17 / semibold", font: DS.Typo.headline, sample: "主操作按钮"),
            TypeToken(name: "body", metrics: "17 / regular · 字距 −0.41", font: DS.Typo.body, sample: "正文与列表行标题"),
            TypeToken(name: "callout", metrics: "16", font: DS.Typo.callout, sample: "次级正文"),
            TypeToken(name: "subheadline", metrics: "15", font: DS.Typo.subheadline, sample: "字段名与说明"),
            TypeToken(name: "footnote", metrics: "13", font: DS.Typo.footnote, sample: "分组标题与脚注"),
            TypeToken(name: "caption", metrics: "12", font: DS.Typo.caption, sample: "标签"),
            TypeToken(name: "data", metrics: "17 · 等宽数字", font: DS.Typo.data, sample: "356 V / 12 A")
        ]
    }

    private var typographyGroup: some View {
        DSGroup(title: "文字", trailing: "\(typeTokens.count)", footer: "字号用 iOS 的真实阶梯；仪器感来自字重差，不来自颜色。") {
            ForEach(Array(typeTokens.enumerated()), id: \.element.id) { idx, token in
                DSGroupRow(showsSeparator: idx < typeTokens.count - 1) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(token.sample)
                            .font(token.font)
                            .foregroundStyle(KanseiPalette.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("\(token.name) · \(token.metrics)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(KanseiPalette.secondary)
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
            ("页面边距", "\(Int(DS.Space.page)) pt"),
            ("分组内边距", "\(Int(DS.Space.cardPadding)) pt"),
            ("行高", "\(Int(DS.Space.row)) pt"),
            ("圆角 · 小 / 分组 / 弹层", "\(Int(DS.Radius.small)) / \(Int(DS.Radius.card)) / \(Int(DS.Radius.hero)) pt"),
            ("发丝线", "\(DS.Hair.line) pt"),
            ("主按钮高度", "\(Int(DS.Size.button)) pt")
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
        return [
            ("首页加载耗时", homeLoad > 0 ? String(format: "%.2f s", homeLoad) : "—"),
            ("指令历史", "\(store.commandHistory.count) 条"),
            ("能耗记录", "\(store.energyHistory.count) 次"),
            ("已缓存接口", "\(cachedCount) 项"),
            ("网络状态", networkText),
            ("车辆 ID", store.carId.isEmpty ? "—" : store.carId)
        ]
    }

    private var networkText: String { store.networkStatus.rawValue }

    private var actionsGroup: some View {
        DSGroup(title: "操作", footer: "诊断信息包含版本、车辆 ID、缓存与网络状态，用于报障时贴给开发。") {
            DSGroupRow {
                DSRow(icon: "doc.on.doc", title: "复制诊断信息") {
                    UIPasteboard.general.string = diagnostics
                    DSHaptic.result(true)
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
