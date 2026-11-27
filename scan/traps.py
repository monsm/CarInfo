#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
真机崩溃构造检查器 —— 「编译得过、门禁全绿，但一进某个页面就闪退」

为什么需要它（真实事故，2026-09-23）：
  真机报告（iPhone17,1 / iOS 27.2，`bug_type: 309`，`EXC_BREAKPOINT`）：

      VehicleTipsSection.body.getter
        → VehicleTipsSection.tips.getter
          → ServiceReminderManager.reminders.getter
            → ServiceReminderManager.defaultReminders.getter   ← SIGTRAP

  那行是：

      nextDate: cal.date(byAdding: .month, value: 6 + type.hashValue * 2, to: today)!

  `hashValue` 不是固定值、也不是枚举序号 —— 它是**每进程随机种子**（能到 ±9.2e18）。
  于是 `6 + hashValue * 2` 本身就会**整数溢出**（Swift 溢出即 trap = SIGTRAP）；
  就算侥幸不溢出，`date(byAdding: .month, value: 4.6e18)` 也返回 nil，而这里用了 `!`。
  两者都是「编译通过、静态门禁 17 项全绿、本地看不出来、真机一进那一页必崩」。

  这一整类问题（整型溢出 trap、nil 强解包 trap、数组越界、`fatalError`）**编译期不报错**，
  而本项目唯一的编译器是 CI 的 macOS runner —— 它也只证明「能编译」。

判据（刻意收窄到能给出**确定**结论的三条，避免假阳性）：
  ① `.hashValue` 出现在 App 源码里。它在业务代码里只有两种正当用法 ——
     作为 `Hashable` 身份、或喂给 `Set`/`Dictionary`。一旦它出现在**算术里**
     （乘、加、下标、当参数传给日期/距离），那就是随机数冒充业务数据，且可能溢出。
     本项目里它一次都不该出现：需要固定序号就用 `CaseIterable` 的下标或显式表。
  ② 日期构造的强解包：`date(byAdding:` / `date(from:` / `startOfDay` / `startOfMonth`
     同一行末尾带 `!`。`Calendar` 的这些 API 返回 `Date?` 是有原因的（DST、极端偏移、
     非法组件），而它们的失败路径在真机上比在模拟器上多。
  ②' **任何**调用结果的强解包（`...)!` 结尾）。它和上面的崩溃同源：
     `arr.min()!`（空数组）、`data(using:)!`（编码失败）、`URL(string:)!`（服务端给回来
     的字符串）都是「上游一变就崩」。本项目现在这一条**一次都不出现**，全用
     `guard let` / `??` 换掉了 —— 因为它们都能改写成不崩的写法，而代价只是两行。
  ③ `try!` / `as!`。前者把「可恢复的错误」变成崩溃，后者在服务端返回结构变化时崩溃。

  白名单（下面 `ALLOWED`）只给「确实必须」用，且每条要写理由。

