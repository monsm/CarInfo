#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
perf.py —— 「每次界面求值都会跑的那条路上，不许有一次性就能建好的东西」

为什么需要它（2026-09-25「性能轮」，先量后改）：

  这一轮把三处真实的开销量出来并改掉了，三处都是**同一个形状**：
  **一个每次求值都会重来的东西，里面含一个「其实只取决于常量」的构造。**

  ① `DateFormatter()` —— 全仓原有 9 处。构造它要现装一套 ICU 格式化器，而同一个
     (locale, 格式串) 造出来的东西**永远一样**。其中三处落在每次求值的路径上：
       · `MapTripLine.timeText`：`MapSpineLayers` 为每一段行程读一次 → 30 段行程
         就是 30 次构造，而地图页在车动起来时**每 2 秒**求值一次（`RefreshLoop`）；
       · `VM.parseDate(_:)`：一次调用最多造 **7 个**（按 7 种格式挨个试），
         而它是按记录调用的 —— 一页列表 = 7 × 条数次；
       · `RawLogStore.now()` / `VM.nowText()`：每记一条日志一个。
     现在构造器只有一个出处：`CarKeeper/Services/DateText.swift` 的池子
     （键是 `locale|格式`，所以它**有界** —— 能进池子的都是源码里写死的字符串）。

  ② `CLLocation(...)` 出现在**比较闭包**里 —— 这一条比①更隐蔽，因为它看起来
     只是一个「坐标对象」。`clusterChargers` 原来的判据是
     `out.firstIndex(where: { CLLocation(...).distance(from: here) <= r })`：
     **每一次比较**都现造一个 CLLocation（一枚钉子 × 已有的每一组），几十个站
     就是几百次分配，而它跑在地图每次求值的图层里。改成「每个站/每个组各造一次」
     之后分组结果一字未改 —— 它换的是**分配次数**，不是算法。

判据（两条，都只认代码位置 —— 注释与字符串先抹掉）：

  ① `DateFormatter()` / `NumberFormatter()` / `ISO8601DateFormatter()` 的构造
     只允许出现在 `ALLOWED` 列出的文件里。**目前只有一个**：`DateText.swift`。
     要加第二个，必须在 `ALLOWED` 里写清「这里的构造器为什么不能进池子」。
  ② `CLLocation(` 不许出现在比较/筛选/排序闭包里（`firstIndex(where:`、`filter {`、
     `contains(where:`、`sorted {`、`min {`、`max {`、`reduce(` 等）。判据从闭包
     开口处往后按花括号配对扫到闭包结束，所以**跨行的闭包也认**。
     允许的形状：在循环体里为**每个元素**造一次（那是 O(n)，不是 O(n × 比较次数)），
     以及把已经造好的对象当参数传进去。
     例外表是 `COORD_ALLOWED`（目前为空）：与 ① 同一个规矩 ——
     **例外必须写理由**，不写就等于没同意。不然下一个人会以为「加一行就能过」。

两条判据的方向都是「宁可漏，不可噪」：
  · ① 只认那三个明确的类型名，`DateFormatter` 的其它写法（比如自定义包装）不看；
  · ② 只在闭包**体内**找 `CLLocation(`，闭包外的循环变量不看；
    闭包体超出 `MAX_CLOSURE_LINES` 行就不判（真实闭包都是几行，长到那种程度
    说明形状已经不像比较了，那时误报比漏报更贵）。

为什么是门禁而不是「改一次就好」：这两处都**不报错、不崩、编译全过**，
只是慢 —— 而慢没有输出。下一次有人写一个按行取时间的 `Text`、或者一个
按记录解析日期的函数，他会照着旁边那一行写，而那一行现在是对的。

