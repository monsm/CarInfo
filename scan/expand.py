#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
expand.py —— 「展开后的高度不能是写下来的」

为什么需要它（用户 2026-09-25）：
  · 「所有卡片内需要展开的都要严格计算展开后的拥挤程度，完全根据数据来，不能猜」；
  · 同一轮更早一次：「每个卡片仔细核对，内容展开后是否拥挤」。

  这个仓库在没有它之前，处理「展开后有多高」的办法是**写一个数**：
    · 体检卡：有问题就全展开（有几行由报文决定，一屏里可能出现 24 行）；
    · 消息卡：正文 `lineLimit(isOpen ? nil : 2)` —— 收起有界，展开无界；
    · 指令历史：历史桶最多 50 条，全部列出来、再摊开几条，卡片能长到三屏多；
    · 导出预览：`ScrollView { … }.frame(height: 100)` —— 高度是拍的，而且卡片里
      又多了一层滚动（叠叠乐自管手势，内层拿到的还是无限高：永远滚不动，却吃掉拖动）；
    · 车形俯视图：`.frame(height: 286)` —— 画布本来按 `min` 缩放，高度写小了就白拿
      一圈左右留白。

  那一轮的修法是 `Design/CardFit.swift`：用**当前动态字号下的真实行高**
  （`UIFont.preferredFont(forTextStyle:).lineHeight`）、真实折行数（`NSString.boundingRect`）
  与 `ArcStack` 量到的真实视口算出行数/屏数，放不下就切在量出来的行边界上。
  规则因此变成：**高度要么由内容撑，要么由 `CardFit` 算。**

判据（只有一条）：界面代码里不得出现固定的 `frame(height: 数字)`。
  · 认的形状：`.frame(height: <数字>)` —— **只给高度、没给宽度**的那种。
    它说的就是「这个块有多高」，而那一行里的高度几乎总是内容的（正文块、列表、
    图表所在的那一整块）。`.frame(width: 44, height: 44)` 这种同时给了宽高的
    是**形状**（图标、圆点、图钉、宽高成比例的缩略图），本检查器不管 ——
    把它们也列进来只会把表变成一张空话清单。
  · **不管** minHeight / maxHeight：那是上下界，不是写死的高度。
  · 允许的例外见 `ALLOWED`，键是「文件:值」，每一条都必须是**画出来的几何**：
    图表（Swift Charts 没有固有高度）、指示线、样例色块、控件自己的形状、
    缩略图。给内容写死高度不在其中 —— 那种高度要由内容撑，或由 `CardFit` 算。
  · 刻度与设计令牌本身（`Tokens.swift`）不查：它就是把数字变成名字的地方。

检查范围与 `copy.py` / `spacing.py` 一致（两个 Services 目录都算）。

退出码：0 = 全部通过；1 = 有没在表里的固定高度。
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
]

EXEMPT_FILES = {
    os.path.join(APP, "Design", "Tokens.swift").replace("\\", "/"),
    os.path.join(APP, "Design", "CardFit.swift").replace("\\", "/"),
}

def key(rel):
    """「文件:值」的键。路径统一正斜杠 —— 与 `swift_files()` 里那一步必须一致，
    否则表里每一条都对不上（而那种失败看起来很像「一处都不需要例外」）。"""
    return os.path.join(APP, rel).replace("\\", "/")


# 「文件:值」→ 为什么这个高度是画出来的、不是量出来的。
# 多一条就要多一个理由 —— 这条判据的全部价值都在这里。
ALLOWED = {
    key("Features/Battery/ChargeView.swift") + ":96":
        "单体电压柱图（Swift Charts 没有固有高度，不写就是 0）",
    key("Features/Battery/ChargeView.swift") + ":80":
        "温度探针柱图，同上",
    key("Features/Mine/MineView.swift") + ":120":
        "壁纸缩略图（按宽度填满后裁切，120 是它的展示高度）",
    key("Features/SplashView.swift") + ":2":
        "开场那一横线（2pt 的图形，不是行高）",
    key("Features/ThemeGalleryView.swift") + ":4":
        "主题样例里的光带走线",
    key("Features/ThemeGalleryView.swift") + ":0.5":
        "主题样例里的发丝线",
    key("Features/Trips/MessagesSection.swift") + ":30":
        "标签胶囊自己的形状（分段控件那一档高度，不是内容高度）",
    key("Features/Trips/ScoreSection.swift") + ":5":
        "评分条（一条 5pt 的走线）",
    key("Features/Trips/ScoreSection.swift") + ":130":
        "分段得分折线图（Swift Charts）",
    key("Features/Trips/TripsEventsView.swift") + ":132":
        "行程小地图缩略图（按宽度裁切）",
    key("Design/DS.swift") + ":32":
        "分段控件里那一枚药丸自己的高度（系统分段控件同量级）",
}

FORM = re.compile(r"\.frame\(([^()]*?)height:\s*([0-9]+(?:\.[0-9]+)?)")


def swift_files():
    out = []
    for base in SCAN_DIRS:
        if not os.path.isdir(base):
            continue
        for dp, dn, fn in os.walk(base):
            for f in sorted(fn):
                if not f.endswith(".swift"):
                    continue
                p = os.path.join(dp, f)
                out.append(p.replace("\\", "/"))
    return sorted(out)


def strip_comment(line):
    """注释里的 `.frame(height: 100)` 是在解释「这里曾经是什么」，不是代码。"""
    for marker in ("//", "///", "*"):
        i = line.find(marker)
        if i >= 0:
            line = line[:i]
    return line


def main():
    assert_roots(SCAN_DIRS)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)

    bad = []
    used = set()
    for path in swift_files():
        if path in EXEMPT_FILES:
            continue
        with io.open(path, encoding="utf-8", errors="ignore") as f:
            for n, raw in enumerate(f, 1):
                code = strip_comment(raw)
                if ".frame(" not in code:
                    continue
                for m in FORM.finditer(code):
                    before, value = m.group(1), m.group(2)
                    if before.rstrip().endswith(("min", "max")):
                        continue          # minHeight / maxHeight：上下界，不是写死
                    if "width:" in before:
                        continue          # 同时给了宽高 = 形状（图标 / 圆点 / 缩略图）
                    k = path + ":" + value
                    if k in ALLOWED:
                        used.add(k)
                        continue
                    bad.append((path, n, value, code.strip()))

    stale = sorted(set(ALLOWED) - used)
    print(f"扫描 {len(swift_files())} 个 Swift 文件，"
          f"例外表 {len(ALLOWED)} 条（每一条都是一个理由）")
    if stale:
        print(f"\n❌ 例外表里有 {len(stale)} 条已经不成立了 —— 那些高度要么改了值，要么没了：")
        for k in stale:
            print(f"   {k}  ← {ALLOWED[k]}")
        print("\n   例外表也得跟着代码走：不成立的理由留在表里，会让下一个改这里的人"
              "以为「它可以写死」，而实际上没人再核过它。值改了就把键改成新值（顺便重核理由）。")
        return 1
    if bad:
        print(f"\n❌ {len(bad)} 处固定高度没在表里：")
        for path, n, value, code in bad:
            print(f"   {path}:{n}  height: {value}")
            print(f"      {code[:100]}")
        print("\n   展开类内容的高度要么由内容撑，要么用 `CardFit` 按数据算")
        print("   （Design/CardFit.swift：真实行高 + 真实折行数 + ArcStack 量到的视口）。")
        print("   真要是画出来的几何（图表 / 指示线 / 缩略图），把它连同理由加进 ALLOWED。")
        return 1

    print("✅ 没有写死的固定高度（没在表里的一个都没有）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
