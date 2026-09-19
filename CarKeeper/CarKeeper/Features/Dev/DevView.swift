import SwiftUI

// =============================================================================
// ColorPreview —— 深色模式颜色预览面板
// 覆盖 Theme 全量色板：品牌色 / 语义色 / 文字层级 / 系统填充 / 玻璃材质 / 背景
// 用法：在任意页面嵌入，或作为独立导航页展示所有颜色在深浅双模式下的表现。
// =============================================================================

// MARK: - 单色卡片

private struct ColorSwatch: View {
    let name: String
    let color: Color
    let sampleText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(color)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(Theme.font(.caption as Font).bold()).foregroundStyle(.primary)
                    if let sampleText {
                        Text(sampleText).font(Theme.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeCompress()
        .glassCard()
        .glassLongPressDeform()
    }
}

// MARK: - 颜色组（标签 + 多个色块）

private struct ColorGroup: View {
    let groupName: String
    let items: [(name: String, color: Color, sample: String?)]
    let gridCols = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 2)

    var body: some View {
        CardBox(title: groupName, side: "\(items.count)") {
            LazyVGrid(columns: gridCols, spacing: Theme.Spacing.sm) {
                ForEach(items.indices, id: \.self) { i in
                    let (name, color, sample) = items[i]
                    HStack(spacing: Theme.Spacing.sm) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color)
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name).font(Theme.caption)
                                .foregroundStyle(.primary)
                            if let sample {
                                Text(sample).font(Theme.micro).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                }
            }
        }
    }
}

// MARK: - 对比预览行（浅色 vs 深色同一颜色）

private struct ContrastRow: View {
    let name: String
    let lightColor: Color
    let darkColor: Color

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(lightColor)
                            .frame(width: 64, height: 48)
                    )
                Text("浅色").font(Theme.micro).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(darkColor)
                            .frame(width: 64, height: 48)
                    )
                Text("深色").font(Theme.micro).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(Theme.font(.caption as Font).bold()).foregroundStyle(.primary)
                Text("light: #\(lightColor.hexString())\ndark:  #\(darkColor.hexString())")
                    .font(Theme.micro)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .dynamicTypeCompress()
        .glassCard()
        .glassLongPressDeform()
    }
}

// MARK: - 主预览面板

