#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
glass.py —— 「玻璃只有一个人说了算」

为什么需要它（用户 2026-09-25：「全局液态玻璃的质感全项目每个犄角旮旯方方面面都做到位了吗」）：

  那一轮查下来的答案是没有，而且病根是**名字**而不是细节：

    · 真正的材质（`.glassEffect`）只出现在 3 处 —— 卡片、底部模式条、地图那颗圆钮。
      其余每一处「浮在内容之上」的表面（轻提示、次操作按钮、地图图层胶囊、分段控件、
      芯片、搜索框）用的都是 `TokensPalette.glassLight` —— 而那个令牌**就是
      `fillSubtle`**（同一个值、两个名字）。一个叫 glass 的名字下面是一块扁平色：
      不折射、不反射、不随底下内容变。那是材质的**假象**，不是材质。
    · 更糟的是有两处「玻璃底下垫了一块不透明的面」（`Capsule().fill(fillSubtle)`
      再接 `.glassEffect(...)`；`Circle().fill(glassHighlight)` 再接玻璃）——
      材质本身就被那块面挡掉了，看起来是「磨砂色块 + 一圈高光」。

  那一轮的修法是造一个唯一入口 `dsGlass`（`Design/DSGlass.swift`：变体按**底下是什么**
  选、`interactive` 交给系统演按压、`dsGlassLayer` 负责「多块玻璃算一层」），
  再把上面每一处搬到它名下。本检查器守的就是「以后也只能这么写」。

判据（四条，每条都有真实事故对应）：

  ① `.glassEffect(` 只许出现在 `Design/DSGlass.swift` —— 别处出现就是又开了第二个入口。
  ② `GlassEffectContainer` 同上：一片区域里的多块玻璃必须由 `dsGlassLayer` 划定，
     否则挨着的两块玻璃各自按自己的边界算（看起来像两张贴纸）。
  ③ **玻璃底下不许垫不透明的面**：同一条链里，`.fill(TokensPalette.…)` /
     `.background(TokensPalette.…)` 出现在 `.dsGlass` **之前**就报红。
     （玻璃之后的不算 —— `.dsGlass(...).overlay { … }` 盖在玻璃**上面**是正当的。）
  ④ 不许再引入旧材质语言（`ultraThinMaterial` / `regularMaterial` …）：那是
     Liquid Glass 之前的写法，两套材质语言同时在仓里，就没有一套是准的。

  反例（本检查器**不**管的，免得它变成「猜」）：
    · 哪个表面「该」是玻璃 —— 那要读设计意图，静态判不出来；
      能判的是「已经是玻璃的地方有没有把它写坏」。
    · 令牌名里带 glass 的还剩 `glassHighlight` —— 它是**玻璃里面**那一层更亮的形状
      （模式条上被选中的那一枚），不是浮层的底，合法，见 `Tokens.swift` 的注。

检查范围与 `spacing.py` / `copy.py` 一致（两个 Services 目录都算），外加
`CarKeeper/Design/`（顶层那个 Design 目录里也有编译进 App 的界面代码）。

