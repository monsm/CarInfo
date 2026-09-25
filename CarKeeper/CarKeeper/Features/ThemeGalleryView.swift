// =============================================================================
// ThemeGalleryView.swift — 艺术主题样张（真机上一按就换，用眼睛挑）
//
//  2026-09-23：它从**一个独立页面**（DevView 里 NavigationLink 推开）降成
//  **「诊断」那一屏里的一节**（`ThemeGallerySection`）。理由与其余几处一样：
//  它是「诊断」的一部分，为它多一层导航只会让「我的」看起来像两个 App。
// =============================================================================
//
// 为什么不用截图挑：三种方向在缩略图里全都"差不多好看"，差别要上手才读得出来。
// 所以这一页做的是 —— **每块样张都用那套主题自己的令牌真渲染**：
//   底色、表面、发丝线、文字三档、强调色、光条、超大数字的字重与字距、
//   以及那条艺术规则（光池 / 纸纹 / 发丝网格）全部按该主题的取值画出来。
// 点一下 → 写 UserDefaults + 触觉反馈 → CarKeeperApp 的 root 靠 .id 重建整棵树，
// 于是**全 App**（约 340 处令牌调用点）立刻跟着换。
//
// 诚实边界（别以为这里已经全都做了）：
//   ① App 里仍有约 130 处直接写死的 Color(uiColor:) / .white / .black，不跟随主题；
//   ② 这张表只覆盖「令牌 + 画布」，不改变信息架构。
//   （原先还有一条「小组件与实时活动不跟随主题」—— 那两个扩展已整体删除。）
// =============================================================================
import SwiftUI

struct ThemeGallerySection: View {
    @AppStorage(ArtThemeStore.key) private var raw: String = ArtTheme.native.rawValue

    private var current: ArtTheme { ArtTheme(rawValue: raw) ?? .native }

    var body: some View {
        // 切换器就在这一节的顶部。
        // 它原来被刻意放在 ScrollView **外面** —— 切主题会重建整棵树（见 CarKeeperApp 的 .id），
        // 滚动位置会回到顶部，所以要有一个永远看得见的按钮。
        // 降成「节」之后它不再有自己的 ScrollView，那个理由自然也就不在了。
        VStack(alignment: .leading, spacing: TokensSpacing.lg) {
            // 「当前是哪一套」写在标题右边 —— 不用另占一行字（那一行只会在切换后重复一遍）
            DSSectionHeader(title: "艺术主题", trailing: current.title)
            switcher
            content
        }
    }

    // MARK: - 常驻切换器

    private var switcher: some View {
        // 二十套全在一行排不下（4 套那会儿排得下）：整行做成横向可滑的，
        // 每枚胶囊**保持自定宽**（不 `maxWidth: .infinity` 均分 —— 滑条上的均分会
        // 把一枚宽到读不完标题），滑到底才看见全部。
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TokensSpacing.xs) {
                ForEach(ArtTheme.allCases) { theme in
                    Button {
                        apply(theme)
                    } label: {
                        Text(theme.title)
                            .font(TokensTypo.subheadline)
                            .padding(.horizontal, TokensSpacing.sm)
                            .padding(.vertical, TokensSpacing.sm)
                            .background {
                                RoundedRectangle(cornerRadius: TokensRadius.small, style: .continuous)
                                    .fill(theme == current ? TokensPalette.accent : TokensPalette.surface)
                            }
                            .foregroundStyle(theme == current ? TokensPalette.labelOnTint : TokensPalette.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("切换到\(theme.title)主题")
                    .accessibilityAddTraits(theme == current ? [.isSelected] : [])
                }
            }
            .padding(.trailing, TokensSpacing.xs)
        }
    }

    // MARK: - 页面内容

    private var content: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.lg) {
            intro

            DSSectionHeader(title: "\(ArtTheme.allCases.count) 套方向")
            VStack(spacing: TokensSpacing.md) {
                ForEach(ArtTheme.allCases) { theme in
                    ThemeTile(theme: theme, isActive: theme == current) {
                        apply(theme)
                    }
                }
            }

            DSSectionHeader(title: "在真 MapKit 上的处境")
            VStack(spacing: 0) {
                ForEach(ArtTheme.allCases) { theme in
                    verdictRow(theme)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                    .fill(TokensPalette.surface)
            }

            footnotes
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 头部说明

    private var intro: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            Text("点一下，全 App 立刻换装")
                .font(TokensTypo.headline)
                .foregroundStyle(TokensPalette.primary)
            Text("样张用真令牌渲染，不是截图。")
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 处境行

    private func verdictRow(_ theme: ArtTheme) -> some View {
        VStack(alignment: .leading, spacing: TokensSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                Text(theme.title)
                    .font(TokensTypo.subheadline)
                    .foregroundStyle(TokensPalette.primary)
                Spacer(minLength: TokensSpacing.sm)
                Text(theme == current ? "正在使用" : " ")
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.accent)
            }
            Text(theme.mapKitVerdict)
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, TokensSpacing.md)
        .padding(.horizontal, TokensSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TokensPalette.hairline)
                .frame(height: TokensHair.line)
        }
    }

    // MARK: - 脚注

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            DSSectionHeader(title: "没做的部分")
            Text("① 约 130 处写死的系统颜色不跟随主题；"
                 + "② 主题只换取值，不改信息架构。")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 切换

    private func apply(_ theme: ArtTheme) {
        guard theme != current else {
            TokensHaptic.tap()
            return
        }
        ArtThemeStore.set(theme)     // 写 UserDefaults + 发通知
        raw = theme.rawValue         // 显式更新 @AppStorage，触发 root 的 .id 重建
        TokensHaptic.select()
    }
}