struct DevView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.cardSpacing) {
                // Hero 说明卡
                VStack(spacing: Theme.Spacing.sm) {
                    Text("颜色预览").font(Theme.h2.bold()).foregroundStyle(.primary)
                    Text("iOS 27 Liquid Glass · 深浅双模式一致性检查")
                        .font(Theme.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .dynamicTypeCompress()
                .glassHeroCard()
                .glassLongPressDeform()

                // 品牌色
                ColorGroup(groupName: "品牌色", items: [
                    ("brand",         .blue,          "系统蓝色"),
                    ("brandLight",    Color(hex: "0A84FF"), "高亮蓝 0A84FF"),
                    ("brandDark",     Color(hex: "0056CC"), "深色蓝 0056CC"),
                ])

                // 语义色
                ColorGroup(groupName: "语义色", items: [
                    ("ok  通过",      .green,         "正常 / 成功"),
                    ("warn  警告",    .orange,        "注意 / 预警"),
                    ("bad  错误",     .red,           "故障 / 异常"),
                    ("acc  强调",     Theme.Colors.accent,   "品牌强调色"),
                    ("na   未知",     .secondary,     "无数据 / 未定义"),
                ])

                // 文字层级
                ColorGroup(groupName: "文字层级", items: [
                    ("primary",   .primary,   "主文本"),
                    ("secondary", .secondary, "次要文本"),
                    ("tertiary",  Color(.tertiaryLabel),  "辅助信息"),
                    ("quaternary", Color(.systemGray4), "极低对比度"),
                ])

                // 系统填充色
                ColorGroup(groupName: "系统填充色", items: [
                    ("systemFill",       Color(.systemFill),       "通用填充"),
                    ("secondaryFill",    Color(.secondarySystemFill),    "次级填充"),
                    ("tertiaryFill",     Color(.tertiarySystemFill),     "三级填充"),
                    ("quaternaryFill",   Color(.quaternarySystemFill),   "四级填充"),
                ])

                // 玻璃材质
                ColorGroup(groupName: "玻璃材质", items: [
                    ("thin",       Material.thin,       "卡片材质（默认）"),
                    ("prominent",  Material.prominent,  "模态背景"),
                    ("ultraThin",  Material.ultraThin,  "极淡材质"),
                    ("sidebar",    Material.sidebar,    "侧栏背景"),
                    ("content",    Material.content,    "内容背景"),
                ])

                // 页面背景色
                ColorGroup(groupName: "页面背景", items: [
                    ("pageAccent",    Theme.pageAccent,    "车况页（默认）"),
                    ("pageGreen",     Theme.pageGreen,     "电池/健康页"),
                    ("pageBlue",      Theme.pageBlue,      "车控页"),
                    ("pageIndigo",    Theme.pageIndigo,    "全量数据页"),
                ])

                // 表面色（ColorSystem）
                ColorGroup(groupName: "表面色", items: [
                    ("background",   Theme.ColorSystem.background,   "系统分组背景"),
                    ("cardBg",       Theme.ColorSystem.cardBg,       "次级分组背景"),
                    ("overlay",      Theme.ColorSystem.overlay,      "磨砂覆盖层"),
                    ("glass",        Theme.ColorSystem.glass,        "玻璃材质（与 overlay 统一）"),
                ])

                // 边框与填充色
                ColorGroup(groupName: "边框与填充", items: [
                    ("border",          Theme.ColorSystem.border,          "分隔线"),
                    ("borderSubtle",    Theme.ColorSystem.borderSubtle,    "浅边框"),
                    ("fill",            Theme.ColorSystem.fill,            "次级填充"),
                    ("fillSubtle",      Theme.ColorSystem.fillSubtle,      "三级填充"),
                    ("fillHighlighted", Theme.ColorSystem.fillHighlighted, "四级填充"),
                ])

                // 阴影色
                ColorGroup(groupName: "阴影色", items: [
                    ("shadowLight",   Theme.ColorSystem.shadowLight,   "轻微阴影 4%"),
                    ("shadowMedium",  Theme.ColorSystem.shadowMedium,  "中等阴影 8%"),
                    ("shadowStrong",  Theme.ColorSystem.shadowStrong,  "强阴影 12%"),
                ])

                // 深浅双模式对比
                ContrastRow(name: "语义色对比",
                            lightColor: .green, darkColor: .green)
                ContrastRow(name: "品牌色对比",
                            lightColor: Color(hex: "0A84FF"),
                            darkColor: Color(hex: "0056CC"))
                ContrastRow(name: "状态色对比",
                            lightColor: .orange, darkColor: .orange)
                ContrastRow(name: "危险色对比",
                            lightColor: .red, darkColor: .red)

                // 自定义 HEX 色板
                ColorGroup(groupName: "自定义 HEX 色", items: [
                    ("#0A84FF", Color(hex: "0A84FF"), "高亮蓝"),
                    ("#0056CC", Color(hex: "0056CC"), "深色蓝"),
                ])

                // #22 性能指标
                PerformanceMetricsCard()

                // Footer
                Text("深色模式下请检查各颜色是否可读，尤其是 tertiary / quaternary 与玻璃背景的对比度")
                    .font(Theme.footnote).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }
            .padding(.horizontal, 16)
            .safeAreaPadding(.bottom, 12)
        }
        .pageBackground(Theme.Colors.accent)
        .navigationTitle("颜色预览").navBarStyle()
    }
}

// MARK: - 辅助扩展

extension Color {
    /// 返回 6 位 HEX 字符串（不含 #）
    func hexString() -> String {
        let components = UIColor(self).cgColor.components ?? [0, 0, 0]
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

// MARK: - 性能指标卡片 (#22)
struct PerformanceMetricsCard: View {
    private let homeLoadTime = UserDefaults.standard.double(forKey: "carkeeper_home_load_time")
    private let commandCount = AppStore.shared.commandHistory.count
    private let energyRecords = AppStore.shared.energyHistory.count

    var body: some View {
        CardBox(title: "性能指标", cornerRadius: Theme.Radius.card) {
            VStack(spacing: 10) {
                HStack {
                    Text("首页加载耗时").font(Theme.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(homeLoadTime > 0 ? String(format: "%.2fs", homeLoadTime) : "—")
                        .font(Theme.monoLg).foregroundStyle(homeLoadTime > 1.5 ? .orange : .green)
                }
                ListDivider()
                HStack {
                    Text("指令历史记录").font(Theme.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(commandCount) 条").font(Theme.monoLg).foregroundStyle(Theme.Colors.accent)
                }
                ListDivider()
                HStack {
                    Text("能耗记录次数").font(Theme.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(energyRecords) 次").font(Theme.monoLg).foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct DevView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DevView()
        }
    }
}
#endif
