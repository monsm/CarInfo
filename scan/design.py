#!/usr/bin/env python3
"""设计令牌纪律（Design token discipline）—— 「完全统一」这件事的可执行定义。

一个 App 里「同一个灰」有两个值、同一段文字有 13/14/15pt 三个字号，
就是「缝合感」的**机械成因**：它不来自审美，来自同一个决定被做了很多次。

三类字面量只允许出现在**定义令牌的那几个文件**里：

  ① 字号字面量
     `.font(.system(size: 17))` / `Font.system(size: 22, weight: .bold)`
     → 只允许 Tokens.swift / WidgetTokens.swift

  ② 颜色分量字面量（手写 RGB）
     `Color(red:green:blue:)` / `Color(white:)` / `Color(hue:)` / `Color(hex:)` / `UIColor(red:…)`
     → 只允许 ArtTheme.swift（主题取值表）/ WidgetTokens.swift（世界面取值表）

  ③ 色相字面量（直接点系统色名）
     `.foregroundStyle(.white)` / `.tint(.blue)` / `.fill(.green)` / `Color.orange`
     → 一律不允许。层级样式 `.primary/.secondary/.tertiary` **不在**此列：
       那是排版层级（跟随深浅色的文字层级），不是颜色，是 iOS 原生做法本身。

为什么 ③ 连 `.white` 也拦：`.white` 在深色/浅色下都是同一个白，而这里的画布会随主题变
（纸上主题是暖米色）—— 白字会「在纸面上戳一个洞」。令牌里有 `TokensPalette.lightSource`
与 `labelOnTint`，它们各自对应一个真实用途。

例外必须**显式写明理由**（与 paths.py 的豁免同一约定）：靠沉默蒙过去是不行的。
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---- 允许出现字面量的文件：这是「令牌定义处」，不是「例外」 -------------------
TOKEN_FILES = {
    "CarKeeper/CarKeeper/Design/Tokens.swift": "设计令牌的唯一来源（字号/间距/圆角/字距）",
    "CarKeeper/Shared/WidgetTokens.swift": "小组件与实时活动的世界面令牌（App 也从这里取值，避免漂移）",
    "CarKeeper/CarKeeper/Design/ArtTheme.swift": "艺术主题的取值表：换主题就是换这里的值",
}

# ---- 显式豁免：必须写出理由，输出成 ⚠️ 而不是 ✅ -----------------------------
EXEMPT = {
    # 例：{"CarKeeper/xxx.swift": "为什么这里只能是字面量"}
    "CarKeeper/CarKeeper/Features/ThemeGalleryView.swift":
        "主题样张页：它的**职责**就是把主题的真实取值显示给人看（用眼睛挑主题），"
        "所以它必须打印原始数值，而不是引用令牌 —— 引用令牌会让样张与真机看起来一样，"
        "而它的用途恰恰是「核对样张与真机是否一致」。",
    "CarKeeper/WatchApp/WatchApp.swift":
        "watchOS 上的字号是按 155pt 画布另定的一套，而且它**不能**共享 WT 那份令牌："
        "`WT.Palette` 里的系统语义色在 watchOS 上不存在 —— 已对 Apple 文档 JSON 核实"
        "（secondarySystemGroupedBackground 的 platforms = iOS / iPadOS / Mac Catalyst / visionOS，"
        "无 watchOS），所以手表这一份只能是自己的阶梯。",
    "CarKeeper/WatchApp/WatchApp/Sources/WatchApp.swift":
        "同上（这是 Watch 扩展 target 的那一份副本，由 paths.py 保证两份一字不差）。",
}

# ---- 规则 -------------------------------------------------------------------
RULES = [
    ("① 字号字面量",
     re.compile(r"\.system\(size:\s*\d"),
     "字体一律从 TokensTypo 出（语义阶梯 largeTitle/body/footnote… 跟随 Dynamic Type；"
     "数字用 display/metric/data/digits，它们等宽，换数值时不跳动）"),
    ("② 颜色分量字面量",
     re.compile(r"\b(?:UI)?Color\((?:red|white|hue|hex):"),
     "颜色一律从 TokensPalette 出；换主题时改的是主题取值表，调用点一行不改"),
    ("③ 色相字面量",
     re.compile(r"\.(?:foregroundStyle|foregroundColor|tint|fill|background|stroke|border)"
                r"\(\s*\.(?:red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|white|black|gray)\b"
                r"|\bColor\.(?:red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|white|black|gray)\b"
                # 裸色名（`colors: [.red, .orange]` / `tint: .white`）：
                # 前面不能是标识符或点（避开 `someEnum.blue` 这种自定义枚举）
                r"|(?<![\w.])\.(?:red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|white|black|gray)\b"),
     "色相只能来自令牌（accent / success / warning / error / info）；"
     "文字层级用 .primary/.secondary/.tertiary"),
]

SKIP_DIRS = ("scan/", "scan\\", ".git/")


def swift_files():
    out = []
    base = os.path.join(ROOT, "CarKeeper")
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for fn in filenames:
            if fn.endswith(".swift"):
                p = os.path.join(dirpath, fn)
                out.append(os.path.relpath(p, ROOT).replace("\\", "/"))
    return sorted(out)


def strip_noise(line, in_block):
    """去掉注释与字符串字面量的影响（保持行号可用的逐行近似）。

    返回 (可读代码, 进入块注释后是否仍在块注释里)。
    字符串里的内容会被替换成引号本身，避免把文案里的 "¥" 之类当成代码。
    """
    out = []
    i, n = 0, len(line)
    while i < n:
        c = line[i]
        if in_block:
            j = line.find("*/", i)
            if j < 0:
                return "".join(out), True
            i = j + 2
            in_block = False
            continue
        if c == "/" and i + 1 < n and line[i + 1] == "/":
            break
        if c == "/" and i + 1 < n and line[i + 1] == "*":
            in_block = True
            i += 2
            continue
        if c == '"':
            # 跳过整个字面量（含 \(...) 插值里的代码：插值里出现字面量的概率极低，
            # 而"把插值里的代码也当字符串"会让检查漏报，所以插值内容原样保留）。
            out.append('"')
            i += 1
            depth = 0
            while i < n:
                if line[i] == "\\" and i + 1 < n and line[i + 1] == "(":
                    # 插值：把里面的内容当代码递归处理
                    inner, i2 = [], i + 2
                    d = 1
                    while i2 < n and d:
                        if line[i2] == "(":
                            d += 1
                        elif line[i2] == ")":
                            d -= 1
                            if d == 0:
                                break
                        inner.append(line[i2])
                        i2 += 1
                    out.append("".join(inner))
                    i = i2 + 1
                    continue
                if line[i] == "\\":
                    i += 2
                    continue
                if line[i] == '"':
                    i += 1
                    break
                i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out), in_block


def main():
    problems = []
    exempt_used = set()
    print("设计令牌纪律（字号 / 颜色分量 / 色相 只能来自令牌）\n")

    for rel in swift_files():
        if rel.startswith(SKIP_DIRS):
            continue
        if rel in TOKEN_FILES:
            continue
        try:
            text = open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        hits = []
        in_block = False
        for lineno, raw in enumerate(text.splitlines(), 1):
            code, in_block = strip_noise(raw, in_block)
            for title, rx, advice in RULES:
                if rx.search(code):
                    hits.append((lineno, title, raw.strip(), advice))
        if not hits:
            continue
        if rel in EXEMPT:
            exempt_used.add(rel)
            print(f"  ⚠️  {rel}（已显式豁免）—— {EXEMPT[rel]}")
            print(f"      仍有 {len(hits)} 处字面量")
            continue
        print(f"  ❌ {rel}")
        for lineno, title, src, _ in hits:
            print(f"       {rel}:{lineno}  [{title}]  {src[:96]}")
        problems.append((rel, hits))

    print()
    for rel in sorted(set(EXEMPT) - exempt_used):
        print(f"  ⚠️  豁免名单里的 {rel} 已经不需要豁免了（或文件不存在）—— 这条豁免该删了")
        print(f"      理由原为：{EXEMPT[rel]}")

    if problems:
        print("\n❌ 高嫌疑：")
        for rel, hits in problems:
            print(f"   {rel}：{len(hits)} 处字面量绕过了令牌")
        for title, _, advice in RULES:
            print(f"   {title}：{advice}")
        print("   若某处**确实**只能是字面量，请写进 design.py 的 EXEMPT 并说明理由。")
        return 1

    print("✅ 字号 / 颜色全部来自令牌（定义处之外没有字面量）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
