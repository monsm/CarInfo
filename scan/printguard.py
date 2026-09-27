#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
printguard.py —— 「失败要留在能被看到的地方」

为什么需要它（2026-09-25 地毯式对抗式审核查出来的两处）：

  全仓只有两个 `print(`，而它们各自都是一处**静默失败**：
    · `MaintenanceReminderScheduler`：申请通知授权失败 → `print(...)` → 直接返回 false；
    · `InsuranceReminderScheduler`：布置到期提醒失败 → `print(...)` → 函数结束。

  这两处都是「提醒没响」的方向：用户不会收到提醒，也不会在任何界面上看到原因，
  而诊断页里那本日志（`RawLogStore`）—— 专门为这种事存在的那本 —— 一个字都没有。

  为什么是门禁而不是「改一次就好」：`print` 的问题不在于吵，而在于**它没有读者**。
  调试器能看到的只有开发者本人、只在连着调试器时；用户看不到，诊断页看不到，
  崩溃报告里也没有。写它的时候看起来像「已经处理了错误」，所以它是最容易被
  留着不删的那种代码。这个仓库已经有两处真实事故级的东西死在这上面，够一条判据了。

判据（一条）：App / Services 代码里不得出现 `print(`。
  · 认的形状：`print(`。
  · 允许的例外见 `ALLOWED`，键是「文件:行数上限」这种形式不取 —— 以**文件**为键，
    每一条写明「这里的输出为什么必须走标准输出」。目前只有一处：排障页
    （`Features/Dev/DevView.swift`）自己那份调试输出。
  · 注释与字符串里的 `print(` 不算（先抹掉再查 —— 判据只认代码位置）。

该往哪写：`RawLogStore.shared`（诊断页在读的那本，会打码与限长，同时写一条系统日志）。
（另一条出口「启动阶段的路标写 `StartupJournal.shared.mark(_:)`」已随那个文件一起
删于 2026-09-27 —— 诊断页的「上一次启动」与它一起走了。）

退出码：0 = 全部通过；1 = 有 print(。
"""

import io
import os
import re
import sys

from _roots import assert_roots

APP = os.path.join("CarKeeper", "CarKeeper")
SERVICES = os.path.join("CarKeeper", "Services")
DESIGN = os.path.join("CarKeeper", "Design")
#  顶层的 `CarKeeper/Models` 项随 `AppDataModel.swift` 一起删（2026-09-26）：
#  这个清单走 `assert_roots`，而它对不存在的目录是**立即失败** ——
#  删目录时忘了改这里，这条门禁当场红（那是故意的）。

SCAN_DIRS = [APP, SERVICES, DESIGN]

# 以文件为键：这里的标准输出是它自己要的东西（排障页的调试输出）。
# ⚠️ 理由 2026-09-25 第九轮改过一次：那一页不再是「设计令牌页」（色板与字体样张已删），
# 而它仍然要往标准输出打东西 —— 变的只是这一条为什么成立。
ALLOWED = {
    os.path.join(APP, "Features", "Dev", "DevView.swift").replace("\\", "/"):
        "排障页自己的调试输出：它本来就是把内部读数摊开给人看的那一页",
}

FORM = re.compile(r"\bprint\s*\(")


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


def strip_comment(line):
    for marker in ("//", "///", "*"):
        i = line.find(marker)
        if i >= 0:
            line = line[:i]
    return line


def main():
    assert_roots(SCAN_DIRS)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)

    paths = swift_files()
    bad = []
    for path in paths:
        if path in ALLOWED:
            continue
        with io.open(path, encoding="utf-8", errors="ignore") as f:
            for n, raw in enumerate(f, 1):
                code = strip_comment(raw)
                if FORM.search(code):
                    bad.append((path, n, code.strip()))

    print(f"扫描 {len(paths)} 个 Swift 文件，例外 {len(ALLOWED)} 处（标准输出只许在那里用）")
    if bad:
        print(f"\n❌ {len(bad)} 处 print( —— 它没有读者：")
        for path, n, code in bad:
            print(f"   {path}:{n}")
            print(f"      {code[:100]}")
        print("\n   失败要写进能被看到的地方：")
        print("   · 运行期错误 → `RawLogStore.shared.logError(method:url:message:)`（诊断页在读）")
        print("   · 要让人当场知道 → `EnhancedToastManager` / `ToastManager`")
        print("   真需要标准输出（设计令牌页那类），把文件加进本文件的 ALLOWED 并写明理由。")
        return 1

    print("✅ 没有 print(（失败都留在能被看到的地方）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
