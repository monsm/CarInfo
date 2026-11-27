#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
_roots.py —— scan/ 下各检查器共用的「源码根目录」解析。

为什么需要它（这不是理论风险，是正在发生的事）：

  这些脚本收集待检查文件的方式是

      files = {p for tk in TK for p in Path(tk).rglob("*.swift")}

  而 `rglob` 对**不存在的目录**不报错，只是安静地返回空。于是

      「根目录写错了」  和  「那个目录里确实没有 Swift 文件」

  在输出上完全一样 —— 都是「0 个问题 ✅」。

  真实发生过：小组件 / 表盘 / App Clip / CarPlay / HealthKit 接连删除之后，
  `Shared` / `Widgets` / `WatchApp` / `HealthKit` 四个根目录已经不存在，
  而 futureproof / lexguard / shadowguard 三个脚本的 TK 里仍列着它们。
  清单越长、真实检查范围越小 —— 这正是「越改越安全」的反面。

  所以这里把「列出来的根目录必须存在」变成硬失败。多一步显式声明，
  换来的是：删目录的人必须同时改这里，否则 CI 立刻红 —— 检查范围不可能悄悄缩小。
"""

import sys
from pathlib import Path

EXISTING_ROOTS = [
    "CarKeeper/CarKeeper",
    "CarKeeper/Services",
    "CarKeeper/Design",
    "CarKeeper/Tests",
]


def assert_roots(roots):
    """roots 里的每一项都必须是真实存在的目录，而且里面得有 .swift。

    给那些自己走 os.walk / 自己汇总的检查器用（它们不需要文件清单，
    但同样会被「根目录不存在」静默地掏空）。
    """
    missing = [r for r in roots if not Path(r).is_dir()]
    if missing:
        print("❌ 声明了不存在的源码根目录:")
        for r in missing:
            print(f"   {r}")
        print("   `rglob` / `os.walk` 对不存在的目录不报错，只是什么都不返回 ——")
        print("   那会让这个检查器的范围悄悄变成「什么都没查」。")
        print("   目录已删就把它从清单里去掉；目录该在就把目录找回来。")
        sys.exit(1)
    if not any(Path(r).rglob("*.swift") for r in roots):
        print("❌ 声明的源码根目录里一个 .swift 都没有 —— 检查范围是空的。")
        sys.exit(1)


def swift_files(roots):
    """收集 roots 下全部 .swift。任何一个 root 不存在 → 直接失败。

    参数 roots 是相对当前工作目录的目录名（CI 与本地都在仓库根运行这些脚本）。
    """
    assert_roots(roots)
    return sorted({str(p) for tk in roots for p in Path(tk).rglob("*.swift")})
