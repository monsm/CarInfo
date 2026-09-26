import SwiftUI

// =============================================================================
//  DSSegmentPicker —— 分段选择器，**系统的那一枚**
// =============================================================================
//
//  它是 `Picker` + `.pickerStyle(.segmented)`（底下就是 UIKit 的
//  `UISegmentedControl`），一个薄封装。全 App 的「N 选一」都走它。
//
//  为什么不留自己搭的那一排 `Button`（2026-09-26 之前的样子：自画凹槽 + 白色滑块、
//  自己算选中、自己加 `.isSelected`）—— 用户第 4 条：「尽可能的使用 ios27 的原生控件」，
//  而这一枚正好是**系统里有一模一样东西**的那一类。原生那一枚拿走的四件事，
//  每一件都是我们自己搭的时候要自己负责的：
//    · 命中区（HIG 的最小触控目标、两段交界处怎么算）；
//    · 按下反馈（按下那一小段、拖过整条时手指跟到哪一段 —— 自造的那一排没有这个）；
//    · 无障碍（`.isSelected` / 「按钮 / 已选中」怎么被读出来）；
//    · 以及**随平台换代**：iOS 26/27 那套玻璃化的外观，系统控件自己就跟着变。
//
//  这不是「好看不好看」的选择，而是这一仓刚用血换过一次的同一件事：
//  图源那一行（`MineView.wallpaperRow`）连换三代自造控件都没修好，真因在**别的层**
//  （缩略图的溢出与命中，见 `HANDOFF.md` §37.2）——「控件写得再对，也修不了不是控件的问题」。
//  原生能给的那一份不再自己扛，是我们能少犯一遍那类错的方式。
//
//  ⚠️ 代价一条，如实记（用户看得到、也会问）：**外观随系统**。它不再读
//  `TokensPalette.fillSubtle`（凹槽）与 `glassHighlight`（滑块）—— 后者因此
//  全仓零读者，已随本文件一起删（`Tokens.swift` 里那一段说明同步改了）。
struct DSSegmentPicker<T: Hashable>: View {
    /// 每一段：值 + 段名。段名要短（一行里挤 N 段，全名装不下时就换短的 —— 全名留给
    /// 那一行自己的标题，见 `WallpaperSource.segmentTitle` 的说明）。
    var options: [(value: T, title: String)]
    /// 当前选中的那一档。
    @Binding var selection: T
    /// 这是什么选择。它是**无障碍的标签**，也是这一行唯一的说法
    /// （`labelsHidden()` 之后屏幕上不再有它 —— 但那只是不画，不是不用）。
    var label: String

    var body: some View {
        Picker(label, selection: $selection) {
            // `id: \.offset`：段本身没有身份，位置就是它的身份（与 `options` 一一对应）。
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Text(option.title).tag(option.value)
            }
        }
        .pickerStyle(.segmented)
        // 标签不画在控件上面（它是这一行的说明，不是控件的一部分）——
        // 但读屏仍然读得到：`labelsHidden()` 只是不显示。
        .labelsHidden()
        .accessibilityLabel(Text(label))
    }
}