退出码：0 = 全部通过；1 = 有构造器跑到池子外 / 有分配跑进比较闭包。
"""

import io
import os
import re
import sys

from _roots import assert_roots

APP = os.path.join("CarKeeper", "CarKeeper")
SCAN_DIRS = [APP]

# 池子的家。以文件为键，每条写明「为什么这里的构造器不能（或暂时不该）进池子」。
ALLOWED = {
    "CarKeeper/CarKeeper/Services/DateText.swift":
        "日期文案的唯一出口：全仓的池子就在这里，`pool` 的键是 `locale|格式` 的有界集合",
}

# ② 的例外表（目前是空的）。**键是文件路径，值写明「这里的比较为什么不许把对象提出来」。**
# 与 ① 的 ALLOWED 同一个规矩：例外必须写理由，不写就等于没同意。
COORD_ALLOWED = {}

# ① 只认这三个类型名 —— 它们都是「造一次就永远够用」的东西。
CTOR = re.compile(r"\b(DateFormatter|NumberFormatter|ISO8601DateFormatter)\s*\(\s*\)")

# ② 比较/筛选/排序闭包的开口。`(` 与 `{` 两种写法都收。
CLOSURE = re.compile(
    r"(firstIndex|lastIndex|first|contains|allSatisfy|filter|sorted|min|max|reduce)"
    r"\s*(\(\s*)?(where\s*:)?\s*\{"
)

COORD = re.compile(r"\bCLLocation\s*\(")

# 闭包体超过这么多行就不判（见文件头「宁可漏」那一段）。
MAX_CLOSURE_LINES = 30


def swift_files():
    out = []
    for base in SCAN_DIRS:
        if not os.path.isdir(base):
            continue
        for dp, dn, fn in os.walk(base):
            for f in sorted(fn):
                if f.endswith(".swift"):
                    out.append(os.path.join(dp, f).replace("\\", "/"))
    return sorted(out)


def mask(line):
    """抹掉行注释与字符串字面量 —— 判据只认代码位置。

    与 `extguard.mask` 同一套做法（那个门禁的注释里记着它自己的一个洞：
    处理 `//` 时留下开头那根 `/`，把标签抽取弄脏过），这里直接整段砍掉。
    """
    out = []
    in_str = False
    i = 0
    while i < len(line):
        ch = line[i]
        if in_str:
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                in_str = False
            i += 1
            continue
        if ch == '"':
            in_str = True
            i += 1
            continue
        if ch == "/" and i + 1 < len(line) and line[i + 1] == "/":
            break
        out.append(ch)
        i += 1
    return "".join(out)


def closure_body(lines, start, col):
    """从 (行, 列) 处的 `{` 开始，按花括号配对返回闭包体覆盖的行号范围。

    返回 (起, 止) 闭区间；括号没配平（截断 / 写法超出判据）就返回 (start, None)。
    """
    depth = 0
    for n in range(start, min(len(lines), start + MAX_CLOSURE_LINES + 1)):
        text = lines[n]
        ix = col if n == start else 0
        while ix < len(text):
            ch = text[ix]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return (start, n)
            ix += 1
    return (start, None)


def main():
    assert_roots(SCAN_DIRS)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)

    paths = swift_files()
    ctor_bad = []
    coord_bad = []
    for path in paths:
        with io.open(path, encoding="utf-8", errors="ignore") as f:
            raw = f.read().split("\n")
        lines = [mask(x) for x in raw]

        if path not in ALLOWED:
            for n, text in enumerate(lines, 1):
                if CTOR.search(text):
                    ctor_bad.append((path, n, text.strip()))

        if path in COORD_ALLOWED:
            continue
        for n, text in enumerate(lines):
            for m in CLOSURE.finditer(text):
                brace = text.find("{", m.start())
                lo, hi = closure_body(lines, n, brace)
                if hi is None:
                    continue
                window = "\n".join(lines[lo:hi + 1])
                if COORD.search(window):
                    coord_bad.append((path, lo + 1, window.strip().split("\n")[0][:100]))

    print(f"扫描 {len(paths)} 个 Swift 文件，构造器池子例外 {len(ALLOWED)} 处")

    if ctor_bad:
        print(f"\n❌ {len(ctor_bad)} 处构造器跑到了池子外（它们每次求值都会重造一遍）：")
        for path, n, code in ctor_bad:
            print(f"   {path}:{n}")
            print(f"      {code[:100]}")
        print("\n   改成从池子里取（`DateText.shared` —— 它不是 @MainActor，后台线程也要调）：")
        print("   · 写文案 → `DateText.shared.string(_ date: Date, _ format: String, locale: String?)`")
        print("   · 解析文本 → `DateText.shared.date(_ text: String, formats: [String], locale: String?)`")
        print("   · locale 是**逐调用点的事实**，不要合并：给人看的传 nil（沿用系统），")
        print("     报文格式传 `\"en_US_POSIX\"`，中文日期传 `\"zh_CN\"`。")
        print("   真不该进池子，把文件加进本文件的 ALLOWED 并写明理由。")
        return 1

    if coord_bad:
        print(f"\n❌ {len(coord_bad)} 处 CLLocation 造在比较闭包里（每次比较都分配一次）：")
        for path, n, code in coord_bad:
            print(f"   {path}:{n}")
            print(f"      {code}")
        print("\n   改法：把对象提到循环**外**，每个元素/每个组各造一次，闭包里只做比较。")
        print("   （`clusterChargers` 2026-09-25 就是这么改的：分配从 O(n × 组数) 降到 O(n)，")
        print("     分组结果一字未改。）")
        return 1

    print("✅ 便宜的东西没有每次重造（构造器有池子、坐标不在比较闭包里）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
