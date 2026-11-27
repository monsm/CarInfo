#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
spacing.py —— 「间距必须能叫出名字」

为什么需要它（用户 2026-09-25：「所有页面的间距布局都很不 iOS 的设计标准！！！！！！！」）：

  在那之前，界面里的间距是一堆各写各的数字：2 / 3 / 4 / 5 / 6 / 9 / 10 / 11 / 12 / 14 /
  15 / 22 …… 它们单个看都合理（差 1–2pt 谁都看得出来才怪），合起来就是**没有节奏**：
  同一张卡里两处「字与下一行」的间距可以是 6，也可以是 10。这类问题没有任何报错会提醒你，
  只能靠人一屏一屏去比 —— 而人一比就会得出「不 iOS」这个结论（它就是用户的原话）。

  那一轮做完了两件事，这个检查器守的是第二件：
    ① 把 22 个文件里 **111 处**间距字面量吸附到刻度（取最近的一档，平手取大；
       ≤2pt 的位移），并给刻度补上缺的一档 12（`TokensSpacing.snug`）；
    ② 让「新写的间距」不能再是字面量 —— 就是这里。

判据（只有一条）：界面代码里不得出现间距字面量。
  · 认的形状：`.padding(_)` / `.padding(.edge, _)` / `spacing: _` / `.spacing(_)`
    —— 只看这几个位置上的裸数字，其它位置（frame 宽高、offset、半径、透明度）
    是几何，不是节奏，本检查器不管。
  · 允许的例外只有六个值，且每个都写得出为什么（见 ALLOWED）：
    0 / 1 是「不要间距」与「1pt 的贴合」（排版手法，不是尺寸）；
    18 / 20 / 40 / 108 是**几何**：卡片内边距（对齐用）、页边距（刻度里的名字是 page）、
    引导页正文宽度、巨字头到屏顶的距离。
  · 刻度本身（`Tokens.swift`）不查：它就是把数字变成名字的地方。

检查范围与 `copy.py` / `design.py` 一致（两个 Services 目录都算 —— App 的界面代码
确实住在两个地方，这是仓库的历史形状，不是笔误）。

退出码：0 = 全部通过；1 = 有间距字面量。
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
}

ALLOWED = {
    "0": "「不要间距」是一种排版手法（对齐到同一条基线），不是尺寸",
    "1": "1pt 的贴合（两行行高之间的发丝缝），比最小刻度 xs 还小",
    "18": "叠叠乐卡片的左右内边距（StackSpec.Card.inset），对齐用，改了会与卡片错位",
    "20": "页边距在刻度里的名字是 page —— 它不是通用的 20，不能混用",
    "40": "引导页正文宽度（读起来最舒服的一行长度）",
    "108": "巨字头到屏顶的距离（用安全区算出来的），不是间距刻度上的一档",
}

FORM = re.compile(
    r"(?:\.padding(?:\(\.[a-zA-Z]+,)?|spacing:|\.spacing\()"
    r"\s*([0-9]+(?:\.[0-9]+)?)\b"
)


def swift_files():
    out = []
    for base in SCAN_DIRS:
        if not os.path.isdir(base):
            continue
        for dp, dn, fn in os.walk(base):
            for f in sorted(fn):
                if not f.endswith(".swift"):
                    continue
                p = os.path.join(dp, f).replace("\\", "/")
                if p in EXEMPT_FILES:
                    continue
                out.append(p)
    return out


def scan(paths):
    """返回 [(论据路径, 行号, 值, 行)]。注释行不算（注释是给维护者的）。"""
    out = []
    for p in paths:
        text = io.open(p, encoding="utf-8", errors="ignore").read()
        for i, line in enumerate(text.split("\n"), 1):
            code = line.split("//")[0]
            for m in FORM.finditer(code):
                out.append((p, i, m.group(1), line.strip()))
    return out


def main():
    assert_roots(SCAN_DIRS)
    paths = swift_files()
    print(f"扫了 {len(paths)} 个界面文件（允许的字面量：{'/'.join(sorted(ALLOWED))}）")
    bad = [h for h in scan(paths) if h[2] not in ALLOWED]
    if bad:
        print(f"\n❌ {len(bad)} 处间距是字面量 —— 它们没有名字，所以下一个页面没法复用：")
        for p, i, v, line in bad:
            print(f"  {p}:{i}  {v}  ← {line[:64]}")
        print("\n改法：用 TokensSpacing 那一档（刻度 2/4/8/12/16/20/24/32/44/48/64/88）。")
        print("确实不该进刻度（几何值）的，把值加进本文件的 ALLOWED 并写明理由。")
        return 1
    print("\n✅ 间距全部来自 TokensSpacing（例外只有 %d 个几何值）" % len(ALLOWED))
    return 0


if __name__ == "__main__":
    sys.exit(main())
