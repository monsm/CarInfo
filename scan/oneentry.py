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
  ③ `homeMode` 的每一档都要在 `HomeModeHead` 里出现**两次**（巨字 + 依据行）——
     防的是「加了档位、但 02 那张卡只有内容没有头」，那样加出来的档位
     看起来就和其余档位不像一家人。

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

# 深链别名：它们指向的页面与某个档位是同一个，所以同样不准被 push
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

    # 档位名：`case now` 这一行（switch 里的 `case .now:` 不会命中，因为行尾有冒号）
    modes = re.findall(r"^\s{4}case\s+(\w+)\s*$", home, re.M)
    if not modes:
        print("❌ 扫描失败：没能从 HomeMode.swift 里读出档位")
        return 1

    problems = []

    # ---- ② 档位 ↔ 页面 ----
    page_body = block_of(spine, "private func pageContent(_ mode: HomeMode)")
    page_cases = set(re.findall(r"case\s+\.(\w+)\s*:", page_body))
    for m in modes:
        if m not in page_cases:
            problems.append(f"② 档位 `{m}` 没有对应的页面："
                            f"在 MapSpineView.pageContent 里补一个 `case .{m}:`")
    for c in sorted(page_cases - set(modes)):
        problems.append(f"② pageContent 里的 `.{c}` 不是一个档位（HomeMode 里没有它）")

    # ---- ③ 档位 ↔ 02 的卡头（巨字 + 依据行）----
    for m in modes:
        n = len(re.findall(r"case\s+\.%s\s*:" % re.escape(m), head))
        if n < 2:
            problems.append(f"③ 档位 `{m}` 在 HomeModeHead 里只出现 {n} 次"
                            f"（需要 2 次：巨字 hero + 依据行 facts）")

    # ---- ① 属于某一档的深链不准被 push（哪里都不行，深链也走 openMode）----
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

    # ---- ③' path 只准在 NavState / App 入口里被改写 ----
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