退出码：0 = 无这类构造；1 = 有（或扫描失败）。
"""

import os
import re
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SCOPE_DIRS = [
    "CarKeeper/CarKeeper",
    "CarKeeper/Services",
    "CarKeeper/Models",
    "CarKeeper/Design",
    "CarKeeper/Shared",
    "CarKeeper/Widgets",
    "CarKeeper/WatchApp",
]

ALLOWED = {
}

HASH_VALUE = re.compile(r"\.hashValue\b")
DATE_API = re.compile(r"date\(byAdding:|date\(from:|startOfDay\(|startOfMonth\(")
FORCE_UNWRAP_TAIL = re.compile(r"\)![\s,\]]*$|\)!\s*$")
CALL_UNWRAP = re.compile(r"\)\s*!\s*(?:[,)\]}]|$)")
COLLECTION_UNWRAP = re.compile(r"\.(?:first|last|min|max)\s*!")
TRY_BANG = re.compile(r"\btry!")
AS_BANG = re.compile(r"\bas!\s*[A-Za-z_\[]")


def swift_files():
    out = []
    for d in SCOPE_DIRS:
        root = os.path.join(PROJECT_ROOT, d)
        if not os.path.isdir(root):
            continue
        for dirpath, _, filenames in os.walk(root):
            if "/Tests" in dirpath or dirpath.endswith("/Tests"):
                continue
            for f in filenames:
                if f.endswith(".swift"):
                    p = os.path.join(dirpath, f)
                    out.append(os.path.relpath(p, PROJECT_ROOT).replace(os.sep, "/"))
    return sorted(set(out))


def strip_comment(line):
    """去掉行内注释（`//` 之后）。字符串里的 `//` 极少会跟在日期 API 后面，忽略即可。"""
    idx = line.find("//")
    return line if idx < 0 else line[:idx]


def main():
    files = swift_files()
    if not files:
        print("❌ 扫描范围为空 —— 路径写错了？")
        return 1

    problems = []
    for rel in files:
        with open(os.path.join(PROJECT_ROOT, rel), encoding="utf-8", errors="ignore") as fh:
            for i, raw in enumerate(fh, 1):
                line = strip_comment(raw.rstrip("\n"))
                if not line.strip():
                    continue
                key = f"{rel}:{i}"
                if key in ALLOWED:
                    continue
                if HASH_VALUE.search(line):
                    problems.append((rel, i, "①", "`.hashValue` 出现在 App 源码里 —— "
                                     "它是每进程随机种子，参与算术会溢出（真机 SIGTRAP），"
                                     "当业务数据则是随机的。需要固定值就用显式表或下标。",
                                     line.strip()))
                if DATE_API.search(line) and FORCE_UNWRAP_TAIL.search(line):
                    problems.append((rel, i, "②", "日期构造后强解包 —— `Calendar` 的这类 API "
                                     "返回 Optional 是有原因的（极端偏移 / 非法组件），"
                                     "失败路径在真机上比模拟器多。请用 `?? 兜底`。",
                                     line.strip()))
                elif CALL_UNWRAP.search(line):
                    problems.append((rel, i, "②'", "调用结果强解包 —— 空数组 / 编码失败 / "
                                     "服务端给回来的字符串都会走到这条崩溃。"
                                     "请改写为 `guard let` 或 `?? 兜底`。",
                                     line.strip()))
                if COLLECTION_UNWRAP.search(line):
                    problems.append((rel, i, "②''", "空集合取值的强解包 —— `first` / `last` / "
                                     "`min()` / `max()` 在空集合上都是 nil，`!` 即崩溃。"
                                     "用 `map`/`??` 或 `guard let`（`arr.isEmpty ? A : B!` "
                                     "这种“看上去守过了”的写法同属这一类）。",
                                     line.strip()))
                if TRY_BANG.search(line):
                    problems.append((rel, i, "③", "`try!` —— 把可恢复的错误变成崩溃。",
                                     line.strip()))
                if AS_BANG.search(line):
                    problems.append((rel, i, "③", "`as!` —— 服务端/上游结构一变就崩溃。",
                                     line.strip()))

    print(f"扫描 {len(files)} 个 Swift 源文件（App + 扩展 target）")
    print("检查真机崩溃构造：hashValue 算术 · 日期强解包 · 调用结果强解包 · try! · as!")

    if problems:
        print("\n❌ 发现会在真机上崩溃的构造：\n")
        for rel, i, tag, why, code in problems:
            print(f"   {tag} {rel}:{i}")
            print(f"      {why}")
            print(f"      {code}")
        print("\n   来历：2026-09-23 真机崩溃（EXC_BREAKPOINT，栈：VehicleTipsSection.tips"
              "\n   → ServiceReminderManager.defaultReminders）—— `6 + type.hashValue * 2`"
              "\n   溢出 + `date(byAdding:)!`。编译通过、17 项门禁全绿、真机一进那一页必崩。")
        return 1

    print("\n✅ 无『编译得过但真机必崩』的构造（hashValue 算术 / 日期与调用结果强解包 / try! / as!）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