退出码：0 = 全部通过；1 = 有违规。
"""

import io
import os
import re
import sys

from _roots import assert_roots

APP = os.path.join("CarKeeper", "CarKeeper")
SERVICES = os.path.join("CarKeeper", "Services")
SCAN_DIRS = [
    os.path.join(APP, "Features"),
    os.path.join(APP, "Design"),
    os.path.join(APP, "Services"),
    os.path.join(APP, "Models"),
    SERVICES,
    os.path.join("CarKeeper", "Design"),
]

# 唯一入口本尊。它是**唯一**能直接调系统材质的地方（其余全走 dsGlass）。
ENTRY = os.path.join(APP, "Design", "DSGlass.swift").replace("\\", "/")

# ① 直接调系统材质
MATERIAL = re.compile(r"\.glassEffect\s*\(")
# ② 玻璃容器（多块玻璃成一层）
CONTAINER = re.compile(r"\bGlassEffectContainer\b")
# ③ 玻璃之下的不透明面
GLASS_CALL = re.compile(r"\.dsGlass(?:Capsule|Rounded)?\s*\(")
UFLAT = re.compile(r"\.(?:fill|background)\s*\(\s*(?:TokensPalette|Color)\.\w+")
# ④ 旧材质语言
LEGACY = re.compile(r"\b(?:ultraThin|thin|regular|thick|ultraThick)Material\b")


def swift_files():
    out = []
    for base in SCAN_DIRS:
        if not os.path.isdir(base):
            continue
        for dp, dn, fn in os.walk(base):
            for f in sorted(fn):
                if f.endswith(".swift"):
                    out.append(os.path.join(dp, f).replace("\\", "/"))
    return out


def statements(text):
    """把文件切成「一条链」—— 续行以 `.` 开头，这是本仓的排版约定。

    返回 [(起始行号, [行, …])]。注释行不参与判断。
    """
    blocks = []
    cur, start = [], 0
    for i, line in enumerate(text.split("\n"), 1):
        code = line.split("//")[0].rstrip()
        stripped = code.strip()
        if not stripped:
            if cur:
                blocks.append((start, cur))
                cur = []
            continue
        if stripped.startswith(".") and cur:
            cur.append(stripped)
        else:
            if cur:
                blocks.append((start, cur))
            cur, start = [stripped], i
    if cur:
        blocks.append((start, cur))
    return blocks


def scan(paths):
    """返回 [(路径, 行号, 为什么)]。"""
    out = []
    for p in paths:
        text = io.open(p, encoding="utf-8", errors="ignore").read()
        # 注释里提到这些名字是允许的（这一仓的注释很爱解释历史），
        # 所以逐行剥掉 `//` 之后再判 —— 与 `spacing.py` 同一手法。
        lines = [ln.split("//")[0] for ln in text.split("\n")]

        if p != ENTRY:
            for i, code in enumerate(lines, 1):
                if MATERIAL.search(code):
                    out.append((p, i, "直接调 `.glassEffect` —— 玻璃的入口只有 `dsGlass`"))
                if CONTAINER.search(code):
                    out.append((p, i, "直接用 `GlassEffectContainer` —— 用 `dsGlassLayer`"))
                if LEGACY.search(code):
                    out.append((p, i, "旧材质语言（`…Material`）—— Liquid Glass 之前的写法"))

        # ③ 同一条链里，扁平面垫在玻璃底下
        for start, block in statements(text):
            joined = "\n".join(block)
            g = GLASS_CALL.search(joined)
            if not g:
                continue
            before = joined[: g.start()]
            flat = UFLAT.search(before)
            if flat:
                line_no = start + before[: flat.start()].count("\n")
                out.append((p, line_no,
                            "玻璃底下垫了一块不透明的面（`%s`）—— 材质会被它挡掉"
                            % flat.group(0).strip()))
    return out


def main():
    assert_roots(SCAN_DIRS)
    paths = swift_files()
    print(f"扫了 {len(paths)} 个界面文件（玻璃的唯一入口：{ENTRY}）")
    bad = scan(paths)
    if bad:
        print(f"\n❌ {len(bad)} 处玻璃写得不对：")
        for p, i, why in bad:
            print(f"  {p}:{i}  {why}")
        print("\n改法：浮在内容之上的表面走 `dsGlass`（形状 / 变体 / interactive 三件事它都收）；")
        print("多块玻璃同屏时，把那一片包进 `dsGlassLayer`。")
        print("确有必要直连系统材质的，把理由写进 `Design/DSGlass.swift` 而不是绕开它。")
        return 1
    print("\n✅ 玻璃只有一个入口，且没有一块被垫在不透明面底下")
    return 0


if __name__ == "__main__":
    sys.exit(main())