// =============================================================================
// ThemeTile —— 一块真渲染的样张
// =============================================================================
private struct ThemeTile: View {
    let theme: ArtTheme
    let isActive: Bool
    let onTap: () -> Void

    private var s: ArtThemeSpec { theme.spec }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: TokensSpacing.md) {
                sample
                caption
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    // MARK: 小界面样本（用该主题自己的取值画）

    private var sample: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.snug) {
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                Text("车在这儿")
                    .font(s.usesSerifTitles
                          ? .system(size: 17, weight: .semibold, design: .serif)
                          : .system(size: 17, weight: .semibold))
                    .foregroundStyle(s.label)
                Spacer(minLength: 8)
                Text("已上锁")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, TokensSpacing.sm)
                    .padding(.vertical, TokensSpacing.xs)
                    .background(Capsule().fill(s.accent))
                    .foregroundStyle(s.onAccent)
            }

            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.xs) {
                Text("78")
                    .font(.system(size: 76, weight: s.displayWeight).monospacedDigit())
                    .tracking(-76 * 0.035 + s.displayTracking)
                    .foregroundStyle(s.label)
                Text("%")
                    .font(.system(size: 20, weight: .regular).monospacedDigit())
                    .foregroundStyle(s.labelSecondary)
            }

            // 光条 = 电量（该主题的光条渐变）
            ZStack(alignment: .leading) {
                Capsule().fill(s.track).frame(height: 4)
                Capsule()
                    .fill(LinearGradient(colors: s.lightBar, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 4)
                    .scaleEffect(x: 0.78, y: 1, anchor: .leading)
                    .shadow(color: glowColor, radius: 6, x: 0, y: 0)
            }

            // 行 + 发丝线（表面与分隔线的取值）
            VStack(spacing: 0) {
                row("电量", "78%", "412 km")
                Rectangle().fill(s.hairline).frame(height: 0.5)
                row("今天", "52.9 km", "7 段")
                Rectangle().fill(s.hairline).frame(height: 0.5)
                row("异常", "1 条", "后备箱 · 14:20")
            }
            .padding(.horizontal, TokensSpacing.snug)
            .padding(.vertical, TokensSpacing.xs)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(s.surface)
            }

            // 语义色只有三个点：颜色只表达状态
            HStack(spacing: TokensSpacing.md) {
                dot(s.success, "正常")
                dot(s.warning, "关注")
                dot(s.error, "异常")
            }
        }
        .padding(TokensSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                s.canvas
                decorOverlay
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: TokensRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TokensRadius.large, style: .continuous)
                .strokeBorder(isActive ? s.accent : s.hairline, lineWidth: isActive ? 2 : 1)
        }
    }

    private var glowColor: Color {
        s.allowsGlow ? s.lightBar.first?.opacity(0.55) ?? .clear : .clear
    }

    private func row(_ key: String, _ value: String, _ note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.snug) {
            Text(key)
                .font(.system(size: 13))
                .foregroundStyle(s.labelSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(s.label)
            Text(note)
                .font(.system(size: 12))
                .foregroundStyle(s.labelTertiary)
        }
        .padding(.vertical, TokensSpacing.sm)
    }

    private func dot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: TokensSpacing.xs) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(s.labelSecondary)
        }
    }

    /// 该主题的画布装饰 —— **就是 App 用的那一份实现**（`SkyOverlay`），
    /// 只是把 spec 传成这套主题自己的取值。
    ///
    /// 这里曾经手搓过一份「小号版」：两个实现已经开始分叉（发丝网格一边写死 0.07、
    /// 一边读 `CanvasDecor.strength`），而且那份里还有一个写死的纸色
    /// `Color(red: 0.78, …)` —— 样张与真机不一致，这张「用眼睛挑」的表就失效了。
    /// 现在样张不可能和真机不一致：它们是同一个 View。
    ///
    /// 没有车的位置就没有光 —— 不编一个方向（与 AppCanvas 同一条规则）。
    @ViewBuilder
    private var decorOverlay: some View {
        if s.decor != .none, let c = AppStore.shared.currentLocation?.coordinate {
            SkyOverlay(light: SkyLight.now(at: Date(), coordinate: c), spec: s)
        }
    }

    // MARK: 说明（用当前主题的令牌，保证在任何主题下都可读）

    private var caption: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                Text(theme.title)
                    .font(TokensTypo.subheadline)
                    .foregroundStyle(TokensPalette.primary)
                if isActive {
                    Text("正在使用")
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.accent)
                }
                Spacer(minLength: 0)
            }
            Text(theme.mechanism)
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
