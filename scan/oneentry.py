#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
入口唯一性检查器 —— 「同一件事只准有一条到达路径」

为什么需要它（真实事故）：
  这个项目反复长回「缝合怪」的机制只有一个 —— 同一个功能又长出第二个入口。
  到 2026-09-23 为止，收掉的入口有：5 个 Tab / 顶部图层胶囊条 / 索引页一整份
  「全部功能」目录 / 「我的」的 27 个磁贴 / 4 个「有名字、没发射」的导航通知。
  每一次都是手工审计发现的，而每一次改完之后，**没有任何东西阻止下一个人
  再加一个回去** —— 加了照样编译得过、界面照样“能用”。

  所以这条检查器把「入口只有一条」从口头约定变成 CI 会拦下的硬约束。

判据（三条，每条都对应上面的一次事故）：
  ① **任何文件**都不准 `pushNavigation(.某个属于档位的深链)` —— 包括 App 入口。
     想「去看某个功能」只有一条路：`nav.openMode(...)`（拨模式条）。
     深链也走它（`openDeeplink` → `openMode(for:)`）：能对应到某一档的拨条子，
     对应不到的（隐私 / OTA / 家庭 / 钥匙）由 `openMode(for:)` 自己 push。
  ② 档位与页面一一对应：`HomeMode` 的每个 case 都要在
     `MapSpineView.pageContent` 里有一个 case（`.now` 也在 —— 它是地图本身）。
  ③ `HomeMode` 的每一档在 `HomeModeHead` 里要出现**恰好一次**。
     0 次：加了档位、但 02 那张卡只有内容没有头，那个档位看起来就和其余档位
     不像一家人（原判据守的就是这一半）。
     ≥2 次：同一档在头卡里有两处表述 —— 2026-09-24 之前的写照是「巨字 hero +
     三行依据（车牌/车架号/保险）」，而那三行逐条又在紧下面那张卡里再说一遍
     （车辆档的头写「车牌/车架号/保险」，紧跟的「身份」卡就是这三样）。
     用户当天要求「精致度」，删的就是这个：**一个事实只留一个出处**。
     判据跟着从「< 2 报错」翻成「≠ 1 报错」—— 否则门禁会一直拦着正确的写法，
     而它拦下的恰好是本轮唯一一处真实事故（2026-09-24 CI 红在 785fb8c）。

双向验证（本仓库的门禁写法约定 ⑤，探针结果留档）：
  2026-09-24 在 `HomeModeHead` 里临时注入第二个 `switch mode`（让每一档再说一遍 ——
  旧形态的等效写法），本判据报出 6 条「出现了 2 次」并退出 1；
  撕掉探针后 `HomeModeHead.swift` 与 HEAD 逐字节一致
  （`git hash-object` = 16dfdda…）且转绿。两个方向都确实出声过。

退出码：0 = 只有一条入口；1 = 发现第二条（或扫描失败）。
"""

import io
import os
import re
import sys

APP = os.path.join("CarKeeper", "CarKeeper")
HOME_MODE = os.path.join(APP, "Features", "Map", "HomeMode.swift")
MAP_SPINE = os.path.join(APP, "Features", "Map", "MapSpineView.swift")
MODE_HEAD = os.path.join(APP, "Features", "Map", "HomeModeHead.swift")
APP_ENTRY = os.path.join(APP, "CarKeeperApp.swift")

ALIASES = {"dashboard", "score", "parking"}

SCAN_DIRS = [
    os.path.join("CarKeeper", "CarKeeper"),
    os.path.join("CarKeeper", "Services"),
    os.path.join("CarKeeper", "Shared"),
]


def read(path):
    with io.open(path, encoding="utf-8", errors="ignore") as f:
        return f.read()


def swift_files():
    out = []
    for root in SCAN_DIRS:
        for dirpath, _, names in os.walk(root):
            if "baseline" in dirpath:
                continue
            for n in names:
                if n.endswith(".swift"):
                    out.append(os.path.join(dirpath, n).replace("\\", "/"))
    return sorted(out)


def block_of(text, signature):
    """取一个函数的函数体（按花括号配平），找不到返回 ''。"""
    i = text.find(signature)
    if i < 0:
        return ""
    depth = 0
    started = False
    for j in range(i, len(text)):
        ch = text[j]
        if ch == "{":
            depth += 1
            started = True
        elif ch == "}":
            depth -= 1
            if started and depth == 0:
                return text[i:j + 1]
    return text[i:]


def main():
    for p in (HOME_MODE, MAP_SPINE, MODE_HEAD, APP_ENTRY):
        if not os.path.exists(p):
            print(f"❌ 扫描失败：找不到 {p}")
            return 1

    home = read(HOME_MODE)
    spine = read(MAP_SPINE)
    head = read(MODE_HEAD)

    home_enum = block_of(home, "enum HomeMode")
    modes = re.findall(r"^\s{4}case\s+(\w+)\s*$", home_enum, re.M)
    if not modes:
        print("❌ 扫描失败：没能从 HomeMode.swift 里读出档位")
        return 1

    problems = []

    page_body = block_of(spine, "private func pageContent(_ mode: HomeMode)")
    page_cases = set(re.findall(r"case\s+\.(\w+)\s*:", page_body))
    for m in modes:
        if m not in page_cases:
            problems.append(f"② 档位 `{m}` 没有对应的页面："
                            f"在 MapSpineView.pageContent 里补一个 `case .{m}:`")
    for c in sorted(page_cases - set(modes)):
        problems.append(f"② pageContent 里的 `.{c}` 不是一个档位（HomeMode 里没有它）")

    for m in modes:
        n = len(re.findall(r"case\s+\.%s\s*:" % re.escape(m), head))
        if n == 0:
            problems.append(f"③ 档位 `{m}` 在 HomeModeHead 里一次都没出现"
                            f"（每一档都要有卡头，否则它和其余档位不像一家人）")
        elif n > 1:
            problems.append(f"③ 档位 `{m}` 在 HomeModeHead 里出现了 {n} 次"
                            f"（同一档只该有一处表述：卡头巨字；依据在下面每一张卡里）")

    banned = set(modes) | ALIASES
    pushes = []
    for f in swift_files():
        text = read(f)
        for m in re.finditer(r"pushNavigation\(\s*\.(\w+)", text):
            if m.group(1) in banned:
                pushes.append((f, m.group(1), text[:m.start()].count("\n") + 1))
    for f, name, line in pushes:
        problems.append(f"① {f}:{line} 直接 push 了 `.{name}` —— 它属于某一档，"
                        f"应当用 `nav.openMode(.{name})` 拨模式条（深链也一样）")

    for f in swift_files():
        if f.replace("\\", "/") == APP_ENTRY.replace("\\", "/"):
            continue
        text = read(f)
        for m in re.finditer(r"\bpath\s*=\s*\[|\bpath\.append\(", text):
            problems.append(f"③ {f}:{text[:m.start()].count(chr(10)) + 1} 直接改写了导航栈"
                            f"（路径只归 NavState 管，页面请用 openMode / pushNavigation）")

    if problems:
        print("\n❌ 发现了第二条入口（同一个功能应当只有一条到达路径）：\n")
        for p in problems:
            print(f"   {p}")
        print("\n   规则与来历见 scan/oneentry.py 顶部的三条判据。")
        return 1

    print(f"  档位 {len(modes)} 个：{' / '.join(modes)}")
    print(f"  逐条核对：档位↔页面 ✅　档位↔卡头 ✅　属于档位的深链零 push ✅　导航栈只有一处改写 ✅")
    print("\n✅ 入口唯一（功能只有一条到达路径：底部模式条）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
